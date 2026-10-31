"""Refaz os pequenos ladrilhos PBR sem emenda autorados para a oficina existente do Digo.

Só offline. Os pixels são determinísticos; o jogo carrega as texturas importadas uma vez.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

SIZE = 512
OUT = Path(__file__).resolve().parents[2] / "assets/materials/digo_workshop"
RNG = np.random.default_rng(19102026)


def noise(band: float) -> np.ndarray:
    frequency = np.fft.fftfreq(SIZE)
    radius = frequency[:, None] ** 2 + frequency[None, :] ** 2
    spectrum = np.fft.fft2(RNG.normal(size=(SIZE, SIZE)))
    result = np.fft.ifft2(spectrum * np.exp(-radius * band)).real
    return result / max(float(result.std()), 0.001)


def save(kind: str, rgb: np.ndarray, roughness: np.ndarray, height: np.ndarray) -> None:
    Image.fromarray(np.clip(rgb, 0, 255).astype("uint8")).save(OUT / f"{kind}_albedo.png")
    Image.fromarray(np.clip(roughness, 0, 255).astype("uint8"), "L").save(OUT / f"{kind}_roughness.png")
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 1.6
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 1.6
    normal = np.stack([-dx, dy, np.ones_like(dx)], axis=2)
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    Image.fromarray(((normal * 0.5 + 0.5) * 255).astype("uint8")).save(OUT / f"{kind}_normal.png")


def floor() -> None:
    cloud = noise(18000)
    grain = noise(100)
    pores = noise(2)
    value = cloud * 2.2 + grain * 0.9 + pores * 0.45
    rgb = np.array([119.0, 126.0, 128.0])[None, None, :] + value[:, :, None]
    rough = 181 + cloud * 6 + grain * 2
    # Manchas sutis de arranhado variam o acabamento, nunca poças espelhadas nem óleo preto.
    scuff = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(scuff)
    for _ in range(35):
        x, y = RNG.integers(0, SIZE, size=2)
        length = int(RNG.integers(8, 34))
        draw.line((int(x), int(y), int(x + length), int(y + length // 4)), fill=12, width=1)
    wear = np.asarray(scuff, dtype=float)
    rough += wear
    rgb += wear[:, :, None] * 0.15
    save("epoxy", rgb, rough, grain * 0.012 + pores * 0.009)


def wall() -> None:
    yy, xx = np.indices((SIZE, SIZE))
    row = yy // 64
    staggered = (xx + (row % 2) * 64) % SIZE
    column = staggered // 128
    block_tones = RNG.uniform(-2.5, 2.5, size=(8, 4))
    pores = noise(3)
    grain = noise(90)
    grout = ((yy % 64) < 2) | ((staggered % 128) < 2)
    value = block_tones[row, column] + grain * 1.6 + pores * 0.8
    rgb = np.array([184.0, 183.0, 175.0])[None, None, :] + value[:, :, None]
    rgb[grout] = np.array([150, 153, 148])
    rough = 222 + grain * 2 + pores
    rough[grout] = 238
    height = grain * 0.015 + pores * 0.006
    height[grout] -= 0.13
    save("block", rgb, rough, height)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    floor()
    wall()
    print(f"DIGO_MATERIALS generated six {SIZE}x{SIZE} tiles in {OUT}")
