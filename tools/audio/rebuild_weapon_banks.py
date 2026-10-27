"""Reconstrói os bancos de tiro que soavam mal (27/10/2026).

Medido nas tomadas antes de mexer (forma de onda + espectrograma; ninguém ouviu aqui):
- variantes novas (audio/weapon_variants/*/shot_*): tiro duplo dentro da tomada, tiro que só
  começa 0,2 s depois do gatilho, blocos de ruído com envelope retangular e corte seco, e cliques
  de 20-40 ms sem nada abaixo de 150 Hz. Saíram da conta grátis do site (sem licença comercial).
- pistola (Firefly): 2 das 4 tomadas são só o estalo, 13 dB mais fracas que as outras.
- magnum, SMG, rifle de caça (ElevenLabs 16/10): segundo disparo embutido, tomadas saturadas
  (onda quadrada por 0,3 s) e quase nada de grave.
- escopeta (Firefly): a cauda chega a ficar mais alta que o próprio tiro.
- bombeada: uma tomada só tem metade do movimento e as outras demoram 0,45 s entre ir e voltar,
  fora do tempo da animação (vai em 0,10-0,29 s e volta em 0,29-0,48 s depois do tiro).

Como resolve: cada tomada nova é montada só com gravações licenciadas que o jogo já usa (Firefly
e as do V1), alinhadas pelo ataque: estalo de uma tomada + corpo grave (passa-baixa) de outra,
cauda aparada por envelope, cauda externa sintética onde a original tinha outro tiro, baque
grave assado no arquivo (o jogo não soma `CombatAudio.gun_body` em família gravada) e nível
casado pela energia dos primeiros 120 ms, não pelo pico. Pico máximo -3 dBFS, como antes.

Repetível: a primeira execução copia os originais para evidence/weapon-audio-20261027/originals
(fora do Git) e as seguintes partem sempre deles. Também grava preview_*.ogg (antes | depois).
Uso: python -I tools/audio/rebuild_weapon_banks.py
"""
import json
import os
import shutil
import time
from fractions import Fraction

import numpy as np
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfilt

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EVIDENCE = os.path.join(ROOT, "evidence", "weapon-audio-20261027")
ORIGINALS = os.path.join(EVIDENCE, "originals")
R = 48000
CEILING_DB = -3.0

WF = "audio/weapons_fire/"
V1 = "assets/gameplay/audio/"
VAR = "audio/weapon_variants/"

# Arquivos que este script reescreve (e cujos originais ficam guardados).
TOUCHED = [WF + "pistol_%d.wav" % i for i in range(4)] + [WF + "magnum_%d.wav" % i for i in range(3)] \
    + [WF + "smg_%d.wav" % i for i in range(3)] + [WF + "shotgun_%d.wav" % i for i in range(4)] \
    + [WF + "sawed_off_%d.wav" % i for i in range(3)] + [WF + "hunting_rifle_%d.wav" % i for i in range(3)] \
    + [WF + "shotgun_pump_%d.wav" % i for i in range(3)] \
    + [VAR + "%s/shot_%d.wav" % (v, i) for v in ("pistol_suppressed", "smg_compact", "smg_tactical", "shotgun_auto") for i in range(5)] \
    + [V1 + "suppressed_%s_%d.wav" % (f, i) for f in ("pistol", "smg", "shotgun", "ak47", "m4a1", "hunting_rifle") for i in range(5)]


def original(rel):
    """Sempre a versão anterior a este script (guardada na primeira execução)."""
    kept = os.path.join(ORIGINALS, rel)
    if not os.path.exists(kept):
        os.makedirs(os.path.dirname(kept), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, rel), kept)
    return kept


def load(rel):
    x, rate = sf.read(original(rel) if rel in TOUCHED else os.path.join(ROOT, rel), always_2d=True)
    x = x.mean(axis=1).astype("float64")
    if rate != R:
        fr = Fraction(R, rate).limit_denominator(1000)
        x = resample_poly(x, fr.numerator, fr.denominator)
    return x - np.mean(x)


