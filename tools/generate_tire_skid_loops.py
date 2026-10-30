"""Gera OFFLINE os loops de pneu cantando (derrapagem, freio de mão, patinada).

Playtest 30/10: "o freio de mão e o drift: o som é terrível". Os skid_*.wav antigos eram 1 s a
22 050 Hz com um seno puro (pico estreito ~18 dB acima do vizinho), tremolo fixo de ~13 Hz e
ruído branco chapado até 11 kHz (4-8 kHz a só -9,6 dB do total; centróide 1,8-2,5 kHz). Envelope
constante (variação de 4% em blocos de 20 ms): a repetição a cada 1 s e o "bip" eram audíveis.

Aqui o pneu é montado em três camadas, cada uma um loop sem costura (todos os moduladores são
ruído periódico feito no domínio da frequência e as fases fecham em número inteiro de ciclos):
  - tire_squeal_<tipo>.wav: guincho tonal (dois pneus levemente desafinados, harmônicos 2-4,
    deriva lenta de tom, aspereza de stick-slip, banda estreita de ruído em volta da nota),
    passa-baixa em ~3,6 kHz;
  - tire_rubber_body.wav: borracha grave/rumble (80-600 Hz, granulado);
  - tire_scrub_hiss.wav: chiado leve de raspagem, para o começo da deriva.
Os comprimentos diferem (3,0 / 2,6 / 3,4 s) para as camadas não realinharem juntas.

Cada arquivo leva 8 amostras extras que repetem o começo: o jogo usa loop_end = total - 8
(VehicleTireEffects.prewarm_skid_audio / DesertCarAudio._loop), e assim o salto é contínuo.

Uso: python tools/generate_tire_skid_loops.py   (grava em audio/vehicle_fx/)
Nada disto roda no jogo.
"""
import wave
from pathlib import Path

import numpy as np

RATE = 44100
TAIL = 8
OUT = Path(__file__).resolve().parent.parent / "audio" / "vehicle_fx"

# Nota base do guincho por tipo; o jogo ainda aplica o tom fixo do carro (peso) e ±5% pelo slip.
SQUEAL_KINDS = {
	"street": {"f0": 900.0, "seed": 11, "rasp": .9},
	"sport": {"f0": 1100.0, "seed": 23, "rasp": .75},
	"heavy": {"f0": 620.0, "seed": 37, "rasp": 1.25},
	"muscle": {"f0": 760.0, "seed": 41, "rasp": 1.1},
	"monaliza": {"f0": 1000.0, "seed": 53, "rasp": .85},
}


def band_noise(n, lo, hi, rng, tilt=0.0):
	"""Ruído periódico (período n) limitado a [lo, hi] Hz, média zero, desvio 1."""
	spec = np.fft.rfft(rng.standard_normal(n))
	f = np.fft.rfftfreq(n, 1.0 / RATE)
	edge = np.clip((f - lo * .8) / (lo * .2 + 1e-9), 0, 1) * np.clip((hi * 1.25 - f) / (hi * .25), 0, 1)
	if tilt:
		edge = edge * np.power(np.maximum(f, 1.0) / max(lo, 1.0), tilt)
	spec *= edge
	spec[0] = 0.0
	x = np.fft.irfft(spec, n)
	return x / (x.std() + 1e-12)


def shape(x, lowpass, highpass, order=4):
	"""Filtro circular (preserva o loop): passa-alta e passa-baixa tipo Butterworth em módulo."""
	spec = np.fft.rfft(x)
	f = np.fft.rfftfreq(len(x), 1.0 / RATE)
	gain = 1.0 / np.sqrt(1.0 + (f / lowpass) ** (2 * order))
	gain *= 1.0 / np.sqrt(1.0 + (highpass / np.maximum(f, 1e-3)) ** (2 * order))
	return np.fft.irfft(spec * gain, len(x))


def partial(n, seconds, f0, rng):
	"""Fase de um pneu: nota que fecha em ciclos inteiros + deriva/aspereza de média zero."""
	cycles = round(f0 * seconds)
	f = cycles / seconds
	# Deriva lenta (0,15-2,5 Hz) de ~1,8% e tremido de stick-slip (18-70 Hz) de ~0,5%.
	dev = .018 * band_noise(n, .15, 2.5, rng) + .005 * band_noise(n, 18.0, 70.0, rng)
	dev -= dev.mean()
	inc = f * (1.0 + dev) / RATE
	# Fase exclusiva: phase[0] = 0 e phase[n] = ciclos inteiros, sem salto no loop.
	phase = 2 * np.pi * np.concatenate(([0.0], np.cumsum(inc)[:-1]))
	return phase, f


