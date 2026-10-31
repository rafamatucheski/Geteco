"""Assa o albedo original e sem emenda do calçamento de Harbor. Pillow + numpy, só offline.
Repetição de 16 metros: desgaste irregular, juntas de construção contidas e lixo esparso.
Sem decals, nós, física, passes extras de material no runtime nem assets do GTA.
"""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw

SIZE = 512
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/materials/harbor_paving"
FINISHES = ["service", "limestone", "brick", "quay"]
# concrete.png é um asset autorado no ImageGen; preserve-o ao refazer os acabamentos que o acompanham.

def bake(name, seed):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[:SIZE, :SIZE].astype(float)
    # Ondas de frequência inteira fecham exatamente nas duas bordas da textura.
    field = np.zeros((SIZE, SIZE))
    fine = np.zeros_like(field)
    for target, count, low, high in [(field, 24, 1, 8), (fine, 24, 12, 72)]:
        for _ in range(count):
            kx, ky = rng.integers(low, high, 2) * rng.choice([-1,1],2)
            target += np.sin((xx*kx+yy*ky)*2*math.pi/SIZE+rng.uniform(0,2*math.pi))/count
    tone = 232 + field*9 + fine*13 + rng.normal(0,1.5,(SIZE,SIZE))
    # Acúmulos irregulares de sujeira, áreas largas claras e gastas e manchas isoladas de graxa.
    stain_count = 32 if name == "service" else 9 if name == "quay" else 6
    for _ in range(stain_count):
        cx, cy = rng.uniform(0,SIZE,2)
        dx = (xx-cx+SIZE/2)%SIZE-SIZE/2
        dy = (yy-cy+SIZE/2)%SIZE-SIZE/2
        angle = rng.uniform(0,math.pi)
        u, v = dx*math.cos(angle)+dy*math.sin(angle), -dx*math.sin(angle)+dy*math.cos(angle)
        sx, sy = rng.uniform(4,22),rng.uniform(2,8)
        mask = np.exp(-.5*((u/sx)**2+(v/sy)**2))
        tone -= mask*rng.uniform(8,24)*(1+field*1.8)
    # Concreto moldado tem cortes de dilatação ocasionais, nunca uma grade quadrada completa.
    joints = Image.new("L",(SIZE,SIZE),0)
    draw = ImageDraw.Draw(joints)
    if name in ["concrete","service","quay"]:
        for _ in range(3 if name == "service" else 2):
            x,y = rng.integers(24,SIZE-120,2)
            length = int(rng.integers(55,120))
            draw.line([(x,y),(x+length,y)],fill=18,width=1)
    else:
        # Altura das fiadas e comprimento das pedras variam; a erosão quebra a argamassa.
        y = 0
        while y < SIZE:
            height = int(rng.integers(10,19) if name == "brick" else rng.integers(28,55))
            draw.line([(0,y),(SIZE,y)],fill=7,width=1)
            x = -int(rng.integers(10,45))
            while x < SIZE:
                draw.line([(x,y),(x,y+height)],fill=7,width=1)
                x += int(rng.integers(19,38) if name == "brick" else rng.integers(40,100))
            y += height
    tone -= np.asarray(joints)*np.clip(.45+field*5,0,1)
    rgb = np.repeat(np.clip(tone,0,255).astype(np.uint8)[:,:,None],3,axis=2)
    image = Image.fromarray(rgb,"RGB").convert("RGBA")
    detail = Image.new("RGBA",image.size)
    pen = ImageDraw.Draw(detail)
    # Trincas finas, curtas e ramificadas, não um segundo padrão de calçamento.
    for _ in range(8 if name == "service" else 4):
        x,y = rng.integers(40,SIZE-80,2)
        points = [(int(x),int(y))]
        for step in range(int(rng.integers(3,7))):
            x += rng.integers(3,10); y += rng.integers(-5,7)
            points.append((int(x),int(y)))
        pen.line(points,fill=(85,81,73,44),width=1)
        if len(points)>3:
            x,y=points[2]; pen.line([(x,y),(x+2,y-5),(x+8,y-8)],fill=(85,81,73,30),width=1)
    # Algumas folhas/restos jogados a cada 256 m², pintados no próprio albedo.
    papers = {"concrete":6,"service":8,"limestone":2,"brick":4,"quay":3}[name]
    for n in range(papers):
        sheet = Image.new("RGBA",(18,22))
        d = ImageDraw.Draw(sheet)
        d.polygon([(5,4),(14,5),(13,9),(15,18),(5,19),(6,12),(4,10)],fill=(75,70,61,165))
        paper = (182,161,124,255) if n%3 == 0 else (255,253,241,255)
        d.polygon([(4,3),(13,4),(12,8),(14,17),(4,18),(5,11),(3,9)],fill=paper)
        d.line([(4,11),(12,9),(14,17)],fill=(112,108,96,200),width=1)
        if n%2 == 0:
            for y in [6,8,14]: d.line([(6,y),(10,y)],fill=(105,109,104,185),width=1)
        sheet = sheet.rotate(int(rng.integers(0,360)),resample=Image.Resampling.BICUBIC,expand=True)
        x,y = rng.integers(30,SIZE-45,2)
        detail.alpha_composite(sheet,(int(x),int(y)))
    image = Image.alpha_composite(image,detail).convert("RGB")
    image.save(OUTPUT/f"{name}.png",optimize=True)

if __name__ == "__main__":
    OUTPUT.mkdir(parents=True,exist_ok=True)
    for i,name in enumerate(FINISHES): bake(name,14102026+i*103)
    print("Baked 4 companion 512px textures; preserved authored concrete.png.")
