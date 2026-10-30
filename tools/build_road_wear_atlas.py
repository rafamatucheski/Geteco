"""Atlas do desgaste das ruas do Harbor (pedido do jogador de 29/10: "ruas muito limpas para
uma cidade portuária; faltam buracos").

Uma textura RGBA só, 1024x1024, desenhada aqui uma vez (fora do jogo) e importada em BC7 com
mipmaps: buraco, remendo, rachadura, tampa de bueiro, chapa de aço, grelha, óleo, ferrugem, poça
e faixas longas (sujeira do meio-fio, óleo no meio da faixa, borracha de pneu, tinta lascada,
vala remendada, selante de trinca). O jogo não calcula nada disso: HarborRoadWear só escolhe a
célula e o tamanho de cada quad, num lote por trecho.

As cores ficam em sRGB perto do asfalto como ele sai do shader (~44/255). Sombra e brilho vêm
pintados SEM direção (borda clara e parede escura em volta toda), porque o mesmo decalque gira e
o sol muda: um buraco iluminado de um lado só ficaria errado no outro.

Determinístico (semente fixa). Rode de novo só se mudar o desenho:
    python -I tools/build_road_wear_atlas.py
depois `tools/run_godot_locked.sh --headless --path . --import` para reimportar.
A disposição das células está espelhada em world/shared/roads/HarborRoadWear.gd (CELLS).
"""
import pathlib

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "materials" / "harbor_road_wear" / "road_wear_atlas.png"
SIZE = 1024
CELL = 256
STRIP_H = 32
ASPHALT = np.array([44, 45, 48], np.float32)
rng = np.random.default_rng(29102026)


# ---------------------------------------------------------------- ruído

def smooth_noise(h, w, scale, seed):
    """Ruído suave em 0..1: grade aleatória ampliada com bicúbica (barato e sem padrão)."""
    local = np.random.default_rng(seed)
    gh, gw = max(2, int(h / scale) + 2), max(2, int(w / scale) + 2)
    grid = (local.random((gh, gw)) * 255).astype(np.uint8)
    big = Image.fromarray(grid, "L").resize((int(gw * scale), int(gh * scale)), Image.BICUBIC)
    arr = np.asarray(big, np.float32)[:h, :w] / 255.0
    return arr


def fbm(h, w, scale, seed, octaves=4):
    total = np.zeros((h, w), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += smooth_noise(h, w, max(scale / (2 ** o), 1.0), seed + o * 101) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def speckle(h, w, density, seed):
    local = np.random.default_rng(seed)
    return (local.random((h, w)) < density).astype(np.float32)


def grid(h, w):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    return x, y


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def blur(arr, radius):
    img = Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), "L")
    from PIL import ImageFilter
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), np.float32) / 255.0


def rgba(color, alpha):
    """color (h,w,3) em 0..255, alpha (h,w) em 0..1 -> (h,w,4) uint8."""
    out = np.zeros(alpha.shape + (4,), np.float32)
    out[..., :3] = np.clip(color, 0, 255)
    out[..., 3] = np.clip(alpha, 0, 1) * 255.0
    return out.astype(np.uint8)


def tone(value, h, w):
    return np.broadcast_to(np.asarray(value, np.float32), (h, w, 3)).copy()


def lerp_color(a, b, t):
    return a + (b - a) * t[..., None]


def edge_fade(h, w, margin):
    """Alfa zero nas bordas da célula: o mipmap não puxa a célula vizinha."""
    x, y = grid(h, w)
    d = np.minimum(np.minimum(x, w - 1 - x), np.minimum(y, h - 1 - y))
    return smoothstep(0, margin, d)


def blob(h, w, radius, wobble, seed, cx=None, cy=None):
    """Distância normalizada a um contorno irregular (<1 dentro)."""
    x, y = grid(h, w)
    cx = w / 2 if cx is None else cx
    cy = h / 2 if cy is None else cy
    ang = np.arctan2(y - cy, x - cx)
    local = np.random.default_rng(seed)
    r = np.ones_like(ang)
    for k, amp in ((2, 0.16), (3, 0.12), (4, 0.06), (7, 0.035), (13, 0.015)):
        r += amp * wobble * np.sin(ang * k + local.random() * 6.283)
    n = fbm(h, w, 18, seed + 7, 3)
    dist = np.hypot(x - cx, y - cy) / (radius * r)
    return dist + (n - 0.5) * 0.22 * wobble


