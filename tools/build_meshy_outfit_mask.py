"""Gera a máscara de regiões e zonas de roupa do Dante Meshy, em espaço UV.

Uso (na raiz do repositório do jogo):
    python tools/build_meshy_outfit_mask.py assets/characters/meshy_dante/dante_grip.glb assets/characters/meshy_dante/dante_outfit_regions.png scripts/player/MeshyDanteRegionStats.gd

A textura do Meshy é uma cor assada única: jaqueta, henley, jeans e botas não
são materiais separados. Para trocar o traje sem novo modelo, cada texel recebe
uma região. A classificação cruza o osso dominante do triângulo (onde no corpo)
com a cor, porque as ilhas UV do Meshy misturam peças: henley, cinto e jeans são
contíguos no atlas. No quadril, barra da jaqueta e jeans têm o mesmo azul escuro;
ali a decisão é por peça conectada (média de luminância), não por texel.

Canal R = região * 32: 0 pele, 1 cabelo/barba, 2 jaqueta, 3 camisa, 4 calça, 5 cinto, 6 bota.
Canal G = zona do corpo * 32: 0 tronco/cabeça, 1 braço, 2 antebraço, 3 mão, 4 coxa, 5 canela, 6 pé.
As zonas permitem regata (braço em pele), bermuda (canela em pele) e luvas.
"""
import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SKIN, HAIR, JACKET, SHIRT, PANTS, BELT, BOOTS = range(7)
NAMES = ["pele", "cabelo", "jaqueta", "camisa", "calca", "cinto", "bota"]
TORSO, UPPER_ARM, FOREARM, HAND, THIGH, SHIN, FOOT = range(7)
# Peça do quadril com luminância média acima disto é barra da jaqueta xadrez.
HIP_JACKET_LUM = 46.0

source, destination, stats_path = map(Path, sys.argv[1:4])
raw = source.read_bytes()
json_size = struct.unpack("<I", raw[12:16])[0]
gltf = json.loads(raw[20:20 + json_size])
binary = raw[28 + json_size:]


def accessor(index):
    item = gltf["accessors"][index]
    view = gltf["bufferViews"][item["bufferView"]]
    dtype = np.dtype({5126: "<f4", 5125: "<u4", 5123: "<u2", 5121: "u1"}[item["componentType"]])
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[item["type"]]
    return np.ndarray((item["count"], width), dtype=dtype, buffer=binary,
        offset=view.get("byteOffset", 0) + item.get("byteOffset", 0),
        strides=(view.get("byteStride", dtype.itemsize * width), dtype.itemsize)).copy()


primitive = gltf["meshes"][0]["primitives"][0]
attributes = primitive["attributes"]
positions = accessor(attributes["POSITION"])
uvs = accessor(attributes["TEXCOORD_0"])
joints = accessor(attributes["JOINTS_0"])
weights = accessor(attributes["WEIGHTS_0"])
triangles = accessor(primitive["indices"]).reshape(-1, 3).astype(np.int64)
skin = gltf["skins"][0]
bone_names = [gltf["nodes"][j]["name"] for j in skin["joints"]]

