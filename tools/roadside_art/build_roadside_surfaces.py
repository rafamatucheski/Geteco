"""Texturas de superfície da beira de estrada do deserto (detalhe em tons de cinza + mapa de normais).

Por que existe: os lugares da Estrada do Sal (runtime/desert/roadside/RoadsideSaltRoad.gd) usavam cor
chapada em parede, madeira, caixote e tanque, e liam "flat" na câmera do jogo (revisão de 20/10/2026).
Cada textura aqui é quase branca na média, com a variação do material (tábua, reboco, crosta): o
material multiplica pela cor que o lugar já usa (RoadsideArt.detail), então uma textura serve para
várias cores. O mapa de normais dá relevo às juntas, tábuas e rachaduras sem geometria a mais.

Saída (BC7 + mipmaps; normal em RGTC com normal_map=1 no .import):
  assets/roadside/surfaces/<nome>.jpg         detalhe (cinza)
  assets/roadside/surfaces/<nome>_normal.png  normal (OpenGL, verde para cima)

Uso: python -I tools/roadside_art/build_roadside_surfaces.py   (depois `--import` do Godot pela fila)
Determinístico: mesma semente, mesmas imagens. Todas repetem sem costura (ruído e desenho periódicos).
"""
import pathlib

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "roadside" / "surfaces"
SIZE = 512
NL = chr(10)
ALBEDO_PARAMS = {"compress/mode": "2", "compress/high_quality": "true", "mipmaps/generate": "true",
                 "detect_3d/compress_to": "0"}
NORMAL_PARAMS = {"compress/mode": "2", "compress/normal_map": "1", "mipmaps/generate": "true",
                 "detect_3d/compress_to": "0"}

rng = np.random.default_rng(2010)


