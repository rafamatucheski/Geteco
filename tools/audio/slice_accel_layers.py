"""Fatia uma arrancada gerada no ElevenLabs em camadas de rpm + efeitos de turbo (2026-10-16).

Em vez de gerar 7 loops de rpm fixo, usa-se UMA subida de rpm (ex.: 2JZ_ACELERACAO_b): cada
janela curta da subida vira uma camada (loop sem emenda, rms -12,2 dB como as camadas de
audio/acoustic) e o resto vira efeitos soltos (spool, flutter). Faixas além do rpm que o clipe
alcança saem de subir o tom da última camada (reamostragem).
Uso: python tools/audio/slice_accel_layers.py <wav> <saida_dir> <familia>
"""
import os, sys
import numpy as np, soundfile as sf
from scipy.signal import resample_poly
from fractions import Fraction

src, out, fam = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
x, R = sf.read(src, always_2d=True, dtype="float32"); m = x.mean(axis=1)

def seg(a, b): return m[int(a * R):int(b * R)].copy()
def fuse(s, xf=0.12):
    k = int(xf * R); n = len(s) - k; t = np.linspace(0, 1, k, endpoint=False)
    o = s[:n].copy(); o[:k] = s[:k] * np.sin(t * np.pi / 2) + s[n:n + k] * np.cos(t * np.pi / 2); return o - o.mean()
def level(s, db=-12.2):
    y = s * (10 ** (db / 20) / np.sqrt(np.mean(s ** 2))); pk = np.max(np.abs(y)); return y * (0.89 / pk) if pk > 0.89 else y
def pitch(s, f):  # f>1 = mais agudo e mais curto
    fr = Fraction(1 / f).limit_denominator(100); return resample_poly(s, fr.numerator, fr.denominator).astype("float32")
def tile(s, sec):
    return np.tile(s, int(np.ceil(sec * R / len(s))))[:int(sec * R)]

idle = fuse(seg(9.0, 11.2), 0.3)
l1, l2, l3, l4 = fuse(seg(1.0, 1.6)), fuse(seg(2.5, 3.1)), fuse(seg(3.0, 3.6)), fuse(seg(3.4, 4.0))
layers = [idle, l1, l2, l3, l4, fuse(pitch(seg(3.4, 4.2), 1.3)), fuse(pitch(seg(3.4, 4.3), 1.6))]
for i, l in enumerate(layers):
    sf.write(os.path.join(out, f"engine_{fam}_{i}.wav"), level(l), R, subtype="PCM_16")
sf.write(os.path.join(out, f"turbo_spool_{fam}.wav"), level(seg(0.2, 3.9), -14), R, subtype="PCM_16")
sf.write(os.path.join(out, f"turbo_flutter_{fam}.wav"), level(seg(3.9, 6.6), -14), R, subtype="PCM_16")
demo = np.concatenate([np.concatenate([tile(level(l), 2.0), np.zeros(int(0.1 * R), dtype="float32")]) for l in layers] + [np.zeros(R, dtype="float32"), level(seg(0.2, 7.0), -14)])
sf.write(os.path.join(out, f"DEMO_{fam}.wav"), demo, R, subtype="PCM_16"); print(len(demo) / R, "s")