def db(v):
    return 20 * np.log10(max(float(v), 1e-12))


def onset(x, rel_db=-20.0):
    pk = np.max(np.abs(x)) + 1e-12
    hit = np.argmax(np.abs(x) > pk * 10 ** (rel_db / 20))
    return max(0, int(hit) - int(0.0015 * R))


def head(x):
    return x[onset(x):].copy()


def filt(x, kind, hz, order=4):
    return sosfilt(butter(order, hz, kind, fs=R, output="sos"), x)


def pitch(x, factor):
    fr = Fraction(1.0 / factor).limit_denominator(400)
    return resample_poly(x, fr.numerator, fr.denominator)


def pad(x, n):
    return np.pad(x, (0, max(0, n - len(x))))[:n] if n else x


def mix(*layers):
    n = max(len(layer) for layer in layers)
    return sum(pad(layer, n) for layer in layers)


def at(x, seconds):
    return np.concatenate([np.zeros(int(seconds * R)), x])


def decay_after(x, keep_s, db_per_s):
    """Envelope que segura `keep_s` e cai `db_per_s` depois: mata o segundo tiro e a cauda que cresce."""
    t = np.arange(len(x)) / R
    gain = np.where(t < keep_s, 1.0, 10 ** (-(t - keep_s) * db_per_s / 20))
    return x * gain


def fade_out(x, s=0.03):
    n = min(len(x), int(s * R))
    y = x.copy()
    y[-n:] *= np.linspace(1.0, 0.0, n) ** 2
    return y


def trim_tail(x, floor_db=-52.0, max_s=None):
    win = int(0.005 * R)
    env = np.sqrt(np.convolve(x * x, np.ones(win) / win, mode="same"))
    keep = np.where(env > env.max() * 10 ** (floor_db / 20))[0]
    end = int(keep[-1]) + win if len(keep) else len(x)
    if max_s: end = min(end, int(max_s * R))
    return fade_out(x[:end], 0.025)


def thump(freq, decay, seconds, rng):
    """Baque grave assado no arquivo (mesma fórmula de CombatAudio.GUN_BODY)."""
    t = np.arange(int(seconds * R)) / R
    f = freq * (1.0 + 0.8 * np.exp(-t * 40.0))
    phase = 2 * np.pi * np.cumsum(f) / R
    body = np.sin(phase) * np.exp(-t * decay) * np.minimum(t / 0.002, 1.0)
    roll = filt(rng.uniform(-1, 1, len(t)), "low", 160, 2) * 6.0 * np.minimum(t / 0.025, 1.0) * np.exp(-t * 4.6 / seconds)
    return np.tanh(body * 0.95 + roll * 0.5) * 0.9


def outdoor_tail(source_head, seconds, rng, level_db=-14.0):
    """Cauda externa lisa no lugar da original que trazia outro disparo: ruído filtrado com
    decaimento exponencial e três reflexões abafadas do próprio ataque."""
    n = int(seconds * R)
    t = np.arange(n) / R
    noise = filt(filt(rng.uniform(-1, 1, n), "low", 1800, 2), "high", 90, 2)
    env = np.minimum(t / 0.02, 1.0) * np.exp(-t * 6.9 / seconds)
    rms = np.sqrt(np.mean(source_head[:int(0.12 * R)] ** 2)) + 1e-9
    tail = noise / (np.sqrt(np.mean(noise ** 2)) + 1e-9) * env * rms * 10 ** (level_db / 20)
    early = filt(source_head[:int(0.15 * R)], "low", 2200, 2)
    for delay, gain_db in ((0.047, -13.0), (0.083, -17.0), (0.131, -21.0)):
        tail = mix(tail, at(early * 10 ** (gain_db / 20), delay))
    return tail[:n]


