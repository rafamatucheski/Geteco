"""Original deterministic tire textures, rendered offline; no synthesis in gameplay."""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
COUNT = RATE * 4


def render(kind, seed):
    rng = random.Random(seed)
    low = mid = grains = 0.0
    values = []
    for i in range(COUNT + 2048):
        noise = rng.uniform(-1, 1)
        low += .025 * (noise - low)
        mid += .22 * (noise - mid)
        grains *= .86 if kind == "dirt" else .96
        if rng.random() < (.012 if kind == "dirt" else .003):
            grains += rng.uniform(-.6, .6)
        t = i / RATE
        flutter = .8 + .12 * math.sin(math.tau * 3.25 * t) + .08 * math.sin(math.tau * 7 * t)
        if kind == "grass":
            value = (low * 1.8 + mid * .48 + grains * .14) * flutter
        elif kind == "dirt":
            value = low * 1.3 + mid * .65 + grains * .55
        elif kind == "snow":
            value = (mid * .65 + low * 1.7 + grains * .12) * flutter
        else:  # Wet tire spray: broadband hiss without gravel transients.
            value = (noise - mid) * .3 + low * 1.2
        if i >= 2048:
            values.append(value)
    # Equal-power overlap removes the loop seam without a recurring silence.
    overlap = 1024
    for i in range(overlap):
        blend = i / overlap
        values[i] = values[-overlap + i] * math.cos(blend * math.pi / 2) + values[i] * math.sin(blend * math.pi / 2)
    values = values[:-overlap]
    rms = math.sqrt(sum(v * v for v in values) / len(values))
    gain = min(.16 / rms, .82 / max(abs(v) for v in values))
    path = Path(__file__).parent / f"tire_{kind}.wav"
    with wave.open(str(path), "wb") as output:
        output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(b"".join(struct.pack("<h", round(v * gain * 32767)) for v in values))


if __name__ == "__main__":
    for seed, kind in enumerate(("grass", "dirt", "snow", "wet"), 701):
        render(kind, seed)
