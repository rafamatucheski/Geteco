"""Instala os gritos de dor/morte e os impactos de bala no corpo gerados na ElevenLabs (27/10/2026).

Entrada: a pasta onde o navegador baixou os WAV (nome = começo do prompt + "_#n-<carimbo>.wav").
Saída:
  audio/pain_voices/<gênero>_<tipo>_<grupo>_<n>.wav   (audio/PainVoiceBank.gd)
  audio/body_impacts/bullet_<flesh|vest>_<n>.wav       (CombatAudio.body_hit_take)
Tratamento: mono 48 kHz, corte do silêncio do começo e do fim, passa-alta em 70 Hz, nível casado
pela energia da parte com voz (não pelo pico), teto de pico -2 dBFS (-3 nos impactos), fades
curtos. Tomada quase muda (pico < 0,03, comum na geração) ou fora da faixa de duração é
descartada e listada. Os originais vão para evidence/elevenlabs-dor-20261027 (fora do Git).

Ninguém ouviu aqui: a escolha das boas foi de quem baixou; o script só mede e padroniza.
Uso: python -I tools/audio/install_pain_voices.py <pasta dos downloads> [--dry-run]
"""
import glob
import json
import os
import re
import shutil
import sys
from fractions import Fraction

import numpy as np
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfilt

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KEEP = os.path.join(ROOT, "evidence", "elevenlabs-dor-20261027")
PAIN = os.path.join(ROOT, "audio", "pain_voices")
BODY = os.path.join(ROOT, "audio", "body_impacts")
R = 48000

# Começo do prompt (como o site nomeia o arquivo) -> (destino, chave, nível rms dB, teto dB, duração mín/máx s)
JOBS = {
    "Young_woman_short_sh": ("pain", "female_light_young", -19.0, -2.0, 0.15, 1.2),
    "Middle-aged_woman_pa": ("pain", "female_light_mature", -19.0, -2.0, 0.15, 1.2),
    "Woman_screams_in_pai": ("pain", "female_heavy_any", -16.5, -2.0, 0.2, 1.4),
    "Woman's_dying_cry,_p": ("pain", "female_death_any", -18.0, -2.0, 0.3, 1.8),
    "Man_short_pained_gru": ("pain", "male_light_adult", -19.0, -2.0, 0.15, 1.2),
    "Young_man_sharp_cry_": ("pain", "male_light_young", -19.0, -2.0, 0.15, 1.2),
    "Heavy-set_older_man_": ("pain", "male_light_older", -19.0, -2.0, 0.15, 1.2),
    "Man_yells_in_pain_af": ("pain", "male_heavy_any", -16.5, -2.0, 0.2, 1.4),
    "Man's_dying_groan,_p": ("pain", "male_death_any", -18.0, -2.0, 0.3, 1.8),
    "Bullet_hitting_a_hum": ("body", "bullet_flesh", -15.0, -3.0, 0.06, 0.5),
    "Bullet_impact_into_f": ("body", "bullet_flesh", -15.0, -3.0, 0.06, 0.5),
    "Bullet_hitting_a_kev": ("body", "bullet_vest", -15.0, -3.0, 0.06, 0.5),
}
MAX_TAKES = 8
## Tomadas vetadas depois de olhar a forma de onda (prompt + número da tomada no site).
## "Man's dying groan" #2: estalo seco no começo e voz quase sumida depois.
EXCLUDE = ("Man's_dying_groan,_p_#2",)


def mono48(path):
    x, rate = sf.read(path, always_2d=True)
    x = x.mean(axis=1).astype("float64")
    if rate != R:
        fr = Fraction(R, rate).limit_denominator(1000)
        x = resample_poly(x, fr.numerator, fr.denominator)
    return x - np.mean(x)


def envelope(x, ms=8):
    win = max(1, int(R * ms / 1000))
    return np.sqrt(np.convolve(x * x, np.ones(win) / win, mode="same"))


def trim(x, start_db=-32.0, end_db=-48.0):
    env = envelope(x)
    top = env.max() + 1e-12
    on = np.flatnonzero(env > top * 10 ** (start_db / 20))
    off = np.flatnonzero(env > top * 10 ** (end_db / 20))
    if not len(on): return x[:0]
    a = max(0, int(on[0]) - int(0.008 * R))
    b = min(len(x), int(off[-1]) + int(0.02 * R))
    return x[a:b]


def limit(x, ceiling_db):
    ceiling = 10 ** (ceiling_db / 20)
    a = np.abs(x)
    need = np.where(a > ceiling, ceiling / (a + 1e-12), 1.0)
    gain = np.ones_like(x)
    g = 1.0
    rel = np.exp(-1.0 / (0.05 * R))
    for i in range(len(x)):
        g = need[i] if need[i] < g else 1.0 - (1.0 - g) * rel
        gain[i] = g
    look = int(0.0005 * R)
    gain = np.minimum(gain, np.concatenate([gain[look:], np.ones(look)]))
    return x * gain


