"""Texturas dos materiais da blitz do prólogo (runtime/prologue/BlitzLook.gd).

Gera, de forma procedural e repetível (sementes fixas), as famílias de superfície que a cena
usa em triplanar de mundo: asfalto molhado, vegetação, concreto de fôrma, pintura sobre metal,
madeira, tecido, reboco/papel e uma variação larga ("macro") que entra no canal de AO para
quebrar a repetição vista de cima. Grava em assets/prologue/ com o .import em BC7 + mipmaps.

    python -I tools/build_prologue_materials.py          # todas
    python -I tools/build_prologue_materials.py asphalt  # só uma família

Convenções (BlitzLook depende delas):
- *_albedo.png: RGB em sRGB com média LINEAR de 0,40 por canal (a cor da cena vem do
  albedo_color do material, que BlitzLook divide por essa média); alfa = rugosidade relativa
  (multiplica a rugosidade escalar do material).
- *_normal.png: normal em espaço tangente, convenção OpenGL (verde para cima), como o Godot lê.
- macro.png: cinza linear com média 0,80 (AO; BlitzLook compensa o escurecimento).
Depois de gerar: importar pela fila (tools/run_godot_locked.sh --headless --path . --import).
"""
import pathlib
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "prologue"
MEAN = 0.40
MACRO_MEAN = 0.80
NL = chr(10)


# --- Ferramentas (tudo periódico: a textura repete sem emenda) ----------------------------------

def spectral(size, seed, beta=2.0, fmin=1.0, fmax=None, stretch=(1.0, 1.0)):
    """Ruído de espectro 1/f^beta, periódico por construção, média 0 e desvio 1.
    stretch > 1 num eixo encolhe a frequência nele: traços alongados naquele eixo (x, y)."""
    white = np.random.default_rng(seed).standard_normal((size, size))
    fy = np.fft.fftfreq(size)[:, None] * size
    fx = np.fft.fftfreq(size)[None, :] * size
    freq = np.sqrt((fx * stretch[0]) ** 2 + (fy * stretch[1]) ** 2)
    freq[0, 0] = 1.0
    amp = freq ** (-beta / 2.0)
    amp[freq < fmin] = 0.0
    if fmax:
        amp *= np.exp(-(freq / fmax) ** 2)
    amp[0, 0] = 0.0
    noise = np.real(np.fft.ifft2(np.fft.fft2(white) * amp))
    return (noise - noise.mean()) / (noise.std() + 1e-9)


def worley(size, count, seed):
    """Células de Voronoi periódicas: distância ao 1º e 2º ponto, índice do mais perto e os pontos."""
    points = np.random.default_rng(seed).random((count, 2)) * size
    tree = cKDTree(points, boxsize=size)
    yy, xx = np.mgrid[0:size, 0:size]
    query = np.stack([xx.ravel() + .5, yy.ravel() + .5], 1)
    dist, index = tree.query(query, k=2, workers=-1)
    return dist[:, 0].reshape(size, size), dist[:, 1].reshape(size, size), index[:, 0].reshape(size, size), points


def warp(image, dx, dy):
    size = image.shape[0]
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    return ndimage.map_coordinates(image, [yy + dy, xx + dx], order=1, mode="grid-wrap")


def blur(image, sigma):
    return ndimage.gaussian_filter(image, sigma, mode="wrap")


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def percentile_step(field, low, high):
    """0 abaixo do percentil `low`, 1 acima de `high` (cobertura controlada, não valor absoluto)."""
    return smoothstep(np.percentile(field, low), np.percentile(field, high), field)


def fold(canvas, size, combine=np.maximum):
    """Dobra uma tela 3x3 (desenho com sobra para fora da borda) de volta num ladrilho periódico."""
    out = canvas[size:2 * size, size:2 * size].copy()
    for row in range(3):
        for col in range(3):
            if row == 1 and col == 1:
                continue
            out = combine(out, canvas[row * size:(row + 1) * size, col * size:(col + 1) * size])
    return out


