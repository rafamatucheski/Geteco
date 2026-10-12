"""Author loaded combustion loops offline; preserve the existing idle recordings.

Requires numpy. Run with --output DIRECTORY to preview without replacing assets.
The seven-band runtime contract is 22050 Hz mono PCM, a one-second circular
signal and eight duplicated guard frames (EngineBankCache excludes the guard).
No filters, procedural synthesis, extra voices or larger buffers run in game.
"""
import argparse
import json
from pathlib import Path
import wave

import numpy as np

RATE = 22050
GUARD = 8
ROOT = Path(__file__).resolve().parents[1]
# Four-stroke cycles per second, matching VehicleEngineProfile.NOMINAL.
# cylinders, exhaust resonance, breathing cutoff, cylinder/bank imbalance.
PROFILES = {
    "street": ([6, 9, 13, 18, 25, 35, 50], 4, 145, 1250, .10),
    "sport": ([7, 11, 15, 21, 31, 44, 62], 6, 190, 1800, .08),
    "muscle": ([6, 8, 11, 16, 22, 32, 45], 8, 105, 1250, .34),
    "suv": ([6, 8, 11, 15, 21, 30, 42], 6, 120, 1100, .17),
    "diesel": ([5, 7, 9, 12, 16, 21, 28], 4, 100, 1300, .23),
    "truck": ([4, 5, 6, 8, 11, 14, 19], 6, 80, 950, .22),
    "bus": ([3, 4, 6, 8, 10, 14, 18], 6, 75, 900, .20),
    "fire_diesel": ([4, 5, 7, 9, 12, 16, 21], 6, 85, 1050, .22),
    "ambulance": ([5, 7, 10, 13, 18, 24, 33], 8, 115, 1200, .20),
    "police": ([6, 9, 13, 18, 26, 37, 52], 8, 130, 1500, .24),
    "vq35": ([6, 9, 13, 18, 26, 38, 55], 6, 175, 1650, .13),
    "m8_v8": ([7, 10, 15, 23, 34, 50, 74], 8, 135, 1550, .30),
    "rosso_v12": ([8, 11, 16, 23, 34, 49, 70], 12, 210, 2100, .06),
}


def unit(signal):
    signal = signal - np.mean(signal)
    return signal / max(float(np.std(signal)), 1e-9)


def render(family, index):
    rates, cylinders, resonance, cutoff, imbalance = PROFILES[family]
    cycles = rates[index]
    rng = np.random.default_rng(71023 + list(PROFILES).index(family) * 100 + index)
    t = np.arange(RATE) / RATE
    freq = np.fft.rfftfreq(RATE, 1 / RATE)
    events = cycles * cylinders
    impulses = np.zeros(RATE)
    # Individual explosions instead of a handful of fixed sine waves. Keep the
    # mean firing rate exact while allowing pressure and timing to vary per fire.
    for event in range(events):
        cylinder = event % cylinders
        at = (event + rng.uniform(-.028, .028)) * RATE / events
        amplitude = (1 + imbalance * np.cos(2 * np.pi * cylinder / cylinders)
                     + rng.uniform(-.30, .30))
        pos = int(np.floor(at))
        frac = at - pos
        impulses[pos % RATE] += amplitude * (1 - frac)
        impulses[(pos + 1) % RATE] += amplitude * frac
    # A finite pressure pulse and a damped exhaust cavity have broad spectra.
    # The resonance stays tied to the vehicle, not to an oscillator's harmonic.
    pulse = (np.exp(-t / .0028) - np.exp(-t / .00035))
    pulse += .30 * np.sin(2 * np.pi * resonance * t) * np.exp(-t / .014)
    pressure = np.fft.irfft(np.fft.rfft(impulses) * np.fft.rfft(pulse), RATE)
    pressure = unit(pressure)
    air_filter = (freq / np.maximum(freq + 65, 1)) * np.exp(-(freq / cutoff) ** 2)
    air = unit(np.fft.irfft(np.fft.rfft(rng.normal(size=RATE)) * air_filter, RATE))
    # Turbulence is pressure-modulated, so it breathes with the exhaust instead
    # of adding a constant white hiss. Cross-plane families retain bank rumble.
    breath = air * (.62 + .38 * np.clip(np.abs(pressure), 0, 2))
    bank = np.sin(2 * np.pi * cycles * 2 * t + .12 * np.sin(2 * np.pi * 3 * t))
    signal = .68 * pressure + (.30 + .025 * index) * breath + imbalance * bank
    spectrum = np.fft.rfft(signal)
    spectrum *= (1 - np.exp(-(freq / 35) ** 2)) / np.sqrt(1 + (freq / (cutoff * .8)) ** 4)
    signal = np.fft.irfft(spectrum, RATE)
    # Gentle saturation retains transients without harsh hard clipping. Equal
    # RMS across loaded bands avoids an artificial loudness jump at crossfades.
    signal = np.tanh(unit(signal) * .62)
    signal = unit(signal) * .245
    return signal


def metrics(signal):
    spectrum = np.abs(np.fft.rfft(signal)) ** 2
    return {
        "rms": float(np.std(signal)), "peak": float(np.max(np.abs(signal))),
        "top_five_bin_power": float(np.sort(spectrum)[-5:].sum() / spectrum.sum()),
        "seam_step": float(abs(signal[0] - signal[-1])),
        "max_step": float(np.max(np.abs(np.diff(signal)))),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "audio/acoustic")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    report = {}
    for family in PROFILES:
        for index in range(1, 7):
            signal = render(family, index)
            assert np.isfinite(signal).all() and np.max(np.abs(signal)) < .98
            pcm = np.rint(np.concatenate([signal, signal[:GUARD]]) * 32767).astype("<i2")
            name = f"engine_{family}_{index}.wav"
            with wave.open(str(args.output / name), "wb") as out:
                out.setnchannels(1)
                out.setsampwidth(2)
                out.setframerate(RATE)
                out.writeframes(pcm.tobytes())
            report[name] = metrics(signal)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