def click(rng, freqs=(2400.0, 3900.0), decay=180.0, seconds=0.03):
    """Estalo metálico curto (ferrolho/telha): ruído em duas ressonâncias."""
    n = int(seconds * R)
    t = np.arange(n) / R
    burst = rng.uniform(-1, 1, n) * np.exp(-t * decay)
    out = np.zeros(n)
    for f in freqs:
        out += filt(burst, "bandpass", [f * 0.88, f * 1.12], 2)
    return out / (np.max(np.abs(out)) + 1e-9)


def composite(crack_src, body_src, split_hz=1200.0, body_db=0.0):
    """Estalo de uma tomada (passa-alta) sobre o corpo de outra (passa-baixa), alinhados no ataque."""
    crack = filt(head(crack_src), "high", split_hz, 2)
    body = filt(head(body_src), "low", split_hz, 2) * 10 ** (body_db / 20)
    return mix(crack, body)


def limit(x, ceiling_db=CEILING_DB):
    """Limitador de pico com ataque de 0,5 ms e soltura de 40 ms (sem distorcer o ataque)."""
    ceiling = 10 ** (ceiling_db / 20)
    a = np.abs(x)
    need = np.where(a > ceiling, ceiling / (a + 1e-12), 1.0)
    gain = np.ones_like(x)
    g = 1.0
    rel = np.exp(-1.0 / (0.040 * R))
    for i in range(len(x)):
        g = need[i] if need[i] < g else 1.0 - (1.0 - g) * rel
        gain[i] = g
    # Ataque: olha 0,5 ms à frente para o ganho já estar baixo quando o pico chegar.
    look = int(0.0005 * R)
    gain = np.minimum(gain, np.concatenate([gain[look:], np.ones(look)]))
    return x * gain


LIMITED = []


def level(x, rms_db, max_limit_db=3.0):
    """Casa a energia dos primeiros 120 ms (o que o ouvido julga como 'força' do tiro), sem deixar
    o limitador cortar mais que `max_limit_db` do ataque: tomada muito pontuda fica um pouco
    abaixo do alvo em vez de virar um estalo achatado."""
    h = x[onset(x):onset(x) + int(0.12 * R)]
    rms = np.sqrt(np.mean(h ** 2)) + 1e-12
    peak = np.max(np.abs(x)) + 1e-12
    gain = min(10 ** (rms_db / 20) / rms, 10 ** ((CEILING_DB + max_limit_db) / 20) / peak)
    y = x * gain
    LIMITED.append(round(max(0.0, db(np.max(np.abs(y))) - CEILING_DB), 1))
    return limit(y)


def write(rel, x):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    y = np.clip(x, -1.0, 1.0)
    # Um editor do Godot aberto reimporta o arquivo assim que ele muda e o segura por instantes.
    for attempt in range(20):
        try:
            sf.write(path, y.astype("float32"), R, subtype="PCM_16")
            break
        except sf.LibsndfileError:
            if attempt == 19: raise
            time.sleep(0.5)
    return y


def write_ogg(path, x):
    # Vorbis grande de uma vez derruba o libsndfile (sem traceback): grava em blocos de 1 s.
    with sf.SoundFile(path, "w", R, 1, format="OGG", subtype="VORBIS") as handle:
        for start in range(0, len(x), R):
            handle.write(x[start:start + R].astype("float32"))


def metrics(x):
    h = x[onset(x):onset(x) + int(0.12 * R)]
    return {"dur": round(len(x) / R, 3), "peak_db": round(db(np.max(np.abs(x))), 1),
            "rms120_db": round(db(np.sqrt(np.mean(h ** 2))), 1),
            "low150": round(float(np.sum(np.abs(np.fft.rfft(h))[:int(150 * len(h) / R)] ** 2) / (np.sum(np.abs(np.fft.rfft(h)) ** 2) + 1e-12)), 3)}


REPORT = {}
PREVIEW = {}