def tile_noise(scale, octaves=4, persistence=.5):
    """Ruído periódico 0..1 (sem costura): soma de oitavas de grade aleatória interpolada em toro."""
    total = np.zeros((SIZE, SIZE), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        cells = max(2, int(scale * 2 ** o))
        grid = rng.random((cells, cells)).astype(np.float32)
        coords = np.arange(SIZE, dtype=np.float32) * cells / SIZE
        i0 = np.floor(coords).astype(int) % cells
        i1 = (i0 + 1) % cells
        t = coords - np.floor(coords)
        t = t * t * (3 - 2 * t)
        a = grid[i0][:, i0] * (1 - t)[None, :] + grid[i0][:, i1] * t[None, :]
        b = grid[i1][:, i0] * (1 - t)[None, :] + grid[i1][:, i1] * t[None, :]
        total += (a * (1 - t)[:, None] + b * t[:, None]) * amp
        norm += amp
        amp *= persistence
    return total / norm


def normal_from_height(h, strength):
    """Normal OpenGL (y para cima) a partir da altura 0..1, com vizinhos periódicos."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return Image.fromarray(((n * .5 + .5) * 255).astype(np.uint8))


def gray(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).convert("RGB")


def plaster():
    """Reboco: granulado fino, manchas, escorrido e rachaduras finas."""
    grain = tile_noise(64, 3)
    blotch = tile_noise(3, 4)
    streak = tile_noise(1, 2)[:, :1] * 0 + np.repeat(tile_noise(24, 2)[:1, :], SIZE, 0)
    # Rachadura fina e rara: só onde uma segunda máscara deixa.
    crack = (np.abs(tile_noise(16, 3) - .5) < .005) & (tile_noise(3, 2) > .62)
    albedo = .9 + (grain - .5) * .1 - (blotch - .5) * .12 - (streak - .5) * .03
    albedo[crack] -= .16
    height = grain * .5 + blotch * .3
    height[crack] -= .5
    return gray(albedo), normal_from_height(height, 2.2)


def planks():
    """Tábuas na horizontal (8 por textura), veio, juntas escuras e pregos."""
    y = np.arange(SIZE)[:, None]
    board = (y // (SIZE // 8)) % 8
    shade = (rng.random(8)[board] - .5) * .14
    fiber = tile_noise(2, 2)[:, :] * 0 + np.repeat(tile_noise(48, 3)[:1, :], SIZE, 0)
    fiber = (fiber + tile_noise(8, 3) * .5)
    seam = (y % (SIZE // 8)) < 3
    albedo = .86 + shade + (fiber - .5) * .18
    albedo = np.broadcast_to(albedo, (SIZE, SIZE)).copy()
    albedo[np.broadcast_to(seam, (SIZE, SIZE))] = .42
    height = .6 + (fiber - .5) * .2
    height = np.broadcast_to(height, (SIZE, SIZE)).copy()
    height[np.broadcast_to(seam, (SIZE, SIZE))] = 0
    for k in range(8):
        for x in (SIZE * .1, SIZE * .6):
            cy, cx = int(k * SIZE / 8 + SIZE / 16), int(x + k * 13) % SIZE
            albedo[cy - 2:cy + 3, cx - 2:cx + 3] = .3
    return gray(albedo), normal_from_height(height, 3.0)


def crate():
    """Caixote: tábuas verticais, travessas em X e moldura (uma face por textura)."""
    x = np.arange(SIZE)[None, :]
    y = np.arange(SIZE)[:, None]
    board = (x // (SIZE // 5)) % 5
    fiber = np.repeat(tile_noise(40, 3)[:, :1], SIZE, 1) * .6 + tile_noise(6, 3) * .4
    albedo = .84 + (rng.random(5)[board] - .5) * .12 + (fiber - .5) * .16
    height = np.full((SIZE, SIZE), .5, np.float32) + (fiber - .5) * .15
    seam = (x % (SIZE // 5)) < 3
    albedo = np.where(seam, .4, albedo)
    height = np.where(seam, 0, height)
    frame = (x < 40) | (x > SIZE - 40) | (y < 40) | (y > SIZE - 40)
    d1 = np.abs(x - y) < 26
    d2 = np.abs(x + y - SIZE) < 26
    brace = frame | d1 | d2
    albedo = np.where(brace, albedo * .92, albedo)
    height = np.where(brace, 1.0, height)
    return gray(albedo), normal_from_height(height, 4.0)


def metal():
    """Metal pintado: tinta lisa com riscos, ferrugem pontual e amassados suaves."""
    dent = tile_noise(4, 3)
    scratch = np.abs(tile_noise(30, 2) - .5) < .006
    rust = tile_noise(10, 4) > .78
    albedo = .9 - (dent - .5) * .06
    albedo = np.where(scratch, .98, albedo)
    albedo = np.where(rust, albedo * .62, albedo)
    return gray(albedo), normal_from_height(dent * .6 + scratch * .2, 1.2)


def salt_crust():
    """Crosta de sal: placas poligonais com bordas levantadas (rachaduras de lama seca)."""
    cells = 28
    pts = rng.random((cells, 2)) * SIZE
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    dists = []
    for px, py in pts:
        for ox in (-SIZE, 0, SIZE):
            for oy in (-SIZE, 0, SIZE):
                dists.append(np.hypot(xx - px - ox, yy - py - oy))
    two = np.partition(np.stack(dists), 1, axis=0)[:2]
    d1, d2 = two[0], two[1]
    edge = np.clip((d2 - d1) / 10.0, 0, 1)
    grain = tile_noise(48, 3)
    albedo = .9 + grain * .08 - (1 - edge) * .1
    height = (1 - edge) * .8 + grain * .2
    return gray(albedo), normal_from_height(height, 2.5)


def brine():
    """Salmoura rasa: marolas suaves e crosta branca nas bordas das manchas."""
    ripple = tile_noise(5, 3)
    crust = tile_noise(7, 4)
    albedo = .8 + (ripple - .5) * .1 + np.clip((crust - .68) * 2.5, 0, .14)
    crust = crust > .74
    height = ripple * .3 + crust * .25
    return gray(albedo), normal_from_height(height, 1.6)


def pool_tile():
    """Azulejo de piscina 15 cm: rejunte claro e sujeira desbotada no fundo."""
    x = np.arange(SIZE)[None, :]
    y = np.arange(SIZE)[:, None]
    step = SIZE // 8
    grout = ((x % step) < 4) | ((y % step) < 4)
    stain = tile_noise(3, 3)
    albedo = .86 + (rng.random((8, 8))[(y // step) % 8, (x // step) % 8] - .5) * .06 - (stain - .5) * .14
    albedo = np.where(grout, 1.0, albedo)
    height = np.where(grout, 0.0, 1.0).astype(np.float32)
    return gray(albedo), normal_from_height(height, 2.0)


def gravel():
    """Cascalho de sal/terra batida: pedrinhas com sombra própria."""
    stones = tile_noise(40, 2)
    fine = tile_noise(120, 2)
    albedo = .82 + (stones - .5) * .25 + (fine - .5) * .1
    return gray(albedo), normal_from_height(stones * .8 + fine * .2, 3.0)


def clay_tile():
    """Telha colonial de barro: fileiras de canais (meio cilindro), cor variando por peça."""
    y = np.arange(SIZE)[:, None].astype(np.float32)
    x = np.arange(SIZE)[None, :].astype(np.float32)
    cols, rows = 8, 6
    u = (x * cols / SIZE) % 1.0
    v = (y * rows / SIZE) % 1.0
    curve = np.sin(u * np.pi)
    lap = np.clip((v - .82) / .18, 0, 1)
    piece = rng.random((rows, cols))[(y * rows / SIZE).astype(int) % rows, (x * cols / SIZE).astype(int) % cols]
    albedo = .78 + (piece - .5) * .2 + curve * .12 - lap * .25 + (tile_noise(40, 2) - .5) * .08
    height = curve * .8 - lap * .5
    return gray(albedo), normal_from_height(height, 3.0)


def sandstone():
    """Arenito das cavernas do deserto (20/10): manchas grandes de tom, grão e pintas, camadas
    horizontais bem fracas e lascas escuras raras. A primeira versão tinha faixas fortes com
    linha escura na borda e lia como veio de madeira (caixotes empilhados) na câmera do jogo."""
    y = np.arange(SIZE)[:, None].astype(np.float32)
    mottle = tile_noise(4, 4)
    blotch = tile_noise(12, 3)
    grain = tile_noise(140, 2)
    speck = (tile_noise(200, 1) > .8).astype(np.float32)
    warp = (tile_noise(3, 2) - .5) * .08
    layers = np.sin(((y / SIZE) + warp) * np.pi * 2 * 5) * .5 + .5
    chip = np.clip((tile_noise(18, 2) - .72) * 6, 0, 1)
    albedo = .8 + (mottle - .5) * .3 + (blotch - .5) * .14 + (grain - .5) * .1 + layers * .05 - speck * .08 - chip * .22
    height = mottle * .5 + blotch * .4 + grain * .25 - chip * .6 + layers * .1
    return gray(albedo), normal_from_height(height, 4.0)


SURFACES = {"plaster": plaster, "planks": planks, "crate": crate, "metal": metal,
            "salt_crust": salt_crust, "brine": brine, "pool_tile": pool_tile, "gravel": gravel, "clay_tile": clay_tile,
            "sandstone": sandstone}


def write_import(texture, params):
    path = texture.with_name(texture.name + ".import")
    if not path.exists():
        lines = ["[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "", "[params]", ""]
        lines += [f"{k}={v}" for k, v in params.items()]
        path.write_text(NL.join(lines) + NL, encoding="utf-8")
        return
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        key = line.split("=", 1)[0]
        out.append(f"{key}={params[key]}" if key in params and "=" in line else line)
    path.write_text(NL.join(out) + NL, encoding="utf-8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, painter in SURFACES.items():
        albedo, normal = painter()
        albedo.save(OUT / f"{name}.jpg", quality=92)
        normal.save(OUT / f"{name}_normal.png")
        write_import(OUT / f"{name}.jpg", ALBEDO_PARAMS)
        write_import(OUT / f"{name}_normal.png", NORMAL_PARAMS)
    print("superfícies", len(SURFACES), "em", OUT)


if __name__ == "__main__":
    main()
