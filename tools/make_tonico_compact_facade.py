"""Gera assets/facades/loja-tonico-compacta a partir de loja-tonico (recorte + faixa de reboco)."""
import hashlib, json, os, shutil, sys
from PIL import Image

ROOT = sys.argv[1]
SRC = os.path.join(ROOT, "assets/facades/loja-tonico")
DST = os.path.join(ROOT, "assets/facades/loja-tonico-compacta")
STYLE = "loja-tonico-compacta"
os.makedirs(DST, exist_ok=True)
OVERLAP = 5


def hconcat(im, pieces):
    """Junta faixas de colunas com fusão linear de OVERLAP px nas emendas."""
    h = im.size[1]
    parts = [im.crop((a, 0, b, h)) for a, b in pieces]
    total = sum(p.size[0] for p in parts) - OVERLAP * (len(parts) - 1)
    out = Image.new("RGB", (total, h))
    x = 0
    for i, p in enumerate(parts):
        if i == 0:
            out.paste(p, (0, 0))
            x = p.size[0]
            continue
        start = x - OVERLAP
        out.paste(p.crop((OVERLAP, 0, p.size[0], h)), (x, 0))
        for k in range(OVERLAP):
            t = (k + 1) / (OVERLAP + 1)
            col_prev = out.crop((start + k, 0, start + k + 1, h))
            col_next = p.crop((k, 0, k + 1, h))
            out.paste(Image.blend(col_prev, col_next, t), (start + k, 0))
        x = start + p.size[0]
    return out


def vinsert(im, at, src_a, src_b, count):
    """Insere `count` linhas depois da linha `at`, espelhando a faixa [src_a, src_b)."""
    w, h = im.size
    strip = im.crop((0, src_a, w, src_b))
    flipped = strip.transpose(Image.FLIP_TOP_BOTTOM)
    out = Image.new("RGB", (w, h + count))
    out.paste(im.crop((0, 0, w, at)), (0, 0))
    y = 0
    flip = True
    while y < count:
        tile = flipped if flip else strip
        take = min(tile.size[1], count - y)
        out.paste(tile.crop((0, 0, w, take)), (0, at + y))
        y += take
        flip = not flip
    out.paste(im.crop((0, at, w, h)), (0, at + count))
    return out


def vshift(im, at, src_a, src_b, count, seed=7):
    """Insere `count` linhas depois de `at` com cópias da faixa [src_a, src_b)
    deslocadas na horizontal (sem espelho, que desenhava manchas simétricas),
    fundidas na vertical. Só para faixas de reboco sem cano/janela."""
    import random
    rng = random.Random(seed)
    w, h = im.size
    strip = im.crop((0, src_a, w, src_b))
    sh = strip.size[1]
    out = Image.new("RGB", (w, h + count))
    out.paste(im.crop((0, 0, w, at)), (0, 0))
    out.paste(im.crop((0, at, w, h)), (0, at + count))
    fill = Image.new("RGB", (w, count + sh))
    y = 0
    while y < count:
        dx = rng.randrange(w)
        tile = Image.new("RGB", (w, sh))
        tile.paste(strip.crop((dx, 0, w, sh)), (0, 0))
        tile.paste(strip.crop((0, 0, dx, sh)), (w - dx, 0))
        if y == 0:
            fill.paste(tile, (0, 0))
        else:
            # Duas linhas de fusão na emenda horizontal.
            for k in range(2):
                row_prev = fill.crop((0, y + k, w, y + k + 1))
                row_next = tile.crop((0, k, w, k + 1))
                fill.paste(Image.blend(row_prev, row_next, (k + 1) / 3), (0, y + k))
            fill.paste(tile.crop((0, 2, w, sh)), (0, y + 2))
        y += sh - 2
    out.paste(fill.crop((0, 0, w, count)), (0, at))
    return out


def vstretch(im, a, b, count):
    """Estica a faixa [a, b) em `count` linhas a mais (canos verticais seguem retos)."""
    from PIL import ImageFilter
    w, h = im.size
    band = im.crop((0, a, w, b)).resize((w, b - a + count), Image.BICUBIC)
    out = Image.new("RGB", (w, h + count))
    out.paste(im.crop((0, 0, w, a)), (0, 0))
    out.paste(band, (0, a))
    out.paste(im.crop((0, b, w, h)), (0, b + count))
    return out


def save(im, name):
    im.save(os.path.join(DST, name), quality=92)


def load(name):
    return Image.open(os.path.join(SRC, name)).convert("RGB")


FRONT_PIECES = [(38, 217), (328, 440), (551, 730)]
for name in ["front.jpg", "front_glow.jpg"]:
    im = hconcat(load(name), FRONT_PIECES)
    # Linhas 21-28: reboco entre a faixa azul e o topo das janelas/porta.
    im = vshift(im, 25, 21, 28, 29)
    assert im.size == (460, 148), im.size
    save(im, name)

for name in ["back.jpg", "back_glow.jpg"]:
    im = load(name).crop((170, 0, 630, 119))
    # Fundos: o reboco livre fica abaixo dos aparelhos de ar (linhas 40-56).
    im = vstretch(im, 38, 58, 29)
    assert im.size == (460, 148), im.size
    save(im, name)

for name in ["side.jpg", "side_glow.jpg"]:
    im = load(name)
    # Lateral (138 px/m): 0,7 m de reboco acima das venezianas.
    im = vstretch(im, 58, 102, 97)
    assert im.size == (1024, 498), im.size
    save(im, name)

roof = load("roof.jpg")
save(roof.crop((154, 0, 614, 304)), "roof.jpg")

for name in ["door_front.jpg", "door_front_inside.jpg"]:
    shutil.copyfile(os.path.join(SRC, name), os.path.join(DST, name))

# Vão da porta na composição: colunas 348,1-419,9 da original -> 194,1-265,9 de 460.
door = [round(194.1 / 460, 4), round((31.4 + 29) / 148, 4), round(265.9 / 460, 4), 1.0]
style = {
    "style": STYLE,
    "module": [11.2, 3.6],
    "side": [7.4, 3.6],
    "eave": 0.0,
    "snow_roof": False,
    "openings": {"front": [{"rect": door, "leaf": True}], "back": []},
    "doors": {"front": door},
}
with open(os.path.join(DST, "style.json"), "w", encoding="utf-8", newline="\n") as f:
    f.write(json.dumps(style, indent="\t") + "\n")

template = open(os.path.join(SRC, "front.jpg.import"), encoding="utf-8").read()
for name in sorted(os.listdir(DST)):
    if not name.endswith(".jpg"):
        continue
    res = "res://assets/facades/%s/%s" % (STYLE, name)
    digest = hashlib.md5(res.encode()).hexdigest()
    text = template.replace("res://assets/facades/loja-tonico/front.jpg", res)
    text = text.replace("front.jpg-43f73c6cc7a5f499b626bf29da5589ec", "%s-%s" % (name, digest))
    # Sem uid: o Godot cria um na primeira importação.
    text = "\n".join(l for l in text.split("\n") if not l.startswith("uid="))
    with open(os.path.join(DST, name + ".import"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
print("ok", door)
