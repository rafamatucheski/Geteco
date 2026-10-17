"""Caixa de ferramentas de mixagem para render crédito de geração de som (2026-10-16).

A geração cobra por segundo (ElevenLabs: ~40 créditos/s; cada geração já traz 4 variações), então
o jogo deve extrair o máximo de poucos clipes: fatiar, mudar tom e velocidade, filtrar,
empilhar camadas e fechar loops. Tudo aqui é numpy/scipy, mono, float32, 48 kHz.

Receitas (ver também tools/audio/slice_accel_layers.py):
- Um motor -> vários carros: `pitch` (±15% soa como outro motor) + `eq` (grave para muscle/diesel,
  agudo para moto) + `layer` com um ruído de escapamento.
- Subida de rpm -> camadas: `slice_` em janelas curtas + `loop_fuse` + `level`.
- Flutter / estouro -> variações: `pitch` ±10% e `gain` diferente por tomada, nunca a mesma duas vezes.
- Um ambiente -> vários lugares: `eq` passa-baixa (dentro de casa/túnel), `reverb_tail` (galpão).
- Distância: `distance` (passa-baixa + volume + atraso) faz o mesmo tiro soar longe sem nova geração.
"""
import numpy as np
from fractions import Fraction
from scipy.signal import butter, sosfilt, resample_poly, fftconvolve

R = 48000


def slice_(x, a, b, r=R):
    return x[int(a * r):int(b * r)].copy()


def pitch(x, factor):
    """factor > 1: mais agudo e mais curto (muda tom e duração juntos, como mudar o pitch_scale)."""
    fr = Fraction(1.0 / factor).limit_denominator(200)
    return resample_poly(x, fr.numerator, fr.denominator).astype("float32")


def stretch_loop(x, seconds):
    """Repete até `seconds` (para estender um trecho estável sem pagar mais geração)."""
    return np.tile(x, int(np.ceil(seconds * R / len(x))))[:int(seconds * R)]


def eq(x, low=None, high=None, order=2):
    """Passa-baixa em `low` Hz e/ou passa-alta em `high` Hz."""
    y = x
    if low: y = sosfilt(butter(order, low, "low", fs=R, output="sos"), y)
    if high: y = sosfilt(butter(order, high, "high", fs=R, output="sos"), y)
    return y.astype("float32")


def bandboost(x, lo, hi, db):
    band = eq(x, low=hi, high=lo)
    return (x + band * (10 ** (db / 20) - 1)).astype("float32")


def gain(x, db):
    return (x * 10 ** (db / 20)).astype("float32")


def level(x, rms_db=None, peak_db=None):
    """Casa o nível: rms alvo e/ou pico alvo (o menor dos dois manda)."""
    y = x - np.mean(x)
    if rms_db is not None: y = y * (10 ** (rms_db / 20) / (np.sqrt(np.mean(y ** 2)) + 1e-12))
    if peak_db is not None:
        pk = np.max(np.abs(y)) + 1e-12
        cap = 10 ** (peak_db / 20)
        if rms_db is None or pk > cap: y = y * (cap / pk)
    return y.astype("float32")


def fade(x, inn=0.0, out=0.05):
    y = x.copy()
    a, b = int(inn * R), int(out * R)
    if a: y[:a] *= np.linspace(0, 1, a)
    if b: y[-b:] *= np.linspace(1, 0, b)
    return y


def loop_fuse(x, xf=0.12):
    """Loop sem emenda: o final se funde no começo com potência igual."""
    k = int(xf * R); n = len(x) - k
    t = np.linspace(0, 1, k, endpoint=False)
    y = x[:n].copy(); y[:k] = x[:k] * np.sin(t * np.pi / 2) + x[n:n + k] * np.cos(t * np.pi / 2)
    return (y - y.mean()).astype("float32")