def cracks(size, seed, count, length, width, wander=.35, step=4.0):
    """Trincas/linhas sinuosas periódicas (passeio aleatório com inércia), valor 0..1."""
    rng = np.random.default_rng(seed)
    canvas = np.zeros((3 * size, 3 * size), np.float32)
    for _ in range(count):
        x, y = rng.random(2) * size + size
        heading = rng.random() * 2 * np.pi
        points = [(x, y)]
        for _ in range(int(rng.uniform(.5, 1.0) * length / step)):
            heading += rng.normal(0, wander)
            x += np.cos(heading) * step
            y += np.sin(heading) * step
            points.append((x, y))
        pts = np.array(points, np.float32)
        thickness = max(1, int(round(rng.uniform(.6, 1.0) * width)))
        cv2.polylines(canvas, [np.round(pts).astype(np.int32)], False, float(rng.uniform(.6, 1.0)), thickness, cv2.LINE_AA)
    return np.clip(fold(canvas, size), 0, 1)


def normal_from_height(height_mm, pixel_mm):
    dx = (np.roll(height_mm, -1, 1) - np.roll(height_mm, 1, 1)) * .5 / pixel_mm
    dy = (np.roll(height_mm, -1, 0) - np.roll(height_mm, 1, 0)) * .5 / pixel_mm
    nx, ny, nz = -dx, dy, np.ones_like(dx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / length, ny / length, nz / length], -1) * .5 + .5
    return (np.clip(rgb, 0, 1) * 255 + .5).astype(np.uint8)


def srgb8(linear):
    linear = np.clip(linear, 0, 1)
    encoded = np.where(linear <= .0031308, 12.92 * linear, 1.055 * np.power(linear, 1 / 2.4) - .055)
    return (encoded * 255 + .5).astype(np.uint8)


def finish_albedo(rgb_linear, roughness):
    """Normaliza cada canal para média linear MEAN e junta a rugosidade no alfa."""
    rgb = rgb_linear.astype(np.float64).copy()
    for channel in range(3):
        rgb[..., channel] *= MEAN / max(rgb[..., channel].mean(), 1e-6)
    over = float((rgb > 1.0).mean())
    alpha = (np.clip(roughness, 0, 1) * 255 + .5).astype(np.uint8)
    return np.dstack([srgb8(rgb), alpha]), over


def tint(gray, color):
    return gray[..., None] * np.asarray(color, np.float64)[None, None, :]


def save(name, pixels, normal=False):
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    mode = "L" if pixels.ndim == 2 else ("RGB" if pixels.shape[2] == 3 else "RGBA")
    Image.fromarray(pixels, mode).save(path, optimize=True)
    write_import(path, normal)
    print(f"{name}: {pixels.shape[1]}x{pixels.shape[0]} {mode} {path.stat().st_size / 1024:.0f} KiB")


