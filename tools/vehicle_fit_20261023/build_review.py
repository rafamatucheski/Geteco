"""Publica comparações realmente renderizadas. Nenhuma imagem conceitual gerada é usada."""
from pathlib import Path
import html
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts/vehicle-fit-20261023"
MODELS = [
    ("bike_sport", "Vortex RR 900", "motorcycles", "side"),
    ("bike_cruiser", "Ironhorse 1700", "motorcycles", "rear_quarter"),
    ("bike_urban", "Cometa City 250", "motorcycles", "front_quarter"),
    ("porto_rosso", "Porto Rosso", "passenger", "rear"),
    ("beach_cabriolet", "Cabriolet", "passenger", "front"),
    ("orbita_micro", "Órbita", "passenger", "front"),
    ("vale_crossover", "Vale", "passenger", "rear"),
    ("ranch_pickup", "Ranch", "utility", "cab_rear"),
    ("ranch_single", "Ranch Single", "utility", "cab_rear"),
    ("boxrunner", "Boxrunner", "utility", "front"),
    ("toco_minitruck", "Toco", "utility", "front"),
]


def source(row, phase):
    ident, _, group, view = row
    separator = "_" if group == "motorcycles" else "-"
    return OUT / group / phase / f"{ident}{separator}{view}.png"


def main():
    cards = []
    for row in MODELS:
        before, after = source(row, "before"), source(row, "after")
        if not before.exists() or not after.exists():
            raise FileNotFoundError(f"Missing real comparison for {row[0]}")
        cards.append(f'<section><h2>{html.escape(row[1])}</h2><div>'
                     f'<figure><figcaption>Antes</figcaption><img src="{before.relative_to(OUT).as_posix()}"></figure>'
                     f'<figure><figcaption>Depois</figcaption><img src="{after.relative_to(OUT).as_posix()}"></figure>'
                     '</div></section>')
    template = '''<!doctype html><html lang="pt-BR"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Veículos — revisão dos encaixes</title>
<style>body{margin:32px auto;max-width:1600px;padding:0 20px;background:#131b20;color:#edf0ed;font:17px system-ui}h1{font-size:30px}h2{font-size:20px;margin:22px 0 8px}section{border-top:1px solid #536169;margin:28px 0}section>div{display:grid;grid-template-columns:1fr 1fr;gap:16px}figure{margin:0}figcaption{margin:8px 0;color:#b8c4ca}img{display:block;width:100%;height:auto}p{max-width:900px;line-height:1.5}@media(max-width:700px){section>div{grid-template-columns:1fr}}</style>
<h1>Carros e motos: revisão de modelagem e encaixes</h1>
<p>Comparações das cenas reais, com a mesma câmera e iluminação em cada par. Onze modelos corrigidos; outros veículos da frota não estão aprovados por esta revisão. As medições de performance usam a cidade renderizada, separadamente destas capturas de estúdio.</p>'''
    (OUT / "review.html").write_text(template + "".join(cards) + "</html>", encoding="utf-8")
    # Uma folha de contato concisa para entrega em linha; a galeria tem as onze.
    featured = [MODELS[i] for i in (0, 3, 7, 9)]
    width, panel_h = 800, 460
    sheet = Image.new("RGB", (width * 2, 76 + (panel_h + 45) * len(featured)), "#172027")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 27)
    small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 22)
    draw.text((20, 20), "ANTES", font=font, fill="#c5ced0")
    draw.text((width + 20, 20), "DEPOIS", font=font, fill="#edf5ee")
    for i, row in enumerate(featured):
        y = 76 + i * (panel_h + 45)
        draw.text((20, y + 4), row[1], font=small, fill="#edf5ee")
        for j, phase in enumerate(("before", "after")):
            im = Image.open(source(row, phase)).convert("RGB")
            # A folha em linha compara os modelos. Mantém as imagens originais
            # na galeria; corta a mesma faixa de HUD de diagnóstico dos dois
            # painéis da folha, para o FPS momentâneo lido não sugerir um benchmark.
            im = im.crop((0, 40, im.width, im.height))
            im.thumbnail((width - 8, panel_h), Image.Resampling.LANCZOS)
            sheet.paste(im, (j * width + (width - im.width) // 2, y + 38 + (panel_h - im.height) // 2))
    sheet.save(OUT / "comparison.jpg", quality=92)
    print(json.dumps({"gallery": str(OUT / "review.html"), "models": len(cards), "comparison": str(OUT / "comparison.jpg")}))


if __name__ == "__main__":
    main()
