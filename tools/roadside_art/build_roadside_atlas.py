"""Gera o atlas pintado da beira de estrada do deserto (placas, letreiros, adesivos do lanche).

Por que existe: os quatro lugares da beira de estrada (runtime/desert/roadside/) eram caixas de
cor chapada, sem nome legível (revisão de 19/10/2026). Em vez de modelar letra por letra ou usar
Label3D (texto sem luz própria e sem sujeira), cada placa vira um retângulo deste atlas, no mesmo
jeito dos prédios pintados (PaintedFacadeKit): uma imagem só, um material só, e uma máscara de luz
noturna que acende letreiro, visor da bomba e janela do lanche pelo relógio de PaintedWindow.

Saída (BC7 + mipmaps no .import, como tools/build_painted_facades.py):
  assets/roadside/roadside_atlas.jpg        cor
  assets/roadside/roadside_atlas_glow.jpg   máscara de luz noturna (preto = apagado)
  assets/roadside/roadside_atlas.json       retângulos em UV (0..1) lidos por RoadsideArt.gd

Uso: python -I tools/roadside_art/build_roadside_atlas.py   (depois `--import` do Godot pela fila)
Determinístico: mesma semente, mesma imagem.
"""
import json
import pathlib
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "roadside"
FONT_BOLD = ROOT / "assets" / "fonts" / "barlow" / "BarlowSemiCondensed-SemiBold.ttf"
FONT_REGULAR = ROOT / "assets" / "fonts" / "barlow" / "BarlowSemiCondensed-Regular.ttf"
FONT_HAND = ROOT / "assets" / "fonts" / "caveat" / "Caveat.ttf"
SIZE = 2048
PAD = 10
NL = chr(10)
IMPORT_PARAMS = {"compress/mode": "2", "compress/high_quality": "true", "mipmaps/generate": "true",
                 "detect_3d/compress_to": "0"}

rng = random.Random(1910)
np_rng = np.random.default_rng(1910)


def font(path, size):
    return ImageFont.truetype(str(path), size)