def write_import(texture, normal):
    """.import mínimo em BC7 com mipmaps; o Godot completa uid/caminhos ao importar e respeita [params].
    Alfa é rugosidade (nunca transparência): sem fix_alpha_border, que trocaria a cor do texel."""
    params = {"compress/mode": "2", "compress/high_quality": "true", "compress/normal_map": "1" if normal else "0",
              "mipmaps/generate": "true", "process/fix_alpha_border": "false", "detect_3d/compress_to": "0"}
    path = texture.with_name(texture.name + ".import")
    if not path.exists():
        lines = ["[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "", "[params]", ""]
        lines += [f"{k}={v}" for k, v in params.items()]
        path.write_text(NL.join(lines) + NL, encoding="utf-8", newline=NL)
        return
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        key = line.split("=", 1)[0]
        out.append(f"{key}={params[key]}" if key in params and "=" in line else line)
    path.write_text(NL.join(out) + NL, encoding="utf-8", newline=NL)


def report(name, over):
    if over > .002:
        print(f"  aviso {name}: {over * 100:.2f}% dos texels passam de 1 depois de normalizar")


# --- Famílias -----------------------------------------------------------------------------------

def asphalt():
    """Asfalto de rodovia molhado, ladrilho de 6 m (170 px/m): agregado à mostra onde o pneu gastou,
    selagem de trinca brilhante, trincas finas, manchas de óleo e poças (lisas e chatas na normal)."""
    size, tile_mm = 1024, 6000.0
    pixel = tile_mm / size
    f1, f2, cell, points = worley(size, 30000, 11)
    # Pedra de agregado não é célula de Voronoi: contorno torto, tamanho variado, vão de ligante.
    jx, jy = 1.6 * spectral(size, 24, 1.4, 30, 300), 1.6 * spectral(size, 25, 1.4, 30, 300)
    f1, f2 = warp(f1, jx, jy), warp(f2, jx, jy)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    cell = ndimage.map_coordinates(cell, [yy + jy, xx + jx], order=0, mode="grid-wrap")
    rng = np.random.default_rng(12)
    stone_value = rng.uniform(0, 1.0, len(points)) ** 1.3
    stone_hue = rng.normal(0, 1, len(points))
    stone_size = rng.uniform(1.6, 4.4, len(points)) * (rng.random(len(points)) > .28)
    edge = f2 - f1
    stone = smoothstep(.3, 1.4, edge) * smoothstep(-.6, .6, stone_size[cell] - f1)
    wear = smoothstep(-1.4, 1.2, spectral(size, 13, 2.2, 2, 40))
    exposed = stone * (.45 + .55 * wear)
    fine = blur(np.random.default_rng(14).standard_normal((size, size)), .7)
    fine /= fine.std()
    binder = .20 * (1 + .06 * spectral(size, 15, 1.6, 4, 200))
    lum = binder * (1 - exposed) + (.27 + .26 * stone_value[cell]) * exposed
    lum *= 1 + .09 * fine
    lum *= 1 + .07 * spectral(size, 16, 2.6, 1, 18)
    # Selagem de trinca (piche, mais escura e mais lisa) e trincas finas.
    seal = cracks(size, 17, 3, 1600, 6, .10, 6.0)
    hair = cracks(size, 18, 9, 260, 1, .45, 3.0) * (1 - seal)
    oil = percentile_step(spectral(size, 19, 3.0, 3, 30) + .4 * spectral(size, 20, 2.0, 8, 80), 96.5, 99.4)
    # Poças: manchas largas de borda irregular; em volta, um anel úmido mais escuro.
    field = spectral(size, 21, 3.2, 1, 9)
    field = warp(field, 9 * spectral(size, 22, 2.0, 4, 40), 9 * spectral(size, 23, 2.0, 4, 40))
    puddle = percentile_step(field, 86, 90)
    damp = percentile_step(field, 62, 86)
    lum *= (1 - .45 * seal) * (1 - .35 * hair) * (1 - .30 * oil)
    lum *= 1 - .15 * damp - .30 * puddle
    hue = stone_hue[cell] * exposed
    rgb = np.stack([lum * (1 + .035 * hue), lum * (1 + .01 * hue), lum * (1 - .03 * hue)], -1)
    rough = .90 + .04 * fine - .12 * exposed * wear
    rough = rough * (1 - seal) + .58 * seal
    rough = rough * (1 - oil) + .55 * oil
    rough *= 1 - .22 * damp
    rough = rough * (1 - puddle) + .30 * puddle
    albedo, over = finish_albedo(rgb, rough)
    report("asphalt", over)
    height = 3.5 * exposed * np.sqrt(np.clip(1 - f1 / 4.5, 0, 1)) + .25 * fine - .5 * seal - .9 * hair
    calm = blur(height, 6)
    height = height * (1 - puddle) + calm * puddle
    save("asphalt_albedo.png", albedo)
    save("asphalt_normal.png", normal_from_height(height, pixel), True)


def vegetation():
    """Mato da beira e copa das árvores, ladrilho de 4 m (128 px/m): touceiras com folhas em leque,
    vão escuro de terra entre elas, trechos secos e lama molhada."""
    size, tile_mm = 512, 4000.0
    pixel = tile_mm / size
    f1, f2, cell, points = worley(size, 150, 31)
    rng = np.random.default_rng(32)
    dry = percentile_step(spectral(size, 33, 2.4, 1, 10), 70, 92)
    clump_tone = rng.uniform(.7, 1.15, len(points))
    clump_dry = rng.uniform(0, 1, len(points)) ** 2
    radius = rng.uniform(16, 34, len(points))
    dome = np.clip(1 - f1 / radius[cell], 0, 1)
    tuft_f1, _, tuft_cell, tuft_points = worley(size, 1400, 34)
    tuft = np.clip(1 - tuft_f1 / 7.0, 0, 1)
    # Folhas: traços curtos saindo do centro da touceira mais perto.
    tree = cKDTree(points, boxsize=size)
    blades = np.zeros((3 * size, 3 * size), np.float32)
    blade_height = np.zeros_like(blades)
    starts = rng.random((26000, 2)) * size
    _, nearest = tree.query(starts, workers=-1)
    for (x, y), index in zip(starts, nearest):
        cx, cy = points[index]
        ddx, ddy = (x - cx + size / 2) % size - size / 2, (y - cy + size / 2) % size - size / 2
        angle = np.arctan2(ddy, ddx) + rng.normal(0, .45)
        length = rng.uniform(5, 13)
        x0, y0 = x + size, y + size
        x1, y1 = x0 + np.cos(angle) * length, y0 + np.sin(angle) * length
        value = float(rng.uniform(.55, 1.0))
        cv2.line(blades, (int(x0), int(y0)), (int(x1), int(y1)), value, 1, cv2.LINE_AA)
        cv2.line(blade_height, (int(x0), int(y0)), (int(x1), int(y1)), value * rng.uniform(.5, 1.0), 1, cv2.LINE_AA)
    blades = np.clip(fold(blades, size), 0, 1)
    blade_height = np.clip(fold(blade_height, size), 0, 1)
    mud = percentile_step(spectral(size, 35, 2.8, 2, 14) + .5 * spectral(size, 36, 2.0, 8, 60), 91, 96)
    cover = np.clip(.35 + .9 * dome + .4 * tuft, 0, 1) * (1 - mud)
    green = np.array([.085, .14, .045])
    olive = np.array([.13, .15, .055])
    straw = np.array([.24, .21, .10])
    soil = np.array([.07, .055, .035])
    wet_mud = np.array([.06, .048, .033])
    # Valores por touceira desfocados: sem isso a borda reta da célula de Voronoi aparecia no mato.
    dryness = np.clip(.55 * dry + .5 * blur(clump_dry[cell], 7), 0, 1)[..., None]
    tone = blur(clump_tone[cell], 5)
    leaf = (green * (1 - dryness) + olive * dryness * (1 - dry[..., None]) + straw * dryness * dry[..., None])
    leaf = leaf * tone[..., None] * (.75 + .55 * blades[..., None]) * (.85 + .3 * dome[..., None])
    rgb = leaf * cover[..., None] + soil * (1 - cover[..., None]) * (1 - mud[..., None])
    rgb = rgb + wet_mud * mud[..., None]
    rgb *= (1 + .06 * spectral(size, 37, 1.5, 6, 200))[..., None]
    rough = .95 - .06 * blades - .35 * mud
    albedo, over = finish_albedo(rgb, rough)
    report("vegetation", over)
    height = 60 * dome ** .6 + 25 * tuft + 22 * blade_height - 15 * (1 - cover)
    height = height * (1 - mud) + blur(height, 4) * .3 * mud
    save("vegetation_albedo.png", albedo)
    save("vegetation_normal.png", normal_from_height(height, pixel), True)


def concrete():
    """Concreto de fôrma da muralha, ladrilho de 4 m (128 px/m). Linha de concretagem no topo do
    ladrilho (y múltiplo de 4 m no mundo), juntas de painel a cada 2 m, furos de tirante, escorrimento
    de chuva descendo das linhas e dos furos, respingo escuro na base (logo acima do chão)."""
    size, tile_mm = 512, 4000.0
    pixel = tile_mm / size
    rng = np.random.default_rng(41)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    mottle = .10 * spectral(size, 42, 2.2, 1, 40) + .04 * spectral(size, 43, 1.4, 10, 220)
    lum = .5 * (1 + mottle)
    # Junta de concretagem (horizontal, topo) e de painel (vertical, a cada 2 m).
    lift = np.exp(-((yy - 1.0) / 1.3) ** 2) + np.exp(-((yy - size + 1.0) / 1.3) ** 2)
    panel = sum(np.exp(-((xx - x) / 1.0) ** 2) for x in (0, size / 2, size)) * .6
    # Furos de tirante: grade de 6 x 6 (0,67 m), um pouco fora do prumo.
    ties = np.zeros((size, size))
    tie_points = []
    for row in range(6):
        for col in range(6):
            cx = (col + .5) * size / 6 + rng.normal(0, 1.2)
            cy = (row + .5) * size / 6 + rng.normal(0, 1.2)
            tie_points.append((cx, cy))
            d = np.hypot((xx - cx + size / 2) % size - size / 2, (yy - cy + size / 2) % size - size / 2)
            ties = np.maximum(ties, np.clip(1 - d / 2.6, 0, 1))
    # Escorrimento: colunas de intensidade aleatória, decaindo para baixo a partir do topo.
    column = np.clip(spectral(size, 44, 1.2, 8, 260, (1.0, 1.0))[0], -2, 3)
    column_noise = smoothstep(.3, 2.2, spectral(size, 45, 1.0, 30, 400, (1.0, 40.0)))
    reach = np.clip(.25 + .55 * smoothstep(-1, 2, spectral(size, 46, 1.0, 20, 300, (1.0, 40.0))), 0, 1) * size
    streak = column_noise * np.exp(-yy / np.maximum(reach, 1.0)) * (.6 + .4 * smoothstep(-1, 1.5, column))
    tie_streak = np.zeros((size, size))
    for cx, cy in tie_points:
        span = rng.uniform(20, 70)
        dxw = np.abs((xx - cx + size / 2) % size - size / 2)
        below = (yy - cy) % size
        tie_streak = np.maximum(tie_streak, np.exp(-(dxw / rng.uniform(1.2, 2.4)) ** 2) * np.exp(-below / span) * (below > 2))
    # Base: respingo de chuva e limo, borda superior irregular (0,25–0,45 m acima do chão).
    band_top = size - (32 + 18 * smoothstep(-1.5, 1.5, spectral(size, 47, 1.6, 4, 80)[0]))
    splash = smoothstep(band_top[None, :] - 14, band_top[None, :] + 10, yy) * (.75 + .25 * smoothstep(-1, 1, spectral(size, 48, 1.4, 20, 200)))
    pores = (np.random.default_rng(49).random((size, size)) > .9982).astype(np.float64)
    pores = np.clip(blur(pores, .6) * 6, 0, 1)
    lum *= (1 - .35 * lift) * (1 - .18 * panel) * (1 - .55 * ties) * (1 - .30 * pores)
    lum *= (1 - .38 * streak) * (1 - .30 * tie_streak) * (1 - .36 * splash)
    rgb = tint(lum, (1.0, .99, .96))
    rgb[..., 1] *= 1 + .05 * splash
    rgb[..., 2] *= 1 - .04 * splash
    rough = .93 - .10 * streak - .08 * tie_streak - .12 * splash + .03 * spectral(size, 50, 1.4, 20, 200)
    albedo, over = finish_albedo(rgb, rough)
    report("concrete", over)
    height = 1.2 * spectral(size, 51, 1.6, 6, 200) - 6 * lift - 2.5 * panel - 9 * ties - 2 * pores
    save("concrete_albedo.png", albedo)
    save("concrete_normal.png", normal_from_height(height, pixel), True)


def painted():
    """Pintura sobre metal/plástico, ladrilho de 1,5 m (341 px/m): casca de laranja, escorrido de sujeira
    vertical, lascas mostrando primer/ferrugem, riscos e sujeira de respingo na base (perto do chão)."""
    size, tile_mm = 512, 1500.0
    pixel = tile_mm / size
    rng = np.random.default_rng(61)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    peel = blur(np.random.default_rng(62).standard_normal((size, size)), 1.4)
    peel /= peel.std()
    f1, f2, cell, points = worley(size, 1800, 63)
    chip_pick = rng.random(len(points)) < .045
    chip_shape = smoothstep(.3, 2.5, f2 - f1) * chip_pick[cell] * smoothstep(-.4, .9, spectral(size, 64, 1.8, 6, 120))
    chip = np.clip(chip_shape * 1.8, 0, 1)
    rust = chip * smoothstep(-.5, 1.2, spectral(size, 65, 1.6, 10, 200))
    grime = smoothstep(.4, 2.4, spectral(size, 66, 1.0, 20, 400, (1.0, 30.0))) * (.4 + .6 * yy / size)
    band_top = size - (52 + 22 * smoothstep(-1.5, 1.5, spectral(size, 67, 1.6, 4, 80)[0]))
    splash = smoothstep(band_top[None, :] - 18, band_top[None, :] + 14, yy)
    scratch = cracks(size, 68, 40, 70, 1, .08, 3.0)
    lum = .5 * (1 + .025 * peel + .03 * spectral(size, 69, 2.0, 1, 30))
    lum *= (1 - .30 * grime) * (1 - .35 * splash) * (1 - .22 * scratch)
    rgb = tint(lum, (1, 1, 1))
    primer = np.array([.12, .10, .09])
    rust_color = np.array([.16, .07, .03])
    under = primer * (1 - rust[..., None]) + rust_color * rust[..., None]
    rgb = rgb * (1 - chip[..., None]) + under * chip[..., None]
    rgb[..., 0] *= 1 + .04 * splash
    rgb[..., 2] *= 1 - .06 * splash
    rough = .78 + .02 * peel + .18 * grime + .15 * splash
    rough = rough * (1 - chip) + 1.0 * chip
    albedo, over = finish_albedo(rgb, rough)
    report("painted", over)
    height = .08 * peel - .8 * chip - .5 * scratch
    save("painted_albedo.png", albedo)
    save("painted_normal.png", normal_from_height(height, pixel), True)


def wood():
    """Madeira (móveis, piso, rodapé), ladrilho de 1 m (512 px/m), veio ao longo de x: anéis deformados,
    fibra fina, poros em traço e dois nós."""
    size, tile_mm = 512, 1000.0
    pixel = tile_mm / size
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    bend = 14 * spectral(size, 71, 2.4, 1, 10, (6.0, 1.0)) + 3 * spectral(size, 72, 2.0, 4, 40, (4.0, 1.0))
    rows = yy + bend
    for kx, ky, strength, spread in ((140, 180, 26, 22), (390, 400, 20, 16)):
        dxk = (xx - kx + size / 2) % size - size / 2
        dyk = (yy - ky + size / 2) % size - size / 2
        rows += strength * np.exp(-(dxk ** 2 / (spread * 3) ** 2 + dyk ** 2 / spread ** 2)) * np.sign(dyk + 1e-6)
    rows += 4 * spectral(size, 76, 1.6, 8, 120, (10.0, 1.0))
    ring = (rows / 6.5) % 1.0
    late = smoothstep(.62, .80, ring) * (1 - smoothstep(.88, 1.0, ring))
    fiber = spectral(size, 73, 1.4, 4, 300, (25.0, 1.0))
    pores = smoothstep(1.6, 3.0, spectral(size, 74, .6, 30, 400, (12.0, 1.0)))
    knots = np.zeros((size, size))
    for kx, ky, spread in ((140, 180, 7), (390, 400, 5)):
        d = np.hypot((xx - kx + size / 2) % size - size / 2, ((yy - ky + size / 2) % size - size / 2) * 1.4)
        knots = np.maximum(knots, np.exp(-(d / spread) ** 2))
    tone = .035 * spectral(size, 75, 2.2, 1, 12, (2.0, 1.0))
    light = np.array([.42, .27, .15])
    dark = np.array([.22, .13, .07])
    mix = np.clip(.25 + .42 * late + .10 * fiber + .5 * knots, 0, 1)[..., None]
    rgb = light * (1 - mix) + dark * mix
    rgb *= (1 + tone - .18 * pores)[..., None]
    rough = .80 + .08 * late + .05 * pores - .04 * fiber
    albedo, over = finish_albedo(rgb, rough)
    report("wood", over)
    height = -.25 * late - .3 * pores + .08 * fiber - .5 * knots
    save("wood_albedo.png", albedo)
    save("wood_normal.png", normal_from_height(height, pixel), True)


def fabric():
    """Tecido (lençol, cobertor, travesseiro, cortina, jaqueta), ladrilho de 0,5 m (1024 px/m): trama
    simples de 4 mm, dobras amassadas, bolinhas e duas manchas apagadas."""
    size, tile_mm = 512, 500.0
    pixel = tile_mm / size
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    period = 4.0
    warp_thread = np.cos(np.pi * ((xx % period) / period - .5)) ** 2
    weft_thread = np.cos(np.pi * ((yy % period) / period - .5)) ** 2
    over = ((xx // period + yy // period) % 2).astype(bool)
    weave = np.where(over, warp_thread, weft_thread)
    folds = np.zeros((size, size))
    rng = np.random.default_rng(81)
    for index in range(4):
        angle = rng.random() * np.pi
        freq = rng.uniform(1.0, 2.2)
        # Direção inteira em ciclos por ladrilho: a onda continua periódica.
        kx, ky = round(np.cos(angle) * freq), round(np.sin(angle) * freq)
        phase = 2 * np.pi * (kx * xx + ky * yy) / size + 1.6 * spectral(size, 82 + index, 2.4, 1, 8)
        folds += rng.uniform(.15, .35) * (1 - np.abs(np.sin(phase))) ** 2.0
    # Ondulação larga e suave domina; os vincos entram fracos (com peso alto viravam dunas de areia).
    folds += 1.0 * spectral(size, 90, 3.6, 1, 5)
    folds = (folds - folds.min()) / (folds.max() - folds.min())
    pill = smoothstep(2.2, 3.2, spectral(size, 91, .5, 40, 400))
    stain_field = spectral(size, 92, 3.0, 1, 10)
    stain = percentile_step(stain_field, 95.5, 97.0)
    tide = percentile_step(stain_field, 95.0, 95.6) * (1 - stain)
    lum = .5 * (1 + .04 * spectral(size, 93, 1.8, 2, 80) + .06 * (folds - .5) + .025 * weave + .06 * pill)
    rgb = tint(lum, (1, 1, 1))
    rgb *= (1 - np.array([.03, .06, .14]) * stain[..., None]) * (1 - np.array([.06, .09, .16]) * tide[..., None])
    rough = np.full((size, size), .98) - .03 * weave
    albedo, over_count = finish_albedo(rgb, rough)
    report("fabric", over_count)
    height = 9.0 * folds + .12 * weave + .1 * pill
    save("fabric_albedo.png", albedo)
    save("fabric_normal.png", normal_from_height(height, pixel), True)


def plaster():
    """Reboco pintado do quarto (e papel/papelão em escala menor), ladrilho de 2 m (256 px/m):
    rolo de tinta, casca fina, manchas de infiltração com borda, trincas finas e arranhões."""
    size, tile_mm = 512, 2000.0
    pixel = tile_mm / size
    stucco = blur(np.random.default_rng(101).standard_normal((size, size)), 1.0)
    stucco = stucco / stucco.std() + .6 * spectral(size, 102, 1.8, 20, 200)
    roller = .02 * spectral(size, 103, 1.2, 3, 60, (1.0, 12.0))
    stain_field = spectral(size, 104, 3.2, 1, 8)
    stain_field = warp(stain_field, 6 * spectral(size, 105, 2.0, 4, 50), 6 * spectral(size, 106, 2.0, 4, 50))
    stain = percentile_step(stain_field, 94, 98.5)
    tide = percentile_step(stain_field, 92.8, 94.2) * (1 - percentile_step(stain_field, 94.2, 95.8))
    hairline = cracks(size, 107, 3, 130, 1, .16, 2.0) * .7
    scuff = cracks(size, 108, 14, 30, 1, .05, 2.0)
    lum = .5 * (1 + .025 * stucco + roller + .04 * spectral(size, 109, 2.2, 1, 20))
    lum *= (1 - .08 * stain) * (1 - .10 * tide) * (1 - .22 * hairline) * (1 - .10 * scuff)
    rgb = tint(lum, (1, 1, 1))
    rgb *= (1 - np.array([.02, .05, .12]) * (stain + tide)[..., None])
    rough = .95 - .05 * stain + .02 * stucco * .2
    albedo, over = finish_albedo(rgb, rough)
    report("plaster", over)
    height = .25 * stucco - .35 * hairline - .2 * scuff
    save("plaster_albedo.png", albedo)
    save("plaster_normal.png", normal_from_height(height, pixel), True)


def macro():
    """Variação larga (AO no UV2 triplanar, escala de dezenas de metros): quebra a repetição do
    ladrilho visto de cima. Cinza linear, média 0,80, entre ~0,55 e 1."""
    size = 512
    field = spectral(size, 121, 2.3, 1, 30) + .35 * spectral(size, 122, 1.6, 6, 120)
    field = (field - field.mean()) / field.std()
    value = np.clip(MACRO_MEAN + .085 * field, .5, 1.0)
    value *= MACRO_MEAN / value.mean()
    pixels = (np.clip(value, 0, 1) * 255 + .5).astype(np.uint8)
    save("macro.png", pixels)
    print(f"  macro: média {pixels.mean() / 255:.3f}, mín {pixels.min() / 255:.2f}, máx {pixels.max() / 255:.2f}")


FAMILIES = {"asphalt": asphalt, "vegetation": vegetation, "concrete": concrete, "painted": painted,
            "wood": wood, "fabric": fabric, "plaster": plaster, "macro": macro}

if __name__ == "__main__":
    wanted = sys.argv[1:] or list(FAMILIES)
    for name in wanted:
        FAMILIES[name]()
