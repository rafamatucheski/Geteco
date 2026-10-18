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

Os vãos e o tamanho do módulo de cada estilo ficam em tools/painted_facades*.json
(medidos à mão na folha de contato; "eave" opcional força a fração da empena quando o fundo da lateral não é transparente nem preto; a detecção automática erra porta cortada pela
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


def grow(rect: list, margin: float = DOOR_MARGIN) -> list:
    return [round(max(0.0, rect[0] - margin), 4), round(max(0.0, rect[1] - margin), 4),
            round(min(1.0, rect[2] + margin), 4), round(min(1.0, rect[3] + margin * .5), 4)]


def warp_columns(image: Image.Image, points: list) -> Image.Image:
    """Estica/comprime faixas verticais da imagem (já no tamanho final) para levar
    pontos da origem (fração em U) a outros pontos de destino. Serve para casar os
    vãos pintados com portões 3D que já existem em outro lugar (galpão Vértice:
    a arte tem baias a 18,67 m de espaçamento e os portões do jogo ficam a 18 m).
    `points`: [[u_origem, u_destino], ...] crescentes, de 0 a 1."""
    width = image.width
    out = Image.new("RGB", image.size)
    for (s0, d0), (s1, d1) in zip(points, points[1:]):
        x0, x1 = round(s0 * width), round(s1 * width)
        y0, y1 = round(d0 * width), round(d1 * width)
        if y1 > y0 and x1 > x0:
            out.paste(image.crop((x0, 0, x1, image.height)).resize((y1 - y0, image.height), Image.LANCZOS), (y0, 0))
    return out


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


def glow_mask(path: pathlib.Path, width: int, warp: list = None, min_r: int = 115) -> Image.Image:
    night = flatten(Image.open(path))
    night = night.resize((width, round(width * night.height / night.width)), Image.LANCZOS)
    if warp:
        night = warp_columns(night, warp)
    pixels = night.load()
    for y in range(night.height):
        for x in range(night.width):
            r, g, b = pixels[x, y]
            warm = r > min_r and r > b * 1.5 and g > b * 1.15
            pixels[x, y] = (r, g, b) if warm else (0, 0, 0)
    return night


# Fachada é textura 3D vista de perto e de longe: VRAM comprimida (BC7 no PC) com
# mipmaps. O padrão do Godot para JPG novo era sem perda, sem mips e sem VRAM:
# 3,5 s de carga decodificando 335 materiais, ~1 GB retido e cintilação de longe
# (auditoria de desempenho de 15/10).
NL = chr(10)
IMPORT_PARAMS = {"compress/mode": "2", "compress/high_quality": "true", "mipmaps/generate": "true",
                 "detect_3d/compress_to": "0"}


def write_import_params(texture: pathlib.Path) -> None:
    """Grava os parâmetros acima no .import (cria um mínimo se ainda não existe;
    o Godot completa uid/caminho na importação e respeita [params])."""
    path = texture.with_name(texture.name + ".import")
    if not path.exists():
        lines = ["[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "", "[params]", ""]
        lines += [f"{k}={v}" for k, v in IMPORT_PARAMS.items()]
        path.write_text(NL.join(lines) + NL, encoding="utf-8")
        return
    text = path.read_text(encoding="utf-8").splitlines()
    out = []
    for line in text:
        key = line.split("=", 1)[0]
        out.append(f"{key}={IMPORT_PARAMS[key]}" if key in IMPORT_PARAMS and "=" in line else line)
    path.write_text(NL.join(out) + NL, encoding="utf-8")


def styles(config: dict) -> list:
    requested = [a.split("=", 1)[1].split(",") for a in sys.argv[1:] if a.startswith("--styles=")]
    if requested:
        return requested[0]
    # Pacote alto só entra na conversão geral depois de ter os vãos medidos no JSON:
    # a detecção automática de uma porta só não serve para térreo de prédio alto.
    return sorted(p.name for p in SOURCE.iterdir()
                  if p.is_dir() and p.name not in SKIP and ((p / "frente-dia.png").exists()
                  or ((p / TALL_MARKER).exists() and p.name in config)))


# Prédio alto (pacote em peças por andar, 23 imagens): para cada lado o térreo
# (4 m), UM andar típico (3 m) que o kit repete na vertical e o topo com
# coroamento (3 m). Detectado pela presença do andar da frente.
TALL_MARKER = "frente-andar-dia.png"
TALL_SIDES = {"frente": "front", "lateral": "side", "fundos": "back"}
TALL_PIECES = {"terreo": "ground", "andar": "floor", "topo": "top"}
# Largura de saída por lado. O andar é largo e baixo (16 x 3 m = 4096 x 768 px na
# torre cívica): 2048 px dá 128 px/m num módulo de 16 m (os estilos de uma altura
# ficam entre 40 e 130 px/m) e mantém a altura do andar em 384 px, sem borrar
# esquadria nem junta de pedra. A lateral (6 m) fica com 1024 px = 170 px/m.
TALL_WIDTHS = {"front": 2048, "back": 2048, "side": 1024}
TALL_DOORS = {"porta-frente": "door_front", "porta-frente-verso": "door_front_inside",
              "porta-fundos": "door_back", "porta-fundos-verso": "door_back_inside", "telhado": "roof"}


def convert_tall(style: str, source: pathlib.Path, target: pathlib.Path, entry: dict) -> dict:
    """Converte o pacote alto e devolve o style.json. As alturas das peças saem da
    proporção das imagens da frente (largura do módulo conhecida); a lateral e os
    fundos têm de bater com elas, senão o andar repetido sai com degrau na quina."""
    sizes = entry.get("sizes", {})
    module_w = float(entry.get("module_w", DEFAULT_MODULE_W))
    side_w = float(entry.get("side_w", DEFAULT_SIDE_W))
    heights = {}
    for side, key in TALL_SIDES.items():
        span = side_w if key == "side" else module_w
        for piece, name in TALL_PIECES.items():
            day = Image.open(source / f"{side}-{piece}-dia.png")
            height = span * day.height / day.width
            heights.setdefault(name, {})[key] = round(height, 3)
            width = int(sizes.get(f"{side}-{piece}", TALL_WIDTHS[key]))
            image = flatten(day).resize((width, round(width * day.height / day.width)), Image.LANCZOS)
            image.save(target / f"{key}_{name}.jpg", quality=88, optimize=True)
            # "glow_min_r": parede quente e clara à noite (reboco ocre, tijolo) passava
            # no corte padrão e acendia inteira; o estilo sobe o mínimo de vermelho.
            glow_mask(source / f"{side}-{piece}-noite.png", width, None, int(entry.get("glow_min_r", 115))).save(target / f"{key}_{name}_glow.jpg", quality=85, optimize=True)
    for part, name in TALL_DOORS.items():
        if not (source / f"{part}.png").exists():
            continue
        width = int(sizes.get(part, SIZES[part]))
        image = flatten(Image.open(source / f"{part}.png"))
        image.resize((width, round(width * image.height / image.width)), Image.LANCZOS).save(target / f"{name}.jpg", quality=88, optimize=True)
    for name, by_side in heights.items():
        if max(by_side.values()) - min(by_side.values()) > 0.05:
            print(f"  aviso {style}: altura de '{name}' difere entre os lados {by_side} (vale a da frente)")
    floors = [heights["ground"]["front"], heights["floor"]["front"], heights["top"]["front"]]
    openings = {}
    for key in ["front", "back"]:
        # Vãos só no térreo: o retângulo é fração da imagem do térreo daquele lado.
        openings[key] = [{"rect": grow(o["rect"], float(entry.get("margin", DOOR_MARGIN))), "leaf": bool(o.get("leaf", True))}
                         for o in entry.get(key, [])]
    doors = {}
    for key in ["front", "back"]:
        leafs = [o["rect"] for o in openings[key] if o["leaf"]]
        if leafs:
            doors[key] = leafs[0]
    return {
        "style": style,
        "tall": True,
        # [térreo, andar típico (repetido), topo] em metros.
        "floors": floors,
        # Módulo e lateral: largura e altura do TÉRREO (o kit soma os andares).
        "module": [module_w, floors[0]],
        "side": [side_w, heights["ground"]["side"]],
        "eave": 0.0,
        "snow_roof": False,
        "openings": openings,
        "doors": doors,
    }


def main() -> None:
    # Um arquivo por região (painted_facades_<região>.json) para agentes em paralelo
    # não editarem o mesmo arquivo.
    config = {}
    for path in sorted(CONFIG.parent.glob("painted_facades*.json")):
        config.update(json.loads(path.read_text(encoding="utf-8")))
    for style in styles(config):
        source = SOURCE / style
        target = TARGET / style
        target.mkdir(parents=True, exist_ok=True)
        entry = config.get(style, {})
        if (source / TALL_MARKER).exists():
            data = convert_tall(style, source, target, entry)
            for texture in target.glob("*.jpg"):
                write_import_params(texture)
            (target / "style.json").write_text(json.dumps(data, indent="\t"), encoding="utf-8")
            print(style, "alto", json.dumps({k: data[k] for k in ["floors", "module", "side"]}), len(data["openings"]["front"]), len(data["openings"]["back"]))
            continue
        # Opções por estilo (só para quem pede; os demais seguem os padrões acima):
        # "sizes" troca a largura de saída de uma peça (galpão de 56 m precisa de mais
        # que 768 px), "front_warp" casa os vãos da frente com portões 3D existentes,
        # "roof_crop" usa só um recorte do telhado (a arte traz as duas águas; o kit
        # espelha a mesma água nas duas), "margin" é a folga dos vãos (0 = pixel preto exato).
        sizes = entry.get("sizes", {})
        front_warp = entry.get("front_warp")
        for part, width in SIZES.items():
            if not (source / f"{part}.png").exists():
                continue
            image = flatten(Image.open(source / f"{part}.png"))
            if part == "telhado" and "roof_crop" in entry:
                box = entry["roof_crop"]
                image = image.crop((round(box[0] * image.width), round(box[1] * image.height), round(box[2] * image.width), round(box[3] * image.height)))
            width = int(sizes.get(part, width))
            image = image.resize((width, round(width * image.height / image.width)), Image.LANCZOS)
            if part == "frente-dia" and front_warp:
                image = warp_columns(image, front_warp)
            image.save(target / f"{NAMES[part]}.jpg", quality=88, optimize=True)
        for part, (name, width) in GLOWS.items():
            glow_mask(source / f"{part}.png", int(sizes.get(part, width)), front_warp if part == "frente-noite" else None).save(target / f"{name}.jpg", quality=85, optimize=True)
        front = Image.open(source / "frente-dia.png")
        side = Image.open(source / "lateral-dia.png")
        module_w = float(entry.get("module_w", DEFAULT_MODULE_W))
        side_w = float(entry.get("side_w", DEFAULT_SIDE_W))
        openings = {}
        for key, name in [("front", "frente"), ("back", "fundos")]:
            if key in entry:
                openings[key] = [{"rect": grow(o["rect"], float(entry.get("margin", DOOR_MARGIN))), "leaf": bool(o.get("leaf", True))} for o in entry[key]]
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
            "eave": float(entry["eave"]) if "eave" in entry else side_eave(source / "lateral-dia.png"),
            "snow_roof": (source / "telhado-sem-neve.png").exists(),
            "openings": openings,
            "doors": doors,
        }
        for texture in target.glob("*.jpg"):
            write_import_params(texture)
        (target / "style.json").write_text(json.dumps(data, indent="\t"), encoding="utf-8")
        print(style, json.dumps({k: data[k] for k in ["module", "side", "eave"]}), len(openings["front"]), len(openings["back"]))


if __name__ == "__main__":
    main()
