"""Converte as imagens do interior e dos minijogos dos bares (output/imagegen/bar-*/, fora do Git,
geradas pelo Codex em 28/10 com docs/prompts/bares-gpt-20261028.md) em texturas do jogo em
assets/places/bars/.

Por que existe: os PNGs vêm com 1-3 MB e o jogo precisa de ~250 px/m nos quadros e ~256 px/m nas
texturas que repetem. Interior vira JPG em BC7 com mipmaps (mesmos parâmetros das fachadas
pintadas). Os quadros pintados com fundo branco ou preto fora da placa (peixe, mapa, cabeça de boi)
recebem a cor média da parede no lugar desse fundo: o material é opaco, sem recorte por alfa, para
não criar variante de shader nova no jogo.

Minijogos: sprites com alfa recortados no conteúdo (bolas uma por arquivo, taco, dardos) e a mesa
com a área de jogo medida em `table_felt` no JSON de saída, que a tela usa para casar a física
(640 x 320) com a pintura.

Uso: python -I tools/build_bar_textures.py
"""
import json
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "output" / "imagegen"
TARGET = ROOT / "assets" / "places" / "bars"
sys.path.insert(0, str(ROOT / "tools"))
from build_painted_facades import write_import_params  # noqa: E402

# Nome no jogo: (pasta, arquivo, largura em px).
INTERIOR = {
    "lastro_wall": ("bar-lastro", "int-parede-tijolo", 512),
    "lastro_floor": ("bar-lastro", "int-piso-taco", 512),
    "lastro_counter": ("bar-lastro", "int-balcao-frente", 1024),
    "lastro_shelf": ("bar-lastro", "int-estante-garrafas", 1024),
    "lastro_harbor": ("bar-lastro", "int-quadro-cais", 512),
    "lastro_fish": ("bar-lastro", "int-quadro-peixe", 512),
    "lastro_menu": ("bar-lastro", "int-cardapio-lousa", 384),
    "lastro_neon": ("bar-lastro", "int-placa-neon-acesa", 512),
    "lastro_dartboard": ("bar-lastro", "int-alvo-dardos", 512),
    "lastro_felt": ("bar-lastro", "int-feltro-bilhar", 512),
    "sede_wall": ("bar-sede", "int-parede-reboco", 512),
    "sede_floor": ("bar-sede", "int-piso-tabuas", 512),
    "sede_counter": ("bar-sede", "int-balcao-frente", 1024),
    "sede_shelf": ("bar-sede", "int-estante-garrafas", 1024),
    "sede_skull": ("bar-sede", "int-cabeca-boi", 512),
    "sede_map": ("bar-sede", "int-mapa-estrada", 512),
    "sede_moto": ("bar-sede", "int-placa-moto", 512),
    "sede_menu": ("bar-sede", "int-cardapio-tabua", 384),
    "sede_neon": ("bar-sede", "int-placa-neon-acesa", 512),
    "sede_dartboard": ("bar-sede", "int-alvo-dardos", 512),
    "sede_felt": ("bar-sede", "int-feltro-bilhar", 512),
}
# Fundo fora da placa trocado pela cor média da parede: (escuro?, parede).
BACKDROP = {"lastro_fish": (False, "lastro_wall"), "sede_map": (False, "sede_wall"), "sede_skull": (True, "sede_wall")}


def average(image: Image.Image) -> tuple:
    small = image.convert("RGB").resize((1, 1), Image.BOX)
    return small.getpixel((0, 0))


def replace_backdrop(image: Image.Image, dark: bool, color: tuple) -> Image.Image:
    """Preenche a partir das bordas só os pixels de fundo (quase branco ou quase preto)
    ligados à borda, sem tocar no miolo da placa."""
    image = image.convert("RGB")
    width, height = image.size
    pixels = image.load()

    def backdrop(rgb: tuple) -> bool:
        return max(rgb) < 34 if dark else min(rgb) > 218

    seen = bytearray(width * height)
    stack = [(x, y) for x in range(width) for y in (0, height - 1)] + [(x, y) for y in range(height) for x in (0, width - 1)]
    while stack:
        x, y = stack.pop()
        index = y * width + x
        if seen[index] or not backdrop(pixels[x, y]):
            continue
        seen[index] = 1
        pixels[x, y] = color
        if x > 0: stack.append((x - 1, y))
        if x < width - 1: stack.append((x + 1, y))
        if y > 0: stack.append((x, y - 1))
        if y < height - 1: stack.append((x, y + 1))
    return image


