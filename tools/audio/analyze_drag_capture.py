"""Analisa uma saída real de capture_drag_audio_identity.gd sem afirmar que houve audição.

Uso: python tools/audio/analyze_drag_capture.py evidence/drag-audio-identity-...
"""
from pathlib import Path
import json
import sys
import numpy as np
import soundfile as sf


def stats(values):
    if len(values) == 0:
        return {"frames": 0}
    peak = np.max(np.abs(values))
    rms = np.sqrt(np.mean(values * values))
    return {"frames": len(values), "peak_dbfs": round(float(20 * np.log10(max(peak, 1e-12))), 3),
            "rms_dbfs": round(float(20 * np.log10(max(rms, 1e-12))), 3),
            "saturated_samples": int(np.count_nonzero(np.abs(values) >= 32767 / 32768))}


def longest_zero_run(values, rate):
    silent = np.all(values == 0, axis=1)
    edges = np.diff(np.concatenate(([False], silent, [False])).astype(np.int8))
    starts, ends = np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)
    return float(np.max(ends - starts) / rate) if len(starts) else 0.0


def main():
    directory = Path(sys.argv[1])
    capture = json.loads((directory / "capture.json").read_text(encoding="utf-8"))
    marks = capture["marks"] + [{"label": "end", "seconds": capture["duration"]}]
    report = {"capture": str(directory), "contract": capture["capture_contract"], "tracks": {}, "intervals": {},
              "limitation": "Objective PCM measurement; not a listening review or frame-time benchmark. Per-source buses precede their parent user bus gains."}
    tracks = {}
    for label in ["mix", "player", "rival", "patio", "pulso"]:
        values, rate = sf.read(directory / (label + ".wav"), dtype="float32", always_2d=True)
        tracks[label] = values
        report["tracks"][label] = {**stats(values), "sample_rate": rate, "seconds": len(values) / rate}
        intervals = {}
        for index, mark in enumerate(marks[:-1]):
            start = round((mark["seconds"] + .3) * rate)
            end = round((marks[index + 1]["seconds"] - .3) * rate)
            selected = values[max(start, 0):max(start, end)]
            intervals[mark["label"]] = {**stats(selected), "longest_digital_zero_seconds": longest_zero_run(selected, rate)}
        report["intervals"][label] = intervals
    # Compara motores nas MESMAS amostras e posições reais do grid de largada, depois
    # da atenuação espacial e antes do bus SFX compartilhado. Evita que vitórias muito à frente
    # passem por prova de equilíbrio entre raias próximas.
    eligible = [step["seconds"] for step in capture["steps"] if step["phase"] in ("staging", "racing") and abs(step["player_x"] - step["rival_x"]) <= 12]
    if eligible:
        start, end = round((min(eligible) + .3) * rate), round((max(eligible) - .3) * rate)
        p, r = stats(tracks["player"][start:end]), stats(tracks["rival"][start:end])
        report["near_pair"] = {"start": start / rate, "end": end / rate, "player": p, "rival": r,
                                "player_rms_lead_db": round(p["rms_dbfs"] - r["rms_dbfs"], 3)}
    if (directory / "concurrency.json").exists():
        report["concurrency"] = json.loads((directory / "concurrency.json").read_text(encoding="utf-8-sig"))
    (directory / "audio-analysis.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"tracks": report["tracks"], "near_pair": report.get("near_pair", {}), "mix_phases": report["intervals"]["mix"]}, indent=2))


if __name__ == "__main__":
    main()