def level(x, rms_db, ceiling_db):
    env = envelope(x, 20)
    voiced = x[env > env.max() * 10 ** (-24 / 20)]
    rms = np.sqrt(np.mean(voiced ** 2)) + 1e-12 if len(voiced) else 1.0
    peak = np.max(np.abs(x)) + 1e-12
    # O limitador corta no máximo 4 dB do ataque; tomada pontuda fica um pouco abaixo do alvo.
    gain = min(10 ** (rms_db / 20) / rms, 10 ** ((ceiling_db + 4.0) / 20) / peak)
    return limit(x * gain, ceiling_db)


def fades(x, fade_in=0.003, fade_out=0.04):
    y = x.copy()
    a, b = min(len(y), int(fade_in * R)), min(len(y), int(fade_out * R))
    if a: y[:a] *= np.linspace(0.0, 1.0, a)
    if b: y[-b:] *= np.linspace(1.0, 0.0, b) ** 2
    return y


def main():
    src = sys.argv[1]
    dry = "--dry-run" in sys.argv
    os.makedirs(KEEP, exist_ok=True)
    os.makedirs(PAIN, exist_ok=True)
    os.makedirs(BODY, exist_ok=True)
    grouped = {}
    for path in sorted(glob.glob(os.path.join(src, "*.wav")), key=os.path.getmtime):
        name = os.path.basename(path)
        prefix = re.sub(r"_?#\d+-\d+\.wav$", "", name)[:20]
        job = JOBS.get(prefix) or JOBS.get(prefix.rstrip("_"))
        if job is None:
            for key in JOBS:
                if name.startswith(key): job = JOBS[key]; break
        if job is None: continue
        grouped.setdefault((job[0], job[1]), []).append((path, job))
    report = {"kept": {}, "rejected": []}
    for (dest, key), entries in grouped.items():
        # Reinstalar não pode deixar tomada velha com índice maior que as novas (o banco lê 0..n).
        if not dry:
            out_dir = PAIN if dest == "pain" else BODY
            for stale in glob.glob(os.path.join(out_dir, "%s_[0-9].wav" % key)):
                os.remove(stale)
        seen = set()
        index = 0
        for path, job in entries:
            if os.path.basename(path).startswith(EXCLUDE):
                report["rejected"].append({"file": os.path.basename(path), "why": "vetada na inspeção"})
                continue
            raw = mono48(path)
            digest = hash(raw[: min(len(raw), R)].tobytes())
            if digest in seen:
                report["rejected"].append({"file": os.path.basename(path), "why": "duplicada"})
                continue
            seen.add(digest)
            peak = float(np.max(np.abs(raw))) if len(raw) else 0.0
            x = trim(raw)
            duration = len(x) / R
            _, _, rms_db, ceiling_db, low_s, high_s = job
            if peak < 0.03 or duration < low_s:
                report["rejected"].append({"file": os.path.basename(path), "why": "quase muda ou curta", "peak": round(peak, 3), "dur": round(duration, 3)})
                continue
            if duration > high_s:
                x = x[: int(high_s * R)]
            x = sosfilt(butter(2, 70.0, "high", fs=R, output="sos"), x)
            x = fades(level(x, rms_db, ceiling_db), 0.003, 0.06 if dest == "pain" else 0.03)
            if index >= MAX_TAKES:
                report["rejected"].append({"file": os.path.basename(path), "why": "acima de %d tomadas" % MAX_TAKES})
                continue
            out_dir = PAIN if dest == "pain" else BODY
            out = os.path.join(out_dir, "%s_%d.wav" % (key, index))
            if not dry:
                shutil.copy2(path, os.path.join(KEEP, os.path.basename(path)))
                sf.write(out, np.clip(x, -1.0, 1.0).astype("float32"), R, subtype="PCM_16")
            report["kept"].setdefault(key, []).append({"from": os.path.basename(path), "to": os.path.relpath(out, ROOT).replace("\\", "/"),
                "dur": round(len(x) / R, 3), "peak_in": round(peak, 3)})
            index += 1
    with open(os.path.join(KEEP, "install_report.json"), "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=1, ensure_ascii=False)
    for key, rows in sorted(report["kept"].items()):
        print("%-22s %d tomadas: %s" % (key, len(rows), ", ".join("%.2fs" % r["dur"] for r in rows)))
    for row in report["rejected"]:
        print("descartada:", row)


if __name__ == "__main__":
    main()
