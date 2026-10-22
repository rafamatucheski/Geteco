"""Instala no banco dirigido as falas (PT-BR e inglês) geradas na ElevenLabs.

Lê o plano e o registro de gerações de evidence/elevenlabs-teste-20261020/, converte cada MP3
para WAV mono PCM16 24 kHz (o formato que o banco dirigido valida), mede o volume com a mesma
política de `mix_directed_voices.py` e grava `audio/mission_voices/directed/elevenlabs.json`.

O arquivo é separado de `runtime.json` de propósito: `build_voice_bank.py publish` reescreve o
manifesto local e apagaria estas falas; o `DirectedVoiceBank` aplica este por cima.
Falas aleatórias recebem `variants` e o banco sorteia uma a cada reprodução.
"""
from __future__ import annotations

import array
import hashlib
import json
import math
import subprocess
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mix_directed_voices import FFMPEG, POLICY, gain_for_measurement, measure  # noqa: E402
from voice_direction import ROOT, digest, read_json, write_json  # noqa: E402

EVIDENCE = ROOT / "evidence/elevenlabs-teste-20261020"
OUTPUT = ROOT / "audio/mission_voices/directed/elevenlabs.json"
WAV_ROOT = ROOT / "audio/mission_voices/directed/elevenlabs"
# Lotes posteriores (pasta, rótulo de aprovação). O primeiro, de 20/10, tem formato próprio.
BATCHES = [("evidence/elevenlabs-lote-ab-20261021", "user_batch_approved_20261021"),
           ("evidence/elevenlabs-maciota-en-20261021", "user_batch_approved_20261021"),
           # Gerado pelo site (conta Free) e baixado num ZIP: o conector apontava para a conta sem cota.
           ("evidence/elevenlabs-missoes-20261022", "user_batch_approved_20261022")]
MODEL = "eleven_v4"
VOICES = {"dante": ("ycxdm1PRMs962FxyyuJ0", "Otto - Intimidating and Aggressive"),
          "maciota": ("GIuLCSVfgJaUuh7hYOY8", "Lucas - Deep & Profound Narrator")}
# Variações de tom para falas que o jogo repete (o rótulo do registro → chave do roteiro).
VARIANTS = {
    "80a833fa7c4bf1c457d0ce1d3fbaf3e0fe21b6b6f926b242223d70ce494307ac": [
        ("dante_dor_aguda", "[dor aguda, curto] Ai!"), ("dante_dor_abafada", "[gemido abafado, dentes cerrados] Ai!"),
        ("dante_dor_susto", "[susto e dor] Ai!"), ("dante_dor_raiva", "[dor com raiva] Ai!")],
    "873a8bd50b524f3b14f0c9c9ecc17d5bb9604f18e4c436e2d15fad6f32108b6b": [
        ("maciota_cumprimento_brincalhao", "[ágil, brincalhão, rindo]"), ("maciota_cumprimento_cansado", "[ágil, cansado, ironia seca]"),
        ("maciota_cumprimento_caloroso", "[ágil, caloroso, animado]")],
}


def convert(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(FFMPEG), "-hide_banner", "-loglevel", "error", "-y", "-i", str(source),
                    "-ac", "1", "-ar", "24000", "-c:a", "pcm_s16le", str(target)], check=True, timeout=60)


def validate(path: Path) -> tuple[float, list[str]]:
    with wave.open(str(path), "rb") as handle:
        if (handle.getnchannels(), handle.getsampwidth(), handle.getframerate()) != (1, 2, 24000):
            raise ValueError(f"{path.name}: formato inesperado")
        frames = handle.getnframes()
        samples = array.array("h", handle.readframes(frames))
    peak = max((abs(s) for s in samples), default=0)
    if frames == 0 or peak < 64:
        raise ValueError(f"{path.name}: áudio silencioso")
    if peak >= 32767:
        raise ValueError(f"{path.name}: pico no limite da escala")
    return frames / 24000.0, ["finite_audio", "non_silent", "mono_pcm16_24khz", "peak_below_full_scale"]


def take(row: dict, voice: tuple[str, str], session: str, prompt: str, mp3_dir: Path, language: str) -> dict:
    mp3 = mp3_dir / f"{session}.mp3"
    mp3_sha = hashlib.sha256(mp3.read_bytes()).hexdigest()
    voice_id, voice_name = voice
    signature = digest({"provider": "elevenlabs", "model": MODEL, "voice_id": voice_id, "prompt": prompt,
                        "session": session, "source_mp3_sha256": mp3_sha, "format": "pcm16_mono_24k"})
    wav = WAV_ROOT / language / f"{row['key']}_{signature[:16]}.wav"
    if not wav.exists():
        convert(mp3, wav)
    duration, checks = validate(wav)
    integrated, true_peak = measure(wav)
    gain, method = gain_for_measurement(integrated, true_peak)
    return {"path": "res://" + wav.relative_to(ROOT).as_posix(), "audio_sha256": hashlib.sha256(wav.read_bytes()).hexdigest(),
            "duration_seconds": round(duration, 4), "signature": signature, "session": session, "prompt": prompt,
            "voice_id": voice_id, "voice_name": voice_name, "checks": checks, "playback_gain_db": gain,
            "input_lufs": integrated if math.isfinite(integrated) else None, "input_true_peak_db": true_peak,
            "mix_method": method}


