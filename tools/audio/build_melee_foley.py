"""Build melee Foley from the repository's credited CC0 contact recordings.

No engine, downloads, oscillators, or random noise. Source licenses and originals:
audio/contact_foley/CREDITS.md. Run: python tools/audio/build_melee_foley.py
"""
from pathlib import Path
import hashlib
import json
import sys

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "audio/contact_foley"))
from build_bank import RATE, layer, mix, recording

TAKES = 4


def cloth_pass(take, duration, cutoff):
    # Discard the impact transient, then shape recorded soft-contact texture
    # into the cloth/air movement of the weapon. No fake impact on a miss.
    source = recording("impactSoft_medium", take, 1.15, cutoff)
    source = source[round(RATE * .025):]
    count = round(RATE * duration)
    if len(source) < 2:
        raise ValueError("Soft-contact source has no tail")
    texture = np.interp(np.linspace(0, len(source) - 1, count), np.arange(len(source)), source)
    texture = sosfilt(butter(2, 500, "highpass", fs=RATE, output="sos"), texture)
    time = np.arange(count) / RATE
    envelope = np.where(time < .05, (time / .05) ** 2, np.exp(-(time - .05) / .035))
    return texture * envelope


def designs():
    for take in range(TAKES):
        for weapon, duration, cutoff in [("knife", .16, 6800), ("bat", .26, 3600),
                                         ("katana", .22, 7800), ("axe", .29, 4300)]:
            air = cloth_pass(take, duration, cutoff)
            yield f"{weapon}_swing_{take}", mix(duration, [(air, 1, 0)], -6)
            for heavy in [False, True]:
                speed = .88 if heavy else 1.0
                if weapon == "knife":
                    layers = [layer("impactSoft_medium", take, .8, 0, 1.3 * speed, 5000),
                              layer("crunch", take + 1, .2, .004, 1.5 * speed, 5800)]
                    length = .22
                elif weapon == "bat":
                    layers = [layer("impactPunch_medium", take, 1, 0, .95 * speed, 4200),
                              layer("impactSoft_heavy", take + 1, .52, .005, speed, 2800)]
                    length = .34
                elif weapon == "katana":
                    layers = [layer("impactSoft_medium", take, .75, 0, 1.18 * speed, 5400),
                              layer("crunch", take + 1, .46, .006, 1.3 * speed, 7000)]
                    length = .29
                else:
                    layers = [layer("impactPunch_medium", take, .85, 0, .83 * speed, 3800),
                              layer("impactSoft_heavy", take + 1, .65, .004, .9 * speed, 2800),
                              layer("crunch", take + 2, .4, .009, .94 * speed, 6000)]
                    length = .39
                yield f"{weapon}_{'heavy' if heavy else 'hit'}_{take}", mix(length, layers, -5)
        for weapon, speed in [("katana", 1.18), ("axe", .91)]:
            # A complete replacement contact, not an extra full-volume impact.
            layers = [layer("impactPunch_medium", take, .55, 0, speed, 4800),
                      layer("impactSoft_heavy", take + 1, .48, .003, speed, 3500),
                      layer("crunch", take + 2, .8, .008, speed, 7000),
                      layer("impactSoft_medium", take + 3, .2, .065, 1.1, 6000)]
            yield f"{weapon}_sever_{take}", mix(.46, layers, -5)
        yield f"landing_{take}", mix(.30, [
            layer("impactSoft_medium", take, 1, 0, .82, 3200),
            layer("footstep_concrete", take + 1, .25, .006, .95, 3800)], -7)


def build():
    output = ROOT / "audio/melee_foley"
    output.mkdir(exist_ok=True)
    report = []
    for name, samples in designs():
        path = output / f"{name}.wav"
        sf.write(path, samples, RATE, subtype="PCM_16")
        resource = "res://" + path.relative_to(ROOT).as_posix()
        imported = "res://.godot/imported/" + path.name + "-" + hashlib.md5(resource.encode()).hexdigest() + ".sample"
        settings = f'''[remap]

importer="wav"
type="AudioStreamWAV"
path="{imported}"

[deps]

source_file="{resource}"
dest_files=["{imported}"]

[params]

force/8_bit=false
force/mono=true
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=0
edit/loop_begin=0
edit/loop_end=-1
compress/mode=0
'''
        # Preserve a UID if a later Godot import has already assigned one.
        import_path = Path(str(path) + ".import")
        if not import_path.exists():
            import_path.write_text(settings, encoding="utf-8")
        report.append({"file": path.name, "seconds": len(samples) / RATE,
                       "peak_dbfs": round(float(20 * np.log10(np.max(np.abs(samples)))), 2),
                       "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    (output / "bank.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Built {len(report)} mono PCM melee clips at {RATE} Hz.")


if __name__ == "__main__":
    build()
