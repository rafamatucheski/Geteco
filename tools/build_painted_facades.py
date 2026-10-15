"""Converte o pacote de fachadas geradas (output/imagegen/<estilo>/, fora do Git)
em texturas do jogo em assets/facades/<estilo>/.

Por que existe: os PNGs originais têm 2-3 MB cada. O jogo precisa de ~190 px/m no
máximo, então redimensiona e grava JPG; a noite vira só uma máscara de luz (pixels
quentes e claros da versão noturna), porque a imagem noturna inteira já vem
escurecida e o jogo escurece de novo pela iluminação.

Grava style.json com:
- module: largura x altura (m) do módulo da frente (altura sai da proporção da imagem);
- side: largura (m) do módulo lateral; eave: fração da altura da lateral onde
  termina a parede e começa a empena (casas de telhado inclinado; 0 = sem empena);
- openings: vãos da frente e dos fundos (fração da imagem, origem no topo), cada um
  com "leaf" (folha 3D que abre) ou sem folha (garagem/portão aberto);
- doors: o primeiro vão com folha de cada lado, formato antigo (sobrados).

Os vãos e o tamanho do módulo de cada estilo ficam em tools/painted_facades.json
(medidos à mão na folha de contato; a detecção automática erra porta cortada pela
base de pedra, portão largo e corredor claro). Estilo sem entrada lá cai na
detecção automática de uma porta só.

Uso: python -I tools/build_painted_facades.py [--styles=a,b,...]
"""
import json
import pathlib
import statistics
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "output" / "imagegen"
TARGET = ROOT / "assets" / "facades"
CONFIG = ROOT / "tools" / "painted_facades.json"
# Pastas de teste antigas e inventários, não estilos.
SKIP = {"fachadas-20261015"}
# Largura em px de cada peça no jogo (a altura segue a proporção da imagem).
SIZES = {"frente-dia": 768, "fundos-dia": 768, "lateral-dia": 1024, "telhado": 768, "telhado-sem-neve": 768,
         "porta-frente": 384, "porta-frente-verso": 384, "porta-fundos": 384, "porta-fundos-verso": 384}
NAMES = {"frente-dia": "front", "fundos-dia": "back", "lateral-dia": "side", "telhado": "roof",
         "telhado-sem-neve": "roof_clear",
         "porta-frente": "door_front", "porta-frente-verso": "door_front_inside",
         "porta-fundos": "door_back", "porta-fundos-verso": "door_back_inside"}
GLOWS = {"frente-noite": ("front_glow", 768), "fundos-noite": ("back_glow", 768), "lateral-noite": ("side_glow", 1024)}
# A detecção pega o miolo escuro; a folha precisa cobrir o vão até o batente.
DOOR_MARGIN = 0.012
DEFAULT_MODULE_W = 6.0
DEFAULT_SIDE_W = 8.0


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
    if x1 - x0 < 4:
        return []
    cx0, cx1 = x0 + (x1 - x0) // 4, x1 - (x1 - x0) // 4
    line = [sum(pixels[x, y] for x in range(cx0, cx1, 2)) / len(range(cx0, cx1, 2)) for y in range(height)]
    top = y0
    while top > 0 and line[top] < wall * .55:
        top -= 1
    bottom = y1
    while bottom < height - 1 and line[bottom] < wall * .8:
        bottom += 1
    return [x0 / width, top / height, x1 / width, bottom / height]


def grow(rect: list) -> list:
    return [round(max(0.0, rect[0] - DOOR_MARGIN), 4), round(max(0.0, rect[1] - DOOR_MARGIN), 4),
            round(min(1.0, rect[2] + DOOR_MARGIN), 4), round(min(1.0, rect[3] + DOOR_MARGIN * .5), 4)]


