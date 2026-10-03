"""Bake an original, loopable ice-cream music-box phrase. Standard library only."""
import math
import struct
import wave
from pathlib import Path

RATE = 22050
BEAT = 0.32
NOTES = [76, 79, 84, 79, 81, 77, 74, 77, 79, 76, 72, 76, 74, 71, 67, None,
         76, 79, 84, 86, 84, 81, 77, 74, 79, 76, 74, 71, 72, None, None, None]
duration = len(NOTES) * BEAT
pcm = []
for i in range(round(RATE * duration)):
    time = i / RATE
    note_index = min(int(time / BEAT), len(NOTES) - 1)
    value = 0.0
    for index in range(max(0, note_index - 2), note_index + 1):
        note = NOTES[index]
        if note is None:
            continue
        age = time - index * BEAT
        frequency = 440 * 2 ** ((note - 69) / 12)
        envelope = min(1.0, age / 0.008) * math.exp(-age * 8)
        value += envelope * (math.sin(math.tau * frequency * age)
                             + .22 * math.sin(math.tau * frequency * 2 * age)
                             + .10 * math.sin(math.tau * frequency * 3 * age)) * .37
    pcm.append(struct.pack('<h', round(max(-1, min(1, value)) * 32767)))
target = Path(__file__).resolve().parents[1] / 'audio' / 'icecream' / 'jingle.wav'
target.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(target), 'wb') as out:
    out.setnchannels(1)
    out.setsampwidth(2)
    out.setframerate(RATE)
    out.writeframes(b''.join(pcm))
print(f'{target}: {duration:.2f}s, mono, {RATE} Hz')
