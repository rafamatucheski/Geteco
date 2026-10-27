"""Som próprio do snowmobile (bike_snow), gerado offline; o jogo só toca os WAVs prontos.

Motor: bicilíndrico de dois tempos (uma explosão por cilindro a cada volta), com a câmara de
expansão do escapamento dando o zumbido rasgado e, na marcha lenta, o "ring-ding" de queimas
falhadas. Sete faixas no contrato do banco de motor (EngineBankCache): 22050 Hz, mono PCM16,
um segundo circular mais 8 quadros de guarda, em audio/acoustic/engine_snowmobile_<n>.wav.
Esteira: garras de borracha batendo na neve e chiado da neve espirrada, laço de 2 s em
audio/snowmobile/track.wav (pitch e volume seguem a velocidade em SnowmobileAudio.gd).
Nenhuma gravação de terceiros. Uso: python audio/snowmobile/generate_snowmobile_audio.py
"""
from pathlib import Path
import json
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
ENGINE_RATE = 22050
GUARD = 8
TRACK_RATE = 24000
# Voltas por segundo de cada faixa: as mesmas de VehicleEngineProfile.NOMINAL["snowmobile"]
# (1500 a 8400 rpm). Inteiras, para o laço de um segundo fechar sem emenda.
REVS = [25, 35, 48, 65, 88, 115, 140]
CYLINDERS = 2
PIPE = 330.0  # ressonância da câmara de expansão (Hz)
REPORT = {}


def unit(signal):
    signal = signal - np.mean(signal)
    return signal / max(float(np.std(signal)), 1e-9)


def colored(rng, n, rate, low, high):
    freq = np.fft.rfftfreq(n, 1 / rate)
    spectrum = np.fft.rfft(rng.normal(size=n))
    spectrum *= np.minimum(1, (freq / max(low, 1)) ** 2) * np.exp(-(freq / high) ** 2)
    spectrum[0] = 0
    return unit(np.fft.irfft(spectrum, n))


def engine(index):
    rng = np.random.default_rng(51027 + index)
    n = ENGINE_RATE
    t = np.arange(n) / ENGINE_RATE
    events = REVS[index] * CYLINDERS
    impulses = np.zeros(n)
    # Marcha lenta de dois tempos queima de forma irregular: parte das explosões falha e as
    # outras variam muito de força. Com carga a queima fica regular.
    misfire = .28 if index == 0 else (.08 if index == 1 else 0.0)
    for event in range(events):
        if rng.uniform() < misfire:
            continue
        at = (event + rng.uniform(-.02, .02)) * n / events
        amplitude = 1 + .12 * (event % CYLINDERS) + rng.uniform(-.35, .35) * (1.6 if index == 0 else 1.0)
        pos = int(np.floor(at))
        frac = at - pos
        impulses[pos % n] += amplitude * (1 - frac)
        impulses[(pos + 1) % n] += amplitude * frac
    # Pulso curto e seco (porta de escape abrindo) e o anel da câmara de expansão, que é o que
    # separa o dois tempos do quatro tempos da moto: mais agudo e rasgado.
    pulse = np.exp(-t / .0016) - np.exp(-t / .0002)
    pulse += .55 * np.sin(2 * np.pi * PIPE * t) * np.exp(-t / .009)
    pulse += .18 * np.sin(2 * np.pi * PIPE * 3.1 * t) * np.exp(-t / .004)
    pressure = unit(np.fft.irfft(np.fft.rfft(impulses) * np.fft.rfft(pulse), n))
    # Batida de pistão e admissão: ruído agudo que respira com cada explosão.
    rattle = colored(rng, n, ENGINE_RATE, 1800, 5200) * (.5 + .5 * np.clip(np.abs(pressure), 0, 2.5))
    intake = colored(rng, n, ENGINE_RATE, 120, 1400)
    signal = .72 * pressure + (.10 + .02 * index) * rattle + (.16 + .015 * index) * intake
    freq = np.fft.rfftfreq(n, 1 / ENGINE_RATE)
    spectrum = np.fft.rfft(signal)
    spectrum *= (1 - np.exp(-(freq / 60) ** 2)) / np.sqrt(1 + (freq / 3600) ** 4)
    signal = np.tanh(unit(np.fft.irfft(spectrum, n)) * .7)
    return unit(signal) * .245


def track():
    rng = np.random.default_rng(81027)
    n = TRACK_RATE * 2
    t = np.arange(n) / TRACK_RATE
    values = np.zeros(n)
    # 22 garras por segundo na velocidade de referência (pitch 1); alternância leve entre elas.
    lugs = 44
    for lug in range(lugs):
        age = (t - lug / 22 + rng.uniform(-.003, .003)) % 2
        thump = np.sin(2 * np.pi * 150 * age) * np.exp(-age * 70)
        slap = np.sin(2 * np.pi * 620 * age + 1.1) * np.exp(-age * 160)
        values += (.32 * thump + .14 * slap) * (1.0 if lug % 2 else .84)
    # Neve espirrada: chiado largo que pulsa com as garras.
    beat = np.maximum(0, np.sin(2 * np.pi * 22 * t)) ** 3
    values += colored(rng, n, TRACK_RATE, 700, 5200) * (.10 + .08 * beat)
    values += colored(rng, n, TRACK_RATE, 60, 400) * .07
    return values


def write(path, values, rate, guard=0, peak=None):
    values = values - np.mean(values)
    if peak is not None:
        values *= peak / max(float(np.max(np.abs(values))), 1e-9)
    assert np.isfinite(values).all() and np.max(np.abs(values)) < .98
    data = np.concatenate([values, values[:guard]]) if guard else values
    pcm = np.rint(data * 32767).astype("<i2")
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(pcm.tobytes())
    REPORT[path.name] = {"seconds": len(values) / rate, "peak": float(np.max(np.abs(values))),
                         "rms": float(np.std(values)), "seam_step": float(abs(values[0] - values[-1]))}


def main():
    for index in range(7):
        write(ROOT / f"audio/acoustic/engine_snowmobile_{index}.wav", engine(index), ENGINE_RATE, GUARD)
    write(ROOT / "audio/snowmobile/track.wav", track(), TRACK_RATE, peak=.7)
    print(json.dumps(REPORT, indent=2))


if __name__ == "__main__":
    main()
