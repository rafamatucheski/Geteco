"""Bake original canyon sounds; no external recordings or runtime PCM work.

Requires numpy. Outputs deterministic 22.05 kHz signed-16 PCM WAV files.
The two beds use periodic Fourier noise and integral-cycle modulation so their
loop seam has the same slope distribution as the rest of the waveform.
"""
from pathlib import Path
import json
import wave
import numpy as np

RATE = 22050
OUT = Path(__file__).resolve().parents[2] / "audio" / "desert_canyon"
RNG = np.random.default_rng(8102026)


def noise(seconds, low, high, slope=0.65):
    n = int(seconds * RATE)
    frequency = np.fft.rfftfreq(n, 1 / RATE)
    spectrum = RNG.normal(size=frequency.size) + 1j * RNG.normal(size=frequency.size)
    weight = (1 - np.exp(-((frequency / low) ** 4))) * np.exp(-((frequency / high) ** 4))
    weight /= np.maximum(frequency, 1) ** slope
    spectrum *= weight
    spectrum[0] = 0
    result = np.fft.irfft(spectrum, n)
    return result / np.std(result)


def echo(signal, delays=((0.19, 0.22), (0.43, 0.09))):
    result = signal.copy()
    for seconds, gain in delays:
        samples = int(seconds * RATE)
        result[samples:] += signal[:-samples] * gain
    return result


def save(name, signal, peak, loop=False):
    signal = signal / max(1e-9, np.max(np.abs(signal))) * peak
    if not loop:
        fade = min(int(RATE * 0.055), len(signal) // 4)
        signal[:fade] *= np.linspace(0, 1, fade)
        signal[-fade:] *= np.linspace(1, 0, fade)
    pcm = np.rint(signal * 32767).astype("<i2")
    with wave.open(str(OUT / name), "wb") as output:
        output.setnchannels(2 if signal.ndim == 2 else 1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    return {"file": name, "seconds": len(signal) / RATE,
            "channels": 2 if signal.ndim == 2 else 1,
            "peak": float(np.max(np.abs(signal))),
            "rms": float(np.sqrt(np.mean(signal ** 2))),
            "loop_seam_delta": float(np.max(np.abs(signal[-1] - signal[0]))),
            "loop": loop}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    report = []
    duration = 12.0
    t = np.arange(int(duration * RATE)) / RATE
    deep = noise(duration, 38, 680, 0.8)
    air = noise(duration, 310, 2100, 0.4)
    envelope = .65 + .18 * np.sin(2 * np.pi * t / duration) + .12 * np.sin(6 * np.pi * t / duration + .6)
    hollow = np.sin(2 * np.pi * 147 * t + .75 * np.sin(2 * np.pi * t / duration))
    left = (deep * .76 + air * .15 + hollow * .09) * envelope
    right = (.84 * np.roll(deep, int(RATE * .013)) + noise(duration, 310, 1500) * .12) * np.roll(envelope, int(RATE * .7))
    report.append(save("gorge_wind.wav", np.column_stack([left, right]), .58, True))

    for variant in range(2):
        duration = 2.4
        t = np.arange(int(duration * RATE)) / RATE
        pitch = 1 + variant * .14
        scrape = noise(duration, 350, 2400, .3) * np.exp(-((t - .48) / .24) ** 2) * .14
        bend = np.zeros_like(t)
        for freq, strength, decay in [(127, .8, 2.5), (231, .42, 3.0), (497, .3, 4.1), (859, .15, 5.3)]:
            phase = 2 * np.pi * freq * pitch * t + .7 * np.sin(2 * np.pi * 2.7 * t)
            bend += np.sin(phase) * strength * np.exp(-t * decay)
        envelope = 1 - np.exp(-t * 90)
        report.append(save(f"bridge_stress_{variant}.wav", echo(bend * envelope + scrape), .62))

    for variant in range(2):
        duration = 2.6
        t = np.arange(int(duration * RATE)) / RATE
        breath = noise(duration, 180, 1750, .15)
        sound = np.zeros_like(t)
        for start, length, pitch in [(.18, .38 + variant * .05, 156 - variant * 15), (.87, .5, 132 + variant * 9)]:
            local = np.maximum(0, t - start)
            envelope = np.where((t >= start) & (local < length), np.sin(np.pi * np.minimum(local / length, 1)) ** 1.5, 0)
            phase = 2 * np.pi * (pitch * local - 35 * local ** 2)
            throat = np.sin(phase) + .45 * np.sin(2.17 * phase) + .18 * np.sin(3.61 * phase)
            flutter = .68 + .32 * np.sin(2 * np.pi * 31 * local)
            sound += envelope * (breath * .45 + throat * .26) * flutter
        report.append(save(f"vulture_croak_{variant}.wav", echo(sound, ((.24, .28), (.51, .12))), .60))

    duration = 8.0
    t = np.arange(int(duration * RATE)) / RATE
    fabric = noise(duration, 350, 1900, .35)
    flap = (.5 + .5 * np.sin(2 * np.pi * 5 * t / duration)) ** 8
    flutter = (.55 + .45 * np.sin(2 * np.pi * 23 * t / duration))
    movement = fabric * flap * flutter * .18
    for start in [2.1, 5.65]:
        local = np.maximum(0, t - start)
        movement += np.where(t >= start, np.sin(2 * np.pi * 385 * local) * np.exp(-local * 19) * .14, 0)
    report.append(save("hideout_canvas.wav", movement, .42, True))
    (OUT / "bank.json").write_text(json.dumps({"original_procedural": True, "sample_rate": RATE,
        "generator": "tools/audio/generate_canyon_ambience.py", "streams": report}, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