material = gltf["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
view = gltf["bufferViews"][gltf["images"][gltf["textures"][material]["source"]]["bufferView"]]
start = view.get("byteOffset", 0)
texture = np.asarray(Image.open(io.BytesIO(binary[start:start + view["byteLength"]])).convert("RGB")).astype(np.float32)
height, width = texture.shape[:2]

GROUP = {"head": 0, "hand": 1, "upper": 2, "hips": 3, "leg": 4, "foot": 5}


def body_group(name):
    if name in ("Head", "head_end", "headfront", "neck"): return GROUP["head"]
    if "Hand" in name: return GROUP["hand"]
    if name == "Hips": return GROUP["hips"]
    if "UpLeg" in name or name.endswith("Leg"): return GROUP["leg"]
    if "Foot" in name or "Toe" in name: return GROUP["foot"]
    return GROUP["upper"]


def body_zone(name):
    if "ForeArm" in name: return FOREARM
    if name in ("LeftArm", "RightArm"): return UPPER_ARM
    if "Hand" in name: return HAND
    if "UpLeg" in name: return THIGH
    if name in ("LeftLeg", "RightLeg"): return SHIN
    if "Foot" in name or "Toe" in name: return FOOT
    return TORSO


def skin_like(r, g, b): return (r > 150) & (r - b > 45) & (g > 90)
def red_like(r, g, b): return (r > 80) & (r > g * 1.45) & (r > b * 1.25)
def brown_like(r, g, b, lum): return (r >= g) & (g >= b - 2) & (r - b > 8) & (lum < 95) & ~skin_like(r, g, b)
def luminance(r, g, b): return 0.299 * r + 0.587 * g + 0.114 * b


dominant = [bone_names[j] for j in joints[np.arange(len(joints)), weights.argmax(1)]]
vertex_group = np.array([body_group(n) for n in dominant])
vertex_zone = np.array([body_zone(n) for n in dominant])


def majority(values):
    per_tri = values[triangles]
    return np.where(per_tri[:, 1] == per_tri[:, 2], per_tri[:, 1], per_tri[:, 0])


tri_group = majority(vertex_group)
tri_zone = majority(vertex_zone)

px = np.clip((uvs[:, 0] * width).astype(int), 0, width - 1)
py = np.clip((uvs[:, 1] * height).astype(int), 0, height - 1)
vertex_rgb = texture[py, px]
tri_rgb = vertex_rgb[triangles].mean(1)
tr, tg, tb = tri_rgb[:, 0], tri_rgb[:, 1], tri_rgb[:, 2]
tri_lum = luminance(tr, tg, tb)

# Peças conectadas do quadril, sem os triângulos vermelhos (henley) e marrons
# (cinto): eles ligariam camisa e jeans numa mesma ilha UV.
hip_candidates = np.nonzero((tri_group == GROUP["hips"]) & ~red_like(tr, tg, tb) & ~brown_like(tr, tg, tb, tri_lum))[0]
parent = np.arange(len(positions))


def find(x):
    root = x
    while parent[root] != root: root = parent[root]
    while parent[x] != root: parent[x], x = root, parent[x]
    return root


for t in hip_candidates:
    a, b, c = triangles[t]
    for other in (b, c):
        ra, ro = find(a), find(other)
        if ra != ro: parent[ro] = ra
labels = np.array([find(triangles[t, 0]) for t in hip_candidates])
hip_class = np.full(len(triangles), PANTS)
component_report = []
for label in np.unique(labels):
    members = hip_candidates[labels == label]
    mean_lum = float(tri_lum[members].mean())
    decision = JACKET if mean_lum > HIP_JACKET_LUM else PANTS
    hip_class[members] = decision
    component_report.append((len(members), mean_lum, NAMES[decision]))
component_report.sort(reverse=True)
print("pecas do quadril (triangulos, luminancia media, decisao):")
for row in component_report[:14]: print("  ", row[0], round(row[1], 1), row[2])


def rasterize(values, default=255):
    image = Image.new("L", (width, height), default)
    draw = ImageDraw.Draw(image)
    for tri, value in zip(triangles, values):
        draw.polygon([(float(uvs[i, 0] * width), float(uvs[i, 1] * height)) for i in tri], fill=int(value))
    return np.asarray(image)


groups = rasterize(tri_group)
zones = rasterize(tri_zone)
hip_map = rasterize(np.where(tri_group == GROUP["hips"], hip_class, PANTS), PANTS)

r, g, b = texture[..., 0], texture[..., 1], texture[..., 2]
lum = luminance(r, g, b)
is_skin = skin_like(r, g, b)
is_red = red_like(r, g, b)
is_brown = brown_like(r, g, b, lum)
is_blue = b > r + 4

regions = np.full((height, width), JACKET, np.uint8)
head = groups == GROUP["head"]
regions[head] = np.where(is_skin[head], SKIN, HAIR)
# A gola da jaqueta é pesada pela cabeça/pescoço, mas é azul-xadrez.
regions[head & is_blue & (lum > 45)] = JACKET
hand = groups == GROUP["hand"]
regions[hand] = np.where(is_skin[hand], SKIN, JACKET)
upper = groups == GROUP["upper"]
regions[upper] = np.select([is_skin[upper], is_red[upper]], [SKIN, SHIRT], JACKET)
hips = groups == GROUP["hips"]
regions[hips] = np.select([is_red[hips], is_brown[hips]], [SHIRT, BELT], hip_map[hips].astype(np.int64))
leg = groups == GROUP["leg"]
# Marrom na coxa é o cinto/passador pesado pela perna; bota só da canela para baixo.
regions[leg] = np.select([is_brown[leg] & (lum[leg] < 60) & (zones[leg] == SHIN), is_brown[leg] & (lum[leg] < 60)], [BOOTS, BELT], PANTS)
foot = groups == GROUP["foot"]
regions[foot] = np.where(is_blue[foot] & (lum[foot] > 28), PANTS, BOOTS)

# Remove sal-e-pimenta com moda 5x5 e estende as bordas das ilhas para o
# mipmap/bilinear da textura base não amostrar uma região vazia vizinha.
covered = groups != 255
smoothed = np.asarray(Image.fromarray((regions * 32).astype(np.uint8)).filter(ImageFilter.ModeFilter(5))) // 32
regions = np.where(covered, smoothed, 255).astype(np.uint8)
zones = np.where(covered, zones, 255).astype(np.uint8)


def grow(values, steps=6, fallback=0):
    for _ in range(steps):
        grown = np.asarray(Image.fromarray(values).filter(ImageFilter.MinFilter(3)))
        values = np.where(values == 255, grown, values)
    return np.where(values == 255, fallback, values).astype(np.uint8)


regions = grow(regions, fallback=JACKET)
zones = grow(zones, fallback=TORSO)

encoded = np.zeros((height, width, 3), np.uint8)
encoded[..., 0] = regions * 32
encoded[..., 1] = zones * 32
destination.parent.mkdir(parents=True, exist_ok=True)
Image.fromarray(encoded).save(destination)
counts = np.bincount(regions[covered].ravel(), minlength=7)
print("texels por regiao:", {NAMES[i]: int(counts[i]) for i in range(7)})

# Luminância linear média por região: o shader multiplica a cor nova pela razão
# entre a luminância local e esta média, preservando dobras e sombras assadas.
linear = np.power(texture / 255.0, 2.2)
linear_lum = linear[..., 0] * 0.2126 + linear[..., 1] * 0.7152 + linear[..., 2] * 0.0722
means = [float(linear_lum[covered & (regions == i)].mean()) if counts[i] else 0.05 for i in range(7)]
stats_path.write_text(
    "extends RefCounted\n"
    "## Gerado por tools/build_meshy_outfit_mask.py a partir de dante_grip.glb; não editar à mão.\n"
    "## Luminância linear média por região (pele, cabelo, jaqueta, camisa, calça, cinto, bota).\n"
    f"const MEANS := [{', '.join(f'{m:.5f}' for m in means)}]\n", encoding="utf-8")
print("medias lineares:", [round(m, 4) for m in means])

palette = np.array([[240, 190, 150], [30, 30, 30], [60, 110, 200], [200, 40, 60], [40, 160, 90], [150, 90, 30], [230, 200, 40]], np.uint8)
zone_palette = np.array([[90, 90, 90], [230, 80, 80], [240, 160, 60], [250, 230, 90], [80, 170, 230], [120, 90, 220], [70, 200, 140]], np.uint8)
preview = np.concatenate([texture.astype(np.uint8), palette[regions], zone_palette[zones]], axis=1)
Image.fromarray(preview).resize((width * 3 // 2, height // 2)).save(destination.with_name(destination.stem + "_preview.png"))