# ---------------------------------------------------------------- células quadradas

def pothole(seed, radius=88, water=False):
    h = w = CELL
    d = blob(h, w, radius, 1.0, seed)
    grain = fbm(h, w, 6, seed + 1, 3)
    fine = smooth_noise(h, w, 1.5, seed + 2)
    # Fundo: lama e brita molhada, quase preto; pedras soltas claras espalhadas.
    color = tone([17, 17, 18], h, w) + (grain[..., None] - 0.5) * 14
    stones = speckle(h, w, 0.035, seed + 3) * (d < 0.85)
    color = lerp_color(color, tone([58, 56, 52], h, w), stones * (0.4 + fine * 0.6))
    # Parede: anel escuro logo dentro da borda (profundidade sem direção de luz).
    wall = smoothstep(0.70, 0.95, d) * (1 - smoothstep(0.95, 1.02, d))
    color = lerp_color(color, tone([9, 9, 10], h, w), wall * 0.85)
    # Borda quebrada: agregado exposto claro, irregular, logo fora do contorno.
    rim = smoothstep(0.98, 1.02, d) * (1 - smoothstep(1.04, 1.16 + grain * 0.14, d))
    exposed = np.clip(rim * (0.35 + speckle(h, w, 0.4, seed + 4) * 0.55 + (fine - 0.5) * 0.4), 0, 1)
    color = lerp_color(color, tone([60, 59, 56], h, w) + (fine[..., None] - 0.5) * 22, exposed * 0.85)
    # Desagregação em volta: brita solta e pó de asfalto gasto.
    ravel = (1 - smoothstep(1.1, 1.6, d)) * (d > 1.0)
    loose = speckle(h, w, 0.05, seed + 5) * ravel
    color = lerp_color(color, tone([58, 57, 54], h, w), loose * 0.8)
    # Halo de asfalto gasto e mais escuro em volta (a água entra e a capa solta antes de cair).
    color = lerp_color(color, tone([33, 33, 35], h, w), ravel * (1 - exposed) * (1 - loose))
    alpha = np.where(d < 1.02, 0.97, 0.0) + exposed * 0.85 + loose * 0.7 + ravel * 0.3
    if water:
        # Água parada no fundo: escura e lisa (o brilho vem do material molhado).
        pool = 1 - smoothstep(0.45, 0.62, d + (grain - 0.5) * 0.25)
        color = lerp_color(color, tone([15, 17, 19], h, w), pool)
    alpha = np.clip(alpha, 0, 1) * edge_fade(h, w, 10)
    return rgba(color, alpha)


def pothole_cluster(seed):
    """Desagregação: pele de jacaré com pedaços arrancados e dois buracos rasos."""
    h = w = CELL
    out = crack_network(seed, cells=26, area=0.92, darkness=0.82)
    base = out.astype(np.float32)
    for k, (cx, cy, r) in enumerate(((96, 110, 34), (165, 150, 24), (130, 70, 15))):
        d = blob(h, w, r, 1.2, seed + 40 + k, cx, cy)
        inside = (d < 1.0).astype(np.float32)
        rim = smoothstep(0.98, 1.03, d) * (1 - smoothstep(1.05, 1.4, d))
        fine = smooth_noise(h, w, 1.5, seed + 50 + k)
        base[..., :3] = lerp_color(base[..., :3], tone([16, 16, 17], h, w), inside)
        base[..., :3] = lerp_color(base[..., :3], tone([58, 57, 54], h, w), rim * (0.4 + fine * 0.5))
        base[..., 3] = np.maximum(base[..., 3], (inside * 0.96 + rim * 0.85) * 255)
    base[..., 3] *= edge_fade(h, w, 10)
    return np.clip(base, 0, 255).astype(np.uint8)


