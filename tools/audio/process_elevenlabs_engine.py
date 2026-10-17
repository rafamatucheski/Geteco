"""Camadas de motor geradas no ElevenLabs (2026-10-16) -> audio/engine_el/engine_<familia>_<0..6>.wav.

O jogo mistura 7 camadas por família (marcha lenta ... corte) trocando por velocidade e
ajustando o tom pelo giro. Cada camada aqui é um trecho de rpm constante (~4,4 s), sem os
primeiros 0,2 s (ataque da geração), fundido nele mesmo em loop sem emenda (potência igual,
0,5 s) e com o mesmo nível (rms -12,2 dB) das camadas antigas de audio/acoustic.
EngineBankCache usa esta pasta quando a família existe nela; apagar a pasta volta ao banco antigo.
Uso: python tools/audio/process_elevenlabs_engine.py <familia> <wav0> ... <wav6>   (do grave ao agudo)
"""
import os, sys, shutil
import numpy as np, soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
family, files = sys.argv[1], sys.argv[2:]
assert len(files) == 7, "são 7 camadas"
OUT = os.path.join(ROOT, "audio", "engine_el"); os.makedirs(OUT, exist_ok=True)
KEEP = os.path.join(ROOT, "evidence", "elevenlabs_originais_20261016", "motor_" + family); os.makedirs(KEEP, exist_ok=True)
for i, f in enumerate(files):
    shutil.copy2(f, os.path.join(KEEP, f"{i}_" + os.path.basename(f).replace(".tmp", ".wav")))
    x, r = sf.read(f, always_2d=True, dtype="float32"); m = x.mean(axis=1)[int(0.2 * r):]
    xf = int(0.5 * r); k = len(m) - xf; t = np.linspace(0, 1, xf, endpoint=False)
    loop = m[:k].copy(); loop[:xf] = m[:xf] * np.sin(t * np.pi / 2) + m[k:k + xf] * np.cos(t * np.pi / 2)
    loop -= loop.mean()
    y = loop * (10 ** (-12.2 / 20) / np.sqrt(np.mean(loop ** 2)))
    pk = np.max(np.abs(y)); y = y * (0.89 / pk) if pk > 0.89 else y
    sf.write(os.path.join(OUT, f"engine_{family}_{i}.wav"), y, r, subtype="PCM_16")
    print(i, f"{len(y) / r:.2f}s rms={20 * np.log10(np.sqrt(np.mean(y ** 2))):.1f}dB pk={20 * np.log10(np.max(np.abs(y))):.1f}dB")
