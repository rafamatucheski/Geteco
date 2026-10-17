"""2JZ-GTE: arrancada contínua pelas marchas, montada do próprio clipe B (sem camadas em loop).

A v1 (build_2jz_car.py) misturava loops curtos de 0,5 s: soava "patinando". Aqui cada subida é
um trecho CONTÍNUO do clipe B, esticado no tempo sem mudar o tom (WSOLA) e depois lido com uma
rampa de velocidade, que sobe o tom como o rpm sobe. O apito do turbo e o flutter são os do
próprio clipe (o turbo já enche com o giro nele); o flutter só é suavizado (passa-baixa, -4 dB).
Saída: evidence/preview_motor/carro_2jz_v3/DEMO_arrancada_v3.wav e as peças soltas.
"""
import os
import numpy as np, soundfile as sf
import sfx_mix as M
R = M.R
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "evidence", "preview_motor"); OUT = os.path.join(SRC, "carro_2jz_v3"); os.makedirs(OUT, exist_ok=True)
x, r = sf.read(os.path.join(SRC, "2JZ_ACELERACAO_b.wav"), always_2d=True, dtype="float32"); b = x.mean(axis=1)
S = lambda a, c: M.slice_(b, a, c)

idle = M.loop_fuse(S(9.0, 11.4), 0.4)
idle_in = np.concatenate([idle, idle])[:int(2.0 * R)]

# 1ª: o clipe todo da subida (1500->~4000 rpm), esticado a 3.0 s e com tom subindo até ~6600 (x1.65)
p1 = M.ramp_resample(M.wsola(S(0.30, 3.75), 3.0 / 3.45), 1.0, 1.65)
# trocas: o alívio natural do clipe (rpm cai, turbo solta), curto
cut1 = M.ramp_resample(S(3.75, 4.10), 1.70, 1.15)
# 2ª e 3ª: parte alta da subida (3200->4000), esticada, tom de x1.40 a x1.75 (~4500 -> 7000 rpm)
p2 = M.ramp_resample(M.wsola(S(2.30, 3.75), 2.6 / 1.45), 1.40, 1.75)
cut2 = M.ramp_resample(S(3.75, 4.10), 1.75, 1.20)
p3 = M.ramp_resample(M.wsola(S(2.45, 3.75), 2.6 / 1.30), 1.42, 1.78)
# alívio final: queda natural com o flutter do clipe, suavizado
lift = M.ramp_resample(S(3.75, 7.40), 1.78, 1.0)
lift = M.eq(lift, low=7500)
tail = M.loop_fuse(S(9.0, 11.4), 0.4)[:int(1.5 * R)]

parts = [idle_in, p1, cut1, p2, cut2, p3, lift, tail]
parts = [M.level(p, rms_db=-14.0) if i in (0, 7) else p for i, p in enumerate(parts)]
mix = M.xfade_join(parts, 0.04)
mix = M.level(mix, peak_db=-2.0)
sf.write(os.path.join(OUT, "DEMO_arrancada_v3.wav"), mix, R, subtype="PCM_16")
sf.write(os.path.join(OUT, "subida_1a.wav"), M.level(p1, peak_db=-2.0), R, subtype="PCM_16")
sf.write(os.path.join(OUT, "subida_2a.wav"), M.level(p2, peak_db=-2.0), R, subtype="PCM_16")

# checagem de continuidade: tom dominante a cada 0,1 s; salto grande = emenda audível
seg = mix
rows = []
for i in range(0, len(seg) - R // 5, R // 10):
    s = seg[i:i + R // 5] * np.hanning(R // 5); sp = np.abs(np.fft.rfft(s, 16384)); f = np.fft.rfftfreq(16384, 1 / R)
    band = (f > 50) & (f < 600); rows.append(f[band][np.argmax(sp[band])])
rows = np.array(rows); jumps = np.abs(np.diff(rows)) / np.maximum(rows[:-1], 1)
print("duração %.1fs" % (len(mix) / R), "| saltos de tom >35%%: %d de %d" % ((jumps > 0.35).sum(), len(jumps)))