def noise(w, h, scale, octaves=3):
    """Ruído suave 0..1 (soma de oitavas de ruído branco ampliado)."""
    total = np.zeros((h, w), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        cw = max(2, int(w / scale * (2 ** o)))
        ch = max(2, int(h / scale * (2 ** o)))
        small = Image.fromarray((np_rng.random((ch, cw)) * 255).astype(np.uint8))
        big = np.asarray(small.resize((w, h), Image.BICUBIC), np.float32) / 255.0
        total += big * amp
        norm += amp
        amp *= .5
    return np.clip(total / norm, 0, 1)


def weather(img, dirt=.18, streaks=.12, scale=40):
    """Sujeira de deserto: manchas, escorrido de baixo para cima e desbotado do sol."""
    a = np.asarray(img, np.float32)
    h, w = a.shape[:2]
    blotch = noise(w, h, scale)
    a *= (1.0 - dirt * (blotch - .35))[..., None]
    # Escorrido vertical: listras finas mais escuras que descem do topo.
    cols = np.asarray(Image.fromarray((np_rng.random((1, max(2, w // 3))) * 255).astype(np.uint8)).resize((w, 1), Image.BILINEAR), np.float32)[0] / 255.0
    ramp = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    a *= (1.0 - streaks * np.clip(cols[None, :] * 1.6 - .6, 0, 1) * (.4 + .6 * ramp))[..., None]
    # Poeira quente no pé.
    dust = np.clip((ramp - .78) / .22, 0, 1) * .22
    a = a * (1 - dust[..., None]) + np.array([186, 150, 108], np.float32) * dust[..., None]
    grain = (np_rng.random((h, w)) - .5) * 10
    a += grain[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def fit_text(draw, text, box_w, box_h, path, start=400):
    size = start
    while size > 8:
        f = font(path, size)
        l, t, r, b = draw.textbbox((0, 0), text, font=f)
        if r - l <= box_w and b - t <= box_h: return f
        size -= 2
    return font(path, 8)


def text_center(draw, text, cx, cy, f, fill, stroke=0, stroke_fill=None):
    l, t, r, b = draw.textbbox((0, 0), text, font=f, stroke_width=stroke)
    draw.text((cx - (r + l) / 2, cy - (b + t) / 2), text, font=f, fill=fill, stroke_width=stroke, stroke_fill=stroke_fill)


def chip(img, amount=60, color=(150, 120, 90), size=(2, 9)):
    """Lascas de tinta (pontos claros irregulares)."""
    d = ImageDraw.Draw(img)
    w, h = img.size
    for _ in range(amount):
        x, y = rng.randrange(w), rng.randrange(h)
        r = rng.randint(*size)
        d.ellipse((x - r, y - r * .6, x + r, y + r * .6), fill=color)


def sun_logo(draw, cx, cy, r, sky=(222, 92, 38), sun=(255, 196, 64), rays=True):
    """Sol poente: meio disco sobre a linha do horizonte, com raios e listras."""
    if rays:
        for i in range(9):
            ang = np.pi * (i + .5) / 9
            x1, y1 = cx + np.cos(ang) * r * 1.18, cy - np.sin(ang) * r * 1.18
            x2, y2 = cx + np.cos(ang) * r * 1.62, cy - np.sin(ang) * r * 1.62
            draw.line((x1, y1, x2, y2), fill=sun, width=max(3, int(r * .12)))
    draw.pieslice((cx - r, cy - r, cx + r, cy + r), 180, 360, fill=sun)
    for k in range(3):
        y = cy - r * (.18 + .22 * k)
        draw.rectangle((cx - r, y - r * .05, cx + r, y + r * .05), fill=sky)
    draw.rectangle((cx - r * 1.7, cy, cx + r * 1.7, cy + max(3, r * .07)), fill=sun)


# --- Painéis ---------------------------------------------------------------------------------

def pylon(w, h):
    """Placa alta do Sol Poente: logotipo em caixa de luz e painel de preços."""
    img = Image.new("RGB", (w, h), (34, 31, 30))
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    d, g = ImageDraw.Draw(img), ImageDraw.Draw(glow)
    top = int(h * .56)
    # Caixa de luz: degradê do laranja ao vinho do pôr do sol.
    for y in range(12, top):
        t = (y - 12) / max(1, top - 12)
        c = (int(196 - 70 * t), int(70 - 38 * t), int(34 + 8 * t))
        d.line((12, y, w - 12, y), fill=c)
    sun_logo(d, w / 2, top * .52, w * .23, sky=(150, 40, 36))
    f = fit_text(d, "SOL POENTE", w - 60, top * .2, FONT_BOLD)
    text_center(d, "SOL POENTE", w / 2, top * .78, f, (255, 232, 176), stroke=3, stroke_fill=(70, 22, 18))
    f2 = fit_text(d, "POSTO · BORRACHARIA", w - 90, top * .07, FONT_BOLD)
    text_center(d, "POSTO · BORRACHARIA", w / 2, top * .92, f2, (255, 210, 150))
    # Luz: a caixa inteira acende quente, mais forte no nome e no sol.
    for y in range(12, top):
        t = (y - 12) / max(1, top - 12)
        g.line((12, y, w - 12, y), fill=(int(120 - 40 * t), int(52 - 22 * t), int(18)))
    sun_logo(g, w / 2, top * .52, w * .23, sky=(110, 30, 14), sun=(255, 170, 60))
    text_center(g, "SOL POENTE", w / 2, top * .78, f, (255, 214, 150), stroke=3, stroke_fill=(90, 30, 10))
    text_center(g, "POSTO · BORRACHARIA", w / 2, top * .92, f2, (200, 150, 90))
    # Painel de preços: fundo escuro, rótulos claros e dígitos de LED âmbar.
    d.rectangle((12, top + 10, w - 12, h - 12), fill=(28, 28, 30))
    rows = [("GASOLINA", "5,79"), ("ETANOL", "3,99"), ("DIESEL S10", "5,49")]
    row_h = (h - 12 - (top + 18)) / len(rows)
    fl = fit_text(d, "DIESEL S10", w * .44, row_h * .42, FONT_BOLD)
    fd = fit_text(d, "8,88", w * .36, row_h * .7, FONT_BOLD)
    for i, (label, price) in enumerate(rows):
        y0 = top + 18 + row_h * i
        d.rectangle((22, y0 + 6, w - 22, y0 + row_h - 6), fill=(238, 232, 220))
        d.text((34, y0 + row_h / 2), label, font=fl, fill=(40, 36, 34), anchor="lm")
        d.rectangle((w * .52, y0 + 12, w - 32, y0 + row_h - 12), fill=(18, 16, 14))
        d.text((w - 42, y0 + row_h / 2), price, font=fd, fill=(255, 168, 40), anchor="rm")
        g.rectangle((22, y0 + 6, w - 22, y0 + row_h - 6), fill=(90, 86, 78))
        g.text((34, y0 + row_h / 2), label, font=fl, fill=(10, 10, 10), anchor="lm")
        g.rectangle((w * .52, y0 + 12, w - 32, y0 + row_h - 12), fill=(0, 0, 0))
        g.text((w - 42, y0 + row_h / 2), price, font=fd, fill=(255, 150, 30), anchor="rm")
    d.rectangle((0, 0, w - 1, h - 1), outline=(70, 66, 62), width=12)
    return weather(img, dirt=.12, streaks=.08), glow


def fascia(w, h):
    """Faixa da cobertura: vermelho-tijolo, filete amarelo e o nome entre dois sóis."""
    img = Image.new("RGB", (w, h), (176, 54, 32))
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    d, g = ImageDraw.Draw(img), ImageDraw.Draw(glow)
    d.rectangle((0, h * .78, w, h), fill=(232, 176, 58))
    d.rectangle((0, 0, w, h * .07), fill=(120, 34, 24))
    f = fit_text(d, "SOL POENTE", w * .3, h * .6, FONT_BOLD)
    for cx in (w * .25, w * .75):
        text_center(d, "SOL POENTE", cx, h * .42, f, (255, 236, 196))
        text_center(g, "SOL POENTE", cx, h * .42, f, (255, 200, 130))
    for cx in (w * .06, w * .5, w * .94):
        sun_logo(d, cx, h * .66, h * .32, sky=(176, 54, 32), rays=False)
        sun_logo(g, cx, h * .66, h * .32, sky=(0, 0, 0), sun=(220, 120, 40), rays=False)
    g.rectangle((0, h * .78, w, h), fill=(110, 70, 18))
    return weather(img, dirt=.16, streaks=.1, scale=30), glow


def shop_band(w, h):
    img = Image.new("RGB", (w, h), (204, 100, 60))
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    d, g = ImageDraw.Draw(img), ImageDraw.Draw(glow)
    text = "CONVENIÊNCIA SOL POENTE"
    f = fit_text(d, text, w * .8, h * .62, FONT_BOLD)
    text_center(d, text, w / 2, h * .5, f, (255, 240, 214), stroke=2, stroke_fill=(120, 44, 24))
    text_center(g, text, w / 2, h * .5, f, (255, 196, 120))
    for cx in (w * .05, w * .95):
        sun_logo(d, cx, h * .7, h * .32, sky=(204, 100, 60), rays=False)
    return weather(img, dirt=.2, streaks=.14, scale=24), glow


def garage_sign(w, h):
    """Placa pintada à mão, como as de borracharia de beira de estrada."""
    img = Image.new("RGB", (w, h), (236, 228, 208))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w - 1, h - 1), outline=(40, 70, 130), width=10)
    tire_r = h * .36
    cx, cy = h * .55, h / 2
    d.ellipse((cx - tire_r, cy - tire_r, cx + tire_r, cy + tire_r), fill=(32, 30, 30))
    d.ellipse((cx - tire_r * .5, cy - tire_r * .5, cx + tire_r * .5, cy + tire_r * .5), fill=(170, 170, 166))
    d.ellipse((cx - tire_r * .16, cy - tire_r * .16, cx + tire_r * .16, cy + tire_r * .16), fill=(60, 60, 60))
    f = fit_text(d, "BORRACHARIA", w * .62, h * .5, FONT_BOLD)
    d.text((h * 1.05, h * .38), "BORRACHARIA", font=f, fill=(196, 34, 30), anchor="lm")
    f2 = fit_text(d, "MECÂNICA · SOCORRO 24 H", w * .62, h * .25, FONT_BOLD)
    d.text((h * 1.08, h * .78), "MECÂNICA · SOCORRO 24 H", font=f2, fill=(40, 70, 130), anchor="lm")
    chip(img, 90, (205, 196, 176))
    return weather(img, dirt=.22, streaks=.18, scale=30), Image.new("RGB", (w, h))


def pump(w, h):
    img = Image.new("RGB", (w, h), (226, 222, 212))
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    d, g = ImageDraw.Draw(img), ImageDraw.Draw(glow)
    d.rectangle((0, 0, w, h * .16), fill=(176, 54, 32))
    sun_logo(d, w / 2, h * .12, w * .2, sky=(176, 54, 32), rays=False)
    g.rectangle((0, 0, w, h * .16), fill=(90, 26, 10))
    d.rectangle((w * .12, h * .22, w * .88, h * .46), fill=(30, 32, 30))
    fd = fit_text(d, "88,88", w * .66, h * .07, FONT_BOLD)
    for i, val in enumerate(("142,30", "24,57")):
        y = h * (.27 + .1 * i)
        d.text((w * .82, y), val, font=fd, fill=(255, 176, 60), anchor="ra")
        g.text((w * .82, y), val, font=fd, fill=(255, 150, 40), anchor="ra")
    fl = fit_text(d, "GASOLINA", w * .76, h * .06, FONT_BOLD)
    d.rectangle((w * .1, h * .52, w * .9, h * .6), fill=(232, 176, 58))
    text_center(d, "GASOLINA", w / 2, h * .56, fl, (40, 30, 24))
    for r in range(3):
        for c in range(3):
            x, y = w * (.3 + .2 * c), h * (.67 + .055 * r)
            d.rectangle((x - 9, y - 7, x + 9, y + 7), fill=(150, 150, 146))
    d.rectangle((0, h * .86, w, h), fill=(80, 76, 70))
    return weather(img, dirt=.2, streaks=.2, scale=20), glow


def scrap_sign(w, h):
    """Chapa enferrujada com letra pintada à mão e lâmpadas no topo."""
    base = np.zeros((h, w, 3), np.float32)
    rust = noise(w, h, 60, 4)
    base[...] = np.array([118, 70, 44], np.float32)
    base += (rust[..., None] - .5) * np.array([90, 50, 30], np.float32)
    # Ondas da chapa.
    wave = (np.sin(np.linspace(0, w / 14, w)) * .5 + .5)[None, :]
    base *= (.88 + .12 * wave)[..., None]
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    d, g = ImageDraw.Draw(img), ImageDraw.Draw(glow)
    d.rectangle((w * .03, h * .14, w * .97, h * .64), fill=(238, 214, 92))
    f = fit_text(d, "FERRO-VELHO DO NONATO", w * .9, h * .4, FONT_BOLD)
    text_center(d, "FERRO-VELHO DO NONATO", w / 2, h * .39, f, (30, 26, 24))
    f2 = fit_text(d, "COMPRA E VENDE SUCATA · PEÇAS USADAS", w * .86, h * .17, FONT_BOLD)
    text_center(d, "COMPRA E VENDE SUCATA · PEÇAS USADAS", w / 2, h * .8, f2, (246, 240, 226))
    for i in range(9):
        cx = w * (.06 + .11 * i)
        d.ellipse((cx - 11, h * .065 - 11, cx + 11, h * .065 + 11), fill=(250, 236, 190))
        g.ellipse((cx - 13, h * .065 - 13, cx + 13, h * .065 + 13), fill=(255, 210, 130))
    text_center(g, "FERRO-VELHO DO NONATO", w / 2, h * .39, f, (60, 50, 20))
    chip(img, 160, (150, 96, 62), (2, 7))
    return weather(img, dirt=.2, streaks=.22, scale=30), glow


def bay_sign(w, h):
    img = Image.new("RGB", (w, h), (238, 214, 92))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w - 1, h - 1), outline=(30, 26, 24), width=8)
    f = fit_text(d, "PÁTIO DE VENDA", w * .86, h * .34, FONT_BOLD)
    text_center(d, "PÁTIO DE VENDA", w / 2, h * .3, f, (30, 26, 24))
    f2 = fit_text(d, "DEIXE O CARRO AQUI", w * .7, h * .2, FONT_BOLD)
    text_center(d, "DEIXE O CARRO AQUI", w * .42, h * .72, f2, (150, 34, 26))
    ax, ay = w * .86, h * .72
    d.polygon([(ax - 34, ay - 22), (ax + 4, ay - 22), (ax + 4, ay - 40), (ax + 40, ay), (ax + 4, ay + 40), (ax + 4, ay + 22), (ax - 34, ay + 22)], fill=(150, 34, 26))
    return weather(img, dirt=.18, streaks=.15, scale=20), Image.new("RGB", (w, h))


def tower_plate(w, h):
    img = Image.new("RGB", (w, h), (232, 232, 226))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w, h * .34), fill=(34, 76, 140))
    f = fit_text(d, "RÁDIO SOL 98,1 FM", w * .9, h * .26, FONT_BOLD)
    text_center(d, "RÁDIO SOL 98,1 FM", w / 2, h * .17, f, (255, 255, 255))
    f2 = fit_text(d, "ESTAÇÃO REPETIDORA", w * .86, h * .17, FONT_BOLD)
    text_center(d, "ESTAÇÃO REPETIDORA", w / 2, h * .5, f2, (34, 76, 140))
    f3 = fit_text(d, "ACESSO RESTRITO", w * .6, h * .15, FONT_BOLD)
    text_center(d, "ACESSO RESTRITO", w / 2, h * .76, f3, (180, 34, 30))
    d.rectangle((0, 0, w - 1, h - 1), outline=(90, 90, 86), width=6)
    return weather(img, dirt=.2, streaks=.2, scale=20), Image.new("RGB", (w, h))


def hazard(w, h):
    img = Image.new("RGB", (w, h), (240, 236, 226))
    d = ImageDraw.Draw(img)
    d.polygon([(w / 2, h * .06), (w * .94, h * .7), (w * .06, h * .7)], fill=(246, 196, 30), outline=(20, 20, 20), width=10)
    d.polygon([(w * .55, h * .2), (w * .4, h * .46), (w * .52, h * .46), (w * .44, h * .64), (w * .62, h * .38), (w * .5, h * .38)], fill=(20, 20, 20))
    f = fit_text(d, "PERIGO", w * .8, h * .2, FONT_BOLD)
    text_center(d, "PERIGO", w / 2, h * .84, f, (180, 30, 26))
    return weather(img, dirt=.18, streaks=.2, scale=16), Image.new("RGB", (w, h))


TRUCK_RED = (168, 40, 34)
TRUCK_CREAM = (240, 226, 188)


def truck_base(w, h):
    img = Image.new("RGB", (w, h), TRUCK_RED)
    d = ImageDraw.Draw(img)
    d.rectangle((0, h * .74, w, h * .82), fill=TRUCK_CREAM)
    d.rectangle((0, h * .82, w, h), fill=(120, 30, 26))
    d.rectangle((0, 0, w, h * .05), fill=(232, 228, 220))
    return img, d


def burger(d, cx, cy, s):
    d.pieslice((cx - s, cy - s * .9, cx + s, cy + s * .5), 180, 360, fill=(222, 150, 64))
    for i in range(7):
        d.ellipse((cx - s * .7 + i * s * .22, cy - s * .55, cx - s * .64 + i * s * .22, cy - s * .5), fill=(250, 236, 196))
    d.rectangle((cx - s * 1.02, cy - s * .2, cx + s * 1.02, cy - s * .02), fill=(90, 170, 60))
    d.rectangle((cx - s * .98, cy - s * .02, cx + s * .98, cy + s * .2), fill=(110, 56, 36))
    d.rectangle((cx - s * 1.0, cy + s * .2, cx + s * 1.0, cy + s * .3), fill=(250, 196, 40))
    d.chord((cx - s, cy + s * .05, cx + s, cy + s * .6), 0, 180, fill=(212, 140, 60))


def truck_window(w, h):
    """Lado do balcão: nome em cima, janela de atendimento aberta (interior aceso) e cardápio."""
    img, d = truck_base(w, h)
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    g = ImageDraw.Draw(glow)
    f = fit_text(d, "LANCHE DA RETA", w * .62, h * .2, FONT_BOLD)
    text_center(d, "LANCHE DA RETA", w * .47, h * .14, f, (252, 214, 64), stroke=4, stroke_fill=(70, 18, 14))
    text_center(g, "LANCHE DA RETA", w * .47, h * .14, f, (200, 150, 40))
    # Janela: x 0,22..0,72 (o balcão 3D fica embaixo dela), y 0,27..0,66.
    x0, x1, y0, y1 = w * .2, w * .74, h * .26, h * .66
    d.rectangle((x0 - 8, y0 - 8, x1 + 8, y1 + 8), fill=(200, 200, 196))
    d.rectangle((x0, y0, x1, y1), fill=(84, 60, 40))
    d.rectangle((x0, y0, x1, y0 + (y1 - y0) * .18), fill=(56, 40, 30))
    # Prateleiras com latas e garrafas, chapa e coifa.
    for k in range(2):
        yy = y0 + (y1 - y0) * (.36 + .26 * k)
        d.rectangle((x0 + 12, yy, x1 - 12, yy + 6), fill=(150, 150, 146))
        for i in range(16):
            cx = x0 + 30 + i * (x1 - x0 - 60) / 15
            col = [(200, 30, 30), (40, 120, 60), (230, 180, 40), (40, 80, 160)][(i + k) % 4]
            d.rectangle((cx - 7, yy - 26, cx + 7, yy), fill=col)
    d.rectangle((x0 + 20, y1 - 30, x1 - 20, y1 - 6), fill=(70, 70, 70))
    g.rectangle((x0, y0, x1, y1), fill=(150, 104, 52))
    g.rectangle((x0 + 20, y1 - 30, x1 - 20, y1 - 6), fill=(40, 30, 20))
    # Cardápio à direita da janela.
    mx0, mx1 = w * .78, w * .97
    d.rectangle((mx0, h * .2, mx1, h * .7), fill=(34, 40, 34))
    fm = font(FONT_HAND, int(h * .06))
    items = ["X-burguer 18", "X-tudo 24", "Pastel 9", "Caldo de cana 7", "Refri 6", "Café 3"]
    for i, item in enumerate(items):
        d.text((mx0 + 12, h * (.24 + .075 * i)), item, font=fm, fill=(238, 236, 226))
    burger(d, w * .1, h * .5, w * .065)
    d.text((w * .03, h * .9), "DONA CIDA · DESDE 1998", font=font(FONT_BOLD, int(h * .07)), fill=TRUCK_CREAM, anchor="lm")
    return weather(img, dirt=.12, streaks=.1, scale=40), glow


def truck_plain(w, h):
    img, d = truck_base(w, h)
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    g = ImageDraw.Draw(glow)
    f = fit_text(d, "LANCHE", w * .5, h * .3, FONT_BOLD)
    text_center(d, "LANCHE", w * .38, h * .26, f, (252, 214, 64), stroke=5, stroke_fill=(70, 18, 14))
    f2 = fit_text(d, "DA RETA", w * .44, h * .24, FONT_BOLD)
    text_center(d, "DA RETA", w * .38, h * .53, f2, TRUCK_CREAM, stroke=4, stroke_fill=(70, 18, 14))
    text_center(g, "LANCHE", w * .38, h * .26, f, (190, 140, 30))
    burger(d, w * .8, h * .42, w * .11)
    f3 = fit_text(d, "X-BURGUER · PASTEL · CALDO DE CANA", w * .9, h * .07, FONT_BOLD)
    text_center(d, "X-BURGUER · PASTEL · CALDO DE CANA", w / 2, h * .78, f3, (120, 30, 26))
    return weather(img, dirt=.12, streaks=.1, scale=40), glow


def truck_sign(w, h):
    """Letreiro de teto do lanche: caixa de luz vermelha com letra amarela."""
    img = Image.new("RGB", (w, h), (150, 30, 26))
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    d, g = ImageDraw.Draw(img), ImageDraw.Draw(glow)
    d.rectangle((0, 0, w - 1, h - 1), outline=(240, 226, 188), width=8)
    f = fit_text(d, "LANCHE DA RETA", w * .86, h * .66, FONT_BOLD)
    text_center(d, "LANCHE DA RETA", w / 2, h * .5, f, (252, 214, 64), stroke=3, stroke_fill=(70, 18, 14))
    g.rectangle((8, 8, w - 9, h - 9), fill=(70, 12, 8))
    text_center(g, "LANCHE DA RETA", w / 2, h * .5, f, (255, 200, 60))
    return weather(img, dirt=.1, streaks=.08, scale=30), glow


def truck_back(w, h):
    img, d = truck_base(w, h)
    d.line((w / 2, h * .08, w / 2, h * .74), fill=(90, 22, 20), width=6)
    for x in (w * .1, w * .9):
        d.rectangle((x - 14, h * .6, x + 14, h * .7), fill=(220, 40, 30))
    d.rectangle((w * .36, h * .84, w * .64, h * .94), fill=(236, 236, 230))
    d.text((w / 2, h * .89), "RTA-1998", font=font(FONT_BOLD, int(h * .07)), fill=(30, 30, 30), anchor="mm")
    f = fit_text(d, "LANCHE DA RETA", w * .84, h * .12, FONT_BOLD)
    text_center(d, "LANCHE DA RETA", w / 2, h * .3, f, (252, 214, 64), stroke=3, stroke_fill=(70, 18, 14))
    glow = Image.new("RGB", (w, h))
    ImageDraw.Draw(glow).rectangle((w * .1 - 14, h * .6, w * .1 + 14, h * .7), fill=(90, 10, 6))
    ImageDraw.Draw(glow).rectangle((w * .9 - 14, h * .6, w * .9 + 14, h * .7), fill=(90, 10, 6))
    return weather(img, dirt=.15, streaks=.12, scale=30), glow


def truck_front(w, h):
    img = Image.new("RGB", (w, h), TRUCK_RED)
    d = ImageDraw.Draw(img)
    d.rectangle((w * .06, h * .06, w * .94, h * .46), fill=(40, 58, 66))
    d.polygon([(w * .1, h * .1), (w * .35, h * .1), (w * .16, h * .42), (w * .1, h * .42)], fill=(90, 116, 124))
    d.rectangle((0, h * .5, w, h * .58), fill=TRUCK_CREAM)
    d.rectangle((w * .26, h * .62, w * .74, h * .8), fill=(40, 40, 40))
    for i in range(5): d.line((w * .28, h * (.65 + .03 * i), w * .72, h * (.65 + .03 * i)), fill=(120, 120, 120), width=3)
    for x in (w * .13, w * .87):
        d.ellipse((x - 24, h * .64, x + 24, h * .78), fill=(240, 238, 220))
    d.rectangle((0, h * .86, w, h), fill=(60, 60, 60))
    glow = Image.new("RGB", (w, h))
    for x in (w * .13, w * .87):
        ImageDraw.Draw(glow).ellipse((x - 24, h * .64, x + 24, h * .78), fill=(160, 150, 110))
    return weather(img, dirt=.15, streaks=.08, scale=30), glow


def menu(w, h):
    """Cavalete de giz na frente do lanche."""
    img = Image.new("RGB", (w, h), (40, 46, 40))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w - 1, h - 1), outline=(120, 86, 56), width=14)
    fh = font(FONT_HAND, int(h * .11))
    text_center(d, "Hoje tem!", w / 2, h * .12, fh, (250, 214, 90))
    fm = font(FONT_HAND, int(h * .075))
    for i, item in enumerate(["X-tudo 24", "Pastel 9", "Caldo de cana 7", "Café 3"]):
        d.text((w * .12, h * (.26 + .14 * i)), item, font=fm, fill=(240, 238, 230))
    a = np.asarray(img, np.float32)
    smudge = noise(w, h, 30)
    a += (smudge[..., None] - .5) * 26
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), Image.new("RGB", (w, h))


