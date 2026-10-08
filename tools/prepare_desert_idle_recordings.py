"""Prepare two licensed field-recorded idle loops; never generates engine audio.

Usage: python tools/prepare_desert_idle_recordings.py --cache <external directory>
Requires numpy, scipy, soundfile and requests. Sources remain in the external cache.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

import numpy as np
import requests
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfiltfilt

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    dict(file="bison_idle.wav", title="dv6_idle_outside.wav", author="Mihacappy",
         page="https://freesound.org/people/Mihacappy/sounds/819134/",
         license="CC0-1.0", license_url="https://creativecommons.org/publicdomain/zero/1.0/"),
    dict(file="coyote_idle.wav", title="Eight-cylinder engine idling.wav", author="Lumamorph",
         page="https://freesound.org/people/Lumamorph/sounds/636066/",
         license="CC-BY-4.0", license_url="https://creativecommons.org/licenses/by/4.0/"),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", type=Path, required=True)
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    out = ROOT / "audio/desert_cars"
    rows = []
    for source in SOURCES:
        response = requests.get(source["page"], timeout=30)
        response.raise_for_status()
        url = re.search(r"https://cdn\.freesound\.org/previews/[^\s\"<>]+-hq\.mp3", response.text).group()
        original = args.cache / (source["file"] + ".source.mp3")
        if not original.exists():
            response = requests.get(url, timeout=60)
            response.raise_for_status()
            original.write_bytes(response.content)
        data, rate = sf.read(original, always_2d=True)
        data = data[int(2 * rate):int(6 * rate)].mean(axis=1)
        data = sosfiltfilt(butter(2, 35, fs=rate, btype="highpass", output="sos"), data)
        from math import gcd
        divisor = gcd(rate, 22050)
        data = resample_poly(data, 22050 // divisor, rate // divisor)
        # Rotate across a 200 ms overlap. End and start continue the same source
        # segment; this avoids an amplitude seam and a periodic fade to silence.
        overlap = 4410
        weight = np.linspace(0, 1, overlap, endpoint=False)
        seam = data[-overlap:] * (1-weight) + data[:overlap] * weight
        data = np.concatenate([seam, data[overlap:-overlap]])
        data -= data.mean()
        data *= min(.24 / np.sqrt(np.mean(data**2)), .74 / np.max(np.abs(data)))
        data = np.concatenate([data, data[:8]])  # existing WAV mixer guard frames
        dest = out / source["file"]
        sf.write(dest, data, 22050, subtype="PCM_16")
        row = dict(source, download=url, source_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),
                   output_sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),
                   changes="HQ MP3 preview decoded; seconds 2-6; mono; 35 Hz high-pass; 22050 Hz; 200 ms overlap; gain normalization; 8 guard frames",
                   seconds=len(data)/22050, peak=float(np.max(np.abs(data))), rms=float(np.sqrt(np.mean(data**2))))
        rows.append(row)
        print(json.dumps(row))
    (out / "SOURCES.json").write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