def squeal(kind, cfg):
	seconds = 3.0
	n = int(RATE * seconds)
	rng = np.random.default_rng(cfg["seed"])
	out = np.zeros(n)
	# Dois pneus traseiros: mesma nota com ~1,7% de diferença -> batimento lento e natural.
	for detune, amp in ((1.0, 1.0), (1.017, .62)):
		phase, _ = partial(n, seconds, cfg["f0"] * detune, rng)
		tone = np.sin(phase) + .38 * np.sin(2 * phase + .7) + .16 * np.sin(3 * phase + 1.9) + .06 * np.sin(4 * phase + .3)
		# Envelope irregular próprio de cada pneu (1,2-8 Hz) e aspereza rápida (25-60 Hz).
		am = 1.0 + .32 * band_noise(n, 1.2, 8.0, rng) + .10 * cfg["rasp"] * band_noise(n, 25.0, 60.0, rng)
		out += amp * tone * np.clip(am, .15, 2.0)
	# Leve saturação: a borracha não é um seno limpo.
	out = np.tanh(.9 * out / np.abs(out).max() * 1.6)
	# Banda estreita de ruído em volta da nota e da 2ª harmônica: dá corpo e tira o "bip".
	f0 = cfg["f0"]
	width = band_noise(n, f0 * .9, f0 * 1.1, rng) * .22 + band_noise(n, f0 * 1.85, f0 * 2.15, rng) * .10
	width *= 1.0 + .4 * band_noise(n, 2.0, 12.0, rng)
	out = out / out.std() + width * cfg["rasp"]
	# Um fio de borracha grave já no guincho, para ele não flutuar sozinho.
	out += .12 * cfg["rasp"] * band_noise(n, 90.0, 380.0, rng)
	out = shape(out, lowpass=3600.0, highpass=260.0)
	return out


def rubber_body():
	"""Borracha grave do pneu arrastando (rumble granulado), base do freio travado."""
	seconds = 2.6
	n = int(RATE * seconds)
	rng = np.random.default_rng(71)
	core = band_noise(n, 70.0, 520.0, rng, tilt=-.35)
	grain = 1.0 + .55 * band_noise(n, 9.0, 32.0, rng) + .25 * band_noise(n, 1.0, 5.0, rng)
	out = core * np.clip(grain, .05, 2.2)
	# Ronco de rolagem travada: um pouco de 35-60 Hz.
	out += .35 * band_noise(n, 35.0, 60.0, rng)
	return shape(out, lowpass=900.0, highpass=45.0)


def scrub_hiss():
	"""Raspagem leve, sem agudo estridente (centróide ~1,6 kHz, nada acima de ~4,5 kHz)."""
	seconds = 3.4
	n = int(RATE * seconds)
	rng = np.random.default_rng(89)
	core = band_noise(n, 700.0, 3800.0, rng, tilt=-.8)
	am = 1.0 + .30 * band_noise(n, 2.5, 10.0, rng) + .15 * band_noise(n, 30.0, 80.0, rng)
	out = core * np.clip(am, .1, 2.0)
	return shape(out, lowpass=3200.0, highpass=500.0)


def write(name, x, rms_db, peak_db=-3.0):
	x = x - x.mean()
	x *= 10 ** (rms_db / 20) / (np.sqrt((x ** 2).mean()) + 1e-12)
	peak = np.abs(x).max()
	limit = 10 ** (peak_db / 20)
	if peak > limit:
		# Limitador suave só nos picos, para manter o RMS.
		x = limit * np.tanh(x / limit)
	x = np.concatenate((x, x[:TAIL]))
	pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
	path = OUT / name
	with wave.open(str(path), "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(RATE)
		w.writeframes(pcm.tobytes())
	print("gravado", path.relative_to(OUT.parent.parent), "%.2f s" % ((len(x) - TAIL) / RATE))


def main():
	OUT.mkdir(parents=True, exist_ok=True)
	for kind, cfg in SQUEAL_KINDS.items():
		write("tire_squeal_%s.wav" % kind, squeal(kind, cfg), -15.0)
	write("tire_rubber_body.wav", rubber_body(), -15.0)
	write("tire_scrub_hiss.wav", scrub_hiss(), -17.0)


if __name__ == "__main__":
	main()
