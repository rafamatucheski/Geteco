"""Gera um loop original de correnteza; não depende de downloads."""
from pathlib import Path
import subprocess
import tempfile

import imageio_ffmpeg
import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT = Path(__file__).resolve().parents[1]
RATE = 32000
DURATION = 26
rng = np.random.default_rng(91026)
count = RATE * (DURATION + 2)
t = np.arange(count) / RATE
channels = []
for channel in range(2):
    noise = rng.normal(size=count)
    rush = signal.sosfilt(signal.butter(2, [280, 4600], btype="bandpass", fs=RATE, output="sos"), noise)
    low = signal.sosfilt(signal.butter(2, [120, 700], btype="bandpass", fs=RATE, output="sos"), noise)
    bed = rush * (0.19 + 0.04 * np.sin(t * 1.3 + channel)) + low * 0.14
    # Pequenos borbulhos irregulares sobre o escoamento, sem pulsação mecânica.
    for _ in range(650):
        start = int(rng.uniform(0, count - RATE // 3))
        length = int(rng.uniform(0.035, 0.15) * RATE)
        tick = np.arange(length) / RATE
        frequency = rng.uniform(450, 2100)
        bubble = np.sin(2 * np.pi * (frequency * tick - frequency * 1.4 * tick**2))
        bubble *= (1 - np.exp(-tick * 500)) * np.exp(-tick * rng.uniform(35, 75))
        bed[start:start+length] += bubble * rng.uniform(0.025, 0.11)
    channels.append(bed)
audio = np.stack(channels, axis=1)
overlap = RATE * 2
fade = np.linspace(0, 1, overlap)[:, None]
audio[:overlap] = audio[-overlap:] * (1 - fade) + audio[:overlap] * fade
audio = audio[:-overlap]
audio *= 0.65 / np.max(np.abs(audio))
output = ROOT / "audio/water/flow.ogg"
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as temp:
    wav = Path(temp) / "flow.wav"
    wavfile.write(wav, RATE, (audio * 32767).astype(np.int16))
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "5", str(output)], check=True)
print(f"{output}: {DURATION}s, peak={np.max(np.abs(audio)):.3f}, RMS={np.sqrt(np.mean(audio**2)):.3f}")
