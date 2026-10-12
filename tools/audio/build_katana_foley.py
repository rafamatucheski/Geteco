"""Render katana air and body cuts offline; reuse credited CC0 contact Foley.

Run from the repository root: python tools/audio/build_katana_foley.py
Sources and licenses: audio/contact_foley/CREDITS.md. Requires numpy/scipy/soundfile.
"""
from pathlib import Path
import sys

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "audio/contact_foley"))
from build_bank import RATE, layer, mix


def build():
    output = ROOT / "audio/katana"
    output.mkdir(exist_ok=True)
    for take in range(3):
        rng = np.random.default_rng(61012 + take)
        t = np.arange(round(RATE * .26)) / RATE
        # Broad air, no pitched oscillator: sharp blade passage at 50 ms.
        noise = rng.normal(0, 1, len(t))
        air = sosfilt(butter(2, [650, 7400], "bandpass", fs=RATE, output="sos"), noise)
        envelope = np.where(t < .05, (t / .05) ** 2, np.exp(-(t - .05) / .035))
        air *= envelope
        air /= np.max(np.abs(air))
        swing = mix(.26, [(air, 1, 0)], -3)
        # Recorded body/cloth contact, short tearing crunch and blade exit.
        cut = mix(.38, [
            layer("impactSoft_medium", take, .75, 0, 1.05 + take * .035, 3400),
            layer("impactPunch_medium", take + 1, .48, .003, 1.1, 5200),
            layer("crunch", take + 2, .65, .008, 1.22 + take * .08, 7200),
            (air, .24, .014),
        ], -2)
        for kind, samples in [("swing", swing), ("cut", cut)]:
            sf.write(output / f"{kind}_{take}.wav", samples, RATE, subtype="PCM_16")
    print("Created 3 blade swings and 3 body cuts (44.1 kHz mono PCM).")


if __name__ == "__main__":
    build()