def bale(w, h, paint):
    """Carro prensado: lata amassada na cor do carro, ferrugem, vidro moído e um pedaço de pneu."""
    rust = noise(w, h, 18, 4)
    crumple = noise(w, h, 7, 3)
    a = np.zeros((h, w, 3), np.float32)
    # Tinta velha: puxa 35% para o cinza (sem isso o fardo lia como bloco de brinquedo).
    p = np.array(paint, np.float32) * .65 + np.array(paint, np.float32).mean() * .35
    rust_col = np.array([116, 66, 40], np.float32)
    mask = np.clip((rust - .52) * 4, 0, 1)[..., None]
    a[...] = p * (.62 + .55 * crumple[..., None]) * (1 - mask) + rust_col * (.7 + .5 * crumple[..., None]) * mask
    # Vincos da prensa: muitos, finos, levemente tortos.
    for _ in range(18):
        y0 = rng.randrange(h)
        tilt = rng.uniform(-.08, .08)
        for x in range(0, w, 4):
            y = int(y0 + tilt * x)
            if 0 <= y < h: a[max(0, y - 1):y + 2, x:x + 4] *= rng.uniform(.35, .6)
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    # Friso cromado, lanterna esmagada e roda.
    y = rng.uniform(.3, .6) * h
    d.line((0, y, w, y + rng.uniform(-14, 14)), fill=(196, 196, 190), width=5)
    lx = rng.uniform(.08, .2) * w
    d.polygon([(lx, h * .2), (lx + 46, h * .24), (lx + 40, h * .36), (lx - 4, h * .32)], fill=(170, 30, 26))
    # Pedaço de pneu esmagado: só uma faixa escura curta, não uma roda inteira.
    rx, ry = rng.uniform(.55, .85) * w, h * rng.uniform(.6, .8)
    d.polygon([(rx - 40, ry - 6), (rx + 36, ry - 12), (rx + 40, ry + 2), (rx - 36, ry + 8)], fill=(34, 33, 32))
    for _ in range(40):
        x, yy = rng.randrange(w), rng.randrange(h)
        d.point((x, yy), fill=(160, 200, 200))
    return img, Image.new("RGB", (w, h))


