"""Edit recorded CC0 crash Foley into game-ready one-shots; no oscillators/noise synthesis.

python tools/build_vehicle_crash_audio.py [--download]
Requires numpy, scipy and soundfile. Sources are cached outside the Godot project.
"""
from pathlib import Path
import argparse
import hashlib
import json
import urllib.request

import numpy as np
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfiltfilt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "audio/vehicle_crashes"
CACHE = ROOT.parent / "assets/audio-sources/vehicle-crashes"
RATE = 44100
SOURCES = {
    "squareal": {"file": "squareal_car_crash.mp3", "author": "squareal",
        "title": "Car Crash", "page": "https://freesound.org/people/squareal/sounds/237375/",
        "download": "https://cdn.freesound.org/previews/237/237375_1502374-hq.mp3",
        "description": "Recorded metal cabinet impact, grit and broken glass Foley."},
    "metal": {"file": "675460.mp3", "author": "craigsmith",
        "title": "S37-12 Car crash; no motor sound; metallic.wav",
        "page": "https://freesound.org/people/craigsmith/sounds/675460/",
        "download": "https://cdn.freesound.org/previews/675/675460_2524442-hq.mp3",
        "description": "Digitized vintage film crash effect, metal collision without engine."},
    "glass": {"file": "592388.mp3", "author": "magnuswaker",
        "title": "Car Crash (with Glass)", "page": "https://freesound.org/people/magnuswaker/sounds/592388/",
        "download": "https://cdn.freesound.org/previews/592/592388_11537497-hq.mp3",
        "description": "Recorded metal panels colliding, layered with recorded glass shattering."},
}


def filtered(x, lo=65, hi=13500):
    return sosfiltfilt(butter(2, [lo, hi], btype="bandpass", fs=RATE, output="sos"), x)


def cut(x, start, length, speed=1.0):
    x = x[round(start * RATE):round((start + length * speed) * RATE)]
    x = resample_poly(x, 1000, round(speed * 1000))
    return x[:round(length * RATE)].copy()


def add(dst, layer, gain, delay=0):
    start = round(delay * RATE)
    n = min(len(layer), len(dst) - start)
    dst[start:start+n] += layer[:n] * gain


def master(x, peak):
    # Preserve the recordings' irregular crunch and transients. No generated bass,
    # aggressive saturation, long reverb or uniform exponential percussion envelope.
    x = filtered(x)
    attack, release = round(.002 * RATE), min(round(.14 * RATE), len(x) // 3)
    x[:attack] *= np.linspace(0, 1, attack)
    x[-release:] *= np.linspace(1, 0, release) ** 1.4
    x *= peak / max(np.max(np.abs(x)), 1e-8)
    return x


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    recordings = {}
    for key, info in SOURCES.items():
        path = CACHE / info["file"]
        if not path.exists():
            if not args.download:
                raise SystemExit(f"Missing {path}; run with --download")
            urllib.request.urlretrieve(info["download"], path)
        info["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        info["license"] = "CC0-1.0"
        info["license_url"] = "https://creativecommons.org/publicdomain/zero/1.0/"
        info["format_note"] = "Public high-quality MP3 preview; edited to mono PCM WAV."
        x, sr = sf.read(path, always_2d=True)
        x = x.mean(axis=1)
        x = resample_poly(x, RATE, sr)
        recordings[key] = x

    metrics, demo = {}, []
    for kind in ["bumper", "metal", "solid", "heavy", "motorcycle"]:
        for take in range(4):
            speed = [1.0, .96, 1.035, .985][take]
            if kind == "bumper":
                # Short deformation from the cabinet/noise-box recording, with
                # a quiet bit of recorded metal flex. No glass tail on light taps.
                length = [.52, .58, .49, .62][take]
                x = filtered(cut(recordings["squareal"], [.418, .455, .492, .535][take], length, speed), 110, 5700)
                add(x, filtered(cut(recordings["metal"], [.09, 1.56, 2.4, 3.05][take], .26), 170, 4200), .12, .018)
                peak = .55
            elif kind == "metal":
                length = [1.18, 1.3, 1.22, 1.38][take]
                x = cut(recordings["metal"], [.082, 1.54, 2.4, 3.02][take], length, speed)
                # Immediate compact contact, followed by recorded bending/rattle.
                add(x, cut(recordings["squareal"], .418 + take * .009, .42), .65)
                x *= np.linspace(1, .12, len(x)) ** .8
                peak = .76
            elif kind == "solid":
                length = [1.12, 1.24, 1.18, 1.3][take]
                x = cut(recordings["squareal"], .414 + take * .008, length, speed)
                add(x, filtered(cut(recordings["metal"], [.09, 2.42, 3.06, 5.66][take], .58), 95, 6800), .28, .027)
                peak = .76
            elif kind == "motorcycle":
                # Only the metallic recording: neither source containing glass.
                length = [.65, .78, .72, .86][take]
                x = cut(recordings["metal"], [.082, 1.54, 2.4, 3.02][take], length, speed)
                x = filtered(x, 100, 6800)
                peak = .72
            else:
                length = [2.18, 2.3, 2.06, 2.36][take]
                x = np.zeros(round(length * RATE))
                add(x, cut(recordings["glass"], [0, .012, .035, .02][take], length, speed), .8)
                add(x, cut(recordings["squareal"], .416, 1.4, speed), .7)
                add(x, cut(recordings["metal"], [.09, 1.54, 3.02, 5.65][take], 1.25), .28, .045 + .012 * take)
                x *= np.linspace(1, .25, len(x)) ** .6
                peak = .84
            x = master(x, peak)
            name = f"{kind}_{take}"
            sf.write(OUT / f"{name}.wav", x, RATE, subtype="PCM_16")
            # Keep PCM import: short impacts need their transient detail intact.
            imp = OUT / f"{name}.wav.import"
            if imp.exists():
                imp.write_text(imp.read_text().replace("compress/mode=2", "compress/mode=0"))
            pcm, _ = sf.read(OUT / f"{name}.wav")
            assert abs(pcm[0]) < 1e-4 and abs(pcm[-1]) < 1e-4
            assert np.max(np.abs(pcm)) < .9
            rms = float(np.sqrt(np.mean(pcm ** 2)))
            assert rms > .018
            metrics[name] = {"seconds": round(len(x) / RATE, 3), "peak_dbfs": round(20*np.log10(peak), 2),
                "rms_dbfs": round(20*np.log10(rms), 2), "sha256": hashlib.sha256((OUT / f"{name}.wav").read_bytes()).hexdigest()}
            if take < 2:
                demo.extend([x, np.zeros(round(.55 * RATE))])
    sf.write(ROOT / "audio/vehicle_crash_review.wav", np.concatenate(demo), RATE, subtype="PCM_16")
    (OUT / "SOURCES.json").write_text(json.dumps(SOURCES, indent=2) + "\n")
    (OUT / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    print(f"Built {len(metrics)} recorded crash edits; PCM peaks below -1.5 dBFS; no synthesized tones.")


if __name__ == "__main__":
    main()