def layer(*parts):
    """parts = (sinal, atraso_s, ganho_db); soma tudo no tamanho do mais longo."""
    n = max(int((d + len(s) / R) * R) for s, d, _ in parts)
    out = np.zeros(n, dtype="float32")
    for s, d, g in parts:
        i = int(d * R); out[i:i + len(s)] += s * 10 ** (g / 20)
    return out


def reverb_tail(x, seconds=0.8, wet=0.25, seed=1):
    """Cauda de reverb barata (ruído com decaimento exponencial convoluído)."""
    rng = np.random.default_rng(seed)
    n = int(seconds * R)
    ir = rng.standard_normal(n) * np.exp(-np.linspace(0, 7, n))
    ir = eq(ir.astype("float32"), low=6000)
    return (x + wet * fftconvolve(x, ir / np.sqrt(np.sum(ir ** 2)))[:len(x)]).astype("float32")


def distance(x, meters):
    """O mesmo som, mais longe: some o agudo, cai o volume e chega atrasado (340 m/s)."""
    y = eq(x, low=max(1500.0, 16000.0 / (1 + meters / 25.0)))
    y = gain(y, -6.0 * np.log2(1 + meters / 10.0))
    return np.concatenate([np.zeros(int(meters / 340.0 * R), dtype="float32"), y])


def variations(x, n=3, pitch_spread=0.06, gain_spread_db=1.5, seed=7):
    """n tomadas diferentes a partir de uma: tom e ganho levemente sorteados."""
    rng = np.random.default_rng(seed)
    return [gain(pitch(x, 1 + rng.uniform(-pitch_spread, pitch_spread)), rng.uniform(-gain_spread_db, gain_spread_db)) for _ in range(n)]


def wsola(x, ratio, win_s=0.04, search_s=0.008):
    """Estica/encurta no tempo SEM mudar o tom (ratio = duração_saída / duração_entrada).
    Janelas de 40 ms alinhadas por correlação: bom para motor (som periódico)."""
    win = int(win_s * R); hop_out = win // 2; search = int(search_s * R)
    hop_in = hop_out / ratio
    n_out = int(len(x) * ratio) + win
    y = np.zeros(n_out + win, dtype=np.float64); norm = np.zeros_like(y)
    w = np.hanning(win)
    pos_in = 0.0; prev = None; i_out = 0
    while i_out + win < n_out and int(pos_in) + win + search < len(x):
        base = int(pos_in)
        if prev is None:
            start = base
        else:
            lo = max(0, base - search); hi = min(len(x) - win, base + search)
            ref = x[prev:prev + win]
            seg = x[lo:hi + win]
            c = np.correlate(seg, ref, "valid")
            start = lo + int(np.argmax(c))
        y[i_out:i_out + win] += x[start:start + win] * w; norm[i_out:i_out + win] += w
        prev = start + hop_out if start + hop_out + win < len(x) else start
        pos_in += hop_in; i_out += hop_out
    norm[norm < 1e-3] = 1.0
    return (y / norm)[:int(len(x) * ratio)].astype("float32")


def ramp_resample(x, speed_a, speed_b):
    """Leitura com velocidade que vai de speed_a a speed_b (muda tom e duração juntos, suave):
    é o que o rpm faz com o som do motor."""
    # velocidade como função da posição relativa na entrada
    n = len(x); out = []; pos = 0.0
    while pos < n - 2:
        s = speed_a + (speed_b - speed_a) * (pos / n)
        out.append(pos); pos += s
    p = np.array(out); j = p.astype(int); f = p - j
    return (x[j] * (1 - f) + x[j + 1] * f).astype("float32")


def xfade_join(parts, xf=0.03):
    """Junta trechos com fusão de potência igual."""
    k = int(xf * R); out = parts[0]
    t = np.linspace(0, 1, k)
    for p in parts[1:]:
        out = np.concatenate([out[:-k], out[-k:] * np.cos(t * np.pi / 2) + p[:k] * np.sin(t * np.pi / 2), p[k:]])
    return out.astype("float32")