def entry(row: dict, persona: str, character_id: str, gender: str, language: str, recorded: dict, approval: str) -> dict:
    voice_id = recorded["voice_id"]
    return {"path": recorded["path"], "spoken_text": row["spoken_en" if language == "en" else "spoken_pt"],
            "signature": recorded["signature"], "character_id": character_id, "persona": persona, "source": row["source"],
            "source_key": row["key"], "voice_gender": gender, "language": language,
            "duration_seconds": recorded["duration_seconds"], "audio_sha256": recorded["audio_sha256"],
            "technical_validation": {"passed": True, "checks": recorded["checks"]},
            # Aprovação em lote pelo usuário no chat; ninguém ouviu fala por fala aqui.
            "artistic_review": approval, "status": "approved",
            "anchor_id": character_id, "anchor_sha256": digest({"provider": "elevenlabs", "voice_id": voice_id}),
            "model": MODEL, "provider": "elevenlabs", "voice_id": voice_id, "voice_name": recorded["voice_name"],
            "prompt": recorded["prompt"], "gender_validation": "reference_authored_unverified",
            "playback_gain_db": recorded["playback_gain_db"], "input_lufs": recorded["input_lufs"],
            "input_true_peak_db": recorded["input_true_peak_db"], "mix_method": recorded["mix_method"],
            "mix_policy": digest(POLICY)}


def with_variants(base: dict, recorded: list[dict]) -> dict:
    if len(recorded) > 1:
        base["variants"] = [{field: r[field] for field in ("path", "audio_sha256", "duration_seconds", "playback_gain_db", "prompt")}
                            for r in recorded]
    return base


def first_batch(direction: dict, lines: dict) -> None:
    """Teste de 20/10: só PT-BR, plano antigo (índice → sessão) e variações declaradas em VARIANTS."""
    plan = read_json(EVIDENCE / "plan.json")
    ledger = {row["label"]: row["session_id"] for row in read_json(EVIDENCE / "ledger.json")["generations"]}
    approval = "user_batch_approved_20261020"
    for index, item in enumerate(plan):
        row = direction[item["key"]]
        persona = item["speaker"]
        recorded = take(row, VOICES[persona], ledger[str(index)], item["prompt"], EVIDENCE / "mp3", "pt_BR")
        lines["pt_BR"][row["key"]] = entry(row, persona, persona, "male", "pt_BR", recorded, approval)
    for key, labels in VARIANTS.items():
        row = direction[key]
        persona = row["speaker"]
        recorded = [take(row, VOICES[persona], ledger[label], prompt if persona == "dante" else f"{prompt} {row['spoken_pt']}",
                         EVIDENCE / "mp3", "pt_BR") for label, prompt in labels]
        lines["pt_BR"][key] = with_variants(entry(row, persona, persona, "male", "pt_BR", recorded[0], approval), recorded)


def planned_batch(folder: Path, direction: dict, cast: dict, lines: dict, approval: str) -> None:
    """Lotes gerados por plan_elevenlabs_batch.py: plan.json + sessions.txt na mesma ordem."""
    plan = read_json(folder / "plan.json")
    sessions = (folder / "sessions.txt").read_text(encoding="utf-8").split()
    if len(plan) != len(sessions):
        raise ValueError(f"{folder.name}: plano e sessões com tamanhos diferentes")
    groups: dict[tuple[str, str], list[dict]] = {}
    for item, session in zip(plan, sessions):
        row = direction[item["key"]]
        recorded = take(row, (item["voice_id"], item["voice_name"]), session, item["prompt"], folder / "mp3", item["language"])
        groups.setdefault((item["key"], item["language"]), []).append((item, recorded))
    for (key, language), takes in groups.items():
        item = takes[0][0]
        gender = gender_of(cast, direction[key])
        base = entry(direction[key], item["persona"], item["character_id"], gender, language, takes[0][1], approval)
        lines[language][key] = with_variants(base, [r for _, r in takes])


def gender_of(cast: dict, row: dict) -> str:
    person = cast.get(row["speaker"], {})
    for variant in person.get("variants", []):
        if row["key"] in variant.get("line_keys", []):
            return variant.get("gender", person.get("gender", "male"))
    return person.get("gender", "male")


def main() -> None:
    direction = {row["key"]: row for row in read_json(ROOT / "data/dialogue/voice-line-direction.json")["lines"]}
    cast = read_json(ROOT / "data/dialogue/voice-cast.json")["personas"]
    lines: dict[str, dict] = {"pt_BR": {}, "en": {}}
    first_batch(direction, lines)
    for folder, approval in BATCHES:
        planned_batch(ROOT / folder, direction, cast, lines, approval)
    write_json(OUTPUT, {"version": 1, "provider": "elevenlabs", "model": MODEL,
                        "voices": {p: {"voice_id": v[0], "name": v[1]} for p, v in VOICES.items()},
                        "mix_policy": POLICY, "lines": lines})
    for language, rows in lines.items():
        variants = sum(len(v.get("variants", [])) for v in rows.values())
        print(f"ELEVENLABS_VOICES {language} lines={len(rows)} variant_takes={variants}")


if __name__ == "__main__":
    main()