def patch_square(seed):
    """Remendo de corte de rede: asfalto mais novo e escuro, borda reta com junta de piche."""
    h = w = CELL
    x, y = grid(h, w)
    jag = (fbm(h, w, 5, seed, 2) - 0.5) * 6
    m = 22
    inside_d = np.minimum(np.minimum(x - m, w - 1 - m - x), np.minimum(y - m, h - 1 - m - y)) + jag
    inside = smoothstep(-0.5, 0.8, inside_d)
    grain = fbm(h, w, 3, seed + 1, 3)
    roller = 0.5 + 0.5 * np.sin(y * 0.09 + fbm(h, w, 30, seed + 2, 2) * 3)
    color = tone([30, 31, 34], h, w) + (grain[..., None] - 0.5) * 12 + (roller[..., None] - 0.5) * 3
    # Pedrisco claro esparso (agregado novo aparecendo).
    color = lerp_color(color, tone([56, 55, 53], h, w), speckle(h, w, 0.02, seed + 3) * inside)
    seam = smoothstep(-0.5, 0.8, inside_d) * (1 - smoothstep(2.0, 4.5, inside_d))
    color = lerp_color(color, tone([14, 14, 15], h, w), seam * 0.9)
    # Trinca de retração num canto, saindo da junta.
    crack = crack_lines(h, w, seed + 4, starts=[(m + 4, m + 30)], steps=90, width=1.2)
    color = lerp_color(color, tone([12, 12, 13], h, w), crack * inside)
    stain = fbm(h, w, 40, seed + 5, 2)
    color = lerp_color(color, tone([38, 38, 40], h, w), smoothstep(0.6, 0.8, stain) * 0.5)
    alpha = inside * 0.93
    return rgba(color, alpha * edge_fade(h, w, 6))


def stamp(canvas, px, py, r):
    """Disco suave de raio r somado (máximo) à tela, recortado nas bordas."""
    h, w = canvas.shape
    x0, x1 = max(0, int(px - r - 1)), min(w, int(px + r + 2))
    y0, y1 = max(0, int(py - r - 1)), min(h, int(py + r + 2))
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    d = np.hypot(xx - px, yy - py)
    canvas[y0:y1, x0:x1] = np.maximum(canvas[y0:y1, x0:x1], np.clip(r + 0.5 - d, 0, 1))