def light_panel(w, h):
    return Image.new("RGB", (w, h), (246, 244, 236)), Image.new("RGB", (w, h), (255, 236, 200))


def beacon(w, h):
    return Image.new("RGB", (w, h), (200, 30, 26)), Image.new("RGB", (w, h), (255, 40, 24))


def payphone(w, h):
    """Frente do orelhão: corpo prata, teclado, fenda do cartão e a placa azul."""
    img = Image.new("RGB", (w, h), (176, 178, 176))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w, h * .14), fill=(30, 70, 150))
    f = fit_text(d, "TELEFONE", w * .84, h * .1, FONT_BOLD)
    text_center(d, "TELEFONE", w / 2, h * .07, f, (255, 255, 255))
    d.rectangle((w * .16, h * .2, w * .84, h * .34), fill=(40, 52, 46))
    for r in range(4):
        for c in range(3):
            x, y = w * (.3 + .2 * c), h * (.44 + .07 * r)
            d.rectangle((x - 9, y - 8, x + 9, y + 8), fill=(60, 60, 64))
    d.rectangle((w * .3, h * .76, w * .7, h * .79), fill=(30, 30, 30))
    d.rounded_rectangle((w * .06, h * .2, w * .16, h * .7), 6, fill=(30, 30, 30))
    return weather(img, dirt=.18, streaks=.15, scale=14), Image.new("RGB", (w, h))


