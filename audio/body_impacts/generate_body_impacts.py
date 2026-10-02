"""Original contact Foley, generated offline with the Python standard library.

Run: python audio/body_impacts/generate_body_impacts.py
Six short mono PCM clips: weight, a dry contact and a little clothing/grit.
No third-party recordings, dependencies or runtime sound synthesis.
"""

import math
from pathlib import Path
import random
import struct
import wave


RATE = 24000
ROOT = Path(__file__).resolve().parent


def clip(kind, take):
    rng = random.Random(40803 + take * 131 + (701 if kind == "body_land" else 0))
    landing = kind == "body_land"
    duration = (0.42 + take * 0.04) if landing else (0.34 + take * 0.03)
    values = []
    low = mid = phase = 0.0
    for index in range(round(RATE * duration)):
        t = index / RATE
        raw = rng.uniform(-1.0, 1.0)
        low += 0.047 * (raw - low)
        mid += 0.34 * (raw - mid)
        frequency = (54 if landing else 68) + (30 + take * 4) * math.exp(-t * 25)
        phase += 2 * math.pi * frequency / RATE
        weight = (0.65 * math.sin(phase) + low * 1.9) * math.exp(-t * 17)
        contact = (mid * 1.3 + (raw - mid) * 0.17) * math.exp(-t * 72)
        fabric = (raw - mid) * 0.10 * math.exp(-t * 22)
        value = weight + contact + fabric
        if landing:
            # A torso settles after the initial contact; these are one sound,
            # not extra voices or delayed runtime callbacks.
            for at, amplitude in ((0.032, 0.16), (0.071, 0.08)):
                age = t - at - take * 0.002
                if age >= 0:
                    value += mid * amplitude * math.exp(-age * 42)
            value += mid * 0.18 * math.exp(-t * 13)
        else:
            # Very short dull panel response under the clothed-body impact.
            value += 0.13 * math.sin(2 * math.pi * (183 + take * 9) * t) * math.exp(-t * 39)
            value += mid * 0.15 * math.exp(-t * 20)
        value = math.tanh(value * 1.3)
        value *= min(1.0, t / 0.0015, (duration - t) / 0.04)
        values.append(value)
    peak = max(abs(value) for value in values)
    values = [value * 0.78 / peak for value in values]
    values[0] = values[-1] = 0.0
    pcm = struct.pack("<%dh" % len(values), *(round(value * 32767) for value in values))
    path = ROOT / ("%s_%d.wav" % (kind, take))
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)
    rms = math.sqrt(sum(value * value for value in values) / len(values))
    print("%s %.2fs peak=%.1fdBFS rms=%.1fdBFS %d bytes" %
          (path.name, duration, 20 * math.log10(0.78), 20 * math.log10(rms), len(pcm)))


if __name__ == "__main__":
    for family in ("body_hit", "body_land"):
        for variant in range(3):
            clip(family, variant)
