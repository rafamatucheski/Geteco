"""Generate original, deterministic vehicle/body Foley (no external samples)."""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
for take in range(3):
    rng = random.Random(714 + take)
    samples = []
    low = 0.0
    for i in range(int(RATE * 0.38)):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low += 0.24 * (noise - low)
        attack = 1 - math.exp(-t * 1800)
        thump = math.sin(math.tau * ((94 - take * 5) * t - 65 * t * t)) * math.exp(-t * 21)
        slap = (low * 1.9 + noise * 0.17) * math.exp(-t * 38)
        tail = 0.0
        for delay in (0.026, 0.051, 0.083):
            u = t - delay
            if u > 0:
                tail += low * 0.65 * (1 - math.exp(-u * 1700)) * math.exp(-u * 65)
        samples.append(attack * (0.66 * thump + 0.65 * slap + tail))
    peak = max(abs(v) for v in samples)
    pcm = b''.join(struct.pack('<h', round(v / peak * 29200)) for v in samples)
    with wave.open(str(Path(__file__).with_name(f'body_{take}.wav')), 'wb') as out:
        out.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        out.writeframes(pcm)
