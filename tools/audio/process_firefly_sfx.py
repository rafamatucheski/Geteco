"""Trata os sons gerados no Firefly (2026-10-15): mono, corte de silêncio, fade, volume casado com os
sons que o jogo já tem, loops sem emenda. Originais vão para evidence/ (fora do Git)."""
import wave, struct, math, os, shutil, glob, json, statistics
from array import array

ROOT = r"D:\geteco\game"
AUDIO = os.path.join(ROOT, "audio")
BACKUP = os.path.join(ROOT, "evidence", "firefly_originais_20261015")


def load(path):
    w = wave.open(path)
    n, ch, rate = w.getnframes(), w.getnchannels(), w.getframerate()
    raw = struct.unpack("<%dh" % (n * ch), w.readframes(n))
    w.close()
    if ch == 1:
        mono = [x / 32768.0 for x in raw]
    else:
        mono = [sum(raw[i * ch:(i + 1) * ch]) / (ch * 32768.0) for i in range(n)]
    return rate, mono


def save(path, rate, data):
    pcm = array("h", [max(-32768, min(32767, int(round(x * 32767)))) for x in data])
    w = wave.open(path, "wb")
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(pcm.tobytes())
    w.close()


def peak(d):
    return max((abs(x) for x in d), default=0.0)


def envelope(d, rate, win=0.01):
    step = max(1, int(rate * win))
    return [math.sqrt(sum(x * x for x in d[i:i + step]) / max(1, len(d[i:i + step]))) for i in range(0, len(d), step)], step


def trim(d, rate, max_len, lead_thresh=0.04, tail_db=-42.0):
    pk = peak(d)
    start = 0
    for i, x in enumerate(d):
        if abs(x) > lead_thresh * pk:
            start = max(0, i - int(0.003 * rate)); break
    d = d[start:]
    env, step = envelope(d, rate)
    floor = pk * (10 ** (tail_db / 20))
    last = 0
    for i, e in enumerate(env):
        if e > floor: last = i
    end = min(len(d), (last + 1) * step + int(0.05 * rate), int(max_len * rate))
    return d[:end]


