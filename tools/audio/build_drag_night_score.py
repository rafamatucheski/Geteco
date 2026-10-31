"""Compõe/renderiza a trilha original Noite de Acerto do Geteco, toda offline.

Sem amostras, melodias ou serviços de modelo externos. Requer numpy/scipy/soundfile.
Duas faixas de 32 compassos alinhadas em fase; reprodução Ogg nativa e limitada no jogo.
Rodar de qualquer pasta: python tools/audio/build_drag_night_score.py
"""
from pathlib import Path
import hashlib
import json

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "audio/drag_night"
RATE = 44100
BPM = 104
BEAT = 60 / BPM
BARS = 32
N = round(BEAT * 4 * BARS * RATE)
RNG = np.random.default_rng(20261018)


def hz(note):
    return 440 * 2 ** ((note - 69) / 12)


def time(seconds):
    return np.arange(round(seconds * RATE)) / RATE


def filtered_noise(t, lo, hi):
    return sosfilt(butter(2, [lo, hi], "bandpass", fs=RATE, output="sos"), RNG.normal(size=len(t)))


def add(dest, wave, beat, gain=1, pan=0):
    # As caudas voltam para o compasso um, e o loop mantém o decaimento e o som da sala.
    indices = (round(beat * BEAT * RATE) + np.arange(len(wave))) % N
    stereo = wave[:, None] * np.array([np.sqrt((1 - pan) / 2), np.sqrt((1 + pan) / 2)])
    dest[indices] += stereo * gain


def kick():
    t = time(.42)
    phase = 2 * np.pi * (47 * t + 1.1 * (1 - np.exp(-t * 36)))
    return np.sin(phase) * np.exp(-t * 11) * np.minimum(t / .002, 1)


def snare():
    t = time(.24)
    snap = filtered_noise(t, 1300, 6900) * np.exp(-t * 33)
    body = .25 * np.sin(2 * np.pi * 184 * t) * np.exp(-t * 38)
    return (snap * .6 + body) * np.minimum(t / .0015, 1)


def hat(opened=False):
    t = time(.17 if opened else .055)
    return filtered_noise(t, 5100, 11000) * np.exp(-t * (28 if opened else 90)) * np.minimum(t / .001, 1)


def knock():
    t = time(.13)
    wave = np.sin(2 * np.pi * 737 * t) + .35 * np.sin(2 * np.pi * 1211 * t)
    return wave * np.exp(-t * 58) * np.minimum(t / .002, 1)


def bass(note, beats):
    t = time(beats * BEAT)
    f = hz(note)
    wave = np.sin(2 * np.pi * f * t) + .27 * np.sin(2 * np.pi * 2 * f * t) + .09 * np.sin(2 * np.pi * 3 * f * t)
    env = np.minimum(t / .012, 1) * np.minimum((len(t) / RATE - t) / .06, 1)
    return wave * env * np.exp(-t * 1.1)


def key(note, beats=2.4):
    t = time(beats * BEAT)
    f = hz(note)
    # Ataque arredondado de piano elétrico, parciais desafinados, nenhuma gravação emprestada.
    wave = np.sin(2 * np.pi * f * t + .8 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 12))
    wave += .14 * np.sin(2 * np.pi * f * 1.002 * t)
    return wave * np.minimum(t / .007, 1) * np.exp(-t * 2.6) * np.minimum((len(t) / RATE - t) / .09, 1)


def chord(notes):
    t = time(5.4 * BEAT)
    wave = np.zeros_like(t)
    for note in notes:
        f = hz(note)
        wave += np.sin(2 * np.pi * f * t) + .16 * np.sin(2 * np.pi * 2.002 * f * t)
    env = np.minimum(t / .22, 1) * np.minimum((len(t) / RATE - t) / .85, 1)
    return wave * env / len(notes)


def measure(samples):
    peak = float(np.max(np.abs(samples)))
    rms = float(np.sqrt(np.mean(samples ** 2)))
    return {"peak_dbfs": round(20 * np.log10(max(peak, 1e-12)), 3),
            "rms_dbfs": round(20 * np.log10(max(rms, 1e-12)), 3),
            "clipped_samples": int(np.count_nonzero(np.abs(samples) >= 1)),
            "seam_step": float(np.max(np.abs(samples[0] - samples[-1]))),
            "max_adjacent_step": float(np.max(np.abs(np.diff(samples, axis=0))))}