def crop_alpha(image: Image.Image) -> Image.Image:
    box = image.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
    return image.crop(box) if box else image


def balls(image: Image.Image, count: int = 7) -> list:
    """Bolas lado a lado e de mesmo tamanho; algumas se encostam na pintura, então a fileira
    é dividida em partes iguais em vez de pelas colunas vazias."""
    row = crop_alpha(image)
    step = row.width / count
    return [crop_alpha(row.crop((round(i * step), 0, round((i + 1) * step), row.height))) for i in range(count)]


def felt_rect(image: Image.Image) -> list:
    """Área de jogo: maior faixa de pixels verdes da mesa, medida no meio de cada eixo."""
    rgb = image.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()

    def green(x: int, y: int) -> bool:
        r, g, b = pixels[x, y]
        return g > r * 1.25 and g > b * 1.05

    def run(points: list) -> tuple:
        flags = [green(x, y) for x, y in points]
        best, start = (0, 0), None
        for index, flag in enumerate(flags + [False]):
            if flag and start is None:
                start = index
            elif not flag and start is not None:
                if index - start > best[1] - best[0]:
                    best = (start, index)
                start = None
        return best

    # Linhas a 1/4 e 3/4 evitam as caçapas do meio.
    xs = run([(x, height // 4) for x in range(width)])
    ys = run([(width // 4, y) for y in range(height)])
    return [round(xs[0] / width, 4), round(ys[0] / height, 4), round(xs[1] / width, 4), round(ys[1] / height, 4)]


def main() -> None:
    TARGET.mkdir(parents=True, exist_ok=True)
    walls = {}
    for name, (folder, file, width) in INTERIOR.items():
        image = Image.open(SOURCE / folder / f"{file}.png").convert("RGB")
        if name.endswith("_wall"):
            walls[name] = average(image)
        if name in BACKDROP:
            dark, wall = BACKDROP[name]
            image = replace_backdrop(image, dark, walls.get(wall) or average(Image.open(SOURCE / INTERIOR[wall][0] / f"{INTERIOR[wall][1]}.png")))
        image = image.resize((width, round(width * image.height / image.width)), Image.LANCZOS)
        out = TARGET / f"{name}.jpg"
        image.save(out, quality=88, optimize=True)
        write_import_params(out)
    ui = TARGET / "ui"
    ui.mkdir(exist_ok=True)
    games = SOURCE / "bar-jogos"
    table = Image.open(games / "mesa-bilhar-topo.png").convert("RGB")
    layout = {"table_felt": felt_rect(table)}
    table.resize((1024, 512), Image.LANCZOS).save(ui / "pool_table.png", optimize=True)
    for index, ball in enumerate(balls(Image.open(games / "bolas-bilhar.png").convert("RGBA"))):
        ball.resize((64, 64), Image.LANCZOS).save(ui / f"pool_ball_{index}.png", optimize=True)
    cue = crop_alpha(Image.open(games / "taco.png").convert("RGBA"))
    cue.resize((1024, max(8, round(1024 * cue.height / cue.width))), Image.LANCZOS).save(ui / "pool_cue.png", optimize=True)
    for file, name in [("dardo", "dart_red"), ("dardo-verde", "dart_green")]:
        dart = crop_alpha(Image.open(games / f"{file}.png").convert("RGBA"))
        dart.resize((256, max(8, round(256 * dart.height / dart.width))), Image.LANCZOS).save(ui / f"{name}.png", optimize=True)
    (TARGET / "layout.json").write_text(json.dumps(layout, indent="\t"), encoding="utf-8")
    print("interior", len(INTERIOR), "jogos", json.dumps(layout))


if __name__ == "__main__":
    main()