def side_eave(path: pathlib.Path) -> float:
    """Fração da altura onde a lateral vira parede cheia (abaixo da empena).
    Fora do triângulo a imagem vem transparente ou preta chapada."""
    image = Image.open(path)
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()
    has_alpha = image.mode in ("RGBA", "LA") or "transparency" in image.info
    for y in range(height):
        filled = 0
        for x in range(0, width, 4):
            r, g, b, a = pixels[x, y]
            background = a < 32 if has_alpha else (r + g + b) < 24
            if not background:
                filled += 1
        if filled >= (width // 4) * .97:
            return round(y / height, 4) if y / height > .06 else 0.0
    return 0.0


def flatten(image: Image.Image) -> Image.Image:
    """Transparência vira preto: o kit só amostra dentro da empena."""
    if image.mode in ("RGBA", "LA", "P"):
        rgba = image.convert("RGBA")
        base = Image.new("RGB", rgba.size, (0, 0, 0))
        base.paste(rgba, mask=rgba.split()[3])
        return base
    return image.convert("RGB")


def glow_mask(path: pathlib.Path, width: int) -> Image.Image:
    night = flatten(Image.open(path))
    night = night.resize((width, round(width * night.height / night.width)), Image.LANCZOS)
    pixels = night.load()
    for y in range(night.height):
        for x in range(night.width):
            r, g, b = pixels[x, y]
            warm = r > 115 and r > b * 1.5 and g > b * 1.15
            pixels[x, y] = (r, g, b) if warm else (0, 0, 0)
    return night


def styles() -> list:
    requested = [a.split("=", 1)[1].split(",") for a in sys.argv[1:] if a.startswith("--styles=")]
    if requested:
        return requested[0]
    return sorted(p.name for p in SOURCE.iterdir()
                  if p.is_dir() and p.name not in SKIP and (p / "frente-dia.png").exists())


def main() -> None:
    config = json.loads(CONFIG.read_text(encoding="utf-8")) if CONFIG.exists() else {}
    for style in styles():
        source = SOURCE / style
        target = TARGET / style
        target.mkdir(parents=True, exist_ok=True)
        entry = config.get(style, {})
        for part, width in SIZES.items():
            if not (source / f"{part}.png").exists():
                continue
            image = flatten(Image.open(source / f"{part}.png"))
            image = image.resize((width, round(width * image.height / image.width)), Image.LANCZOS)
            image.save(target / f"{NAMES[part]}.jpg", quality=88, optimize=True)
        for part, (name, width) in GLOWS.items():
            glow_mask(source / f"{part}.png", width).save(target / f"{name}.jpg", quality=85, optimize=True)
        front = Image.open(source / "frente-dia.png")
        side = Image.open(source / "lateral-dia.png")
        module_w = float(entry.get("module_w", DEFAULT_MODULE_W))
        side_w = float(entry.get("side_w", DEFAULT_SIDE_W))
        openings = {}
        for key, name in [("front", "frente"), ("back", "fundos")]:
            if key in entry:
                openings[key] = [{"rect": grow(o["rect"]), "leaf": bool(o.get("leaf", True))} for o in entry[key]]
            else:
                rect = detect_door(source / f"{name}-dia.png")
                openings[key] = [{"rect": grow(rect), "leaf": True}] if rect else []
        doors = {}
        for key in ["front", "back"]:
            leafs = [o["rect"] for o in openings[key] if o["leaf"]]
            if leafs:
                doors[key] = leafs[0]
        data = {
            "style": style,
            "module": [module_w, round(module_w * front.height / front.width, 3)],
            "side": [side_w, round(side_w * side.height / side.width, 3)],
            "eave": side_eave(source / "lateral-dia.png"),
            "snow_roof": (source / "telhado-sem-neve.png").exists(),
            "openings": openings,
            "doors": doors,
        }
        (target / "style.json").write_text(json.dumps(data, indent="\t"), encoding="utf-8")
        print(style, json.dumps({k: data[k] for k in ["module", "side", "eave"]}), len(openings["front"]), len(openings["back"]))


if __name__ == "__main__":
    main()
