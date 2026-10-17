"""Bake original, seamless facade wear. No runtime noise or per-building textures."""
from pathlib import Path
import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parents[1] / "assets/materials/harbor_facades"
SIZE = 512


def noise(rng, cells):
    # Periodic interpolation keeps every edge continuous after mip filtering.
    values = rng.random((cells, cells)).astype(np.float32)
    p = np.arange(SIZE) * cells / SIZE
    i, f = p.astype(int), p % 1
    f = f * f * (3 - 2 * f)
    a = values[i[:, None] % cells, i[None, :] % cells]
    b = values[i[:, None] % cells, (i[None, :] + 1) % cells]
    c = values[(i[:, None] + 1) % cells, i[None, :] % cells]
    d = values[(i[:, None] + 1) % cells, (i[None, :] + 1) % cells]
    return (a * (1-f)[None, :] + b*f[None, :]) * (1-f)[:, None] + (c*(1-f)[None, :] + d*f[None, :])*f[:, None]


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    y, x = np.indices((SIZE, SIZE))
    for index, kind in enumerate(("brick", "plaster", "concrete")):
        rng = np.random.default_rng(90371 + index)
        broad = noise(rng, 4)
        medium = noise(rng, 16)
        grain = rng.random((SIZE, SIZE))
        # Infrequent rain streaks, not an evenly distributed camouflage pattern.
        rain_columns = noise(rng, 32)[0]
        streaks = np.maximum(0, rain_columns - .67)[None, :] * (.35 + broad)
        value = .91 + (broad-.5)*.095 + (medium-.5)*.045 + (grain-.5)*.045 - streaks*.20
        if kind == "brick":
            course = y // 16
            bx = (x + (course % 2)*16) % SIZE
            tones = rng.random((32, 16))
            value *= .94 + tones[course, bx//32]*.12
            mortar = (y % 16 < 1) | (bx % 32 < 1)
            value[mortar] = .69 + broad[mortar]*.07
            # Sparse spalled corners, low contrast so distance stays readable.
            chips = (grain > .985) & (medium > .65)
            value[chips] *= .73
        elif kind == "plaster":
            worn = np.maximum(0, .27-medium) * np.maximum(0, .48-broad)
            value -= worn*1.9
        else:
            # Large cast panels: fine restrained seams rather than a tile grid.
            value[(y % 256 == 0)] *= .90
            value[(x % 256 == 0) & (broad > .45)] *= .94
        pixels = np.clip(value*255, 0, 255).astype(np.uint8)
        Image.fromarray(pixels).convert("RGB").save(OUT / f"{kind}.png", optimize=True)
        # Godot fills remap/dependencies on import; fix GPU compression and mips.
        cfg = OUT / f"{kind}.png.import"
        if not cfg.exists():
            cfg.write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\ncompress/mode=2\ncompress/high_quality=false\nmipmaps/generate=true\n', encoding="utf-8")


if __name__ == "__main__":
    build()
