"""Original deterministic tank PCM, generated offline (no runtime synthesis or dependencies).

Authored for Geteco: additive diesel combustion, steel track shoes, starter,
large-bore muzzle pressure and debris impact. No sampled/third-party recordings.
Run: python audio/tank/generate_tank_audio.py
"""
from pathlib import Path
import json
import wave
import numpy as np

RATE = 24000
ROOT = Path(__file__).resolve().parent
RNG = np.random.default_rng(912028)
REPORT = {}


def noise(n, low, high):
    bins = np.fft.rfftfreq(n, 1 / RATE)
    spectrum = np.fft.rfft(RNG.normal(0, 1, n))
    spectrum *= np.minimum(1, (bins / max(low, 1)) ** 2)
    spectrum *= np.exp(-((bins / high) ** 2))
    spectrum[0] = 0
    values = np.fft.irfft(spectrum, n)
    return values / max(float(np.std(values)), 1e-9)


def write(name, values, peak=.82, loop=False):
    values -= np.mean(values)
    if not loop:
        attack = min(120, len(values) // 20)
        release = min(2400, len(values) // 12)
        values[:attack] *= np.linspace(0, 1, attack)
        values[-release:] *= np.linspace(1, 0, release)
    values *= peak / max(float(np.max(np.abs(values))), 1e-9)
    pcm = np.rint(values * 32767).astype('<i2')
    with wave.open(str(ROOT / (name + '.wav')), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    REPORT[name] = dict(seconds=len(values) / RATE, peak=float(np.max(np.abs(values))),
                        rms=float(np.sqrt(np.mean(values * values))),
                        seam=float(abs(values[-1] - values[0])), bytes=len(pcm) * 2)


def diesel():
    t = np.arange(RATE * 2) / RATE
    for index, crank in enumerate((10, 13, 16, 20, 24, 28, 33)):
        phase = 2 * np.pi * crank * t
        # Twelve-cylinder four-stroke pulse train, with an uneven low combustion rumble.
        rumble = .48 * np.sin(phase * 2) + .22 * np.sin(phase * 3 + .3)
        firing = .19 * np.sin(phase * 6 + .23 * np.sin(phase))
        firing += .065 * np.sin(phase * 12 + .7) + .025 * np.sin(phase * 18)
        knock = noise(len(t), 180, 2200) * (.035 + .055 * np.maximum(0, np.sin(phase * 6)) ** 8)
        air = noise(len(t), 50, 360) * (.045 + .004 * index)
        values = rumble + firing + knock + air
        # Circular noise and integral firing periods yield seamless loops; no silence gap.
        write('diesel_' + str(index), values, peak=.72, loop=True)


def tracks():
    t = np.arange(RATE * 2) / RATE
    values = .06 * noise(len(t), 90, 950)
    # Sixteen shoe contacts per second at the reference speed, with alternating links.
    for index in range(32):
        age = (t - index / 16) % 2
        env = np.exp(-age * 55)
        values += env * (.2 * np.sin(2 * np.pi * 420 * age)
                         + .1 * np.sin(2 * np.pi * 1060 * age)
                         + .09 * np.sin(2 * np.pi * 1730 * age)) * (1 if index % 2 else .82)
    values += .12 * noise(len(t), 280, 3000) * (0.3 + .7 * np.maximum(0, np.sin(2 * np.pi * 16 * t)) ** 7)
    write('tracks', values, peak=.73, loop=True)


def start():
    t = np.arange(round(RATE * 2.8)) / RATE
    spin = 2 * np.pi * (24 * t + 18 * t ** 2)
    starter = (.17 * np.sin(spin) + .1 * np.sin(spin * 3) + .06 * noise(len(t), 70, 950))
    starter *= np.clip((.9 - t) * 5, 0, 1)
    catch = np.clip((t - .48) / .5, 0, 1)
    crank = 2 * np.pi * (7 * t + 3 * (t - .6 * (1 - np.exp(-t / .6))))
    motor = (.35 * np.sin(crank * 2) + .18 * np.sin(crank * 6) + .1 * noise(len(t), 70, 800)) * catch
    values = starter + motor * np.clip((2.8 - t) / .7, 0, 1)
    for at in (.48, .68, .91):
        age = np.maximum(t - at, 0)
        values += .24 * noise(len(t), 45, 1200) * np.exp(-age * 24) * (t >= at)
    write('diesel_start', values, .8)


def cannon():
    t = np.arange(round(RATE * 3.2)) / RATE
    body = .8 * np.sin(2 * np.pi * (39 * t + 22 * .08 * (1 - np.exp(-t / .08)))) * np.exp(-t * 4)
    pressure = noise(len(t), 30, 850) * .52 * np.exp(-t * 6)
    crack = noise(len(t), 150, 6500) * .48 * np.exp(-t * 70)
    tail = noise(len(t), 25, 280) * .17 * np.exp(-t * 1.65)
    values = body + pressure + crack + tail
    for delay, amplitude in ((.16, .13), (.31, .08), (.48, .04)):
        offset = round(delay * RATE)
        values[offset:] += values[:-offset].copy() * amplitude * np.exp(-t[:-offset] * 1.4)
    write('cannon_fire', values, .92)
    t = np.arange(round(RATE * 3.5)) / RATE
    values = .5 * noise(len(t), 25, 950) * np.exp(-t * 3.8)
    values += .38 * np.sin(2 * np.pi * (31 * t + 13 * .12 * (1 - np.exp(-t / .12)))) * np.exp(-t * 3)
    values += .2 * noise(len(t), 500, 5400) * np.exp(-t * 11)
    for delay in (.13, .24, .42, .65, .88, 1.18):
        age = np.maximum(t - delay, 0)
        values += .09 * noise(len(t), 700, 4500) * np.exp(-age * 34) * (t >= delay) / (1 + delay)
    values += .12 * noise(len(t), 20, 190) * np.exp(-t * 1.5)
    write('cannon_impact', values, .86)


if __name__ == '__main__':
    diesel()
    tracks()
    start()
    cannon()
    print(json.dumps(REPORT, indent=2))
