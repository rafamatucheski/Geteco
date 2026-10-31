"""Auditoria só leitura dos assets de diálogo publicados; nunca certifica atuação por métricas de sinal.

Grava só o relatório pedido explicitamente. Usa o inventário autorado vivo e a
proveniência de produção existente, não uma lista fixa de personagens.
"""
from __future__ import annotations

import argparse
from array import array
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import sys
import wave

from english_voice_catalog import ROOT, inventory


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def waveform(path: Path) -> dict:
    with wave.open(str(path), "rb") as source:
        rate, channels, width, count = (source.getframerate(), source.getnchannels(),
                                      source.getsampwidth(), source.getnframes())
        if width != 2 or channels != 1:
            return {"error": "Expected mono PCM16", "channels": channels, "width": width}
        samples = array("h", source.readframes(count))
    if sys.byteorder != "little":
        samples.byteswap()
    if not samples or rate <= 0:
        return {"error": "Empty recording"}
    active = [i for i, value in enumerate(samples) if abs(value) >= 98]
    return {
        "seconds": round(count / rate, 3), "sample_rate": rate,
        "peak": round(max(abs(value) for value in samples) / 32768, 4),
        "hard_clipped_samples": sum(abs(value) >= 32760 for value in samples),
        "active_seconds": round((active[-1] - active[0] + 1) / rate, 3) if active else 0,
        "leading_silence_seconds": round(active[0] / rate, 3) if active else count / rate,
        "trailing_silence_seconds": round((count - active[-1] - 1) / rate, 3) if active else count / rate,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def audit() -> dict:
    rows = inventory()
    base = ROOT / "audio/mission_voices"
    banks = {"pt_BR": read_json(base / "recordings.json"),
             "en": read_json(base / "en/recordings.json")}
    maciota = read_json(base / "maciota_baritone/recordings.json")
    provenance = {}
    for production in sorted(base.glob("*/production.json")):
        value = read_json(production)
        for take in value.get("lines", []):
            profile = take.get("voice_profile", value.get("profile", value.get("model", "unknown_provenance")))
            if isinstance(profile, str) and isinstance(value.get("profile"), dict):
                profile = value["profile"]
            if isinstance(profile, dict):
                profile = profile.get("voice", profile.get("id", "unknown_provenance"))
            path = take.get("path", "")
            if path:
                provenance[path] = {"profile": profile, "production": production.relative_to(ROOT).as_posix()}
    assets, errors, review, cache = [], [], [], {}
    actors = defaultdict(lambda: defaultdict(set))
    repeated = defaultdict(set)
    for row in rows:
        repeated[row["text"]].add(row["persona"])
        for language in ("pt_BR", "en"):
            bank = maciota if language == "pt_BR" and row["persona"] in ("maciota", "caller") else banks[language]
            resource = bank.get(row["key"], "")
            take = {"key": row["key"], "persona": row["persona"], "language": language,
                    "section": row["section"], "path": resource}
            expected = row["text"] if language == "pt_BR" else row["en"]
            take["text"] = expected
            if not resource.startswith("res://"):
                errors.append(dict(take, error="Missing manifest entry"))
                continue
            path = (ROOT / resource[6:]).resolve()
            if not path.is_relative_to(ROOT.resolve()) or not path.is_file():
                errors.append(dict(take, error="Missing or out-of-project audio file"))
                continue
            try:
                if resource not in cache:
                    cache[resource] = waveform(path)
                take.update(cache[resource])
            except (OSError, wave.Error) as exc:
                errors.append(dict(take, error=str(exc)))
                continue
            if "error" in take:
                errors.append(take)
                continue
            take.update(provenance.get(resource, {"profile": "unknown_provenance", "production": ""}))
            actors[language][str(take["profile"])].add(row["persona"])
            words = len(re.findall(r"\w+", expected, flags=re.UNICODE))
            active_seconds = max(take["active_seconds"], 0.001)
            take["estimated_words_per_minute"] = round(words * 60 / active_seconds)
            flags = []
            if take["peak"] < .01:
                errors.append(dict(take, error="Silent or nearly silent take"))
            if take["hard_clipped_samples"]:
                flags.append("hard_clipping")
            if words >= 10 and take["estimated_words_per_minute"] > 260:
                flags.append("check_rushed_delivery_or_truncation")
            if take["trailing_silence_seconds"] > 1.5:
                flags.append("long_trailing_silence")
            if flags:
                review.append({"key": row["key"], "language": language, "flags": flags})
            assets.append(take)
    return {
        "scope": "Current inventory() and resolved shipped WAVs; silent documents excluded",
        "limitations": [
            "No listening judgement: waveform metrics cannot certify gender, accent, emotion or identity.",
            "Estimated speaking rate uses expected text; an ASR or listening review must confirm actual words.",
            "The current inventory deduplicates persona+text and may hide different physical speakers sharing a name.",
            "No rendered performance measurement; this audit does not run or modify gameplay.",
        ],
        "source_lines": len(rows), "persona_labels": len({row["persona"] for row in rows}),
        "waveforms_checked": len(assets), "errors": errors, "listening_review_flags": review,
        "profiles": {language: {voice: sorted(people) for voice, people in voices.items()}
                     for language, voices in actors.items()},
        "shared_text": [{"text": text, "personas": sorted(people)}
                        for text, people in repeated.items() if len(people) > 1],
        "section_counts": dict(Counter(row["section"] for row in rows)), "assets": assets,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Report already exists; use a new output path to preserve previous evidence")
    result = audit()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({name: result[name] for name in ("source_lines", "persona_labels", "waveforms_checked")}
                     | {"errors": len(result["errors"]), "review_flags": len(result["listening_review_flags"])},
                     ensure_ascii=False))
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
