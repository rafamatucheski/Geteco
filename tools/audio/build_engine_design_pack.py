"""Author the original offline engine banks used by the fleet runtime.

Run: python tools/audio/build_engine_design_pack.py
Requires the project's existing numpy/scipy dependencies. No network or samples.
These are designed inspirations, not recordings or measured engine simulations.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import wave

import numpy as np
from scipy.signal import lfilter

ROOT = Path(__file__).resolve().parents[2]
RATE = 22050
FRAMES = 44100
LOW_FRAMES = 132300
GUARD = 8
PROFILES = [
    dict(id="jz2_i6_turbo", label="Inspirado no 2JZ · seis em linha turbo", cylinders=6,
         rpm_bands=[840, 1320, 2040, 3000, 4200, 5640, 6960],
         banks=[0, 0, 0, 0, 0, 0], runners=[.0021, .0029, .0018, .0026, .0032, .0024],
         resonances=[(155, .7), (340, .36), (680, .16)], cutoff=2300,
         pulse_ms=2.5, uneven=.035, intake=.13, turbo=True,
         description="I6 turbo, escape cheio e admissão discreta; inspiração 2JZ-GTE, não gravação."),
    dict(id="rb26_i6_turbo", label="Inspirado no RB26 · Skyline R34", cylinders=6,
         rpm_bands=[960, 1440, 2160, 3240, 4560, 6120, 7800],
         banks=[0, 0, 0, 0, 0, 0], runners=[.0017, .0025, .0014, .0022, .0028, .0020],
         resonances=[(230, .6), (510, .40), (1080, .22)], cutoff=3200,
         pulse_ms=1.8, uneven=.028, intake=.24, turbo=True,
         description="I6 turbo, admissão mais presente e escape mais brilhante; inspiração RB26DETT."),
    dict(id="v8_crossplane", label="V8 · cross-plane aspirado", cylinders=8,
         rpm_bands=[720, 1200, 1800, 2640, 3720, 5040, 6480],
         # LS-style 1-8-7-2-6-5-4-3: irregular spacing in each exhaust bank.
         banks=[0, 1, 0, 1, 1, 0, 1, 0], runners=[.0035, .0041, .0031, .0045, .0038, .0029, .0042, .0033],
         resonances=[(92, .90), (205, .35), (430, .12)], cutoff=2100,
         pulse_ms=3.8, uneven=.14, intake=.10, turbo=False,
         description="V8 aspirado cross-plane, escape de dois bancos; não representa todo V8."),
    dict(id="v12_gt", label="V12 · GT aspirado", cylinders=12,
         rpm_bands=[840, 1440, 2280, 3360, 4800, 6480, 8400],
         banks=[0, 1] * 6,
         runners=[.0018, .0021, .0016, .0020, .0019, .0023, .0017, .0022, .0015, .0020, .0018, .0021],
         resonances=[(210, .35), (620, .40), (1380, .26)], cutoff=4200,
         pulse_ms=1.5, uneven=.018, intake=.25, turbo=False,
         description="V12 aspirado de alto giro, ignição regular e textura aguda; inspiração de classe GT."),
    dict(id="ap_i4_turbo", label="Inspirado no AP turbo · Gol preparado", cylinders=4,
         rpm_bands=[960, 1440, 2160, 3120, 4320, 5520, 6720],
         banks=[0, 0, 0, 0], runners=[.0030, .0022, .0027, .0034],
         resonances=[(145, .55), (370, .38), (780, .18)], cutoff=2700,
         pulse_ms=2.7, uneven=.11, intake=.19, turbo=True,
         description="I4 turbo preparado, referência autoral AP; candidato ao Gol do Digo, não som de fábrica."),
    dict(id="ea888_i4_turbo", label="Inspirado no EA888 · Jetta GLI", cylinders=4,
         rpm_bands=[840, 1320, 2040, 3000, 4200, 5400, 6600],
         banks=[0, 0, 0, 0], runners=[.0018, .0020, .0017, .0019],
         resonances=[(175, .48), (410, .25), (920, .12)], cutoff=2400,
         pulse_ms=2.0, uneven=.035, intake=.14, turbo=True,
         description="I4 turbo moderno, escape contido e carga cheia; inspiração EA888 do Jetta GLI."),
    dict(id="vq35_v6_na", label="Inspirado no VQ35 · 350Z aspirado", cylinders=6,
         rpm_bands=[840, 1320, 2040, 3000, 4200, 5520, 6720],
         banks=[0, 1, 0, 1, 0, 1], runners=[.0023, .0028, .0020, .0026, .0024, .0030],
         resonances=[(185, .48), (460, .48), (980, .23)], cutoff=3100,
         pulse_ms=2.1, uneven=.065, intake=.28, turbo=False,
         description="V6 aspirado com dois bancos e admissão presente; inspiração VQ35, sem efeitos de turbo."),
    dict(id="tdi_i4_diesel", label="I4 turbodiesel · picape 2.0", cylinders=4,
         rpm_bands=[840, 1200, 1680, 2160, 2760, 3480, 4320],
         banks=[0, 0, 0, 0], runners=[.0031, .0025, .0030, .0027],
         resonances=[(105, .65), (260, .28), (650, .14)], cutoff=1750,
         pulse_ms=2.6, uneven=.10, intake=.08, turbo=True, fuel="diesel", bypass_valve=False,
         description="Quatro cilindros turbodiesel para picape/utilitário, referência Amarok 2.0; sem BOV esportiva."),
    dict(id="city_i4_na", label="I4 aspirado · compacto urbano", cylinders=4,
         rpm_bands=[840, 1320, 1920, 2760, 3840, 5040, 6240],
         banks=[0, 0, 0, 0], runners=[.0022, .0020, .0024, .0021],
         resonances=[(190, .35), (430, .24), (850, .09)], cutoff=2100,
         pulse_ms=1.9, uneven=.07, intake=.12, turbo=False,
         description="I4 aspirado pequeno com escape de rua e admissão contida; candidato aos compactos da cidade."),
    # Append-only: these indices participate in deterministic source seeds.
    # The nine profiles approved before fleet integration retain their bytes.
    dict(id="v8_twin_turbo", label="V8 biturbo · gran turismo moderno", cylinders=8,
         rpm_bands=[720, 1200, 1800, 2760, 3960, 5400, 7080],
         banks=[0, 1, 0, 1, 1, 0, 1, 0], runners=[.0020, .0023, .0018, .0025, .0021, .0017, .0024, .0019],
         resonances=[(125, .55), (310, .38), (760, .18)], cutoff=2650,
         pulse_ms=2.5, uneven=.09, intake=.21, turbo=True,
         description="V8 biturbo moderno, escape de dois bancos e admissão sob pressão; aplicação autoral para o M8."),
    dict(id="truck_i6_diesel", label="I6 turbodiesel · caminhão pesado", cylinders=6,
         rpm_bands=[600, 840, 1080, 1320, 1680, 2040, 2400],
         banks=[0] * 6, runners=[.0042, .0051, .0039, .0048, .0055, .0045],
         resonances=[(78, .72), (180, .38), (470, .16)], cutoff=1450,
         pulse_ms=4.1, uneven=.11, intake=.08, turbo=True, fuel="diesel", bypass_valve=False,
         description="Seis em linha diesel de baixa rotação para caminhões pesados, bombeiro e carro-forte; sem BOV."),
    dict(id="bus_i6_diesel", label="I6 turbodiesel · ônibus urbano", cylinders=6,
         rpm_bands=[600, 840, 1080, 1320, 1560, 1920, 2280],
         banks=[0] * 6, runners=[.0048, .0057, .0045, .0054, .0060, .0051],
         resonances=[(69, .68), (155, .30), (390, .12)], cutoff=1200,
         pulse_ms=4.7, uneven=.07, intake=.055, turbo=True, fuel="diesel", bypass_valve=False,
         description="Diesel seis em linha de ônibus, cadência baixa e escape amortecido; sem válvula esportiva de alívio."),
    dict(id="work_i4_diesel", label="I4 turbodiesel · máquina de trabalho", cylinders=4,
         rpm_bands=[720, 960, 1200, 1560, 1920, 2280, 2640],
         banks=[0] * 4, runners=[.0038, .0045, .0033, .0041],
         resonances=[(100, .50), (270, .35), (700, .19)], cutoff=1950,
         pulse_ms=3.2, uneven=.14, intake=.07, turbo=True, fuel="diesel", bypass_valve=False,
         description="Diesel quatro cilindros de trabalho para retroescavadeira e trator, com clatter mecânico e giro limitado."),
    dict(id="truck_v12_diesel", label="V12 turbodiesel · Freight Cargo", cylinders=12,
         rpm_bands=[600, 840, 1080, 1320, 1680, 2040, 2400],
         banks=[0, 1] * 6,
         runners=[.0048, .0054, .0044, .0051, .0047, .0057, .0045, .0053, .0042, .0050, .0046, .0055],
         resonances=[(65, .62), (145, .43), (360, .18)], cutoff=1350,
         pulse_ms=4.3, uneven=.055, intake=.065, turbo=True, fuel="diesel", bypass_valve=False,
         description="V12 diesel de baixa rotação para o Freight Cargo V12 ficcional; não usa o V12 esportivo de alto giro."),
    dict(id="utility_v6_na", label="V6 aspirado · SUV e utilitário", cylinders=6,
         rpm_bands=[720, 1200, 1800, 2640, 3600, 4800, 6000],
         banks=[0, 1, 0, 1, 0, 1], runners=[.0033, .0038, .0029, .0036, .0031, .0040],
         resonances=[(125, .57), (290, .34), (680, .14)], cutoff=2100,
         pulse_ms=3.0, uneven=.07, intake=.12, turbo=False,
         description="V6 aspirado de utilitário, escape encorpado e menos agressivo; não atribui marca ou motor real aos SUVs ficcionais."),
    dict(id="sport_i4_na", label="I4 aspirado · esportivo leve", cylinders=4,
         rpm_bands=[960, 1440, 2160, 3240, 4560, 5880, 7200],
         banks=[0] * 4, runners=[.0018, .0024, .0020, .0022],
         resonances=[(185, .40), (480, .43), (1150, .25)], cutoff=3400,
         pulse_ms=1.7, uneven=.09, intake=.30, turbo=False,
         description="Quatro cilindros aspirado de alto giro para hatches preparados e esportivos leves; nenhuma turbina presumida."),
    dict(id="classic_i4_na", label="I4 aspirado · sedã e perua clássicos", cylinders=4,
         rpm_bands=[720, 1080, 1680, 2400, 3360, 4560, 5760],
         banks=[0] * 4, runners=[.0032, .0027, .0036, .0030],
         resonances=[(140, .45), (320, .29), (760, .13)], cutoff=2000,
         pulse_ms=2.7, uneven=.09, intake=.10, turbo=False,
         description="Quatro cilindros aspirado de rua para sedãs/peruas clássicos, com ritmo e escape próprios dos compactos antigos."),
]


def unit(x):
    x = x - np.mean(x)
    return x / max(float(np.sqrt(np.mean(x * x))), 1e-12)


def level(x, rms):
    x = unit(x) * rms
    return x * min(1., .90 / max(float(np.max(np.abs(x))), 1e-12))


def filtered_noise(rng, n, low, high):
    freq = np.fft.rfftfreq(n, 1 / RATE)
    response = (1 - np.exp(-(freq / low) ** 2)) / np.sqrt(1 + (freq / high) ** 6)
    return unit(np.fft.irfft(np.fft.rfft(rng.normal(size=n)) * response, n))


def combustion_base(profile, index, loaded):
    """Circular pressure-pulse convolution, one event/cylinder per 720 degrees.

    Randomness is seeded; FFT filtering is circular. Anchors are multiples of
    120 RPM, so every two-second loop contains an integer number of cycles.
    """
    rpm = profile["rpm_bands"][index]
    cycles = rpm / 120
    rng = np.random.default_rng(4417 + PROFILES.index(profile) * 500 + index * 3 + int(loaded))
    t = np.arange(FRAMES) / RATE
    freq = np.fft.rfftfreq(FRAMES, 1 / RATE)
    bank_count = max(profile["banks"]) + 1
    impulses = np.zeros((bank_count, FRAMES))
    cylinder_count = profile["cylinders"]
    # Small, periodic crank-speed variation; not independent pitch jitter.
    for cycle in range(round(cycles * FRAMES / RATE)):
        wander = .0025 * np.sin(2 * np.pi * cycle / (cycles * 2))
        for event, bank in enumerate(profile["banks"]):
            delay = profile["runners"][event]
            at = ((cycle + event / cylinder_count + wander) / cycles + delay) * RATE
            pos = int(np.floor(at))
            frac = at - pos
            strength = 1 + profile["uneven"] * np.cos(event * 2.399) + rng.normal(0, .045)
            impulses[bank, pos % FRAMES] += strength * (1 - frac)
            impulses[bank, (pos + 1) % FRAMES] += strength * frac
    pressure = np.zeros(FRAMES)
    progress = index / 6
    for bank in range(bank_count):
        tau = profile["pulse_ms"] / 1000 * (1 if loaded else .78)
        pulse = np.exp(-t / tau) - np.exp(-t / .00020)
        for resonance, amount in profile["resonances"]:
            f = resonance * (1 + bank * .025)
            pulse += amount * np.sin(2 * np.pi * f * t) * np.exp(-t / (.011 if loaded else .008))
        # Collector and tailpipe reflections; unequal bank paths preserve rumble.
        pulse -= .32 * np.roll(pulse, round((.0052 + bank * .0009) * RATE))
        pulse += .16 * np.roll(pulse, round((.013 + bank * .0013) * RATE))
        p = np.fft.irfft(np.fft.rfft(impulses[bank]) * np.fft.rfft(pulse), FRAMES)
        pressure += p * (1 if bank == 0 else .80)
    pressure = unit(pressure)
    air = filtered_noise(rng, FRAMES, 130, profile["cutoff"])
    turbulence = air * (.25 + .30 * np.minimum(np.abs(pressure), 2.5))
    intake = filtered_noise(rng, FRAMES, 650, min(6500, profile["cutoff"] * 1.7))
    # Inlet breathing follows firing order; no unrelated constant hiss.
    intake *= .45 + .55 * np.maximum(0, np.sin(2 * np.pi * cycles * cylinder_count * t + .8))
    x = pressure + (.13 + progress * .20) * turbulence
    x += profile["intake"] * (0.3 + progress) * intake
    cutoff = profile["cutoff"] * (.85 + .60 * progress) * (1 if loaded else .55)
    response = (1 - np.exp(-(freq / 32) ** 2)) / np.sqrt(1 + (freq / cutoff) ** 6)
    x = np.fft.irfft(np.fft.rfft(x) * response, FRAMES)
    x = np.tanh(unit(x) * (.68 if loaded else .48))
    return level(x, .185 if loaded else .085)


def combustion_low(profile, index, loaded):
    """Long low-RPM cycle: varying pressure shapes instead of sustained ringing.

    Three short impulse responses vary combustion duration event by event.
    Correlated cycle torque and valve noise retain firing order without making
    a perfectly repeating oscillator. All filtering is circular at the seam.
    """
    rpm = profile["rpm_bands"][index]
    cycles = rpm / 120
    n = LOW_FRAMES
    rng = np.random.default_rng(81237 + PROFILES.index(profile) * 500 + index * 3 + int(loaded))
    t = np.arange(n) / RATE
    freq = np.fft.rfftfreq(n, 1 / RATE)
    bank_count = max(profile["banks"]) + 1
    nc = round(cycles * n / RATE)
    count = profile["cylinders"]
    impulses = np.zeros((bank_count, 3, n))
    mechanical = np.zeros(n)
    # Circular, correlated variations in cycle torque; no periodic vibrato.
    torque = rng.normal(size=nc)
    torque = sum(np.roll(torque, k) * w for k, w in [(-2, 1), (-1, 2), (0, 3), (1, 2), (2, 1)]) / 9
    torque = unit(torque)
    diesel = profile.get("fuel") == "diesel"
    rough = .05 if count >= 10 else (.12 if count == 4 else .08)
    if profile["id"] == "v8_crossplane":
        rough = .14
    for cycle in range(nc):
        for event, bank in enumerate(profile["banks"]):
            drift = .004 * torque[cycle] + rng.normal(0, .0007)
            at = ((cycle + event / count + drift) / cycles + profile["runners"][event]) * RATE
            pos = int(np.floor(at))
            frac = at - pos
            strength = 1 + profile["uneven"] * np.cos(event * 2.399)
            strength *= 1 + rough * torque[cycle] + rng.normal(0, rough)
            shape = int(rng.integers(0, 3))
            impulses[bank, shape, pos % n] += strength * (1 - frac)
            impulses[bank, shape, (pos + 1) % n] += strength * frac
            # Valve/injection transients follow the same cylinders.
            valve_pos = (pos + round(.0034 * RATE)) % n
            mechanical[valve_pos] += strength * rng.uniform(.5, 1.25)
    pressure = np.zeros(n)
    for bank in range(bank_count):
        for variant, length in enumerate((.78, 1., 1.24)):
            tau = profile["pulse_ms"] / 1000 * length * (1.15 if loaded else .85)
            pulse = np.exp(-t / tau) - np.exp(-t / (.00013 if diesel else .00042))
            # Shorter, quieter cavity tails remove the low-speed tuned drone.
            for resonance, amount in profile["resonances"]:
                pulse += amount * .22 * np.sin(2 * np.pi * resonance * (1 + .035 * bank) * t) * np.exp(-t / .0042)
            pulse -= .24 * np.roll(pulse, round((.0057 + bank * .0012) * RATE))
            pulse += .09 * np.roll(pulse, round((.012 + bank * .0016) * RATE))
            p = np.fft.irfft(np.fft.rfft(impulses[bank, variant]) * np.fft.rfft(pulse), n)
            pressure += p * (1 if bank == 0 else .80)
    pressure = unit(pressure)
    exhaust_air = filtered_noise(rng, n, 65, 1250 if diesel else 1700)
    breath = exhaust_air * (.12 + .40 * np.minimum(np.abs(pressure), 2))
    clack_ir = (np.exp(-t / .00055) - np.exp(-t / .00007))
    clack_ir -= .6 * np.roll(clack_ir, round(.0008 * RATE))
    clack = unit(np.fft.irfft(np.fft.rfft(mechanical) * np.fft.rfft(clack_ir), n))
    mechanical_air = filtered_noise(rng, n, 700, 3400)
    mechanical_air *= .18 + .22 * np.minimum(np.abs(clack), 2)
    x = pressure + .28 * breath + (.18 if diesel else .055) * clack
    x += (.18 if diesel else .075) * mechanical_air
    cutoff = (2200 if diesel else min(profile["cutoff"], 2600)) * (1 if loaded else .68)
    response = (1 - np.exp(-(freq / 28) ** 2)) / np.sqrt(1 + (freq / cutoff) ** 6)
    x = np.fft.irfft(np.fft.rfft(x) * response, n)
    x = np.tanh(unit(x) * (.47 if loaded else .37))
    return level(x, .185 if loaded else .085)


def combustion(profile, index, loaded):
    if profile["rpm_bands"][index] <= 1500:
        return combustion_low(profile, index, loaded)
    return combustion_base(profile, index, loaded)


def ensure_pcm_import(path):
    """Keep this pack's Godot imports lossless without replacing existing UIDs.

    Only the authored audio/engine_design subtree is owned here. Previews,
    external --output folders and existing legacy banks are left alone.
    """
    path = Path(path).resolve()
    pack_root = (ROOT / "audio/engine_design").resolve()
    if path.suffix.lower() != ".wav" or not path.is_relative_to(pack_root):
        return False
    resource = "res://" + path.relative_to(ROOT).as_posix()
    digest = hashlib.md5(resource.encode("utf-8")).hexdigest()
    imported = f"res://.godot/imported/{path.name}-{digest}.sample"
    target = path.with_suffix(path.suffix + ".import")
    previous = target.read_text(encoding="utf-8-sig") if target.exists() else ""
    updated = previous
    sections = {
        "remap": {"importer": '"wav"', "type": '"AudioStreamWAV"', "path": json.dumps(imported)},
        "deps": {"source_file": json.dumps(resource), "dest_files": json.dumps([imported])},
        "params": {"force/8_bit": "false", "force/mono": "false", "force/max_rate": "false",
                   "force/max_rate_hz": "44100", "edit/trim": "false", "edit/normalize": "false",
                   "edit/loop_mode": "0", "edit/loop_begin": "0", "edit/loop_end": "-1",
                   "compress/mode": "0"},
    }
    for section, settings in sections.items():
        pattern = rf"(?ms)^\[{re.escape(section)}\][ \t]*\n(.*?)(?=^\[|\Z)"
        match = re.search(pattern, updated)
        body = match.group(1) if match else "\n"
        for key, value in settings.items():
            line = f"{key}={value}"
            key_pattern = rf"(?m)^{re.escape(key)}[ \t]*=.*$"
            if re.search(key_pattern, body):
                body = re.sub(key_pattern, lambda _: line, body, count=1)
            else:
                body = body.rstrip() + "\n" + line + "\n\n"
        replacement = f"[{section}]\n{body}"
        if match:
            updated = updated[:match.start()] + replacement + updated[match.end():]
        else:
            updated = updated.rstrip() + "\n\n" + replacement
    updated = updated.lstrip("\n").rstrip() + "\n"
    if updated == previous:
        return False
    target.write_text(updated, encoding="utf-8")
    return True


def write_wave(path, signal, loop=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not np.isfinite(signal).all() or np.max(np.abs(signal)) >= .98:
        raise ValueError(f"Invalid output samples: {path}")
    pcm = np.rint(signal * 32767).astype("<i2")
    if loop:
        pcm = np.concatenate([pcm, pcm[:GUARD]])
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm.tobytes())
    ensure_pcm_import(path)
    return hashlib.sha256(path.read_bytes()).hexdigest()


def smoothstep(low, high, x):
    x = np.clip((x - low) / (high - low), 0, 1)
    return x * x * (3 - 2 * x)


def smooth_signal(x, seconds):
    a = np.exp(-1 / (RATE * seconds))
    return lfilter([1 - a], [1, -a], x, zi=[a * x[0]])[0]


def turbo_assets(profile):
    rng = np.random.default_rng(303 + PROFILES.index(profile))
    t = np.arange(FRAMES) / RATE
    base = 2350 if profile["id"].startswith("jz2") else 2900
    if profile.get("fuel") == "diesel":
        base = 1800
    spool = .55 * filtered_noise(rng, FRAMES, 1400, 7000)
    spool += .30 * np.sin(2 * np.pi * base * t + .4 * np.sin(2 * np.pi * 7 * t))
    spool += .08 * np.sin(2 * np.pi * base * 2 * t)
    spool = level(spool, .05)
    n = round(.68 * RATE)
    tt = np.arange(n) / RATE
    release = filtered_noise(rng, n, 900, 6500)
    # Bypass pressure release, not sustained compressor surge/flutter.
    release *= (1 - np.exp(-tt / .012)) * np.exp(-tt / .13)
    release *= np.clip((.68 - tt) / .12, 0, 1)
    release = release / np.max(np.abs(release)) * .18
    release[0] = release[-1] = 0
    return spool, release


def timeline(profile, low_only=False):
    idle, top = profile["rpm_bands"][0], profile["rpm_bands"][-1]
    segments = [
        (1.4, idle, idle, 0., "marcha_lenta"),
        (1.1, idle, top * .32, .32, "aceleracao_parcial"),
        (2.5, top * .32, top * .96, 1., "primeira"),
        (.20, top * .96, top * .61, 0., "troca_1_2"),
        (2.5, top * .61, top * .98, 1., "segunda"),
        (.20, top * .98, top * .66, 0., "troca_2_3"),
        (2.8, top * .66, top, 1., "terceira"),
        (2.6, top, top * .38, 0., "freio_motor"),
        (2., top * .38, idle, 0., "retorno_marcha_lenta"),
        (.8, idle, idle, 0., "marcha_lenta_final"),
    ]
    if low_only:
        segments = [(4., idle, idle, 0., "marcha_lenta"),
                    (3., idle, 1500., .32, "subida_ate_1500"),
                    (2., 1500., 1500., .25, "carga_parcial_1500"),
                    (2., 1500., idle, 0., "retorno_marcha_lenta"),
                    (2., idle, idle, 0., "marcha_lenta_final")]
    rpm, load, events = [], [], []
    frame = 0
    for duration, start, end, throttle, label in segments:
        count = round(duration * RATE)
        rpm.append(np.linspace(start, end, count, endpoint=False))
        load.append(np.full(count, throttle))
        events.append(dict(at_seconds=frame / RATE, duration_seconds=duration, state=label,
                           rpm_start=start, rpm_end=end, throttle=throttle))
        frame += count
    return np.concatenate(rpm), smooth_signal(np.concatenate(load), .025), events


def sample_loop(signal, position):
    base = np.floor(position).astype(np.int64)
    fraction = position - base
    return signal[base % len(signal)] * (1 - fraction) + signal[(base + 1) % len(signal)] * fraction


def demo(profile, loaded, coast, spool=None, release=None, low_only=False):
    rpm, load, events = timeline(profile, low_only)
    crank_cycles = np.cumsum(rpm / (120 * RATE))
    anchors = np.asarray(profile["rpm_bands"])
    fractional_band = np.interp(np.log(rpm), np.log(anchors), np.arange(7))
    out = np.zeros(len(rpm))
    for i in range(7):
        weight = np.sqrt(np.clip(1 - np.abs(fractional_band - i), 0, 1))
        # One crank phase keeps all band readers at the same physical RPM.
        position = crank_cycles / (anchors[i] / 120) * RATE
        drive = sample_loop(loaded[i], position)
        overrun = sample_loop(coast[i], position)
        # Idle always fires. Off-throttle at speed switches to the coast bank.
        combustion_load = np.maximum(load, 1 - smoothstep(anchors[0] * 1.1, anchors[0] * 1.8, rpm))
        out += weight * (drive * np.sqrt(combustion_load) + overrun * np.sqrt(1 - combustion_load))
    if spool is not None:
        target = load * smoothstep(anchors[-1] * .32, anchors[-1] * .72, rpm)
        boost = np.zeros(len(rpm))
        for i in range(1, len(boost)):
            tau = .48 if target[i] > boost[i - 1] else .13
            boost[i] = boost[i - 1] + (target[i] - boost[i - 1]) * (1 - np.exp(-1 / (RATE * tau)))
        out += sample_loop(spool, np.cumsum(.72 + boost * .48)) * boost ** 1.6
        for event in events:
            if event["state"].startswith("troca") or event["state"] == "freio_motor":
                start = round(event["at_seconds"] * RATE)
                stored = float(boost[max(0, start - 1)])
                if release is not None and stored > .2:
                    count = min(len(release), len(out) - start)
                    out[start:start + count] += release[:count] * stored
    fade = round(.07 * RATE)
    out[:fade] *= np.linspace(0, 1, fade)
    out[-fade:] *= np.linspace(1, 0, fade)
    return out, events


def read_loop(path):
    with wave.open(str(path), "rb") as wav:
        if (wav.getframerate(), wav.getnchannels(), wav.getsampwidth()) != (RATE, 1, 2):
            raise ValueError(f"Unexpected baseline format: {path}")
        return np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2")[:-GUARD].astype(float) / 32768


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "audio/engine_design")
    parser.add_argument("--previews", type=Path, default=ROOT / "artifacts/engine-sound-design-20261016/demos")
    parser.add_argument("--baseline", type=Path, default=ROOT / "artifacts/engine-sound-design-20261016/baseline-v1")
    args = parser.parse_args()
    marker = args.output / "manifest.json"
    if args.output.exists() and any(args.output.iterdir()):
        if not marker.exists() or json.loads(marker.read_text(encoding="utf-8")).get("generator") != "build_engine_design_pack.py":
            raise SystemExit("Output contains files not owned by this generator; select a new directory.")
    manifest = dict(schema_version=2, generator="build_engine_design_pack.py", sample_rate=RATE,
                    channels=1, pcm_bits=16, default_loop_frames=FRAMES, guard_frames=GUARD,
                    provenance="Original offline procedural synthesis; no source recordings or downloaded samples.",
                    status="fleet_runtime_enabled", profiles=[])
    previews = []
    for profile in PROFILES:
        entry = {key: profile[key] for key in ("id", "label", "description", "cylinders", "rpm_bands", "turbo")}
        entry.update(architecture="piston_four_stroke", fuel=profile.get("fuel", "petrol"),
                     bypass_valve=profile.get("bypass_valve", profile["turbo"]),
                     band_frames=[LOW_FRAMES if rpm <= 1500 else FRAMES for rpm in profile["rpm_bands"]])
        entry.update(loaded=[], coast=[], effects={}, sha256={}, nominal_cycles_per_second=[x / 120 for x in profile["rpm_bands"]])
        banks = {}
        for state, prefix in [("loaded", "engine"), ("coast", "coast")]:
            signals = []
            for i in range(7):
                x = combustion(profile, i, state == "loaded")
                name = f"{profile['id']}/{prefix}_{profile['id']}_{i}.wav"
                entry["sha256"][name] = write_wave(args.output / name, x, loop=True)
                entry[state].append(name)
                # Preview the quantized samples delivered to the game, minus guard.
                signals.append(np.rint(x * 32767) / 32768.)
            banks[state] = signals
        spool, release = None, None
        if profile["turbo"]:
            spool, release = turbo_assets(profile)
            effect_assets = [("turbo_spool", spool, True)]
            if entry["bypass_valve"]:
                effect_assets.append(("bypass_release", release, False))
            else:
                release = None
            for effect, signal, loop in effect_assets:
                name = f"{profile['id']}/{effect}.wav"
                entry["sha256"][name] = write_wave(args.output / name, signal, loop)
                entry["effects"][effect] = dict(path=name, loop=loop, guard_frames=GUARD if loop else 0)
        rendered, events = demo(profile, banks["loaded"], banks["coast"], spool, release)
        previews.append((profile, rendered, events))
        low, low_events = demo(profile, banks["loaded"], banks["coast"], low_only=True)
        write_wave(args.previews / f"{profile['id']}_idle_to_1500.wav", low)
        baseline_profile = args.baseline / profile["id"]
        low_metadata = dict(profile=profile["id"], events=low_events)
        if baseline_profile.is_dir():
            original_loaded = [read_loop(baseline_profile / f"engine_{profile['id']}_{i}.wav") for i in range(7)]
            original_coast = [read_loop(baseline_profile / f"coast_{profile['id']}_{i}.wav") for i in range(7)]
            before, _ = demo(profile, original_loaded, original_coast, low_only=True)
            write_wave(args.previews / f"{profile['id']}_idle_before_after.wav",
                       np.concatenate([before, np.zeros(round(.8 * RATE)), low]))
            low_metadata.update(before_after_order=["v1", "revised"], comparison_new_starts_at_seconds=13.8)
        (args.previews / f"{profile['id']}_idle_to_1500.json").write_text(
            json.dumps(low_metadata, indent=2), encoding="utf-8")
        manifest["profiles"].append(entry)
        print(f"Authored {profile['id']}: 14 loops, {len(entry['effects'])} effects", flush=True)
    # Common gain preserves differences between engines and avoids per-file AGC.
    gain = 1.0  # Preserve the exact gain of the acceleration approved in v1.
    if max(float(np.max(np.abs(x))) for _, x, _ in previews) >= .98:
        raise ValueError("A demo would clip at the approved common gain; revise its assets.")
    montage = []
    comparison = []
    offset = 0.
    for profile, x, events in previews:
        name = f"{profile['id']}_acceleration.wav"
        write_wave(args.previews / name, x * gain)
        (args.previews / name.replace(".wav", ".json")).write_text(json.dumps(dict(profile=profile["id"],
            common_gain=gain, duration_seconds=len(x) / RATE, events=events), indent=2), encoding="utf-8")
        comparison.append(dict(profile=profile["id"], start_seconds=offset, duration_seconds=len(x) / RATE))
        montage.extend([x * gain, np.zeros(RATE)])
        offset += len(x) / RATE + 1
    write_wave(args.previews / "compare_all_engines.wav", np.concatenate(montage))
    write_wave(args.previews / "compare_original_engines_revised.wav", np.concatenate(montage[:8]))
    # Keep the five-engine comparison approved in the previous round stable.
    write_wave(args.previews / "compare_new_engines.wav", np.concatenate(montage[8:18]))
    if len(PROFILES) > 9:
        write_wave(args.previews / "compare_fleet_expansion.wav", np.concatenate(montage[18:]))
    (args.previews / "comparison.json").write_text(json.dumps(comparison, indent=2), encoding="utf-8")
    marker.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Pack: {args.output}\nPreviews: {args.previews}\nCommon demo gain: {gain:.4f}")


if __name__ == "__main__":
    main()
