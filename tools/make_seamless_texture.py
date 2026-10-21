#!/usr/bin/env python3
"""Deixa uma textura gerada por IA emendável (repete sem costura) e grava em JPEG para o jogo.

Imagem gerada como "seamless" quase nunca emenda de verdade: a borda esquerda não continua a direita.
Mistura a imagem com ela mesma deslocada em meio quadro: perto das bordas vale a cópia deslocada (que é
contínua ali), no miolo vale a original (onde a cópia tem a costura). Custa um pouco de "fantasma" na
faixa de transição, invisível em pano, pedra e madeira gastos.

Uso: python tools/make_seamless_texture.py <entrada> <saida.jpg> [--size 1024] [--margin 0.22]
"""
import argparse
from PIL import Image, ImageChops


def seamless(image: Image.Image, margin: float) -> Image.Image:
    width, height = image.size
    shifted = ImageChops.offset(image, width // 2, height // 2)
    mask = Image.new("L", (width, height))
    pixels = mask.load()
    band_x, band_y = max(1, int(width * margin)), max(1, int(height * margin))
    for y in range(height):
        wy = min(1.0, min(y, height - 1 - y) / band_y)
        for x in range(width):
            wx = min(1.0, min(x, width - 1 - x) / band_x)
            pixels[x, y] = int(255 * min(wx, wy))
    return Image.composite(image, shifted, mask)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("out_path")
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--margin", type=float, default=0.22)
    args = parser.parse_args()
    image = Image.open(args.source).convert("RGB")
    if image.size != (args.size, args.size):
        image = image.resize((args.size, args.size), Image.LANCZOS)
    seamless(image, args.margin).save(args.out_path, quality=90)
    print("ok", args.out_path)


if __name__ == "__main__":
    main()