def bank(name, rels_before, outs):
    """outs: [(rel, array)] já montados. Grava, mede e guarda para o preview."""
    REPORT[name] = {"before": {}, "after": {}}
    before = []
    for rel in rels_before:
        x = load(rel)
        before.append(x)
        REPORT[name]["before"][rel] = metrics(x)
    after = []
    limited = LIMITED[-len(outs):]
    for index, (rel, x) in enumerate(outs):
        y = write(rel, x)
        after.append(y)
        REPORT[name]["after"][rel] = metrics(y)
        REPORT[name]["after"][rel]["limited_db"] = limited[index] if index < len(limited) else None
    PREVIEW[name] = (before, after)


def variant_bank(variant, takes):
    rels = [VAR + "%s/shot_%d.wav" % (variant, i) for i in range(len(takes))]
    bank("v_" + variant, rels, list(zip(rels, takes)))


def build():
    rng = np.random.default_rng(271027)

    # --- Pistola (Firefly): 1 e 3 eram só o estalo; ganham o corpo de 2 e 0. ---
    p = [load(WF + "pistol_%d.wav" % i) for i in range(4)]
    pistol = [
        p[0],
        composite(p[1], p[2], 1400.0),
        p[2],
        composite(p[3], p[0], 1400.0),
    ]
    pistol = [level(trim_tail(decay_after(head(x), 0.09, 70.0), -50.0, 0.55), -15.0) for x in pistol]
    bank("pistol", [WF + "pistol_%d.wav" % i for i in range(4)], [(WF + "pistol_%d.wav" % i, x) for i, x in enumerate(pistol)])

    # --- Magnum (EL 16/10): 0 e 2 traziam outro disparo; cabeça + cauda externa + baque. ---
    m = [load(WF + "magnum_%d.wav" % i) for i in range(3)]
    magnum = []
    for i, x in enumerate(m):
        h = head(x)
        if i == 1:
            core = decay_after(h, 0.12, 38.0)[:int(0.9 * R)]
        else:
            core = mix(fade_out(h[:int(0.11 * R)], 0.02), outdoor_tail(h, 0.85, rng, -12.0))
        core = mix(core, thump(58.0 + i * 3.0, 19.0, 0.9, rng) * np.max(np.abs(h)) * 0.55)
        magnum.append(level(trim_tail(core, -50.0, 1.0), -12.5))
    bank("magnum", [WF + "magnum_%d.wav" % i for i in range(3)], [(WF + "magnum_%d.wav" % i, x) for i, x in enumerate(magnum)])

    # --- SMG (EL 16/10): 2 estava saturada; vira estalo da 0 sobre o corpo da 1. ---
    s = [load(WF + "smg_%d.wav" % i) for i in range(3)]
    smg = [
        mix(head(s[0]), filt(head(s[1]), "low", 900.0, 2) * 0.5),
        s[1],
        composite(pitch(s[0], 1.04), pitch(s[1], 0.97), 1100.0),
    ]
    smg = [level(trim_tail(decay_after(head(x), 0.05, 120.0), -50.0, 0.32), -14.5) for x in smg]
    bank("smg", [WF + "smg_%d.wav" % i for i in range(3)], [(WF + "smg_%d.wav" % i, x) for i, x in enumerate(smg)])

    # --- Escopeta (Firefly): cauda que crescia depois do tiro passa a cair. ---
    g = [load(WF + "shotgun_%d.wav" % i) for i in range(4)]
    shotgun = [level(trim_tail(decay_after(head(x), 0.12, 42.0), -50.0, 1.15), -11.5) for x in g]
    bank("shotgun", [WF + "shotgun_%d.wav" % i for i in range(4)], [(WF + "shotgun_%d.wav" % i, x) for i, x in enumerate(shotgun)])

    # --- Serrada (EL 16/10): pouco grave para dois canos; baque assado. ---
    w = [load(WF + "sawed_off_%d.wav" % i) for i in range(3)]
    sawed = []
    for i, x in enumerate(w):
        h = decay_after(head(x), 0.10, 46.0)
        h = mix(h, thump(50.0 + i * 2.0, 16.0, 0.8, rng) * np.max(np.abs(h)) * 0.6)
        sawed.append(level(trim_tail(h, -50.0, 0.95), -11.0))
    bank("sawed_off", [WF + "sawed_off_%d.wav" % i for i in range(3)], [(WF + "sawed_off_%d.wav" % i, x) for i, x in enumerate(sawed)])

    # --- Rifle de caça (EL 16/10): 1 e 2 saturadas; refeitas com o estalo do rifle (Firefly). ---
    hr = load(WF + "hunting_rifle_0.wav")
    rs = [load(WF + "rifle_shot_%d.wav" % i) for i in range(4)]
    hunt = [decay_after(head(hr), 0.15, 34.0)]
    for i, donor in ((1, rs[1]), (2, rs[3])):
        h = composite(pitch(donor, 0.88), pitch(hr, 0.96), 900.0)
        hunt.append(mix(fade_out(h[:int(0.16 * R)], 0.03), outdoor_tail(h, 1.1, rng, -11.0)))
    hunt = [level(trim_tail(mix(x, thump(56.0 + i * 2.5, 21.0, 1.0, rng) * np.max(np.abs(x)) * 0.5), -50.0, 1.4), -12.5) for i, x in enumerate(hunt)]
    bank("hunting_rifle", [WF + "hunting_rifle_%d.wav" % i for i in range(3)], [(WF + "hunting_rifle_%d.wav" % i, x) for i, x in enumerate(hunt)])

    # --- Bombeada: ida e volta no tempo da animação (volta 0,20 s depois da ida). ---
    pump_src = [load(WF + "shotgun_pump_%d.wav" % i) for i in range(3)]

    def events(x):
        win = int(0.004 * R)
        env = np.sqrt(np.convolve(x * x, np.ones(win) / win, mode="same"))
        hot = env > env.max() * 0.2
        starts, last = [], -R
        for i in np.flatnonzero(hot):
            if i - last > int(0.12 * R): starts.append(i)
            last = i
        return [fade_out(x[max(0, i - int(0.004 * R)):i + int(0.14 * R)], 0.03) for i in starts]

    e0, e1, e2 = events(pump_src[0]), events(pump_src[1]), events(pump_src[2])
    pumps = [
        mix(e1[0], at(e1[1], 0.20)),
        mix(e2[0], at(e2[1], 0.21)),
        mix(pitch(e1[0], 1.03), at(e0[0], 0.19)),
    ]
    pumps = [level(trim_tail(x, -50.0, 0.42), -21.0) for x in pumps]
    bank("shotgun_pump", [WF + "shotgun_pump_%d.wav" % i for i in range(3)], [(WF + "shotgun_pump_%d.wav" % i, x) for i, x in enumerate(pumps)])

    # --- Variantes: só gravações licenciadas, cada uma com identidade própria. ---
    sup = [load(V1 + "suppressed_pistol_%d.wav" % i) for i in range(3)]
    p_body = filt(head(p[2]), "low", 520.0, 2)
    silenced = []
    for i, (donor, factor) in enumerate(((sup[0], 1.0), (sup[1], 1.0), (sup[2], 1.0), (sup[0], 0.95), (sup[1], 1.05))):
        h = pitch(head(donor), factor)
        core = mix(h, p_body * np.max(np.abs(h)) / (np.max(np.abs(p_body)) + 1e-9) * 0.35)
        slide = click(rng, (2300.0 + i * 60.0, 3800.0), 210.0) * np.max(np.abs(h)) * 0.16
        back = click(rng, (2700.0, 4300.0 - i * 80.0), 260.0) * np.max(np.abs(h)) * 0.10
        core = mix(core, at(slide, 0.032 + i * 0.002), at(back, 0.074 + i * 0.003))
        silenced.append(level(trim_tail(decay_after(core, 0.06, 95.0), -50.0, 0.34), -17.0))
    variant_bank("pistol_suppressed", silenced)

    v1_smg = [load(V1 + "smg_%d.wav" % i) for i in range(5)]
    compact = []
    for i in range(5):
        crack = filt(pitch(head(v1_smg[i]), 1.08), "high", 900.0, 2)
        body = filt(pitch(head(s[i % 2]), 1.05), "low", 1100.0, 2) * 0.6
        x = mix(crack, body)
        x = x + filt(filt(x, "high", 2000.0, 2), "low", 5000.0, 2) * 0.25
        compact.append(level(trim_tail(decay_after(x, 0.03, 165.0), -50.0, 0.24), -15.0))
    variant_bank("smg_compact", compact)

    tactical = []
    for i, donor in enumerate((rs[0], rs[1], rs[2], rs[3], s[1])):
        base = pitch(head(donor), 1.06)
        snap = filt(pitch(head(v1_smg[(i + 2) % 5]), 0.96), "high", 2000.0, 2) * 0.45
        x = mix(base, snap)
        tactical.append(level(trim_tail(decay_after(x, 0.05, 115.0), -50.0, 0.36), -14.0))
    variant_bank("smg_tactical", tactical)

    semi = []
    for i, donor in enumerate((g[3], g[0], g[1], g[2], pitch(g[3], 0.97))):
        x = pitch(head(donor), 1.04)
        bolt = mix(click(rng, (1900.0, 3100.0), 170.0), at(click(rng, (2500.0, 3600.0), 230.0) * 0.8, 0.026))
        x = mix(decay_after(x, 0.10, 70.0), at(bolt * np.max(np.abs(x)) * 0.10, 0.085 + i * 0.004))
        semi.append(level(trim_tail(x, -50.0, 0.72), -12.0))
    variant_bank("shotgun_auto", semi)

    # --- Silenciadas do V1: 3 e 4 vinham de outra fonte, ~3 dB abaixo; nível casado. ---
    for family in ("pistol", "smg", "shotgun", "ak47", "m4a1", "hunting_rifle"):
        rels = [V1 + "suppressed_%s_%d.wav" % (family, i) for i in range(5)]
        xs = [load(rel) for rel in rels]
        target = float(np.mean([metrics(x)["rms120_db"] for x in xs[:3]]))
        bank("sup_" + family, rels, [(rel, level(head(x), target)) for rel, x in zip(rels, xs)])


