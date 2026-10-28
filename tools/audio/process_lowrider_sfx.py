"""Bomba da hidráulica do lowrider a partir do mastro hidráulico da empilhadeira (Firefly, 15/10,
audio/forklift/mast_*.wav, ~4 s, nunca ligado no jogo). Cada movimento da hidráulica dura 0,3-0,7 s,
então cada tomada é o trecho mais forte de 0,9 s do mastro, com entrada curta e saída de 0,3 s.
O mastro 1 sai quase sem corpo (rms 0,05) e fica de fora.

Uso: python -I tools/audio/process_lowrider_sfx.py
"""
import os
import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "audio", "forklift", "mast_%d.wav")
DST = os.path.join(ROOT, "audio", "lowrider", "pump_%d.wav")
TAKES = [2, 3, 0]
LENGTH = 0.9
FADE_IN = 0.015
FADE_OUT = 0.3
PEAK = 0.55


def loudest(x, rate, seconds):
    win = int(seconds * rate)
    hop = int(0.05 * rate)
    energy = [float(np.sum(x[i:i + win] ** 2)) for i in range(0, len(x) - win, hop)]
    start = int(np.argmax(energy)) * hop
    return x[start:start + win].copy()


if __name__ == "__main__":
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    for out, take in enumerate(TAKES):
        x, rate = sf.read(SRC % take, dtype="float32")
        y = loudest(x, rate, LENGTH)
        y[:int(FADE_IN * rate)] *= np.linspace(0, 1, int(FADE_IN * rate))
        n = int(FADE_OUT * rate)
        y[-n:] *= np.cos(np.linspace(0, np.pi / 2, n))
        y *= PEAK / float(np.max(np.abs(y)))
        sf.write(DST % out, y, rate, subtype="PCM_16")
        print(os.path.basename(DST % out), f"mastro {take}, {len(y) / rate:.2f} s, rms {np.sqrt(np.mean(y ** 2)):.3f}")
