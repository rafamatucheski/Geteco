"""Build contact Foley offline from the CC0 recordings listed in CREDITS.md.

Requires numpy, scipy and soundfile. Run from any working directory.
No downloads, synthesis, random noise or runtime processing. Sources are retained
so future changes don't replace the edited Foley with the old procedural bank.
"""
from pathlib import Path
import hashlib
import json
import math

import numpy as np
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfilt

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent / "source"
RATE = 44100


def recording(name, take=0, speed=1.0, lowpass=None):
    if name == "glass":
        path = SOURCE / "glass_breaking.wav"
    elif name == "crunch":
        path = SOURCE / "impcrunch" / f"impactcrunch{take % 5 + 1:02d}.mp3.flac"
    else:
        path = SOURCE / f"{name}_{take % 5:03d}.ogg"
    data, rate = sf.read(path, always_2d=True)
    data = data.mean(axis=1)
    # Remove recording lead-in; preserve 2 ms ahead of the first transient.
    active = np.flatnonzero(np.abs(data) > np.max(np.abs(data)) * 0.012)
    if not len(active):
        raise ValueError(f"Silent source: {path}")
    data = data[max(0, active[0] - int(rate * .002)):]
    source_rate = round(rate * speed)
    gcd = math.gcd(RATE, source_rate)
    data = resample_poly(data, RATE // gcd, source_rate // gcd)
    data = sosfilt(butter(2, 38, "highpass", fs=RATE, output="sos"), data)
    if lowpass:
        data = sosfilt(butter(2, lowpass, fs=RATE, output="sos"), data)
    data /= max(float(np.max(np.abs(data))), 1e-8)
    return data


def layer(name, take, gain=1.0, delay=0.0, speed=1.0, lowpass=None):
    return recording(name, take, speed, lowpass), gain, delay


def mix(duration, layers, peak_db=-3.0):
    data = np.zeros(round(RATE * duration))
    for samples, gain, delay in layers:
        offset = round(delay * RATE)
        count = min(len(samples), len(data) - offset)
        data[offset:offset + count] += samples[:count] * gain
    # Gentle edge fades; don't flatten attack dynamics with a waveshaper.
    data[:44] *= np.linspace(0, 1, 44)
    fade = min(round(.07 * RATE), len(data) // 4)
    data[-fade:] *= np.linspace(1, 0, fade) ** 2
    data *= 10 ** (peak_db / 20) / max(float(np.max(np.abs(data))), 1e-8)
    data[0] = data[-1] = 0
    return data


def designs():
    for take in range(4):
        plate = lambda gain=1, delay=0, speed=.9: layer("impactPlate_heavy", take, gain, delay, speed, 8500)
        weight = lambda gain=1: layer("impactSoft_heavy", take, gain, 0, .82, 2600)
        crunch = lambda gain=.25, delay=.015: layer("crunch", take, gain, delay, .95, 7000)
        yield f"audio/vehicle_crashes/bumper_{take}.wav", mix(.65, [weight(), plate(.22, .012, 1.05)])
        yield f"audio/vehicle_crashes/solid_{take}.wav", mix(.85, [weight(), plate(.6), crunch(.32)])
        yield f"audio/vehicle_crashes/heavy_{take}.wav", mix(1.12, [weight(), plate(.9, .008, .78), crunch(.6), layer("glass", take, .14, .06, 1.02 + take * .04)])
        yield f"audio/vehicle_crashes/metal_{take}.wav", mix(.95, [plate(), layer("impactMetal_heavy", take, .55), crunch(.22), layer("impactTin_medium", take + 1, .18, .12, .88)])
        yield f"audio/vehicle_crashes/motorcycle_{take}.wav", mix(.82, [layer("impactMetal_heavy", take, .8, 0, .95), plate(.5, .01, 1.12), layer("impactTin_medium", take + 2, .22, .09)])
    for take in range(3):
        # Cloth/body weight and panel contact have separate timbres. No bone
        # cracks or glass on a pedestrian; landing adds a dry ground scuff.
        body = layer("impactSoft_heavy", take, 1, 0, .94, 3800)
        yield f"audio/body_impacts/body_hit_{take}.wav", mix(.50, [body, layer("impactPunch_medium", take, .42, .004, .92, 4800), layer("impactPlate_heavy", take, .12, .018, .9, 1800)])
        yield f"audio/body_impacts/body_land_{take}.wav", mix(.54, [body, layer("footstep_concrete", take, .26, .018, .85, 4800), layer("impactSoft_medium", take + 2, .18, .075, 1, 3000)])
        yield f"assets/gameplay/audio/impact_flesh_{take}.wav", mix(.4, [layer("impactPunch_medium", take, .8, 0, 1, 5500), body], -4)
        yield f"assets/gameplay/audio/impact_glass_{take}.wav", mix(1.35, [layer("glass", take, 1, 0, .96 + take * .045), layer("impactGlass_light", take, .2, .055 + take * .011)], -4)
        yield f"assets/gameplay/audio/impact_wood_{take}.wav", mix(.8, [layer("impactWood_heavy", take), layer("crunch", take + 1, .5, .012, 1.05, 8000)])
        yield f"assets/gameplay/audio/impact_metal_{take}.wav", mix(.65, [layer("impactMetal_heavy", take), layer("impactPlate_medium", take, .3, .012)])
        yield f"assets/gameplay/audio/impact_concrete_{take}.wav", mix(.55, [layer("impactMining", take, .75), layer("impactSoft_heavy", take, .35, 0, 1, 2200), layer("crunch", take, .12, .03, 1.25, 5500)])


def build():
    report = []
    for relative, data in designs():
        path = ROOT / relative
        sf.write(path, data, RATE, subtype="PCM_16")
        report.append({"path": relative, "seconds": len(data) / RATE,
                       "peak_dbfs": round(20 * np.log10(np.max(np.abs(data))), 2),
                       "rms_dbfs": round(20 * np.log10(np.sqrt(np.mean(data ** 2))), 2),
                       "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    (Path(__file__).resolve().parent / "bank.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Built {len(report)} mono PCM contact clips at {RATE} Hz.")


if __name__ == "__main__":
    build()
