"""Escape diesel original e flutter de turbo de dois pulsos para a Amarok do Digo, offline."""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "audio" / "digo"
OUT.mkdir(parents=True, exist_ok=True)

def save(name, samples):
    peak = max(abs(v) for v in samples)
    data = b"".join(struct.pack("<h", round(v / max(peak, 1e-6) * 26000)) for v in samples)
    with wave.open(str(OUT / name), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(data)

rng = random.Random(2014)
samples = []
for i in range(RATE * 2):
    t = i / RATE
    # Bancos periódicos de frequência inteira dão um ciclo de escape de dois segundos sem emenda.
    phase = math.tau * 28 * t
    firing = (0.5 + 0.5 * math.sin(phase)) ** 5
    rumble = math.sin(math.tau * 56 * t) * .42 + math.sin(math.tau * 84 * t) * .21
    rasp = sum(math.sin(math.tau * f * t) * g for f, g in [(196,.11),(308,.08),(476,.05),(756,.025)])
    samples.append(rumble * .7 + firing * rasp * 2.2)
save("amarok_exhaust.wav", samples)

samples = []
phase = 0.0
for i in range(int(RATE * .72)):
    t = i / RATE
    v = 0.0
    for start, gain in [(0.0, 1.0), (.28, .72)]:
        local = t - start
        if 0 <= local < .32:
            envelope = math.sin(math.pi * min(local / .025, 1) / 2) * math.exp(-local * 12)
            phase_value = math.tau * (1350 * local - 1450 * local * local)
            v += gain * envelope * (math.sin(phase_value) * .65 + rng.uniform(-1,1) * .2)
    samples.append(v * min(1,(.72-t)*80))
save("amarok_turbo_release.wav", samples)
print("Generated", OUT)