def crack_lines(h, w, seed, starts, steps=120, width=1.5, branch=0.04, turn=0.22):
    """Linhas de passeio aleatório (rachaduras) em 0..1."""
    local = np.random.default_rng(seed)
    canvas = np.zeros((h, w), np.float32)
    # Cada trinca nasce apontando para o meio da célula (não sai da borda logo no começo).
    stack = [(float(sx), float(sy), float(np.arctan2(h / 2 - sy, w / 2 - sx) + local.normal(0, 0.35)), width, steps)
             for sx, sy in starts]
    while stack:
        px, py, heading, wid, n = stack.pop()
        for i in range(n):
            heading += local.normal(0, turn)
            px += np.cos(heading) * 1.2
            py += np.sin(heading) * 1.2
            if px < 2 or py < 2 or px > w - 3 or py > h - 3:
                break
            stamp(canvas, px, py, max(0.6, wid * (1 - i / max(n, 1)) + 0.4))
            if local.random() < branch and wid > 0.7:
                stack.append((px, py, heading + local.choice([-1, 1]) * local.uniform(0.6, 1.3), wid * 0.6, n // 2))
    return canvas


def crack_network(seed, cells=18, area=0.85, darkness=0.85):
    """Pele de jacaré: bordas de Voronoi irregulares, mais fortes no centro."""
    h = w = CELL
    local = np.random.default_rng(seed)
    pts = local.random((cells, 2)) * [w, h]
    x, y = grid(h, w)
    warp = (fbm(h, w, 14, seed + 1, 3) - 0.5) * 16
    xs, ys = x + warp, y + (fbm(h, w, 14, seed + 2, 3) - 0.5) * 16
    d = np.stack([np.hypot(xs - px, ys - py) for px, py in pts])
    d.sort(axis=0)
    edge = 1 - smoothstep(0.6, 2.2, d[1] - d[0])
    region = 1 - smoothstep(area * 0.75, area, blob(h, w, 105, 0.8, seed + 3))
    lines = edge * region
    tile = fbm(h, w, 20, seed + 4, 2)
    color = tone([13, 13, 14], h, w)
    # Lascas de asfalto entre as trincas: algumas mais claras (secas), outras mais escuras.
    chips = region * (1 - edge)
    color = lerp_color(color, tone([52, 51, 49], h, w), chips * smoothstep(0.55, 0.75, tile))
    alpha = lines * darkness + chips * 0.12 * smoothstep(0.5, 0.75, tile)
    return rgba(color, alpha * edge_fade(h, w, 8))


def crack_branch(seed):
    h = w = CELL
    lines = crack_lines(h, w, seed, starts=[(14, 120), (240, 136)], steps=130, width=2.2, branch=0.012, turn=0.14)
    halo = blur(lines, 2.5)
    color = lerp_color(tone([58, 57, 54], h, w), tone([11, 11, 12], h, w), smoothstep(0.2, 0.6, lines))
    alpha = np.maximum(lines * 0.92, halo * 0.22)
    return rgba(color, alpha * edge_fade(h, w, 8))


def manhole(seed):
    """Tampa de ferro fundido rente ao asfalto, aro polido e anel de asfalto recalcado em volta."""
    h = w = CELL
    x, y = grid(h, w)
    cx = cy = 127.5
    r = np.hypot(x - cx, y - cy)
    ang = np.arctan2(y - cy, x - cx)
    cover_r, frame_r, settle_r = 92.0, 104.0, 124.0
    grain = fbm(h, w, 4, seed, 3)
    # Padrão da tampa: anéis concêntricos com quadradinhos em relevo (claro = alto, gasto pelo pneu).
    gx = np.mod(x - cx, 14.0)
    gy = np.mod(y - cy, 14.0)
    raised = ((gx > 3) & (gx < 11) & (gy > 3) & (gy < 11)).astype(np.float32)
    rings = (np.abs(np.mod(r, 24.0) - 12.0) < 2.0).astype(np.float32)
    pattern = np.clip(raised * (r < cover_r - 10) + rings * 0.6, 0, 1)
    worn = 1 - smoothstep(10, cover_r, r)
    cover = tone([40, 39, 37], h, w) + (grain[..., None] - 0.5) * 10
    cover = lerp_color(cover, tone([68, 66, 62], h, w), pattern * (0.55 + worn * 0.45))
    rust = smoothstep(0.55, 0.8, fbm(h, w, 12, seed + 1, 3)) * (1 - pattern)
    cover = lerp_color(cover, tone([70, 50, 36], h, w), rust * 0.4)
    # Furos de içamento.
    for a in (0.6, 0.6 + np.pi):
        hx, hy = cx + np.cos(a) * 58, cy + np.sin(a) * 58
        hole = 1 - smoothstep(3.0, 5.0, np.hypot(x - hx, y - hy))
        cover = lerp_color(cover, tone([8, 8, 8], h, w), hole)
    gap = smoothstep(cover_r - 1.5, cover_r, r) * (1 - smoothstep(cover_r + 1.5, cover_r + 3.0, r))
    frame = smoothstep(cover_r + 2.5, cover_r + 3.5, r) * (1 - smoothstep(frame_r - 1, frame_r, r))
    color = np.where((r < cover_r)[..., None], cover, tone([0, 0, 0], h, w))
    frame_tone = tone([66, 65, 62], h, w) + (smooth_noise(h, w, 3, seed + 2)[..., None] - 0.5) * 18
    color = lerp_color(color, frame_tone, frame)
    color = lerp_color(color, tone([10, 10, 10], h, w), gap)
    # Anel de asfalto recalcado e trincas radiais.
    settle = smoothstep(frame_r - 1, frame_r + 1, r) * (1 - smoothstep(settle_r - 14, settle_r, r + (grain - 0.5) * 18))
    radial = (np.abs(np.sin(ang * 7 + fbm(h, w, 10, seed + 3, 2) * 4)) < 0.05) * settle
    color = lerp_color(color, tone([28, 28, 30], h, w), settle * (r >= frame_r))
    color = lerp_color(color, tone([12, 12, 13], h, w), radial)
    alpha = np.where(r < frame_r, 1.0, 0.0) + settle * 0.62 * (r >= frame_r) + radial * 0.3
    return rgba(color, np.clip(alpha, 0, 1) * edge_fade(h, w, 3))


def steel_plate(seed):
    """Chapa de vala (2:1) com piso xadrez, borda enferrujada e sombra rente."""
    h, w = CELL // 2, CELL
    x, y = grid(h, w)
    m = 10
    inside_d = np.minimum(np.minimum(x - m, w - 1 - m - x), np.minimum(y - m, h - 1 - m - y))
    plate = smoothstep(-0.5, 0.5, inside_d)
    u = (x + y) / 9.0
    v = (x - y) / 9.0
    diamond = ((np.abs(np.mod(u, 2.0) - 1.0) < 0.28) ^ (np.abs(np.mod(v, 2.0) - 1.0) < 0.28)).astype(np.float32)
    grain = fbm(h, w, 5, seed, 3)
    color = tone([50, 51, 52], h, w) + (grain[..., None] - 0.5) * 12
    polish = 1 - smoothstep(0, 0.5, np.abs(y / h - 0.5) - 0.12)
    color = lerp_color(color, tone([72, 72, 70], h, w), diamond * (0.3 + polish * 0.35))
    rust = smoothstep(0.58, 0.85, fbm(h, w, 10, seed + 1, 3) + (1 - smoothstep(0, 16, inside_d)) * 0.3)
    color = lerp_color(color, tone([74, 50, 34], h, w), rust * 0.6)
    for bx, by in ((m + 9, m + 9), (w - m - 10, m + 9), (m + 9, h - m - 10), (w - m - 10, h - m - 10)):
        bolt = 1 - smoothstep(2.5, 4.0, np.hypot(x - bx, y - by))
        color = lerp_color(color, tone([20, 18, 16], h, w), bolt)
    shadow = (1 - plate) * (1 - smoothstep(0, 7, -inside_d))
    color = lerp_color(color, tone([10, 10, 11], h, w), shadow)
    alpha = np.maximum(plate, shadow * 0.55)
    return rgba(color, alpha * edge_fade(h, w, 3))


def grate(seed):
    """Boca de lobo de sarjeta (2:1): moldura de ferro, fendas escuras, ferrugem e lodo."""
    h, w = CELL // 2, CELL
    x, y = grid(h, w)
    m = 12
    inside_d = np.minimum(np.minimum(x - m, w - 1 - m - x), np.minimum(y - m, h - 1 - m - y))
    body = smoothstep(-0.5, 0.5, inside_d)
    slots = ((np.mod(x - m - 6, 23.0) > 9) & (inside_d > 9)).astype(np.float32)
    grain = fbm(h, w, 4, seed, 3)
    color = tone([58, 57, 55], h, w) + (grain[..., None] - 0.5) * 12
    color = lerp_color(color, tone([6, 6, 7], h, w), slots)
    rust = smoothstep(0.5, 0.75, fbm(h, w, 9, seed + 1, 3))
    color = lerp_color(color, tone([72, 50, 34], h, w), rust * (1 - slots) * 0.5)
    silt = smoothstep(0.55, 0.8, fbm(h, w, 14, seed + 2, 2)) * slots
    color = lerp_color(color, tone([46, 40, 32], h, w), silt * 0.6)
    ring = (1 - body) * (1 - smoothstep(0, 9, -inside_d))
    color = lerp_color(color, tone([22, 21, 20], h, w), ring)
    alpha = np.maximum(body, ring * 0.6)
    return rgba(color, alpha * edge_fade(h, w, 3))


def oil(seed, drips=False):
    h = w = CELL
    if drips:
        local = np.random.default_rng(seed)
        acc = np.zeros((h, w), np.float32)
        x, y = grid(h, w)
        for k in range(14):
            cx = 128 + local.normal(0, 22)
            cy = 40 + k * 13 + local.normal(0, 6)
            r = local.uniform(5, 18)
            d = blob(h, w, r, 0.7, seed + k, cx, cy)
            acc = np.maximum(acc, (1 - smoothstep(0.6, 1.1, d)) * local.uniform(0.45, 1.0))
        core = acc
    else:
        d = blob(h, w, 90, 1.1, seed)
        core = 1 - smoothstep(0.35, 1.0, d)
    tide = np.abs(np.sin(core * 9.0 + fbm(h, w, 12, seed + 3, 2) * 3)) < 0.18
    color = tone([16, 15, 14], h, w) + (fbm(h, w, 6, seed + 1, 3)[..., None] - 0.5) * 8
    color = lerp_color(color, tone([30, 28, 25], h, w), tide.astype(np.float32) * 0.5)
    alpha = core * (0.55 + 0.35 * smoothstep(0.3, 0.9, core))
    return rgba(color, alpha * edge_fade(h, w, 10))


def rust_stain(seed):
    h = w = CELL
    d = blob(h, w, 95, 1.3, seed)
    patches = smoothstep(0.42, 0.75, fbm(h, w, 16, seed + 1, 4))
    streak = smoothstep(0.55, 0.85, fbm(h, 1, 1, seed + 2, 1).repeat(w, 1) * 0 + fbm(h, w, 6, seed + 3, 3))
    color = lerp_color(tone([92, 56, 34], h, w), tone([66, 44, 30], h, w), fbm(h, w, 8, seed + 4, 3))
    speck = speckle(h, w, 0.02, seed + 5)
    alpha = (1 - smoothstep(0.6, 1.05, d)) * (patches * 0.55 + streak * 0.15) + speck * 0.4 * (d < 1.1)
    return rgba(color, np.clip(alpha * 0.85, 0, 0.6) * edge_fade(h, w, 10))


def puddle(seed):
    """Poça em depressão: água escura (o brilho é do material molhado) e anel de lodo seco."""
    h = w = CELL
    d = blob(h, w, 92, 1.4, seed)
    water = 1 - smoothstep(0.86, 0.98, d)
    silt = smoothstep(0.9, 1.0, d) * (1 - smoothstep(1.02, 1.25, d))
    color = tone([15, 17, 19], h, w) + (fbm(h, w, 20, seed + 1, 2)[..., None] - 0.5) * 6
    color = lerp_color(color, tone([66, 60, 50], h, w), silt)
    alpha = water * 0.9 + silt * 0.38
    return rgba(color, alpha * edge_fade(h, w, 10))


# ---------------------------------------------------------------- faixas longas (1024x32)

def strip_frame(seed, end_fade=0.06):
    h, w = STRIP_H, SIZE
    x, y = grid(h, w)
    u = x / (w - 1)
    v = y / (h - 1)
    ends = smoothstep(0, end_fade, u) * smoothstep(0, end_fade, 1 - u)
    return h, w, u, v, ends


def curb_grime(seed, sandy=False):
    """Sujeira juntada no meio-fio: v=0 encosta na guia, some em direção à pista."""
    h, w, u, v, ends = strip_frame(seed, 0.08)
    reach = 0.45 + fbm(h, w, 40, seed, 3) * 0.55
    body = 1 - smoothstep(reach * 0.55, reach, v)
    base = [70, 64, 53] if sandy else [52, 49, 44]
    color = tone(base, h, w) + (fbm(h, w, 3, seed + 1, 3)[..., None] - 0.5) * 18
    color = lerp_color(color, tone([38, 36, 33], h, w), smoothstep(0.5, 0.75, fbm(h, w, 30, seed + 5, 3)))
    silt = 1 - smoothstep(0.0, 0.16, v)
    color = lerp_color(color, tone([26, 23, 20], h, w), silt * 0.8)
    leaves = speckle(h, w, 0.03 if sandy else 0.02, seed + 2) * body
    color = lerp_color(color, tone([78, 58, 36], h, w), leaves)
    paper = speckle(h, w, 0.004, seed + 3) * body
    color = lerp_color(color, tone([120, 118, 108], h, w), paper)
    alpha = (body * (0.35 + 0.35 * fbm(h, w, 8, seed + 4, 2)) + silt * 0.3 + leaves * 0.35 + paper * 0.5) * ends
    return rgba(color, np.clip(alpha, 0, 0.85))


def lane_oil(seed):
    h, w, u, v, ends = strip_frame(seed, 0.12)
    across = 1 - smoothstep(0.18, 0.5, np.abs(v - 0.5) + (fbm(h, w, 20, seed, 2) - 0.5) * 0.25)
    blot = fbm(h, w, 24, seed + 1, 3)
    drops = speckle(h, w, 0.01, seed + 2)
    drops = np.clip(blur(drops, 1.2) * 6.0, 0, 1) * across
    color = tone([18, 17, 16], h, w)
    alpha = (across * smoothstep(0.35, 0.7, blot) * 0.38 + drops * 0.5) * ends
    return rgba(color, alpha)


def crack_line_strip(seed, sealant=False):
    h, w, u, v, ends = strip_frame(seed, 0.03)
    local = np.random.default_rng(seed)
    canvas = np.zeros((h, w), np.float32)
    px, py, heading = 2.0, h / 2.0, 0.0
    width = 2.6 if sealant else 1.2
    while px < w - 3:
        heading = np.clip(heading * 0.97 + local.normal(0, 0.05 if sealant else 0.09), -0.45, 0.45)
        heading -= (py - h / 2.0) * 0.004
        px += np.cos(heading) * 1.1
        py = np.clip(py + np.sin(heading) * 0.55, 4, h - 5)
        stamp(canvas, px, py, width * (0.75 + 0.5 * local.random()))
    if sealant:
        color = lerp_color(tone([22, 22, 23], h, w), tone([12, 12, 12], h, w), canvas)
        alpha = canvas * 0.95
    else:
        halo = blur(canvas, 1.5)
        color = lerp_color(tone([60, 58, 55], h, w), tone([11, 11, 12], h, w), smoothstep(0.2, 0.6, canvas))
        alpha = np.maximum(canvas * 0.9, halo * 0.2)
    return rgba(color, alpha * ends)


def tire_grime(seed):
    """Borracha e sujeira na trilha do pneu: estrias ao longo de u."""
    h, w, u, v, ends = strip_frame(seed, 0.1)
    across = 1 - smoothstep(0.25, 0.5, np.abs(v - 0.5))
    streak = np.repeat(np.random.default_rng(seed).random((h, 1)), w, 1).astype(np.float32)
    streak = blur(streak, 0.8)
    body = fbm(h, w, 60, seed + 1, 3)
    color = tone([24, 24, 24], h, w)
    alpha = across * (0.18 + streak * 0.25) * (0.5 + body * 0.5) * ends
    return rgba(color, alpha)


def paint_chips(seed):
    """Tinta lascada: pintinhas escuras em cachos, por cima da faixa pintada."""
    h, w, u, v, ends = strip_frame(seed, 0.02)
    cluster = smoothstep(0.45, 0.7, fbm(h, w, 14, seed, 3))
    chips = speckle(h, w, 0.32, seed + 1)
    chips = smoothstep(0.25, 0.6, blur(chips, 0.7)) * cluster
    wheel = 1 - smoothstep(0.1, 0.5, np.abs(v - 0.5))
    color = tone([36, 37, 39], h, w)
    grime = wheel * smoothstep(0.4, 0.7, fbm(h, w, 30, seed + 2, 2)) * 0.25
    alpha = np.maximum(chips * 0.9, grime) * ends
    return rgba(color, alpha)


def trench_patch(seed):
    """Vala remendada: faixa longa de asfalto novo com bordas serrilhadas e junta."""
    h, w, u, v, ends = strip_frame(seed, 0.01)
    x, y = grid(h, w)
    jag = (fbm(h, w, 4, seed, 2) - 0.5) * 2.5
    inside_d = np.minimum(y - 3, h - 4 - y) + jag
    inside_d = np.minimum(inside_d, np.minimum(x - 4, w - 5 - x) + jag)
    inside = smoothstep(-0.5, 0.8, inside_d)
    color = tone([31, 32, 35], h, w) + (fbm(h, w, 2, seed + 1, 3)[..., None] - 0.5) * 12
    seam = inside * (1 - smoothstep(1.2, 2.8, inside_d))
    color = lerp_color(color, tone([14, 14, 15], h, w), seam * 0.9)
    return rgba(color, inside * 0.94)


# ---------------------------------------------------------------- montagem

def main() -> None:
    atlas = np.zeros((SIZE, SIZE, 4), np.uint8)

    def put(img, col, row):
        atlas[row:row + img.shape[0], col:col + img.shape[1]] = img

    squares = [
        pothole(11, 86), pothole(12, 70, water=True), pothole_cluster(13), patch_square(14),
        crack_network(15, cells=30, area=1.0), crack_branch(16), manhole(17), None,
        oil(18), oil(19, drips=True), rust_stain(20), puddle(21),
    ]
    for index, img in enumerate(squares):
        if img is None:
            continue
        put(img, (index % 4) * CELL, (index // 4) * CELL)
    put(steel_plate(22), 3 * CELL, CELL)
    put(grate(23), 3 * CELL, CELL + CELL // 2)
    strips = [curb_grime(30), curb_grime(31, sandy=True), lane_oil(32), crack_line_strip(33), tire_grime(34),
              paint_chips(35), trench_patch(36), crack_line_strip(37, sealant=True)]
    for index, img in enumerate(strips):
        put(img, 0, 3 * CELL + index * STRIP_H)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(OUT, optimize=True)
    write_import(OUT)
    print("atlas", OUT.relative_to(ROOT), atlas.shape, "alpha>0: %.1f%%" % (100.0 * (atlas[..., 3] > 0).mean()))


# BC7 (bptc) com mipmaps, como as fachadas pintadas: textura 3D vista de perto e de longe.
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=true
process/premult_alpha=false
process/size_limit=0
detect_3d/compress_to=0
"""


def write_import(texture: pathlib.Path) -> None:
    path = texture.with_name(texture.name + ".import")
    if not path.exists():
        path.write_text(IMPORT, encoding="utf-8")


if __name__ == "__main__":
    main()