def office_sign(w, h):
    img = Image.new("RGB", (w, h), (236, 232, 220))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w - 1, h - 1), outline=(30, 26, 24), width=6)
    f = fit_text(d, "ESCRITÓRIO · BALANÇA", w * .9, h * .62, FONT_BOLD)
    text_center(d, "ESCRITÓRIO · BALANÇA", w / 2, h / 2, f, (30, 26, 24))
    return weather(img, dirt=.2, streaks=.2, scale=14), Image.new("RGB", (w, h))


PANELS = [
    ("pylon", 448, 672, pylon),
    ("fascia", 1792, 96, fascia),
    ("shop_band", 1280, 96, shop_band),
    ("garage_sign", 896, 160, garage_sign),
    ("scrap_sign", 1024, 256, scrap_sign),
    ("truck_window", 896, 392, truck_window),
    ("truck_plain", 896, 392, truck_plain),
    ("truck_back", 320, 384, truck_back),
    ("truck_sign", 768, 160, truck_sign),
    ("truck_front", 384, 352, truck_front),
    ("pump", 160, 320, pump),
    ("menu", 256, 384, menu),
    ("bay_sign", 448, 224, bay_sign),
    ("tower_plate", 448, 280, tower_plate),
    ("hazard", 256, 256, hazard),
    ("payphone", 160, 256, payphone),
    ("office_sign", 512, 96, office_sign),
    ("bale_0", 320, 160, lambda w, h: bale(w, h, (150, 40, 34))),
    ("bale_1", 320, 160, lambda w, h: bale(w, h, (52, 84, 128))),
    ("bale_2", 320, 160, lambda w, h: bale(w, h, (196, 186, 160))),
    ("bale_3", 320, 160, lambda w, h: bale(w, h, (70, 110, 70))),
    ("light", 64, 64, light_panel),
    ("beacon", 64, 64, beacon),
]


