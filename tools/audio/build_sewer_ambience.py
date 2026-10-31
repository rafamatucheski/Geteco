"""Fundo de esgoto determinístico e sem emenda: fluxo fechado, gotas irregulares e reflexões."""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 22050
SECONDS = 16
COUNT = RATE * SECONDS
rng = random.Random(71012)
left = [0.0] * COUNT
right = [0.0] * COUNT
low = 0.0
for i in range(COUNT):
    low = low * .96 + rng.uniform(-1, 1) * .04
    flow = low * .55 + rng.uniform(-1, 1) * .018
    pulse = .85 + .15 * math.sin(math.tau * i / COUNT * 3)
    left[i] = flow * pulse
    right[i] = flow * pulse

for _ in range(43):
    start = rng.randrange(COUNT)
    pitch = rng.uniform(520, 1500)
    gain = rng.uniform(.045, .13)
    pan = rng.uniform(.2, .8)
    for delay, level in [(0, 1), (.079, .33), (.137, .22), (.251, .13), (.411, .07)]:
        for j in range(int(RATE * .19)):
            t = j / RATE
            drop = math.sin(math.tau * (pitch * t - 680 * t * t))
            drop += rng.uniform(-.3, .3) * math.exp(-t * 85)
            value = drop * math.exp(-t * 34) * min(1, t * 1700) * gain * level
            index = (start + int(delay * RATE) + j) % COUNT
            left[index] += value * math.sqrt(pan)
            right[index] += value * math.sqrt(1 - pan)

# Um crossfade circular curto tira a borda do ruído sem silenciar o loop.
fade = int(.08 * RATE)
for channel in [left, right]:
    for j in range(fade):
        amount = j / fade
        channel[COUNT - fade + j] = channel[COUNT - fade + j] * (1 - amount) + channel[j] * amount

target = Path(__file__).resolve().parents[2] / 'audio/sewers/enclosed_flow.wav'
target.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(target), 'wb') as out:
    out.setparams((2, 2, RATE, 0, 'NONE', 'not compressed'))
    out.writeframes(b''.join(struct.pack('<hh', int(max(-1, min(1, a)) * 32767), int(max(-1, min(1, b)) * 32767)) for a, b in zip(left, right)))
print(target)
