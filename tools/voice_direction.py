"""Contratos puros e offline para tomadas de atuação autoradas em PT-BR/inglês.

Este módulo nunca inicializa sintetizador, contata serviço, adivinha o gênero de
um personagem nem escolhe voz substituta. Bancos antigos de gravação só alimentam
o jogo; este pipeline grava um banco de testes separado e imutável.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {"pt_BR": ("Portuguese", "spoken_pt"), "en": ("English", "spoken_en")}
MODEL = "Qwen3-TTS-12Hz-1.7B-VoiceDesign"
REVIEW_CHECKS = ("transcript", "language", "gender", "identity", "delivery", "technical_quality")


class DirectionError(ValueError):
    """Autoria/elenco inválido precisa parar a produção, nunca cair num substituto."""


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def canonical_key(persona, source):
    return hashlib.sha256((persona.lower() + "|" + source).encode("utf-8")).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write_json(path, value):
    """A troca atômica vale só para os nossos metadados, nunca para WAVs antigos."""
    import os
    import tempfile
    import time
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                     prefix=path.name + ".", suffix=".pending", delete=False) as file:
        json.dump(value, file, ensure_ascii=False, indent=2)
        file.write("\n")
        pending = Path(file.name)
    # Leitores no Windows (varreduras de assets do editor / auditorias só leitura concorrentes) podem
    # segurar o destino por instantes sem compartilhar exclusão. Mantém o checkpoint
    # completo e repete o rename dos metadados, nunca regenera os WAVs dele.
    for attempt in range(40):
        try:
            os.replace(pending, path)
            return
        except PermissionError:
            if attempt == 39:
                raise
            time.sleep(.05)


def resolve_character(cast, row):
    persona = row["persona"]
    profile = cast.get("personas", {}).get(persona)
    if not profile:
        raise DirectionError(f"No explicit cast for {persona!r}")
    variants = profile.get("variants", [])
    exact = [v for v in variants if row["key"] in v.get("line_keys", [])]
    contextual = [v for v in variants if row.get("section") in v.get("sections", [])]
    matches = exact or contextual
    if len(matches) > 1:
        raise DirectionError(f"Ambiguous character for {persona}: {row['key']}")
    if matches:
        profile = {**profile, **matches[0]}
        character_id = matches[0]["id"]
    else:
        character_id = profile.get("default_character", profile.get("id"))
    if not character_id:
        raise DirectionError(f"Missing stable character id for {persona}")
    if profile.get("gender") not in ("male", "female"):
        raise DirectionError(f"Unresolved voice gender for {persona}/{character_id}")
    voice = profile.get("voice", {})
    if voice.get("provider") != "qwen3_voice_design" or voice.get("model") != MODEL:
        raise DirectionError(f"Unsupported/unassigned expressive actor for {persona}/{character_id}")
    if voice.get("identity") != character_id:
        raise DirectionError(f"Voice identity differs from character for {persona}/{character_id}")
    return character_id, profile


def plan_takes(cast, direction, inventory, languages=("pt_BR", "en"), *,
               model_revision="unresolved", device="cpu", take_index=0, dtype="bfloat16"):
    if not languages or set(languages) - LANGUAGES.keys() or len(set(languages)) != len(languages):
        raise DirectionError("Languages must explicitly be pt_BR and/or en")
    if device not in ("cpu", "cuda") or take_index < 0 or dtype not in ("bfloat16", "float32"):
        raise DirectionError("Invalid synthesis device or take index")
    source_by_key = {}
    for row in inventory:
        if canonical_key(row["persona"], row["text"]) != row["key"]:
            raise DirectionError("Inventory key does not match canonical source")
        if row["key"] in source_by_key:
            raise DirectionError("Duplicate inventory key")
        source_by_key[row["key"]] = row
    directed = {}
    for line in direction.get("lines", []):
        key = line["key"]
        if key in directed:
            raise DirectionError("Duplicate direction key: " + key)
        directed[key] = line
    missing = set(source_by_key) - directed.keys()
    if missing:
        raise DirectionError(f"Missing authored line direction: {len(missing)} ({sorted(missing)[0]})")
    result = []
    for key, row in sorted(source_by_key.items()):
        line = directed[key]
        if line.get("speaker", "").lower() != row["persona"] or line.get("source") != row["text"]:
            raise DirectionError("Direction source/persona mismatch: " + key)
        identity, profile = resolve_character(cast, row)
        if not str(line.get("intent", "")).strip() or not str(line.get("performance_prompt", "")).strip():
            raise DirectionError("Missing line intention/performance: " + key)
        for language in languages:
            model_language, text_field = LANGUAGES[language]
            text = line.get(text_field, "").strip()
            character_direction = profile.get("direction", {}).get(language, "").strip()
            if not text or not character_direction:
                raise DirectionError(f"Missing authored text or direction: {identity}/{language}/{key}")
            if any(marker in text for marker in ("<speak", "[emotion:", "<prosody")):
                raise DirectionError("Stage directions cannot appear in spoken text: " + key)
            language_prompt = ("Speak native Brazilian Portuguese, never European Portuguese."
                               if language == "pt_BR" else "Speak natural conversational English.")
            gender_prompt = "An adult woman's voice." if profile["gender"] == "female" else "An adult man's voice."
            prompt = " ".join((language_prompt, gender_prompt, "Voice identity and usual manner:", character_direction,
                               "Scene performance overrides habitual emotion, pacing and breathing while preserving voice identity:",
                               line["performance_prompt"],
                               "Perform only the supplied dialogue verbatim. No introduction, music or sound effects. Dry close-mic recording."))
            # Estável por ator fictício; isto é reprodutibilidade, NÃO uma afirmação
            # de que o VoiceDesign garante timbre consistente entre tomadas.
            seed = int(digest([identity, take_index])[:8], 16) % (2**31)
            settings = {"temperature": 0.7, "top_p": 0.9, "do_sample": True,
                        "max_new_tokens": min(1200, max(180, len(text) * 3)),
                        "seed": seed, "device": device, "dtype": dtype,
                        "attn_implementation": "sdpa", "threads": 2}
            audible_character = {"character_id": identity, "gender": profile["gender"],
                                 "voice": profile["voice"], "direction": character_direction}
            provenance = {"pipeline_version": 2, "source_key": key, "persona": row["persona"],
                          "character_id": identity, "source": row["text"], "spoken_text": text,
                          "language": language, "voice_gender": profile["gender"],
                          "model": MODEL, "model_revision": model_revision,
                          "voice_profile": profile["voice"], "direction": prompt,
                          "character_revision": digest(audible_character), "settings": settings,
                          "postprocessing": "mono_pcm16_24khz_peak_limit_0.9_v1"}
            result.append({**provenance, "signature": digest(provenance), "model_language": model_language,
                           "take_index": take_index,
                           "intent": line["intent"], "section": row.get("section", ""),
                           "casting_blockers": profile.get("casting_blockers", []) + row.get("publication_blockers", []),
                           "cast_revision": digest(cast), "status": "planned"})
    return result


def approved_manifest(production, review, *, current_plan, root=ROOT):
    """Só bytes correspondentes ouvidos explicitamente podem virar substituições no runtime."""
    takes = {take["signature"]: take for take in production.get("takes", [])}
    current = {take["signature"]: take for take in current_plan}
    published = {"version": 1, "lines": {"pt_BR": {}, "en": {}}}
    seen = set()
    for decision in review.get("reviews", []):
        signature = decision.get("signature")
        if signature in seen:
            raise DirectionError("Duplicate review signature")
        seen.add(signature)
        if decision.get("decision") != "approved":
            continue
        if signature not in takes or not str(decision.get("reviewer", "")).strip():
            raise DirectionError("Approved take needs provenance and reviewer")
        if not all(decision.get("checks", {}).get(name) is True for name in REVIEW_CHECKS):
            raise DirectionError("Transcript, gender, language, identity, delivery and audio checks must pass")
        take = takes[signature]
        if signature not in current:
            raise DirectionError("Approved take is stale against the current cast, text, direction or model")
        for name in ("source_key", "persona", "source", "character_id", "spoken_text", "language",
                     "voice_gender", "character_revision", "model", "model_revision", "direction", "settings"):
            if take.get(name) != current[signature].get(name):
                raise DirectionError("Rendered provenance differs from the current signed plan: " + name)
        if current[signature].get("casting_blockers"):
            raise DirectionError("Character emitter/visual binding is unresolved; casting blockers remain")
        if take.get("status") not in ("review_required", "approved"):
            raise DirectionError("Cannot publish an unrendered/failed take")
        resource = take.get("path", "")
        if not resource.startswith("res://audio/mission_voices/directed/"):
            raise DirectionError("Published take is outside the directed bank")
        path = (root / resource[6:]).resolve()
        path.relative_to((root / "audio/mission_voices/directed").resolve())
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != take.get("audio_sha256"):
            raise DirectionError("Reviewed audio is missing or changed")
        bucket = published["lines"][take["language"]]
        key = take["source_key"]
        if key in bucket:
            raise DirectionError("Two approved takes for the same language/source")
        bucket[key] = {name: take[name] for name in ("path", "spoken_text", "signature", "character_id",
                         "persona", "source", "voice_gender", "cast_revision", "audio_sha256")}
    return published


def merge_reviews(previous, incoming, production, current_plan):
    """Preserva decisões anteriores de elenco; uma tomada nova substitui a mesma vaga.

    Aprovações vencidas ficam no histórico de revisão com status explícito de vencida, mas
    não entram na publicação atual. Rejeição é sempre uma entrada explícita.
    """
    current = {take["signature"] for take in current_plan}
    takes = {take["signature"]: take for take in production.get("takes", [])}
    decisions = {}
    allowed = {"approved", "rejected", "pending", "stale", "superseded"}
    for document in (previous, incoming):
        seen = set()
        for decision in document.get("reviews", []):
            signature = decision.get("signature")
            if signature in seen or signature not in takes or decision.get("decision") not in allowed:
                raise DirectionError("Invalid, duplicate or unknown review decision")
            seen.add(signature)
            if decision["decision"] == "approved":
                take = takes[signature]
                for old_signature, old in list(decisions.items()):
                    previous_take = takes[old_signature]
                    if (old_signature != signature and old["decision"] == "approved" and
                            (previous_take["source_key"], previous_take["language"]) == (take["source_key"], take["language"])):
                        decisions[old_signature] = {**old, "decision": "superseded", "superseded_by": signature}
            decisions[signature] = dict(decision)
    for signature, decision in list(decisions.items()):
        if decision["decision"] == "approved" and signature not in current:
            if any(row.get("signature") == signature and row.get("decision") == "approved" for row in incoming.get("reviews", [])):
                raise DirectionError("New approval is stale against the current production plan")
            decisions[signature] = {**decision, "decision": "stale", "reason": "Current text/cast/direction/model changed"}
    return {"version": 1, "reviews": [decisions[key] for key in sorted(decisions)]}