def pack(panels):
    """Linha do horizonte (skyline): cada painel, do maior lado para o menor, entra no ponto
    mais baixo onde cabe; margem em volta para o mipmap."""
    order = sorted(panels, key=lambda p: -max(p[1], p[2]))
    sky = [0] * SIZE
    rects = {}
    for name, w, h, _ in order:
        bw, bh = w + PAD * 2, h + PAD * 2
        best = None
        best_score = None
        for x in range(0, SIZE - bw + 1, 8):
            top = max(sky[x:x + bw])
            if top + bh > SIZE: continue
            # Menor topo resultante; no empate, menos área perdida embaixo do painel.
            score = (top + bh, sum(top - s for s in sky[x:x + bw]))
            if best_score is None or score < best_score: best, best_score = (x, top), score
        assert best is not None, "atlas cheio: " + name
        x, top = best
        for i in range(x, x + bw): sky[i] = top + bh
        rects[name] = (x + PAD, top + PAD, w, h)
    return rects


def paste_padded(atlas, img, x, y):
    """Cola o painel e estica a borda na margem (mipmap não puxa a cor do vizinho)."""
    w, h = img.size
    atlas.paste(img.resize((w + PAD * 2, h + PAD * 2), Image.NEAREST), (x - PAD, y - PAD))
    atlas.paste(img, (x, y))


