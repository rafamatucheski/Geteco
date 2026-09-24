"""Export the V1 electric inverter loop to the V2 seven-band engine bank.

The waveform is VehicleEngineSound._generate_electric_layer; intermediate
bands provide the resolution expected by the V2 traffic mixer.
"""
from math import pi, sin
from pathlib import Path
from struct import pack
import wave

RATE = 22050
GUARD = 8
CYCLES = (8, 13, 20, 30, 42, 56, 72)
CARRIERS = (620, 760, 870, 980, 1150, 1320, 1480)
OUTPUT = Path(__file__).resolve().parents[1] / "audio" / "acoustic"


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for index, (shaft_hz, carrier_hz) in enumerate(zip(CYCLES, CARRIERS)):
        samples = []
        for frame in range(RATE):
            t = frame / RATE
            rotation = sin(2 * pi * shaft_hz * t) * 0.24
            inverter = sin(2 * pi * carrier_hz * t + sin(2 * pi * shaft_hz * t) * 0.22) * 0.09
            bearing = sin(2 * pi * shaft_hz * 6.0 * t) * 0.025
            value = max(-0.35, min(0.35, (rotation + inverter + bearing) * 0.55))
            samples.append(round(value * 32767))
        with wave.open(str(OUTPUT / f"engine_electric_{index}.wav"), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(RATE)
            output.writeframes(pack(f"<{RATE + GUARD}h", *(samples + samples[:GUARD])))


if __name__ == "__main__":
    main()