def fade(d, rate, fin=0.002, fout=0.1):
    n = len(d)
    a, b = min(n // 2, int(fin * rate)), min(n // 2, int(fout * rate))
    d = list(d)
    for i in range(a): d[i] *= i / a
    for i in range(b): d[n - 1 - i] *= i / b
    return d


def normalize(d, target):
    pk = peak(d)
    if pk <= 0: return d
    g = target / pk
    return [x * g for x in d]


ONSET_KEYS = ("door_close", "door_open", "distant_shot", "turbo_flutter", "wastegate", "handbrake",
              "dry_fire", "grenade_pin", "ricochet", "bullet_whiz")


def cut_to_onset(d, rate, frac=0.25, pre=0.04):
    """Começa perto da pancada principal: porta que bate, tiro distante, alívio do turbo."""
    env, step = envelope(d, rate, 0.01)
    pk = max(env)
    for i, e in enumerate(env):
        if e > frac * pk:
            return d[max(0, i * step - int(pre * rate)):]
    return d


def one_shot(src, dst, target, max_len, fout, lead=True, tail_db=-42.0):
    rate, d = load(src)
    if any(os.path.basename(dst).startswith(k + "_") for k in ONSET_KEYS): d = cut_to_onset(d, rate)
    d = trim(d, rate, max_len, tail_db=tail_db) if lead else d[:int(max_len * rate)]
    d = normalize(fade(d, rate, 0.002, fout), target)
    save(dst, rate, d)
    return len(d) / rate, peak(d)


def crossfade_loop(d, rate, xf=0.8):
    n, x = len(d), int(xf * rate)
    m = n - x
    out = d[:m]
    for i in range(x):
        t = i / x
        out[i] = d[i] * math.sin(t * math.pi / 2) + d[m + i] * math.cos(t * math.pi / 2)
    return out


def onset_loop(d, rate, min_len):
    """Corta de uma batida até outra: loop sem emenda para sons periódicos (bipe)."""
    env, step = envelope(d, rate, 0.005)
    pk = max(env)
    on, armed = [], True
    for i, e in enumerate(env):
        if armed and e > 0.5 * pk:
            on.append(i * step); armed = False
        elif e < 0.15 * pk:
            armed = True
    if len(on) < 3: return None
    period = statistics.median([b - a for a, b in zip(on, on[1:])])
    k = max(1, round(min_len * rate / period))
    # início da primeira batida (com um respiro), fim imediatamente antes da batida k+1
    if len(on) <= k: k = len(on) - 1
    a, b = on[0] - int(0.004 * rate), on[k] - int(0.004 * rate)
    return d[max(0, a):b]


def cv(d, rate):
    env, _ = envelope(d, rate, 0.05)
    env = [e for e in env if e > 0]
    return statistics.pstdev(env) / (statistics.mean(env) + 1e-9)


def backup(folder, names):
    dst = os.path.join(BACKUP, folder)
    os.makedirs(dst, exist_ok=True)
    for n in names:
        s = os.path.join(AUDIO, folder, n)
        if os.path.exists(s) and not os.path.exists(os.path.join(dst, n)):
            shutil.copy2(s, os.path.join(dst, n))


# nome -> (pico alvo, duração máxima, fade final). Alvos casam com o que o jogo já tem:
# tiros ~0,6-0,7; efeitos de veículo 0,8-0,85; detalhes de ambiente ~0,45.
SPEC = {
    "weapons_fire": {"pistol": (.62, 1.4, .25), "shotgun": (.70, 1.8, .35),
                      "distant_shot": (.45, 3.5, .8),
                      "dry_fire": (.55, 0.6, .10), "gun_draw": (.50, 1.2, .15), "grenade_pin": (.55, 1.0, .10),
                      "rocket_flight": (.55, 4.0, .40), "explosion_tail": (.55, 5.0, 1.2), "ricochet": (.60, 1.4, .30),
                      "bullet_whiz": (.55, 0.8, .10)},
    "katana": {"draw": (.60, 1.6, .20)},
    "desert_ambience": {"wind": (.45, 15.0, .6)},
    "wildlife": {"coyote": (.45, 5.0, .6), "crickets": (.45, 15.0, .6)},
    "mining": {"drip": (.45, 15.0, .6), "machinery": (.45, 15.0, .6)},
    "service_vehicles": {"horn": (.55, 3.0, .12), "reverse_beep": (.5, 6.0, .05), "siren": (.55, 8.0, .3)},
    "vehicle_fx": {"ignition": (.70, 1.7, .55), "engine_off": (.60, 3.0, .4), "door_open": (.50, 1.6, .15),
                   "door_close": (.60, 1.4, .12), "car_horn": (.45, 1.4, .12), "turn_signal": (.45, 5.0, .05),
                   "handbrake": (.55, 1.6, .12), "backfire": (.85, 2.4, .25), "turbo_spool": (.60, 4.0, .4),
                   "turbo_spooldown": (.60, 3.0, .4), "wastegate": (.85, 1.6, .15), "turbo_flutter": (.80, 1.8, .15),
                   "diesel_turbo": (.85, 1.6, .5), "supercharger": (.60, 4.0, .3)},
}
MIN_PEAK = 0.12  # abaixo disso a tomada é ruído de fundo: sai do jogo (fica no backup)

report = {}
for folder, sounds in SPEC.items():
    names = [os.path.basename(p) for p in glob.glob(os.path.join(AUDIO, folder, "*.wav"))]
    mine = [n for n in names if any(n.startswith(k + "_") and n[len(k) + 1:-4].isdigit() for k in sounds)]
    backup(folder, mine)
    for key, (target, max_len, fout) in sounds.items():
        keep = []
        for k in range(4):
            name = f"{key}_{k}.wav"
            src = os.path.join(BACKUP, folder, name)  # sempre parte do original
            if not os.path.exists(src): continue
            rate, d = load(src)
            if peak(d) < MIN_PEAK:
                report[f"{folder}/{name}"] = "descartada (volume original muito baixo, só ruído)"
                continue
            keep.append(src)
        # remove as antigas desse som e regrava compactado (0..n-1)
        for k in range(4):
            p = os.path.join(AUDIO, folder, f"{key}_{k}.wav")
            for q in (p, p + ".import"):
                if os.path.exists(q): os.remove(q)
        for j, src in enumerate(keep):
            dst = os.path.join(AUDIO, folder, f"{key}_{j}.wav")
            dur, pk = one_shot(src, dst, target, max_len, fout)
            report[f"{folder}/{key}_{j}.wav"] = f"{dur:.2f}s pico={pk:.2f}"

# tiros de fuzil: fatia a rajada de 3 tiros em tiros únicos
rate_cache = []
burst_backup = os.path.join(BACKUP, "weapons_fire")
backup("weapons_fire", [f"rifle_{k}.wav" for k in range(4)])
shots = []
for k in range(4):
    src = os.path.join(burst_backup, f"rifle_{k}.wav")
    if not os.path.exists(src): continue
    rate, d = load(src)
    env, step = envelope(d, rate, 0.002)
    pk = max(env)
    on, armed = [], True
    for i, e in enumerate(env):
        if armed and e > 0.4 * pk: on.append(i * step); armed = False
        elif e < 0.12 * pk: armed = True
    report[f"weapons_fire/rifle_{k}.wav(burst)"] = f"{len(on)} disparos detectados"
    for a, b in zip(on, on[1:] + [None]):
        end = (b - int(0.01 * rate)) if b else min(len(d), a + int(1.4 * rate))
        seg = d[max(0, a - int(0.003 * rate)):end]
        if len(seg) > int(0.30 * rate): shots.append((rate, seg))  # fragmentos de fogo rápido (<0,3 s) cortam a cauda: ficam de fora
for old in glob.glob(os.path.join(AUDIO, "weapons_fire", "rifle_shot_*.wav*")): os.remove(old)
for j, (rate, seg) in enumerate(shots[:9]):
    # tiro único com no máximo 0,5 s (o ak47 do jogo tem 0,52 s): em fogo automático a
    # cauda longa de um tiro se sobreporia ao seguinte
    seg = seg[:int(0.5 * rate)]
    save(os.path.join(AUDIO, "weapons_fire", f"rifle_shot_{j}.wav"), rate, normalize(fade(seg, rate, 0.002, 0.12 if len(seg) > 0.3 * rate else 0.03), .65))
    report[f"weapons_fire/rifle_shot_{j}.wav"] = f"{len(seg) / rate:.2f}s"
# a rajada original sai (o jogo dispara tiro a tiro)
for k in range(4):
    for q in (os.path.join(AUDIO, "weapons_fire", f"rifle_{k}.wav"), os.path.join(AUDIO, "weapons_fire", f"rifle_{k}.wav.import")):
        if os.path.exists(q): os.remove(q)

# loops sem emenda
def make_loop(folder, key, name, target, how, **kw):
    cands = sorted(glob.glob(os.path.join(BACKUP, folder, f"{key}_[0-9].wav")))
    best = None
    for p in cands:
        rate, d = load(p)
        if peak(d) < MIN_PEAK: continue
        score = cv(d, rate)
        if best is None or score < best[0]: best = (score, p)
    if best is None:
        report[f"{folder}/{name}"] = "sem tomada boa"; return
    rate, d = load(best[1])
    if how == "xfade": loop = crossfade_loop(d, rate, kw.get("xf", 0.8))
    else: loop = onset_loop(d, rate, kw.get("min_len", 2.0))
    if loop is None:
        report[f"{folder}/{name}"] = "não achei batidas para o loop"; return
    loop = normalize(loop, target)
    save(os.path.join(AUDIO, folder, name), rate, loop)
    report[f"{folder}/{name}"] = f"loop de {os.path.basename(best[1])}, {len(loop) / rate:.2f}s"

make_loop("service_vehicles", "siren", "siren_loop.wav", .55, "xfade", xf=1.0)
make_loop("service_vehicles", "reverse_beep", "reverse_beep_loop.wav", .5, "onset", min_len=2.0)
make_loop("vehicle_fx", "supercharger", "supercharger_loop.wav", .6, "xfade", xf=0.6)
make_loop("vehicle_fx", "turn_signal", "turn_signal_loop.wav", .45, "onset", min_len=2.0)
make_loop("desert_ambience", "wind", "wind_loop.wav", .45, "xfade", xf=1.5)
make_loop("weapons_fire", "rocket_flight", "rocket_flight_loop.wav", .55, "xfade", xf=0.8)


def reversed_copies(folder, source_key, target_key, peak_target, fade_in=0.004):
    """Guardar arma = sacar arma ao contrário (couro e metal entrando): sem gastar crédito."""
    for k in range(4):
        src = os.path.join(AUDIO, folder, f"{source_key}_{k}.wav")
        if not os.path.exists(src): continue
        rate, d = load(src)
        d = normalize(fade(d[::-1], rate, fade_in, 0.05), peak_target)
        save(os.path.join(AUDIO, folder, f"{target_key}_{k}.wav"), rate, d)
        report[f"{folder}/{target_key}_{k}.wav"] = f"{len(d) / rate:.2f}s (ao contrário de {source_key})"


reversed_copies("weapons_fire", "gun_draw", "gun_holster", .45)
reversed_copies("katana", "draw", "sheath", .55)

os.makedirs(BACKUP, exist_ok=True)
with open(os.path.join(BACKUP, "relatorio.json"), "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=1)
for k, v in sorted(report.items()): print(f"{k:50s} {v}")
