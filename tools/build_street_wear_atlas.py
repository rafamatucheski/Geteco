"""Atlas de desgaste da rua do Harbor: adesivos, lambe-lambe, pichação, ferrugem, sujeira e plaquetas.

Rodar (determinístico, sem rede):
    python -I tools/build_street_wear_atlas.py

Grava assets/urban_detail/street_wear_atlas.png (512x512, RGBA). O .import ao lado pede BC7 com
mipmaps (compress/mode=2, high_quality); depois do script, `tools/run_godot_locked.sh --headless
--path . --import` gera o .ctex. As células (em pixels) estão espelhadas em
world/city_look/HarborStreetWear.gd (CELLS); mudar uma posição aqui exige mudar lá.

Por que procedural e sem texto legível: o usuário não quer letreiro explicando objeto
(AGENTS.md); o adesivo e o cartaz leem como tal pela forma (barras de "texto", foto, borda
rasgada). A plaqueta do poste só tem dígitos de 7 segmentos.
O desenho sai em 4x (2048) e é reduzido com LANCZOS: borda suave antes do alpha scissor.
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "urban_detail", "street_wear_atlas.png")
SIZE = 512
SS = 4  # supersampling
BIG = SIZE * SS

# Células (x, y, w, h) em pixels do atlas final. Espelhadas em HarborStreetWear.CELLS.
CELLS = {
    **{f"sticker{i}": (i * 64, 0, 64, 64) for i in range(8)},
    **{f"poster{i}": (i * 128, 64, 128, 128) for i in range(4)},
    **{f"tag{i}": (i * 128, 192, 128, 64) for i in range(4)},
    **{f"rust{i}": (i * 64, 256, 64, 128) for i in range(4)},
    **{f"grime{i}": (256 + i * 64, 256, 64, 128) for i in range(4)},
    "plate_number": (0, 384, 64, 128),
    "plate_danger": (64, 384, 64, 64),
    "sticker_cluster": (128, 384, 128, 128),
    "tag_wide": (256, 384, 256, 64),
    "poster_strip": (256, 448, 256, 64),
}

PALETTE = ["#d23a2f", "#f2c230", "#2d6fb6", "#2f8a52", "#f4f1e8", "#202326", "#ef7d2b", "#d8508c", "#6a3fa0", "#2bb3c0"]


def rgba(hex_color: str, alpha: int = 255) -> tuple:
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def big_box(cell: str) -> tuple:
    x, y, w, h = CELLS[cell]
    return x * SS, y * SS, w * SS, h * SS


def text_bars(draw: ImageDraw.ImageDraw, rng: random.Random, x0: float, y0: float, w: float, h: float,
              color: tuple, rows: int) -> None:
    """Linhas de "texto" ilegível: barras com falhas, como letreiro visto de longe."""
    row_h = h / rows
    for r in range(rows):
        cy = y0 + r * row_h + row_h * 0.5
        thick = row_h * rng.uniform(0.35, 0.55)
        cursor = x0
        end = x0 + w * rng.uniform(0.55, 1.0)
        while cursor < end:
            word = w * rng.uniform(0.08, 0.26)
            draw.rectangle([cursor, cy - thick / 2, min(end, cursor + word), cy + thick / 2], fill=color)
            cursor += word + w * rng.uniform(0.03, 0.06)


def sticker(img: Image.Image, cell: str, seed: int) -> None:
    rng = random.Random(seed)
    x, y, w, h = big_box(cell)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    margin = w * rng.uniform(0.08, 0.16)
    shape = rng.choice(["round", "round", "circle", "rect", "oval"])
    bg = rgba(rng.choice(PALETTE))
    fg = rgba("#f4f1e8") if sum(bg[:3]) < 380 else rgba("#202326")
    box = [margin, margin + h * rng.uniform(0.0, 0.12), w - margin, h - margin - h * rng.uniform(0.0, 0.12)]
    border = rgba("#f4f1e8")
    if shape == "circle" or shape == "oval":
        d.ellipse(box, fill=border)
        inset = w * 0.05
        d.ellipse([box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset], fill=bg)
        cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
        if rng.random() < 0.5:
            r = (box[2] - box[0]) * 0.18
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fg)
        else:
            text_bars(d, rng, box[0] + w * 0.2, cy - h * 0.12, (box[2] - box[0]) * 0.6, h * 0.24, fg, 2)
    else:
        radius = w * (0.1 if shape == "round" else 0.01)
        d.rounded_rectangle(box, radius=radius, fill=border)
        inset = w * 0.045
        inner = [box[0] + inset, box[1] + inset, box[2] - inset, box[3] - inset]
        d.rounded_rectangle(inner, radius=radius * 0.7, fill=bg)
        iw, ih = inner[2] - inner[0], inner[3] - inner[1]
        if rng.random() < 0.45:
            # Faixa de cor + "texto": adesivo de banda/política sem palavra legível.
            stripe = rgba(rng.choice(PALETTE))
            d.rectangle([inner[0], inner[1] + ih * 0.62, inner[2], inner[1] + ih * 0.82], fill=stripe)
            text_bars(d, rng, inner[0] + iw * 0.1, inner[1] + ih * 0.12, iw * 0.8, ih * 0.45, fg, 2)
        elif rng.random() < 0.5:
            # Estrela/ícone central.
            cx, cy, r = inner[0] + iw / 2, inner[1] + ih / 2, min(iw, ih) * 0.32
            pts = []
            for k in range(10):
                a = -math.pi / 2 + k * math.pi / 5
                rr = r if k % 2 == 0 else r * 0.45
                pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
            d.polygon(pts, fill=fg)
        else:
            # Quadradinho tipo código + linhas: adesivo de serviço ("disk entulho").
            q = min(iw, ih) * 0.42
            d.rectangle([inner[0] + iw * 0.08, inner[1] + ih * 0.15, inner[0] + iw * 0.08 + q, inner[1] + ih * 0.15 + q], fill=fg)
            for k in range(9):
                if rng.random() < 0.5:
                    cxk = inner[0] + iw * 0.08 + (k % 3 + 0.5) * q / 3
                    cyk = inner[1] + ih * 0.15 + (k // 3 + 0.5) * q / 3
                    d.rectangle([cxk - q / 8, cyk - q / 8, cxk + q / 8, cyk + q / 8], fill=bg)
            text_bars(d, rng, inner[0] + iw * 0.58, inner[1] + ih * 0.15, iw * 0.34, q, fg, 3)
    _weather(layer, rng, fade=0.25, tear=0.18)
    layer = layer.rotate(rng.uniform(-9, 9), resample=Image.BICUBIC)
    img.alpha_composite(layer, (x, y))


def poster(img: Image.Image, cell: str, seed: int, wide: bool = False) -> None:
    """Lambe-lambe: papel colado, barras pretas grossas de manchete, foto, borda rasgada."""
    rng = random.Random(seed)
    x, y, w, h = big_box(cell)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    count = 3 if wide else rng.choice([1, 2, 2])
    for k in range(count):
        d = ImageDraw.Draw(layer)
        paper = rgba(rng.choice(["#efe6cf", "#f3e46a", "#f0a7c0", "#bfe0f0", "#f4f1e8", "#f6c25a"]))
        if wide:
            pw, ph = w * 0.32, h * 0.86
            px, py = k * w * 0.33 + w * 0.01, h * 0.07
        else:
            pw, ph = w * rng.uniform(0.62, 0.86), h * rng.uniform(0.68, 0.9)
            px, py = rng.uniform(0.02, 0.98 - pw / w) * w, rng.uniform(0.02, 0.98 - ph / h) * h
        d.rectangle([px, py, px + pw, py + ph], fill=paper)
        ink = rgba(rng.choice(["#1c1c1c", "#1c1c1c", "#b4231d", "#1d3f8a"]))
        text_bars(d, rng, px + pw * 0.07, py + ph * 0.06, pw * 0.86, ph * 0.26, ink, 2)
        if rng.random() < 0.7:
            photo = rgba(rng.choice(["#5a6e7a", "#7a5a4a", "#3c5a3a", "#8a7a5a", "#4a4a6a"]))
            d.rectangle([px + pw * 0.08, py + ph * 0.38, px + pw * 0.92, py + ph * 0.7], fill=photo)
            # Silhueta clara dentro da "foto".
            d.ellipse([px + pw * 0.4, py + ph * 0.42, px + pw * 0.6, py + ph * 0.58], fill=rgba("#d8c8b0"))
        text_bars(d, rng, px + pw * 0.08, py + ph * 0.74, pw * 0.84, ph * 0.2, ink, 3)
    _weather(layer, rng, fade=0.35, tear=0.4, grime=0.18)
    img.alpha_composite(layer, (x, y))


def tag(img: Image.Image, cell: str, seed: int) -> None:
    """Pichação: traços curvos grossos com contorno e escorrido."""
    rng = random.Random(seed)
    x, y, w, h = big_box(cell)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    main = rgba(rng.choice(["#111111", "#111111", "#c42b2b", "#2a55c4", "#e8e8e8", "#3aa65a"]))
    outline = rgba("#111111") if main[:3] != (17, 17, 17) else rgba(rng.choice(["#e8e8e8", "#d8b030"]))
    strokes = []
    cursor = w * 0.08
    while cursor < w * 0.86:
        width = w * rng.uniform(0.06, 0.14)
        pts = []
        for s in range(9):
            t = s / 8
            px = cursor + width * t + math.sin(t * 6 + seed) * width * 0.2
            py = h * (0.25 + 0.55 * (0.5 + 0.5 * math.sin(t * math.pi * rng.uniform(1.0, 2.5) + rng.uniform(0, 6))))
            pts.append((px, py))
        strokes.append(pts)
        cursor += width * rng.uniform(0.9, 1.3)
    thick = h * 0.09
    for pts in strokes:
        d.line(pts, fill=outline, width=int(thick * 1.7), joint="curve")
    for pts in strokes:
        d.line(pts, fill=main, width=int(thick), joint="curve")
        if rng.random() < 0.4:
            px, py = pts[-1]
            d.line([(px, py), (px, py + h * rng.uniform(0.1, 0.25))], fill=main, width=int(thick * 0.35))
    img.alpha_composite(layer, (x, y))


def streaks(img: Image.Image, cell: str, seed: int, rust: bool) -> None:
    """Ferrugem escorrendo de cima (parafuso, junta) ou sujeira subindo do chão (respingo)."""
    rng = np.random.default_rng(seed)
    x, y, w, h = big_box(cell)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v = yy / h  # 0 em cima, 1 embaixo
    cols = rng.uniform(0.0, 1.0, 9)
    noise = np.zeros((h, w), np.float32)
    for c in cols:
        center = c * w
        width = w * rng.uniform(0.03, 0.12)
        length = rng.uniform(0.3, 0.95)
        band = np.exp(-((xx - center) / width) ** 2)
        if rust:
            fade = np.clip(1.0 - v / length, 0.0, 1.0) ** 0.7
        else:
            fade = np.clip((v - (1.0 - length * 0.6)) / (length * 0.6), 0.0, 1.0) ** 0.8
        noise = np.maximum(noise, band * fade)
    speck = rng.uniform(0, 1, (h // 8, w // 8)).astype(np.float32)
    speck = np.array(Image.fromarray((speck * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR)).astype(np.float32) / 255
    if rust:
        alpha = np.clip(noise * 1.25 + (speck - 0.75) * 1.4 * (1.0 - v), 0, 1)
        base = np.array([0.45, 0.22, 0.09])
        tone = base[None, None, :] * (0.75 + 0.5 * speck[:, :, None])
    else:
        ground = np.clip((v - 0.45) / 0.55, 0, 1) ** 1.4
        alpha = np.clip(np.maximum(noise * 0.9, ground) + (speck - 0.6) * 0.6 * ground, 0, 1)
        base = np.array([0.16, 0.14, 0.12])
        tone = base[None, None, :] * (0.8 + 0.4 * speck[:, :, None])
    rgba_arr = np.dstack([np.clip(tone, 0, 1), alpha]).astype(np.float32)
    layer = Image.fromarray((rgba_arr * 255).astype(np.uint8), "RGBA")
    img.alpha_composite(layer, (x, y))


def seven_segment(draw: ImageDraw.ImageDraw, digit: int, x0: float, y0: float, w: float, h: float, color: tuple) -> None:
    on = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F][digit]
    t = w * 0.15
    segs = [
        (x0 + t, y0, x0 + w - t, y0 + t),
        (x0 + w - t, y0 + t, x0 + w, y0 + h / 2 - t / 2),
        (x0 + w - t, y0 + h / 2 + t / 2, x0 + w, y0 + h - t),
        (x0 + t, y0 + h - t, x0 + w - t, y0 + h),
        (x0, y0 + h / 2 + t / 2, x0 + t, y0 + h - t),
        (x0, y0 + t, x0 + t, y0 + h / 2 - t / 2),
        (x0 + t, y0 + h / 2 - t / 2, x0 + w - t, y0 + h / 2 + t / 2),
    ]
    for bit, seg in enumerate(segs):
        if on & (1 << bit):
            draw.rectangle(seg, fill=color)


def plates(img: Image.Image) -> None:
    # Plaqueta de número do poste (alumínio pintado, dígitos pretos), retrato.
    x, y, w, h = big_box("plate_number")
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([w * 0.12, h * 0.04, w * 0.88, h * 0.96], radius=w * 0.08, fill=rgba("#e9ecea"))
    d.rounded_rectangle([w * 0.16, h * 0.06, w * 0.84, h * 0.94], radius=w * 0.06, outline=rgba("#30363a"), width=int(w * 0.03))
    for k, digit in enumerate([1, 4, 2, 7]):
        seven_segment(d, digit, w * 0.36, h * (0.075 + k * 0.218), w * 0.28, h * 0.2, rgba("#1b1e20"))
    img.alpha_composite(layer, (x, y))
    # Placa de perigo: amarelo com raio preto, sem texto.
    x, y, w, h = big_box("plate_danger")
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon([(w * 0.5, h * 0.06), (w * 0.95, h * 0.9), (w * 0.05, h * 0.9)], fill=rgba("#111111"))
    d.polygon([(w * 0.5, h * 0.16), (w * 0.86, h * 0.85), (w * 0.14, h * 0.85)], fill=rgba("#f2c230"))
    d.polygon([(w * 0.53, h * 0.32), (w * 0.4, h * 0.6), (w * 0.5, h * 0.6), (w * 0.44, h * 0.8),
               (w * 0.62, h * 0.52), (w * 0.52, h * 0.52), (w * 0.6, h * 0.32)], fill=rgba("#111111"))
    img.alpha_composite(layer, (x, y))


def cluster(img: Image.Image) -> None:
    """Costas de placa: vários adesivos sobrepostos."""
    x, y, w, h = big_box("sticker_cluster")
    sub = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    saved = dict(CELLS)
    for k in range(6):
        CELLS["_tmp"] = (0, 0, 64, 64)
        tmp = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
        sticker(tmp, "_tmp", 900 + k)
        piece = tmp.crop((0, 0, 64 * SS, 64 * SS)).resize((int(w * 0.5), int(h * 0.5)), Image.LANCZOS)
        rng = random.Random(77 + k)
        sub.alpha_composite(piece, (int(rng.uniform(0, w * 0.5)), int(rng.uniform(0, h * 0.5))))
    CELLS.clear()
    CELLS.update(saved)
    img.alpha_composite(sub.crop((0, 0, w, h)), (x, y))


def _weather(layer: Image.Image, rng: random.Random, fade: float, tear: float, grime: float = 0.0) -> None:
    """Desbotado, rasgos na borda (alfa) e sujeira: papel e vinil de rua envelhecidos."""
    arr = np.array(layer).astype(np.float32) / 255.0
    h, w = arr.shape[:2]
    nrng = np.random.default_rng(rng.randint(0, 1 << 30))
    low = nrng.uniform(0, 1, (8, 8)).astype(np.float32)
    low = np.array(Image.fromarray((low * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)).astype(np.float32) / 255
    arr[:, :, :3] = arr[:, :, :3] * (1 - fade * low[:, :, None]) + fade * low[:, :, None] * 0.92
    fine = nrng.uniform(0, 1, (h // 6, w // 6)).astype(np.float32)
    fine = np.array(Image.fromarray((fine * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR)).astype(np.float32) / 255
    if tear > 0:
        alpha = arr[:, :, 3]
        edge = np.array(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(int(w * 0.06) | 1))).astype(np.float32) / 255
        rim = np.clip(alpha - edge, 0, 1)
        arr[:, :, 3] = np.where((rim > 0.3) & (fine * low < tear * 0.6), 0.0, alpha)
    if grime > 0:
        arr[:, :, :3] *= (1 - grime * fine[:, :, None] * low[:, :, None])
    layer.paste(Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA"))


def main() -> None:
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    for i in range(8):
        sticker(img, f"sticker{i}", 11 + i * 7)
    for i in range(4):
        poster(img, f"poster{i}", 101 + i * 13)
        tag(img, f"tag{i}", 201 + i * 5)
        streaks(img, f"rust{i}", 301 + i, rust=True)
        streaks(img, f"grime{i}", 401 + i, rust=False)
    plates(img)
    cluster(img)
    tag(img, "tag_wide", 251)
    poster(img, "poster_strip", 151, wide=True)
    small = img.resize((SIZE, SIZE), Image.LANCZOS)
    # Cor sob alfa zero = vizinha (sem halo escuro nos mipmaps com alpha scissor).
    arr = np.array(small).astype(np.float32)
    alpha = arr[:, :, 3:4] / 255.0
    premult = Image.fromarray(np.clip(arr[:, :, :3] * alpha, 0, 255).astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(4))
    weight = Image.fromarray((alpha[:, :, 0] * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(4))
    blur = np.array(premult).astype(np.float32)
    w8 = np.array(weight).astype(np.float32)[:, :, None] / 255.0
    fill = np.where(w8 > 0.004, blur / np.maximum(w8, 0.004), 110.0)
    arr[:, :, :3] = np.where(alpha > 0.02, arr[:, :, :3], np.clip(fill, 0, 255))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").save(OUT)
    print("street wear atlas:", OUT)


if __name__ == "__main__":
    main()
