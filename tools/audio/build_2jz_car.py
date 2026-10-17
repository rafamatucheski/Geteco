"""Monta o 2JZ-GTE completo a partir do que já foi gerado (2026-10-16), sem crédito novo.

Fontes (evidence/preview_motor): 2JZ_ACELERACAO_b.wav (arrancada ~1500->4000 rpm com turbo e
flutter) e flutter/flutter_4.wav, flutter_2.wav (flutter dedicado).
Saídas em evidence/preview_motor/carro_2jz_v2:
  engine_2jz_0..6.wav   camadas de rpm (marcha lenta, baixa, média, alta; as duas últimas são a
                        mais alta com o tom subido), loops sem emenda, rms -12,2 dB
  whistle_loop.wav      só a faixa aguda do turbo (apito), loop; ganho e tom seguem o "boost"
  flutter_soft_0..2.wav flutter delicado (passa-baixa, curto, entrada e saída suaves)
  DEMO_arrancada.wav    simulação do mixer: marcha lenta, 1ª/2ª/3ª com trocas e alívio
O turbo só enche em giro alto e sob carga: boost = carga * smoothstep(3500..6500 rpm), com subida
lenta e descida rápida; o flutter só dispara ao aliviar (ou trocar de marcha) com boost alto.
"""
import os
import numpy as np, soundfile as sf
import sfx_mix as M

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "evidence", "preview_motor")
OUT = os.path.join(SRC, "carro_2jz_v2"); os.makedirs(OUT, exist_ok=True)
R = M.R


def load(p):
    x, r = sf.read(p, always_2d=True, dtype="float32"); assert r == R
    return x.mean(axis=1)


b = load(os.path.join(SRC, "2JZ_ACELERACAO_b.wav"))
fl4 = load(os.path.join(SRC, "flutter", "flutter_4.wav"))
fl2 = load(os.path.join(SRC, "flutter", "flutter_2.wav"))

# --- camadas de rpm (rpm que cada uma representa, estimado pela frequência de ignição) ---
LAYER_RPM = [1500, 2850, 3150, 3650, 3900, 5000, 6200]
raw = [
    M.loop_fuse(M.slice_(b, 9.0, 11.2), 0.3),
    M.loop_fuse(M.slice_(b, 1.0, 1.6)), M.loop_fuse(M.slice_(b, 2.5, 3.1)),
    M.loop_fuse(M.slice_(b, 3.0, 3.6)), M.loop_fuse(M.slice_(b, 3.4, 4.0)),
    M.loop_fuse(M.pitch(M.slice_(b, 3.4, 4.2), 1.3)), M.loop_fuse(M.pitch(M.slice_(b, 3.4, 4.3), 1.6)),
]
layers = [M.level(l, rms_db=-12.2, peak_db=-1.0) for l in raw]
for i, l in enumerate(layers):
    sf.write(os.path.join(OUT, f"engine_2jz_{i}.wav"), l, R, subtype="PCM_16")

# --- apito do turbo: só a faixa aguda da parte com carga ---
whistle = M.loop_fuse(M.eq(M.slice_(b, 2.6, 3.9), low=9000, high=2500, order=3), 0.2)
whistle = M.level(whistle, rms_db=-20.0, peak_db=-3.0)
sf.write(os.path.join(OUT, "whistle_loop.wav"), whistle, R, subtype="PCM_16")

# --- flutter delicado ---
def soft_flutter(src, start, length, pitch_f):
    s = M.slice_(src, start, start + length)
    s = M.pitch(s, pitch_f)
    s = M.eq(s, low=7000, high=250)
    return M.fade(M.level(s, peak_db=-14.0), inn=0.03, out=0.35)

flutters = [soft_flutter(fl4, 0.0, 1.6, 1.0), soft_flutter(fl2, 0.0, 1.4, 0.96), soft_flutter(fl4, 0.15, 1.2, 1.05)]
for i, f in enumerate(flutters):
    sf.write(os.path.join(OUT, f"flutter_soft_{i}.wav"), f, R, subtype="PCM_16")


# --- simulação do mixer ---
def smooth(a, b_, x):
    t = np.clip((x - a) / (b_ - a), 0, 1); return t * t * (3 - 2 * t)


