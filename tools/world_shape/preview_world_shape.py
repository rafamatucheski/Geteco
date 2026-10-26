"""Prévia de cima da forma do mundo (etapa 0 do plano de 26/10/2026).

Desenha as ilhas de world/shape/world_shape.json com o tipo de costa, e por cima o que é jogável hoje
(terras do mapa, estradas, prédios e marcadores exportados por tests/tools/export_world_map_data.gd).
Pontos vermelhos marcam o que caiu no mar ou perto demais da costa, se a lista vier do teste de contrato.

Uso: python tools/world_shape/preview_world_shape.py [world.json] [world_shape.json] [saída.png] [violações.json]
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

geo_path = Path(sys.argv[1] if len(sys.argv) > 1 else "tools/world_shape/world_geography.json")
shape_path = Path(sys.argv[2] if len(sys.argv) > 2 else "world/shape/world_shape.json")
out_path = Path(sys.argv[3] if len(sys.argv) > 3 else "evidence/world-shape/preview.png")
violations_path = Path(sys.argv[4]) if len(sys.argv) > 4 else None

geo = json.loads(geo_path.read_text(encoding="utf-8"))
shape = json.loads(shape_path.read_text(encoding="utf-8"))

X0, X1, Z0, Z1 = -1700, 1060, -1620, 560
SCALE = 0.75  # px por metro
W, H = int((X1 - X0) * SCALE), int((Z1 - Z0) * SCALE)
COAST = {"quay": (150, 150, 150), "beach": (232, 208, 150), "cliff": (150, 95, 60), "rock": (110, 120, 125)}
LAND = {"harbor": (98, 132, 82), "desert": (214, 178, 118), "mountain": (180, 190, 192)}


def px(x, z):
    return ((x - X0) * SCALE, (z - Z0) * SCALE)


def pairs(flat):
    return [(flat[i], flat[i + 1]) for i in range(0, len(flat), 2)]


img = Image.new("RGB", (W, H), (22, 52, 62))
draw = ImageDraw.Draw(img)
for island in shape["islands"]:
    pts = pairs(island["points"])
    draw.polygon([px(x, z) for x, z in pts], fill=LAND.get(island["id"].split("_")[0], (160, 160, 160)))
for island in shape["islands"]:
    pts = pairs(island["points"])
    runs = island["coast"] + [[len(pts), ""]]
    for (start, kind), (end, _) in zip(runs, runs[1:]):
        seg = [px(*pts[i % len(pts)]) for i in range(start, end + 1)]
        draw.line(seg, fill=COAST[kind], width=5)
# O que existe hoje: terras do mapa (contorno), estradas, prédios e marcadores.
for land in geo["lands"]:
    pts = [px(x, z) for x, z in pairs(land["points"])]
    if len(pts) > 2:
        draw.polygon(pts, outline=(255, 255, 255) if land["biome"] != "water" else (80, 160, 220))
for road in geo["roads"]:
    pts = [px(x, z) for x, z in pairs(road["points"])]
    color = (60, 60, 60) if road["surface"] not in ("railway",) else (120, 40, 40)
    if len(pts) > 1:
        draw.line(pts, fill=color, width=2)
for building in geo["buildings"]:
    draw.polygon([px(x, z) for x, z in pairs(building)], fill=(70, 70, 75))
for marker in geo["markers"]:
    x, y = px(marker["x"], marker["z"])
    draw.ellipse((x - 2.5, y - 2.5, x + 2.5, y + 2.5), fill=(20, 30, 40))
bad = []
if violations_path and violations_path.exists():
    bad = json.loads(violations_path.read_text(encoding="utf-8"))
    for v in bad:
        x, y = px(v["x"], v["z"])
        draw.ellipse((x - 7, y - 7, x + 7, y + 7), outline=(230, 40, 40), width=3)
font = ImageFont.load_default()
draw.text((12, 12), "Forma do mundo (etapa 0): ilhas com tipo de costa; branco = terras do mapa de hoje; vermelho = violação (%d)" % len(bad), fill=(240, 240, 240), font=font)
legend_y = 30
for kind, color in COAST.items():
    draw.rectangle((12, legend_y, 30, legend_y + 10), fill=color)
    draw.text((36, legend_y - 1), {"quay": "cais", "beach": "praia", "cliff": "penhasco", "rock": "pedra"}[kind], fill=(240, 240, 240), font=font)
    legend_y += 16
out_path.parent.mkdir(parents=True, exist_ok=True)
img.save(out_path)
print("PREVIEW", out_path, W, H, "violações", len(bad))