def write_ogg(path, samples):
    # O gravador Vorbis do libsndfile no Windows é confiável com gravações limitadas; não
    # passe o array estéreo inteiro de 74 segundos numa chamada nativa só.
    with sf.SoundFile(path, "w", samplerate=RATE, channels=2, format="OGG", subtype="VORBIS") as file:
        for start in range(0, len(samples), 32768):
            file.write(samples[start:start + 32768])


def build():
    print("Composing 32 bars...", flush=True)
    OUT.mkdir(exist_ok=True)
    harmony = np.zeros((N, 2))
    pulse = np.zeros((N, 2))
    chords = [[62, 65, 69, 76], [58, 62, 65, 72], [60, 64, 67, 74], [57, 62, 64, 71]]
    roots = [38, 34, 36, 33]
    motif = [(0, 74), (.75, 77), (1.5, 76), (3, 69)]
    for bar in range(BARS):
        b = bar * 4
        section = bar // 8
        harmony_gain = .27 if section != 2 else .19
        if bar % 2 == 0:
            add(harmony, chord(chords[(bar // 2) % 4]), b, harmony_gain, -.14)
        if bar % 4 in (1, 3):
            for off, note in motif:
                if section == 2 and off < 1.5:
                    continue
                note += -2 if bar % 8 == 7 else 0
                sound = key(note)
                add(harmony, sound, b + off, .105, .28)
                add(harmony, sound, b + off + .75, .026, -.42)
        if section == 2 and bar % 4 == 0:
            add(harmony, key(81, 4), b + 2.5, .08, -.3)
        # Contratempo quebrado com quatro arranjos de oito compassos e pequena variação
        # determinística de intensidade/tempo; nunca uma sirene de corrida constante ou metrônomo.
        kicks = [0, 1.75, 2.5] if bar % 2 == 0 else [0, 2, 3.25]
        if section == 2:
            kicks = [0, 2.5]
        for off in kicks:
            add(pulse, kick(), b + off, .48)
        for off in [1, 3]:
            add(pulse, snare(), b + off + .014, .26, -.05)
        for step in range(8):
            if section == 2 and step % 2:
                continue
            off = step * .5 + (.045 if step % 2 else 0)
            add(pulse, hat(step == 7 and bar % 2 == 1), b + off, .063 + RNG.uniform(-.012, .012), .22 if step % 2 else -.2)
        for off in [.75, 2.75]:
            if bar % 4 != 2:
                add(pulse, knock(), b + off, .052, -.42)
        root = roots[(bar // 2) % 4]
        for off, note, length in [(0, root, .70), (1.75, root, .43), (2.5, root + 7, .65), (3.5, root + 12, .36)]:
            add(pulse, bass(note, length), b + off, .19)
        if bar % 8 == 7:
            for off in [3.5, 3.75]:
                add(pulse, snare(), b + off, .075, .15)
    # O ganho comum preserva o equilíbrio pretendido entre as faixas. Abaixar a música é do
    # runtime; os dois assets continuam alinhados em fase e testáveis em separado.
    scale = 10 ** (-5 / 20) / np.max(np.abs(harmony + pulse))
    harmony *= scale
    pulse *= scale
    report = {"title": "Noite de Acerto", "bpm": BPM, "bars": BARS, "meter": "4/4", "key": "D minor", "sample_rate": RATE,
              "frames": N, "seconds": N / RATE, "source": "Original deterministic synthesis; no external samples or referenced composition", "files": {}}
    for name, samples in [("patio", harmony), ("pulso", pulse)]:
        path = OUT / (name + ".ogg")
        print("Encoding " + name, flush=True)
        write_ogg(path, samples)
        decoded, rate = sf.read(path)
        report["files"][name] = {**measure(decoded), "frames": len(decoded), "rate": rate,
                                  "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    preview = harmony + pulse
    preview_path = ROOT / "artifacts/rachas-continuation-20261018/noite_de_acerto_preview.ogg"
    preview_path.parent.mkdir(exist_ok=True, parents=True)
    write_ogg(preview_path, preview)
    decoded, _ = sf.read(preview_path)
    report["preview"] = measure(decoded)
    (OUT / "composition.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    build()
