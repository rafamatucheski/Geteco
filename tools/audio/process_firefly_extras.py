"""Trata os 5 efeitos finais do Firefly (2026-10-15): mastro e palete da empilhadeira, rotor e sobrevoo
do helicóptero, multidão do parque. Mono 48 kHz, corte de silêncio, fade, pico casado com o que o jogo
já tem, loops sem emenda (crossfade de potência igual). Originais em evidence/.../novos (fora do Git).

Uso: python tools/audio/process_firefly_extras.py
"""
import os
import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "evidence", "firefly_originais_20261015", "novos")


def mono(path):
    x, rate = sf.read(path, always_2d=True, dtype="float32")
    return x.mean(axis=1), rate


def trim(m, rate, lead=0.04, tail_db=-42.0, max_len=None):
    pk = float(np.max(np.abs(m)))
    start = max(0, int(np.argmax(np.abs(m) > lead * pk)) - int(0.003 * rate))
    m = m[start:]
    win = int(0.01 * rate)
    env = np.array([np.sqrt(np.mean(m[i:i + win] ** 2)) for i in range(0, len(m), win)])
    last = int(np.max(np.nonzero(env > pk * 10 ** (tail_db / 20))[0], initial=0))
    end = min(len(m), (last + 1) * win + int(0.05 * rate))
    if max_len: end = min(end, int(max_len * rate))
    return m[:end]


def fade(m, rate, fin, fout):
    m = m.copy()
    a, b = min(len(m) // 2, int(fin * rate)), min(len(m) // 2, int(fout * rate))
    if a: m[:a] *= np.linspace(0, 1, a)
    if b: m[-b:] *= np.linspace(1, 0, b)
    return m


def peak_to(m, target):
    return m * (target / float(np.max(np.abs(m))))


def rms_to(m, target, cap):
    m = m * (target / float(np.sqrt(np.mean(m ** 2))))
    pk = float(np.max(np.abs(m)))
    return m * (cap / pk) if pk > cap else m


def loop(m, rate, seconds):
    xf = int(seconds * rate)
    n = len(m) - xf
    out = m[:n].copy()
    t = np.linspace(0, 1, xf, endpoint=False)
    out[:xf] = m[:xf] * np.sin(t * np.pi / 2) + m[n:n + xf] * np.cos(t * np.pi / 2)
    return out


def save(path, m, rate):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sf.write(path, m, rate, subtype="PCM_16")
    print(os.path.relpath(path, ROOT), f"{len(m) / rate:.2f}s pico={np.max(np.abs(m)):.2f}")


def run():
    out = os.path.join(ROOT, "audio")
    # Empilhadeira: mastro hidráulico (tomadas curtas) e palete caindo (impacto: corta no ataque).
    for i in range(4):
        m, r = mono(os.path.join(SRC, "forklift_mast", f"take_{i}.wav"))
        save(os.path.join(out, "forklift", f"mast_{i}.wav"), peak_to(fade(trim(m, r, max_len=4.0), r, 0.01, 0.15), 0.55), r)
    for i in range(4):
        m, r = mono(os.path.join(SRC, "pallet_drop", f"take_{i}.wav"))
        save(os.path.join(out, "forklift", f"pallet_drop_{i}.wav"), peak_to(fade(trim(m, r, lead=0.15, tail_db=-36.0, max_len=2.0), r, 0.001, 0.2), 0.7), r)
    # Helicóptero: rotor em loop (rms parecido com a ambiência existente) e sobrevoo (sobe e some).
    for i in range(4):
        m, r = mono(os.path.join(SRC, "heli_rotor", f"take_{i}.wav"))
        save(os.path.join(out, "helicopter", f"rotor_loop_{i}.wav"), rms_to(loop(m, r, 1.0), 0.14, 0.6), r)
    for i in (0, 1):
        m, r = mono(os.path.join(SRC, "heli_flyover", f"take_{i}.wav"))
        save(os.path.join(out, "helicopter", f"flyover_{i}.wav"), peak_to(fade(trim(m, r, lead=0.02, tail_db=-45.0), r, 0.4, 1.5), 0.7), r)
    # Multidão do parque: loop baixinho; entra por baixo da música.
    for j, i in enumerate((0, 3)):
        m, r = mono(os.path.join(SRC, "park_crowd", f"take_{i}.wav"))
        save(os.path.join(out, "amusement_park", f"crowd_loop_{j}.wav"), rms_to(loop(m, r, 2.0), 0.05, 0.45), r)


if __name__ == "__main__":
    run()