def write_import_params(texture):
    path = texture.with_name(texture.name + ".import")
    if not path.exists():
        lines = ["[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "", "[params]", ""]
        lines += [f"{k}={v}" for k, v in IMPORT_PARAMS.items()]
        path.write_text(NL.join(lines) + NL, encoding="utf-8")
        return
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        key = line.split("=", 1)[0]
        out.append(f"{key}={IMPORT_PARAMS[key]}" if key in IMPORT_PARAMS and "=" in line else line)
    path.write_text(NL.join(out) + NL, encoding="utf-8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rects = pack(PANELS)
    atlas = Image.new("RGB", (SIZE, SIZE), (90, 84, 76))
    glow = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    uv = {}
    for name, w, h, painter in PANELS:
        x, y, _, _ = rects[name]
        color, light = painter(w, h)
        paste_padded(atlas, color.convert("RGB"), x, y)
        paste_padded(glow, light.convert("RGB"), x, y)
        # Meio texel para dentro: o filtro não pega a margem esticada na borda do quad.
        uv[name] = [(x + .5) / SIZE, (y + .5) / SIZE, (x + w - .5) / SIZE, (y + h - .5) / SIZE]
    atlas.save(OUT / "roadside_atlas.jpg", quality=92)
    glow.save(OUT / "roadside_atlas_glow.jpg", quality=90)
    (OUT / "roadside_atlas.json").write_text(json.dumps({"size": SIZE, "uv": uv}, indent=1) + NL, encoding="utf-8")
    for texture in ("roadside_atlas.jpg", "roadside_atlas_glow.jpg"):
        write_import_params(OUT / texture)
    print("atlas", SIZE, "painéis", len(uv))


if __name__ == "__main__":
    main()
