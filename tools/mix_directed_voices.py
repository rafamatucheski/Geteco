"""Mede o volume e atribui ganho linear de reprodução sem alterar nenhum WAV."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import time

from voice_direction import ROOT, DirectionError, digest, read_json, write_json

FFMPEG = Path("C:/Users/rafae/AppData/Local/Programs/Python/Python311/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe")
POLICY = {"version": "directed_linear_lufs_v1", "target_lufs": -20.0, "max_true_peak_db": -1.5,
          "minimum_gain_db": -12.0, "maximum_gain_db": 12.0, "short_utterance_peak_db": -6.0,
          "processing": "playback_linear_gain_only_no_compression_no_waveform_edit"}


def gain_for_measurement(integrated, true_peak, policy=POLICY):
    if not math.isfinite(true_peak):
        raise DirectionError("Cannot mix silent/unmeasurable audio")
    # O bloco de integração do EBU R128 pode ser maior que um grito autorado muito curto. Usa
    # um alvo de pico declarado só nesse caso, preservando a forma no tempo.
    method = "integrated_loudness" if math.isfinite(integrated) else "short_utterance_peak"
    desired = policy["target_lufs"]-integrated if math.isfinite(integrated) else policy["short_utterance_peak_db"]-true_peak
    safe = min(desired, policy["max_true_peak_db"]-true_peak)
    return round(max(policy["minimum_gain_db"], min(policy["maximum_gain_db"], safe)), 3), method


def measure(path, ffmpeg=FFMPEG):
    process = subprocess.run([str(ffmpeg), "-hide_banner", "-nostats", "-threads", "1", "-filter_threads", "1",
                  "-i", str(path), "-af", "loudnorm=I=-20:TP=-1.5:LRA=20:print_format=json",
                  "-f", "null", "-"], capture_output=True, text=True, timeout=45, check=True)
    end = process.stderr.rfind("}")
    begin = process.stderr.rfind("{", 0, end)
    if begin < 0 or end < 0:
        raise DirectionError("FFmpeg did not return loudness measurements")
    result = json.loads(process.stderr[begin:end+1])
    return float(result["input_i"]), float(result["input_tp"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=ROOT / "audio/mission_voices/directed/cloned-production.json")
    parser.add_argument("--output", type=Path, default=ROOT / "audio/mission_voices/directed/mix.json")
    args = parser.parse_args()
    started = time.monotonic()
    previous = read_json(args.output) if args.output.exists() else {"takes": []}
    policy_sha = digest(POLICY)
    cache = {t["cache_key"]: t for t in previous["takes"]}
    report = {"version": 1, "policy": POLICY, "policy_sha256": policy_sha, "takes": []}
    rows = read_json(args.manifest)["takes"]
    for index, source in enumerate(rows):
        path = (ROOT / source["path"][6:]).resolve()
        path.relative_to((ROOT / "audio/mission_voices/directed").resolve())
        sha = hashlib.sha256(path.read_bytes()).hexdigest()
        if sha != source["audio_sha256"]:
            raise DirectionError("Recording changed since production")
        key = digest([policy_sha, sha])
        if key in cache:
            report["takes"].append(cache[key])
            continue
        integrated, true_peak = measure(path)
        gain, method = gain_for_measurement(integrated, true_peak)
        report["takes"].append({"cache_key": key, "path": source["path"], "audio_sha256": sha,
                     "input_lufs": integrated if math.isfinite(integrated) else None,
                     "input_true_peak_db": true_peak, "playback_gain_db": gain,
                     "mix_method": method, "mix_policy": policy_sha})
        if index % 16 == 0:
            write_json(args.output, report)
            print(f"VOICE_MIX_MEASURED {index+1}/{len(rows)}", flush=True)
    report["elapsed_seconds"] = round(time.monotonic()-started, 3)
    write_json(args.output, report)
    print(f"VOICE_MIX_COMPLETE takes={len(report['takes'])} seconds={report['elapsed_seconds']}")


if __name__ == "__main__":
    main()
