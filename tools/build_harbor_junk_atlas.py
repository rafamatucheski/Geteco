"""Atlas de desgaste dos objetos soltos da rua de Harbor (StreetJunkKit).

Gera assets/city_props/harbor_junk_atlas.png: 4 x 4 quadros de 256 px, um material por quadro
(plástico de saco, papelão, madeira gasta, metal enferrujado, plástico desbotado, lona listrada,
corda, rede, entulho, lixo miúdo...). Os quadros "neutros" são claros e a cor vem do vértice e da
instância (MultiMesh), então um quadro serve saco preto, azul e verde; os "pintados" já trazem a cor.

Por que um atlas: todas as peças novas dividem UM material (uma variante de shader para
pré-aquecer, um draw call por tipo e por chunk) e ainda assim cada uma tem desgaste próprio.
Determinístico (sementes fixas): rodar de novo dá o mesmo arquivo. O .import ao lado pede
VRAM comprimida em alta qualidade (BC7) com mipmaps.

Não confundir com tools/build_street_wear_atlas.py (adesivos/pichação, outra sessão, 29/10): os
dois nasceram no mesmo dia com o mesmo nome e este foi renomeado.

Uso: python -I tools/build_harbor_junk_atlas.py
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

TILE = 256
GRID = 4
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "city_props", "harbor_junk_atlas.png")

# Ordem igual a StreetJunkKit.TILES.
NAMES = ["bag", "bag_clear", "cardboard", "rubber",
         "wood_worn", "wood_painted", "metal_rust", "metal_galv",
         "plastic_faded", "fabric_stripes", "fabric_print", "canvas_stripes",
         "rope", "net", "rubble", "litter"]


def noise(rng, size, cells):
    """Ruído de valor suave (grade aleatória ampliada bicubicamente), 0..1, repete nas bordas."""
    grid = rng.random((cells, cells)).astype(np.float32)
    tiled = np.tile(grid, (3, 3))
    image = Image.fromarray((tiled * 255).astype(np.uint8), "L").resize((size * 3, size * 3), Image.BICUBIC)
    data = np.asarray(image, dtype=np.float32)[size:size * 2, size:size * 2] / 255.0
    return data


def fbm(rng, size, base=4, octaves=4):
    total = np.zeros((size, size), np.float32)
    amplitude = 1.0
    norm = 0.0
    cells = base
    for _ in range(octaves):
        total += noise(rng, size, cells) * amplitude
        norm += amplitude
        amplitude *= 0.5
        cells *= 2
    return total / norm


def rgb(hex_color):
    hex_color = hex_color.lstrip("#")
    return np.array([int(hex_color[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


def compose(base, shade):
    """Cor base (3,) modulada por um mapa (H,W) em torno de 1."""
    return np.clip(base[None, None, :] * shade[:, :, None], 0.0, 1.0)


def blend(dst, color, mask):
    mask = np.clip(mask, 0.0, 1.0)[:, :, None]
    return dst * (1.0 - mask) + color[None, None, :] * mask


def coords():
    y, x = np.mgrid[0:TILE, 0:TILE].astype(np.float32)
    return x / TILE, y / TILE


def tile_bag(rng):
    # Plástico neutro amassado: vincos escuros finos, reflexos alongados. Média ~0,72.
    x, y = coords()
    folds = fbm(rng, TILE, 3, 5)
    creases = np.abs(np.sin((folds * 9.0 + x * 2.0) * np.pi))
    crease_mask = np.clip(1.0 - creases * 6.0, 0, 1)
    gloss = np.clip((fbm(rng, TILE, 2, 3) - 0.55) * 4.0, 0, 1)
    shade = 0.72 + (folds - 0.5) * 0.25 - crease_mask * 0.22 + gloss * 0.25
    return compose(rgb("ffffff"), shade)


def tile_bag_clear(rng):
    # Saco transparente leitoso com o conteúdo aparecendo (papel, casca, garrafa).
    img = compose(rgb("e6e8e2"), 0.85 + (fbm(rng, TILE, 3, 4) - 0.5) * 0.25)
    colors = ["e0c34a", "c0392b", "6f8f3c", "f2efe6", "8a5a3a", "3a7fb6", "d9692b", "b0a090"]
    pil = Image.fromarray((img * 255).astype(np.uint8), "RGB")
    draw = ImageDraw.Draw(pil)
    for _ in range(55):
        cx, cy = rng.integers(0, TILE, 2)
        w, h = rng.integers(10, 46, 2)
        color = tuple(int(c * 255 * 0.82 + 0.18 * 228) for c in rgb(colors[rng.integers(0, len(colors))]))
        if rng.random() < 0.5:
            draw.ellipse([cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2], fill=color)
        else:
            draw.polygon([(cx + rng.integers(-w, w), cy + rng.integers(-h, h)) for _ in range(5)], fill=color)
    pil = pil.filter(ImageFilter.GaussianBlur(3.0))
    img = np.asarray(pil, np.float32) / 255.0
    # Película por cima: clareia e vinca.
    film = np.clip((fbm(rng, TILE, 4, 4) - 0.45) * 2.0, 0, 1)
    return np.clip(img * 0.8 + 0.2 * film[:, :, None] + 0.05, 0, 1)


def tile_cardboard(rng):
    x, y = coords()
    flute = 0.92 + 0.08 * np.sin(y * TILE * 0.9)
    stains = np.clip((fbm(rng, TILE, 3, 4) - 0.6) * 3.0, 0, 1)
    base = compose(rgb("c8a479"), flute * (0.9 + (fbm(rng, TILE, 6, 3) - 0.5) * 0.25))
    base = blend(base, rgb("8c6a45"), stains * 0.7)
    # Fita adesiva e marcas impressas (sem texto: blocos e setas apagadas).
    tape = (np.abs(x - 0.5) < 0.07).astype(np.float32)
    base = blend(base, rgb("d8c08a"), tape * 0.75)
    pil = Image.fromarray((base * 255).astype(np.uint8), "RGB")
    draw = ImageDraw.Draw(pil)
    for _ in range(4):
        cx, cy = rng.integers(30, TILE - 30, 2)
        draw.rectangle([cx - 18, cy - 6, cx + 18, cy + 6], outline=(70, 52, 38), width=2)
    draw.polygon([(40, 200), (60, 180), (80, 200), (68, 200), (68, 225), (52, 225), (52, 200)], fill=(80, 60, 42))
    return np.asarray(pil.filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255.0


def tile_rubber(rng):
    x, y = coords()
    tread = ((np.sin(y * np.pi * 24) > 0.2) ^ (np.sin(x * np.pi * 8 + np.sign(np.sin(y * np.pi * 12)) * 0.8) > 0.6)).astype(np.float32)
    dust = fbm(rng, TILE, 4, 4)
    shade = 0.38 + tread * 0.14 + (dust - 0.5) * 0.18
    out = compose(rgb("ffffff"), shade)
    return blend(out, rgb("8a7a64"), np.clip((dust - 0.62) * 3.0, 0, 1) * 0.5)


def tile_wood_worn(rng):
    x, y = coords()
    grain = fbm(rng, TILE, 2, 4)
    rings = 0.5 + 0.5 * np.sin((x * 6.0 + grain * 5.0) * np.pi * 2)
    planks = (np.mod(y * 4.0, 1.0) < 0.06).astype(np.float32)
    shade = 0.78 + (rings - 0.5) * 0.18 + (fbm(rng, TILE, 8, 3) - 0.5) * 0.2
    out = compose(rgb("b8a080"), shade)
    weather = np.clip((fbm(rng, TILE, 3, 4) - 0.45) * 2.5, 0, 1)
    out = blend(out, rgb("9a948a"), weather * 0.55)  # madeira acinzentada pelo sol
    out = blend(out, rgb("3a2e22"), planks)
    nails = np.zeros_like(x)
    for row in range(4):
        for col in (0.08, 0.92):
            nails += np.exp(-(((x - col) ** 2 + (y - (row + 0.5) / 4.0) ** 2) * 9000.0))
    return blend(out, rgb("5a3a28"), np.clip(nails * 2, 0, 1))


def tile_wood_painted(rng):
    x, y = coords()
    paint = compose(rgb("ececec"), 0.92 + (fbm(rng, TILE, 6, 3) - 0.5) * 0.15)
    chips = np.clip((fbm(rng, TILE, 5, 5) - 0.58) * 6.0, 0, 1)
    wood = compose(rgb("6a5038"), 0.85 + (fbm(rng, TILE, 2, 4) - 0.5) * 0.4)
    out = paint * (1 - chips[:, :, None]) + wood * chips[:, :, None]
    slats = (np.mod(y * 5.0, 1.0) < 0.08).astype(np.float32)
    return blend(out, rgb("2a2420"), slats * 0.85)


def tile_metal_rust(rng):
    x, y = coords()
    paint = compose(rgb("e8e8e6"), 0.9 + (fbm(rng, TILE, 6, 3) - 0.5) * 0.12)
    patches = np.clip((fbm(rng, TILE, 4, 5) - 0.56) * 5.0, 0, 1)
    # Escorrido vertical: ferrugem desce da borda de cima.
    streak_seed = noise(rng, TILE, 24)
    streaks = np.clip((streak_seed[0:1, :] - 0.6) * 4.0, 0, 1) * np.clip(1.0 - y * 1.2, 0, 1)
    rust = compose(rgb("8a4a26"), 0.8 + (fbm(rng, TILE, 10, 3) - 0.5) * 0.6)
    mask = np.clip(patches + streaks * 0.8 + np.clip(y - 0.82, 0, 1) * 3.0, 0, 1)
    out = paint * (1 - mask[:, :, None]) + rust * mask[:, :, None]
    dents = np.clip((fbm(rng, TILE, 7, 2) - 0.5) * 0.25, -0.1, 0.1)
    return np.clip(out * (1.0 + dents[:, :, None]), 0, 1)


def tile_metal_galv(rng):
    x, y = coords()
    spangle = noise(rng, TILE, 48)
    out = compose(rgb("c4c8c8"), 0.85 + (spangle - 0.5) * 0.18 + (fbm(rng, TILE, 3, 3) - 0.5) * 0.2)
    rust = np.clip((fbm(rng, TILE, 6, 4) - 0.66) * 6.0, 0, 1)
    return blend(out, rgb("7a4a2a"), rust * 0.8)


def tile_plastic_faded(rng):
    x, y = coords()
    chalk = fbm(rng, TILE, 3, 4)
    out = compose(rgb("f4f2ec"), 0.88 + (chalk - 0.5) * 0.14)
    pil = Image.fromarray(np.zeros((TILE, TILE), np.uint8), "L")
    draw = ImageDraw.Draw(pil)
    for _ in range(40):
        x0, y0 = rng.integers(0, TILE, 2)
        draw.line([(x0, y0), (x0 + rng.integers(-40, 40), y0 + rng.integers(-12, 12))], fill=int(rng.integers(60, 140)), width=1)
    scratches = np.asarray(pil, np.float32) / 255.0
    out = out * (1.0 - scratches[:, :, None] * 0.25)
    grime = np.clip((y - 0.6) * 2.2, 0, 1) * (0.6 + fbm(rng, TILE, 6, 3) * 0.6)
    return blend(out, rgb("6a6358"), grime * 0.45)


def tile_fabric_stripes(rng):
    # Guarda-sol de praia: listras vermelho/branco ao longo de u, borda azul em v alto.
    x, y = coords()
    stripes = (np.mod(x * 4.0, 1.0) < 0.5).astype(np.float32)
    out = compose(rgb("f2eee2"), np.ones((TILE, TILE), np.float32))
    out = blend(out, rgb("c8322b"), stripes)
    out = blend(out, rgb("1f4f8a"), (y > 0.88).astype(np.float32))
    weave = 0.94 + 0.06 * np.sin(x * TILE * 1.6) * np.sin(y * TILE * 1.6)
    fade = 0.92 + (fbm(rng, TILE, 3, 3) - 0.5) * 0.16
    return np.clip(out * (weave * fade)[:, :, None], 0, 1)


def tile_fabric_print(rng):
    # Estampa amarela com faixa azul e bolinhas brancas (guarda-sol de marca, sem texto).
    x, y = coords()
    out = compose(rgb("e8b52e"), np.ones((TILE, TILE), np.float32))
    out = blend(out, rgb("1f4f8a"), ((y > 0.55) & (y < 0.72)).astype(np.float32))
    dots = (np.mod(x * 6.0, 1.0) - 0.5) ** 2 + (np.mod(y * 6.0, 1.0) - 0.5) ** 2 < 0.03
    out = blend(out, rgb("f4f0e0"), (dots & (y < 0.5)).astype(np.float32))
    out = blend(out, rgb("f4f0e0"), (y > 0.9).astype(np.float32))
    weave = 0.94 + 0.06 * np.sin(x * TILE * 1.6) * np.sin(y * TILE * 1.6)
    fade = 0.9 + (fbm(rng, TILE, 3, 3) - 0.5) * 0.18
    return np.clip(out * (weave * fade)[:, :, None], 0, 1)


def tile_canvas_stripes(rng):
    # Lona de cadeira de praia: listras finas verde, branco e azul ao longo de v.
    x, y = coords()
    band = np.mod(y * 7.0, 1.0)
    out = compose(rgb("f0ece0"), np.ones((TILE, TILE), np.float32))
    out = blend(out, rgb("2f7a55"), (band < 0.35).astype(np.float32))
    out = blend(out, rgb("2d6fb6"), ((band > 0.55) & (band < 0.7)).astype(np.float32))
    weave = 0.92 + 0.08 * np.sin(x * TILE * 2.2) * np.sin(y * TILE * 2.2)
    dirt = np.clip((fbm(rng, TILE, 4, 4) - 0.6) * 2.0, 0, 1)
    out = blend(out * weave[:, :, None], rgb("7a6a50"), dirt * 0.35)
    return np.clip(out, 0, 1)


def tile_rope(rng):
    x, y = coords()
    twist = 0.5 + 0.5 * np.sin((x * 10.0 + y * 10.0) * np.pi * 2)
    fibre = fbm(rng, TILE, 16, 2)
    shade = 0.62 + twist * 0.3 + (fibre - 0.5) * 0.25
    return compose(rgb("f0e6cc"), shade)


def tile_net(rng):
    x, y = coords()
    u = np.mod((x + y) * 9.0, 1.0)
    v = np.mod((x - y) * 9.0, 1.0)
    line = ((u < 0.12) | (v < 0.12)).astype(np.float32)
    knots = ((u < 0.18) & (v < 0.18)).astype(np.float32)
    gaps = compose(rgb("2a3330"), 0.8 + fbm(rng, TILE, 6, 3) * 0.4)
    out = gaps * (1 - line[:, :, None]) + compose(rgb("5f8a6a"), 0.85 + fbm(rng, TILE, 12, 2) * 0.3) * line[:, :, None]
    return blend(out, rgb("3e5a46"), knots)


def tile_rubble(rng):
    out = compose(rgb("9a958c"), 0.8 + fbm(rng, TILE, 6, 4) * 0.4)
    pil = Image.fromarray((out * 255).astype(np.uint8), "RGB")
    draw = ImageDraw.Draw(pil)
    for _ in range(70):
        cx, cy = rng.integers(0, TILE, 2)
        r = int(rng.integers(5, 22))
        tone = rng.random()
        if tone < 0.3:
            color = (int(150 + rng.integers(-20, 20)), int(78 + rng.integers(-15, 15)), 58)  # tijolo
        elif tone < 0.8:
            g = int(130 + rng.integers(-40, 50))
            color = (g, g - 4, g - 10)  # concreto
        else:
            color = (196, 176, 138)  # areia
        draw.polygon([(cx + rng.integers(-r, r), cy + rng.integers(-r, r)) for _ in range(5)], fill=color)
    img = np.asarray(pil.filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255.0
    return img * (0.85 + fbm(rng, TILE, 10, 2)[:, :, None] * 0.3)


def tile_litter(rng):
    # Lixo miúdo: embalagens, latas, papel e tampinhas sobre fundo sujo.
    out = compose(rgb("5a5248"), 0.8 + fbm(rng, TILE, 6, 4) * 0.4)
    pil = Image.fromarray((out * 255).astype(np.uint8), "RGB")
    draw = ImageDraw.Draw(pil)
    palette = ["c0392b", "2d6fb6", "e3c53a", "f2efe6", "b9bec0", "2f7a55", "d9692b", "e98bb7", "8a5a3a"]
    for _ in range(90):
        cx, cy = rng.integers(0, TILE, 2)
        w, h = rng.integers(6, 30, 2)
        color = tuple(int(c * 255) for c in rgb(palette[rng.integers(0, len(palette))]))
        if rng.random() < 0.6:
            draw.polygon([(cx + rng.integers(-w, w), cy + rng.integers(-h, h)) for _ in range(4)], fill=color)
        else:
            draw.ellipse([cx - w // 3, cy - w // 3, cx + w // 3, cy + w // 3], fill=color)
    return np.asarray(pil.filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255.0


BUILDERS = {
    "bag": tile_bag, "bag_clear": tile_bag_clear, "cardboard": tile_cardboard, "rubber": tile_rubber,
    "wood_worn": tile_wood_worn, "wood_painted": tile_wood_painted, "metal_rust": tile_metal_rust,
    "metal_galv": tile_metal_galv, "plastic_faded": tile_plastic_faded, "fabric_stripes": tile_fabric_stripes,
    "fabric_print": tile_fabric_print, "canvas_stripes": tile_canvas_stripes, "rope": tile_rope, "net": tile_net,
    "rubble": tile_rubble, "litter": tile_litter,
}


def main() -> int:
    atlas = np.zeros((TILE * GRID, TILE * GRID, 3), np.float32)
    for index, name in enumerate(NAMES):
        rng = np.random.default_rng(9100 + index)
        tile = BUILDERS[name](rng)
        row, col = divmod(index, GRID)
        atlas[row * TILE:(row + 1) * TILE, col * TILE:(col + 1) * TILE] = tile
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray((np.clip(atlas, 0, 1) * 255).astype(np.uint8), "RGB").save(OUT, optimize=True)
    print("atlas:", OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