def render(timeline):
    """timeline: lista de (duração_s, rpm_inicial, rpm_final, carga). Devolve rpm[], carga[] por amostra."""
    rpm, load = [], []
    for dur, r0, r1, ld in timeline:
        n = int(dur * R); rpm.append(np.linspace(r0, r1, n)); load.append(np.full(n, ld, dtype=float))
    return np.concatenate(rpm), np.concatenate(load)


timeline = [
    (2.0, 1500, 1500, 0.0),      # marcha lenta
    (2.2, 1500, 6800, 1.0),      # 1ª a fundo
    (0.30, 6800, 4300, 0.0),     # troca 1->2 (corta, rpm cai)
    (3.0, 4300, 6900, 1.0),      # 2ª
    (0.30, 6900, 4600, 0.0),     # troca 2->3
    (3.2, 4600, 7000, 1.0),      # 3ª
    (1.6, 7000, 2400, 0.0),      # alivia: rpm cai, turbo esvazia, flutter
    (2.0, 2400, 1500, 0.0),      # volta à marcha lenta
]
rpm, load = render(timeline)
N = len(rpm); t = np.arange(N) / R

# boost com subida lenta (turbo enche) e descida mais rápida
target = load * smooth(3500, 6500, rpm)
boost = np.zeros(N)
for i in range(1, N):
    k = (1 / (0.9 * R)) if target[i] > boost[i - 1] else (1 / (0.35 * R))
    boost[i] = boost[i - 1] + (target[i] - boost[i - 1]) * k

# motor: leitura de cada camada com velocidade rpm/rpm_da_camada, pesos triangulares em log(rpm)
lr = np.log(np.array(LAYER_RPM, dtype=float)); lrpm = np.log(np.clip(rpm, LAYER_RPM[0] * 0.8, LAYER_RPM[-1] * 1.15))
engine = np.zeros(N, dtype=np.float64)
wsum = np.zeros(N)
for i, l in enumerate(layers):
    lo = lr[i - 1] if i > 0 else lr[0] - 0.5
    hi = lr[i + 1] if i < len(lr) - 1 else lr[-1] + 0.5
    w = np.where(lrpm <= lr[i], (lrpm - lo) / (lr[i] - lo), (hi - lrpm) / (hi - lr[i]))
    w = np.clip(w, 0, 1)
    speed = np.clip(rpm / LAYER_RPM[i], 0.55, 1.8)
    pos = np.cumsum(speed) % len(l)
    j = pos.astype(int); fr = pos - j
    sig = l[j] * (1 - fr) + l[(j + 1) % len(l)] * fr
    engine += w * sig; wsum += w
engine = (engine / np.maximum(wsum, 1e-6)).astype("float32")
# carga mexe no volume: aliviando o motor fica mais baixo e grave
engine *= (0.55 + 0.45 * np.clip(load + 0.15, 0, 1)).astype("float32")

# apito: ganho ~ boost^1.5, tom sobe com o boost (0.75 .. 1.45)
wspeed = 0.75 + 0.7 * boost
wpos = np.cumsum(wspeed) % len(whistle); wj = wpos.astype(int); wf = wpos - wj
wh = (whistle[wj] * (1 - wf) + whistle[(wj + 1) % len(whistle)] * wf) * (boost ** 1.5)
mix = engine + M.gain(wh.astype("float32"), -3.0)

# flutter delicado: ao aliviar (queda de carga) ou trocar com boost alto
events = []
prev = 0.0
for i in range(1, N):
    if load[i - 1] > 0.5 and load[i] < 0.5 and boost[i] > 0.55:
        events.append((i / R, boost[i]))
for when, bst in events:
    k = len(events)
for idx, (when, bst) in enumerate(events):
    f = flutters[idx % len(flutters)]
    big = rpm[int(when * R)] > 5500 and idx == len(events) - 1       # só o alívio final é "inteiro"
    f = f if big else M.gain(f[:int(0.7 * R)], -5.0)                  # nas trocas, só um sopro curto
    f = M.fade(f, 0.02, 0.25)
    i0 = int(when * R) + int(0.06 * R)
    n = min(len(f), N - i0)
    mix[i0:i0 + n] += f[:n] * float(np.clip(bst, 0.5, 1.0))
mix = M.level(mix, peak_db=-2.0)
sf.write(os.path.join(OUT, "DEMO_arrancada.wav"), mix, R, subtype="PCM_16")
print("ok", N / R, "s;", len(events), "eventos de flutter nos instantes", [round(e[0], 2) for e in events])
