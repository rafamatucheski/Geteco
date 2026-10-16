"""Trata os sons gerados no ElevenLabs (Sound Effects) em 2026-10-16: armas, clima e ambientes.

Entrada: pasta com os WAV baixados (nome do prompt + "#n-<carimbo>.wav", stereo 48 kHz).
Armas -> audio/weapons_fire/<nome>_<n>.wav (mono 48 kHz, corte de silêncio, fade, pico -3,2 dB).
Ambientes e chuva -> audio/ambience_el/<nome>_<n>.wav como loop sem emenda (final fundido no
começo, potência igual) com nível (rms) casado com os leitos que o jogo já tinha.
Trovões -> audio/ambience_el/<nome>_<n>.wav, pontuais (sem loop).
Originais ficam em evidence/elevenlabs_originais_20261016 (fora do Git).
Uso: python tools/audio/process_elevenlabs_sfx.py <pasta dos downloads>
"""
import os, sys, glob, re, shutil
import numpy as np, soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = sys.argv[1]
KEEP = os.path.join(ROOT, "evidence", "elevenlabs_originais_20261016")
os.makedirs(KEEP, exist_ok=True)
WF = os.path.join(ROOT, "audio", "weapons_fire")
AM = os.path.join(ROOT, "audio", "ambience_el")
os.makedirs(AM, exist_ok=True)
R = 48000

# prefixo do arquivo baixado -> (nome, tipo)
JOBS_RAW = {
    "Single_.44_magnum_re": ("magnum", "shot"), "Single_submachine_gu": ("smg", "shot"),
    "Double-barrel_sawed-": ("sawed_off", "shot"), "Single_high-powered_": ("hunting_rifle", "shot"),
    "RPG-7_rocket_launche": ("rpg", "shot"), "Pump-action_shotgun_": ("shotgun_pump", "shot"),
    "Steady_moderate_rain": ("rain_light", "loop"), "Heavy_downpour_rain": ("rain_heavy", "loop"),
    "Violent_thunderstorm": ("storm", "loop"), "Strong_desert_wind_b": ("sand_wind", "loop"),
    "Busy_city_plaza_crow": ("crowd", "loop"), "Large_city_ambience__": ("city_traffic", "loop"),
    "Peaceful_forest_in_d": ("forest_day", "loop"), "Forest_at_night,_cri": ("forest_night", "loop"),
    "Busy_harbor_docks_am": ("harbor", "loop"),
    "Ocean_waves_rolling_": ("ocean_shore", "loop"), "Open_ocean_at_sea,_d": ("ocean_open", "loop"),
    "Waves_crashing_and_s": ("wave_rocks", "loop"),
    "Container_shipping_t": ("port_terminal", "loop"), "Large_cargo_ship_hor": ("ship_horn", "once"),
    "Heavy_steel_shipping": ("container_clang", "once"), "Harbor_channel_buoy_": ("buoy_bell", "once"),
    "Deep_rolling_thunder": ("thunder_roll", "once"), "Close_lightning_stri": ("thunder_crack", "once"),
}
JOBS = {k.rstrip("_"): v for k, v in JOBS_RAW.items()}
# rms alvo (dBFS) dos leitos: o do jogo antigo ficava perto de -19 (chuva) e -22 (trovão).
LOOP_RMS = {"rain_light": -21, "rain_heavy": -19, "storm": -20, "sand_wind": -24, "crowd": -26,
            "city_traffic": -26, "forest_day": -26, "forest_night": -28, "harbor": -25,
            "ocean_shore": -23, "ocean_open": -24, "wave_rocks": -23, "port_terminal": -24}

def mono(x): return x.mean(axis=1)

def trim_shot(m, tail_db=-48.0, max_s=3.0):
    pk = np.max(np.abs(m)); start = max(0, int(np.argmax(np.abs(m) > 0.05 * pk)) - int(0.003 * R))
    m = m[start:]
    win = int(0.01 * R)
    env = np.array([np.sqrt(np.mean(m[i:i + win] ** 2) + 1e-12) for i in range(0, len(m), win)])
    keep = np.where(20 * np.log10(env / pk) > tail_db)[0]
    end = (keep[-1] + 1) * win if len(keep) else len(m)
    return m[:min(end, int(max_s * R))]

def fade(m, s=0.05):
    n = min(int(s * R), len(m)); m = m.copy(); m[-n:] *= np.linspace(1, 0, n); return m

def loop_fuse(m, secs=0.8):
    xf = int(secs * R); n = len(m); k = n - xf
    out = m[:k].copy(); t = np.linspace(0, 1, xf, endpoint=False)
    out[:xf] = m[:xf] * np.sin(t * np.pi / 2) + m[k:k + xf] * np.cos(t * np.pi / 2)
    return out

def set_rms(m, db, peak_cap=0.9):
    y = m * (10 ** (db / 20) / np.sqrt(np.mean(m ** 2)))
    pk = np.max(np.abs(y))
    return y * (peak_cap / pk) if pk > peak_cap else y

report = []
# Tomadas que não baixaram deixariam buraco na numeração (o banco conta até o primeiro buraco):
# renumera cada som em sequência, na ordem em que vieram.
_seq = {}
_files = []
for f in sorted(glob.glob(os.path.join(SRC, "*#[0-9]-*.wav"))):
    pre0, take0 = re.match(r"(.+)#(\d)-", os.path.basename(f)).groups()
    _files.append((pre0.rstrip("_"), int(take0), f))
_files.sort(key=lambda t: (t[0], t[1]))
for f in [t[2] for t in _files]:
    base = os.path.basename(f)
    pre, take = re.match(r"(.+)#(\d)-", base).groups()
    pre = pre.rstrip("_")
    if pre not in JOBS: continue
    name, kind = JOBS[pre]; i = _seq.get(name, 0); _seq[name] = i + 1
    shutil.copy2(f, os.path.join(KEEP, base))
    x, r = sf.read(f, always_2d=True, dtype="float32"); assert r == R
    m = mono(x)
    if kind == "shot":
        m = trim_shot(m, max_s=2.2 if name in ("magnum", "hunting_rifle", "sawed_off", "rpg") else 1.5)
        m = fade(m, 0.08); m = m * (10 ** (-3.2 / 20) / np.max(np.abs(m)))
        out = os.path.join(WF, f"{name}_{i}.wav")
    elif kind == "once":
        m = trim_shot(m, tail_db=-55, max_s=6.5); m = fade(m, 0.4)
        m = m * (10 ** (-3.0 / 20) / np.max(np.abs(m)))
        out = os.path.join(AM, f"{name}_{i}.wav")
    else:
        m = set_rms(loop_fuse(m), LOOP_RMS[name])
        out = os.path.join(AM, f"{name}_{i}.wav")
    sf.write(out, m.astype("float32"), R, subtype="PCM_16")
    report.append(f"{os.path.relpath(out, ROOT)} {len(m) / R:.2f}s rms={20 * np.log10(np.sqrt(np.mean(m ** 2))):.1f}dB")
print("\n".join(report))
