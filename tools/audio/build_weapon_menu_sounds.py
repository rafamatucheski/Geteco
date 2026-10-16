"""Sons de arma que faltavam (magnum, smg, serrada, rifle de caça) e o trio de menu (2026-10-16).

As armas novas saem dos tiros do Firefly já tratados (pitch, camada de corpo, cauda): o
Firefly estava sem créditos. O menu ganha UM som de troca, UM de confirmar e UM de voltar,
sintetizados (sino curto), no lugar das 4 tomadas aleatórias que soavam como bipe.
Originais do menu vão para evidence/menu_antigo_20261016 (fora do Git).
Uso: python tools/audio/build_weapon_menu_sounds.py
"""
import os, shutil, glob
import numpy as np, soundfile as sf
from scipy.signal import resample_poly, butter, sosfilt
from fractions import Fraction

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WF = os.path.join(ROOT, "audio", "weapons_fire")
MENU = os.path.join(ROOT, "audio", "menu")
R = 48000

def load(name):
    x, r = sf.read(os.path.join(WF, name), dtype="float32", always_2d=True)
    assert r == R
    return x.mean(axis=1)

def speed(x, f):  # f<1 = mais grave e mais longo
    fr = Fraction(f).limit_denominator(100)
    return resample_poly(x, fr.denominator, fr.numerator).astype("float32")

def lp(x, hz):
    return sosfilt(butter(2, hz, "low", fs=R, output="sos"), x).astype("float32")

def mix(*parts):
    n = max(len(p[0]) + p[1] for p in parts)
    out = np.zeros(n, dtype="float32")
    for x, off, g in parts: out[off:off + len(x)] += x * g
    return out

def finish(x, peak_db=-3.2, fade=0.04):
    x = x - np.mean(x)
    x = x * (10 ** (peak_db / 20) / np.max(np.abs(x)))
    n = int(fade * R); x[-n:] *= np.linspace(1, 0, n)
    return x

def write(path, x): sf.write(path, x, R, subtype="PCM_16")

# --- armas ---
for i in range(3):
    p = load(f"pistol_{i}.wav"); s = load(f"shotgun_{i}.wav"); r = load(f"rifle_shot_{i}.wav"); d = load("distant_shot_0.wav")
    magnum = mix((speed(p, .72), 0, 1.0), (lp(speed(s, .6), 700)[:int(.9*R)], 0, .55))
    smg = speed(r, 1.14)[:int(.2*R)]; smg = smg.copy(); smg[-int(.05*R):] *= np.linspace(1, 0, int(.05*R))
    serrada = mix((speed(s, .86), 0, 1.0), (speed(s, .8), int(.02*R), .7), (lp(speed(s, .55), 600)[:int(1.0*R)], 0, .5))
    cacador = mix((speed(r, .78), 0, 1.0), (lp(d, 1800)[:int(1.8*R)], int(.03*R), .35))
    for name, x in [("magnum", magnum), ("smg", smg), ("sawed_off", serrada), ("hunting_rifle", cacador)]:
        write(os.path.join(WF, f"{name}_{i}.wav"), finish(x, fade=.08 if name != "smg" else .02))

# --- menu ---
old = os.path.join(ROOT, "evidence", "menu_antigo_20261016"); os.makedirs(old, exist_ok=True)
for f in glob.glob(os.path.join(MENU, "hover_*.wav")) + glob.glob(os.path.join(MENU, "click_*.wav")) + glob.glob(os.path.join(MENU, "back_*.wav")):
    shutil.move(f, os.path.join(old, os.path.basename(f)))
    for ext in (".import", ".uid"):
        if os.path.exists(f + ext): shutil.move(f + ext, os.path.join(old, os.path.basename(f) + ext))

def bell(freqs, dur, decay, gain=1.0, gap=0.0):
    n = int(dur * R); t = np.arange(n) / R; out = np.zeros(n + int(gap * R * len(freqs)), dtype="float32")
    for k, f in enumerate(freqs):
        env = np.minimum(t / .003, 1) * np.exp(-t * decay)
        tone = np.sin(2*np.pi*f*t) + .35*np.sin(2*np.pi*f*2.76*t)*np.exp(-t*decay*1.6) + .2*np.sin(2*np.pi*f*.5*t)
        o = int(k * gap * R); out[o:o+n] += (tone * env * gain).astype("float32")
    return out

hover = bell([1568], .09, 55)                 # um toque seco e suave
click = bell([784, 1175], .26, 17, gap=.07)   # sobe: confirmou
back = bell([880, 587], .22, 20, gap=.065)    # desce: voltou
for nm, x, pk in [("hover", hover, -13), ("click", click, -9), ("back", back, -9)]:
    write(os.path.join(MENU, f"{nm}_0.wav"), finish(x, pk, .02))
print("ok")
