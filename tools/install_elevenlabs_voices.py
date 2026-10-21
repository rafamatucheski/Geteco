"""Instala no banco dirigido as falas PT-BR geradas na ElevenLabs.

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
WAV_DIR = ROOT / "audio/mission_voices/directed/elevenlabs/pt_BR"
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


def take(row: dict, persona: str, session: str, prompt: str) -> dict:
    mp3 = EVIDENCE / "mp3" / f"{session}.mp3"
    mp3_sha = hashlib.sha256(mp3.read_bytes()).hexdigest()
    voice_id, voice_name = VOICES[persona]
    signature = digest({"provider": "elevenlabs", "model": MODEL, "voice_id": voice_id, "prompt": prompt,
                        "session": session, "source_mp3_sha256": mp3_sha, "format": "pcm16_mono_24k"})
    wav = WAV_DIR / f"{row['key']}_{signature[:16]}.wav"
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


def entry(row: dict, persona: str, recorded: dict) -> dict:
    voice_id = recorded["voice_id"]
    return {"path": recorded["path"], "spoken_text": row["spoken_pt"], "signature": recorded["signature"],
            "character_id": persona, "persona": persona, "source": row["source"], "source_key": row["key"],
            "voice_gender": "male", "language": "pt_BR", "duration_seconds": recorded["duration_seconds"],
            "audio_sha256": recorded["audio_sha256"],
            "technical_validation": {"passed": True, "checks": recorded["checks"]},
            # Aprovado em lote pelo usuário no chat (20/10); ninguém ouviu fala por fala aqui.
            "artistic_review": "user_batch_approved_20261020", "status": "approved",
            "anchor_id": persona, "anchor_sha256": digest({"provider": "elevenlabs", "voice_id": voice_id}),
            "model": MODEL, "provider": "elevenlabs", "voice_id": voice_id, "voice_name": recorded["voice_name"],
            "prompt": recorded["prompt"], "gender_validation": "reference_authored_unverified",
            "playback_gain_db": recorded["playback_gain_db"], "input_lufs": recorded["input_lufs"],
            "input_true_peak_db": recorded["input_true_peak_db"], "mix_method": recorded["mix_method"],
            "mix_policy": digest(POLICY)}


def main() -> None:
    direction = {row["key"]: row for row in read_json(ROOT / "data/dialogue/voice-line-direction.json")["lines"]}
    plan = read_json(EVIDENCE / "plan.json")
    ledger = {row["label"]: row["session_id"] for row in read_json(EVIDENCE / "ledger.json")["generations"]}
    lines: dict[str, dict] = {}
    for index, item in enumerate(plan):
        row = direction[item["key"]]
        lines[row["key"]] = entry(row, item["speaker"], take(row, item["speaker"], ledger[str(index)], item["prompt"]))
    for key, labels in VARIANTS.items():
        row = direction[key]
        persona = row["speaker"]
        recorded = [take(row, persona, ledger[label], prompt if persona == "dante" else f"{prompt} {row['spoken_pt']}")
                    for label, prompt in labels]
        result = entry(row, persona, recorded[0])
        result["variants"] = [{field: r[field] for field in ("path", "audio_sha256", "duration_seconds", "playback_gain_db", "prompt")}
                              for r in recorded]
        lines[key] = result
    write_json(OUTPUT, {"version": 1, "provider": "elevenlabs", "model": MODEL, "language": "pt_BR",
                        "voices": {p: {"voice_id": v[0], "name": v[1]} for p, v in VOICES.items()},
                        "mix_policy": POLICY, "lines": {"pt_BR": lines}})
    variants = sum(len(v.get("variants", [])) for v in lines.values())
    print(f"ELEVENLABS_VOICES lines={len(lines)} variant_takes={variants} -> {OUTPUT.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
