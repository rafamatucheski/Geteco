"""Converte o pacote de fachadas geradas (output/imagegen/<estilo>/, fora do Git)
em texturas do jogo em assets/facades/<estilo>/.

Por que existe: os PNGs originais têm 2-3 MB cada (135 arquivos, ~300 MB). O jogo
precisa de ~190 px/m no máximo, então redimensiona e grava JPG; a noite vira só uma
máscara de luz (pixels quentes e claros da versão noturna), porque a imagem noturna
inteira já vem escurecida e o jogo escurece de novo pela iluminação.

Também grava style.json com o vão da porta (frente e fundos) em fração da imagem,
para o kit abrir o buraco e posicionar a folha 3D que gira.

Uso: python -I tools/build_painted_facades.py
"""
import json
import pathlib
import statistics

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "output" / "imagegen"
TARGET = ROOT / "assets" / "facades"
STYLES = ["tijolo-vermelho", "reboco-creme", "concreto-cinza", "rosa-praia", "tijolo-londrino",
          "pastilha-60", "madeira-azul", "fabrica-tijolo", "comercio-terreo"]
# Largura em px de cada peça no jogo (a altura segue a proporção da imagem).
SIZES = {"frente-dia": 768, "fundos-dia": 768, "lateral-dia": 1024, "telhado": 768,
         "porta-frente": 384, "porta-frente-verso": 384, "porta-fundos": 384, "porta-fundos-verso": 384}
NAMES = {"frente-dia": "front", "fundos-dia": "back", "lateral-dia": "side", "telhado": "roof",
         "porta-frente": "door_front", "porta-frente-verso": "door_front_inside",
         "porta-fundos": "door_back", "porta-fundos-verso": "door_back_inside"}
GLOWS = {"frente-noite": ("front_glow", 768), "fundos-noite": ("back_glow", 768), "lateral-noite": ("side_glow", 1024)}
# A detecção automática (faixa escura mais larga no térreo) erra quando o corredor
# é claro ou cortado por um pilar; estes foram medidos à mão na folha de contato.
DOOR_OVERRIDES = {
    "concreto-cinza/frente": [0.727, 0.555, 0.905, 0.89],
    "concreto-cinza/fundos": [0.707, 0.53, 0.857, 0.87],
    "fabrica-tijolo/frente": [0.593, 0.58, 0.873, 0.92],
    "fabrica-tijolo/fundos": [0.617, 0.53, 0.85, 0.90],
    "comercio-terreo/frente": [0.683, 0.63, 0.867, 0.91],
}
# A detecção pega o miolo escuro; a folha precisa cobrir o vão até o batente.
DOOR_MARGIN = 0.012


def detect_door(path: pathlib.Path) -> list:
    image = Image.open(path).convert("L")
    width, height = image.size
    pixels = image.load()
    y0, y1 = int(height * .62), int(height * .74)
    rows = range(y0, y1, 3)
    column = [sum(pixels[x, y] for y in rows) / len(rows) for x in range(width)]
    wall = statistics.median(column)
    dark = [value < wall * .45 for value in column]
    best = (0, 0)
    x = 0
    while x < width:
        if dark[x]:
            end = x
            while end < width and dark[end]:
                end += 1
            if end - x > best[1] - best[0]:
                best = (x, end)
            x = end
        else:
            x += 1
    x0, x1 = best
    cx0, cx1 = x0 + (x1 - x0) // 4, x1 - (x1 - x0) // 4
    line = [sum(pixels[x, y] for x in range(cx0, cx1, 2)) / len(range(cx0, cx1, 2)) for y in range(height)]
    top = y0
    while top > 0 and line[top] < wall * .55:
        top -= 1
    bottom = y1
    while bottom < height - 1 and line[bottom] < wall * .8:
        bottom += 1
    return [x0 / width, top / height, x1 / width, bottom / height]


def glow_mask(path: pathlib.Path, width: int) -> Image.Image:
    night = Image.open(path).convert("RGB")
    night = night.resize((width, round(width * night.height / night.width)), Image.LANCZOS)
    pixels = night.load()
    for y in range(night.height):
        for x in range(night.width):
            r, g, b = pixels[x, y]
            warm = r > 115 and r > b * 1.5 and g > b * 1.15
            pixels[x, y] = (r, g, b) if warm else (0, 0, 0)
    return night


def main() -> None:
    for style in STYLES:
        source = SOURCE / style
        target = TARGET / style
        target.mkdir(parents=True, exist_ok=True)
        for part, width in SIZES.items():
            image = Image.open(source / f"{part}.png").convert("RGB")
            image = image.resize((width, round(width * image.height / image.width)), Image.LANCZOS)
            image.save(target / f"{NAMES[part]}.jpg", quality=88, optimize=True)
        for part, (name, width) in GLOWS.items():
            glow_mask(source / f"{part}.png", width).save(target / f"{name}.jpg", quality=85, optimize=True)
        doors = {}
        for side in ["frente", "fundos"]:
            rect = DOOR_OVERRIDES.get(f"{style}/{side}") or detect_door(source / f"{side}-dia.png")
            rect = [max(0.0, rect[0] - DOOR_MARGIN), max(0.0, rect[1] - DOOR_MARGIN),
                    min(1.0, rect[2] + DOOR_MARGIN), min(1.0, rect[3] + DOOR_MARGIN * .5)]
            doors["front" if side == "frente" else "back"] = [round(v, 4) for v in rect]
        (target / "style.json").write_text(json.dumps({"style": style, "doors": doors}, indent="\t"), encoding="utf-8")
        print(style, doors)


if __name__ == "__main__":
    main()