def preview():
    beep = np.sin(2 * np.pi * 880 * np.arange(int(0.08 * R)) / R) * 0.15
    gap = np.zeros(int(0.35 * R))
    allparts = []
    for name, (before, after) in PREVIEW.items():
        parts = []
        for x in before: parts += [x / (np.max(np.abs(x)) + 1e-9) * 0.7, gap]
        parts += [gap, beep, gap, gap]
        for x in after: parts += [x, gap]
        clip = np.concatenate(parts)
        write_ogg(os.path.join(EVIDENCE, "preview_%s.ogg" % name), clip)
        allparts += [clip, np.zeros(int(0.8 * R))]
    write_ogg(os.path.join(EVIDENCE, "preview_todas.ogg"), np.concatenate(allparts))


if __name__ == "__main__":
    os.makedirs(EVIDENCE, exist_ok=True)
    for rel in TOUCHED: original(rel)
    build()
    preview()
    with open(os.path.join(EVIDENCE, "rebuild_report.json"), "w", encoding="utf-8") as handle:
        json.dump(REPORT, handle, indent=1, ensure_ascii=False)
    for name, entry in REPORT.items():
        print(name)
        for rel, m in entry["after"].items():
            b = entry["before"].get(rel, {})
            print("  %-48s antes rms %6s pico %6s dur %5s | depois rms %6s pico %6s dur %5s grave %s limitou %s dB" % (
                rel[-48:], b.get("rms120_db"), b.get("peak_db"), b.get("dur"), m["rms120_db"], m["peak_db"], m["dur"], m["low150"], m.get("limited_db")))
