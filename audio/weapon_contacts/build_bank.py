"""Short game Foley edited from the existing CC0 contact recordings.

These are designed contacts, not recordings of particular real cartridges.
Run with Python + numpy/scipy/soundfile. No runtime synthesis or DSP.
"""
from pathlib import Path
import importlib.util
import json
import hashlib
import numpy as np
import soundfile as sf

OUT = Path(__file__).resolve().parent
source = OUT.parent / "contact_foley" / "build_bank.py"
spec = importlib.util.spec_from_file_location("contact_bank", source)
bank = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bank)


def build():
    report = []
    for take in range(3):
        tin = bank.layer("impactTin_medium", take, 1, 0, 2.6, 11000)
        designs = {
            "casing_hard": (.16, [tin, bank.layer("footstep_concrete", take, .12, .007, 2.8, 6500)]),
            "casing_metal": (.24, [tin, bank.layer("impactMetal_heavy", take, .3, .008, 2.4, 9500)]),
            "casing_wood": (.13, [bank.layer("impactWood_heavy", take, 1, 0, 2.8, 5000), bank.layer("impactTin_medium", take, .12, 0, 2.8, 5500)]),
            "casing_soft": (.085, [bank.layer("impactSoft_medium", take, 1, 0, 2.1, 2600)]),
            "casing_snow": (.10, [bank.layer("impactSoft_medium", take, 1, 0, 1.7, 1400)]),
            "impact_soil": (.22, [bank.layer("impactSoft_medium", take, 1, 0, 1.3, 4000), bank.layer("crunch", take, .2, .012, 1.9, 4800)]),
            "impact_snow": (.17, [bank.layer("impactSoft_medium", take, 1, 0, 1.1, 2400)]),
        }
        for name, (duration, layers) in designs.items():
            data = bank.mix(duration, layers, -6)
            # A brief case tick must not have the long body of a panel impact.
            if name.startswith("casing_"):
                data *= np.exp(-np.linspace(0, 3, len(data)))
            path = OUT / f"{name}_{take}.wav"
            sf.write(path, data, bank.RATE, subtype="PCM_16")
            report.append({"file": path.name, "seconds": duration,
                           "peak_dbfs": round(float(20*np.log10(max(np.abs(data)))), 2),
                           "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    (OUT / "bank.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Built {len(report)} weapon contact Foley clips")


if __name__ == "__main__":
    build()
