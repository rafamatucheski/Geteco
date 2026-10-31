"""Albedos originais de mata, assados offline. Uma amostra substitui a grama procedural ruidosa.
512px / 16,7 m: manchas largas de musgo/terra, folhas caídas agrupadas, cascalho esparso.
Sem objetos extras na cena, sobreposições nem geração no runtime. Só Pillow + numpy.
"""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/materials/woodland'
SIZE=512

def bake(kind,seed):
    rng=np.random.default_rng(seed)
    yy,xx=np.mgrid[:SIZE,:SIZE].astype(float)
    field=np.zeros((SIZE,SIZE))
    for _ in range(12):
        kx,ky=rng.integers(1,4,2)*rng.choice([-1,1],2)
        field+=np.sin((xx*kx+yy*ky)*2*math.pi/SIZE+rng.uniform(0,math.tau))/12
    # Variação larga e contida, não camuflagem de alto contraste em cada metro.
    base=np.array([62,77,49] if kind=='woodland' else [105,81,59],float)
    rgb=np.broadcast_to(base,(SIZE,SIZE,3)).copy()
    rgb+=field[:,:,None]*(20 if kind=='woodland' else 19)
    rgb+=rng.normal(0,1.25,(SIZE,SIZE,1))
    clusters=[]
    for _ in range(7 if kind=='woodland' else 4):
        cx,cy=rng.uniform(0,SIZE,2)
        sx,sy=rng.uniform(12,45),rng.uniform(10,32)
        dx=(xx-cx+SIZE/2)%SIZE-SIZE/2
        dy=(yy-cy+SIZE/2)%SIZE-SIZE/2
        patch=np.exp(-.5*((dx/sx)**2+(dy/sy)**2))*.60
        soil=np.array([91,76,52] if kind=='woodland' else [88,69,51])
        rgb=rgb*(1-patch[:,:,None])+soil*patch[:,:,None]
        clusters.append((cx,cy,sx,sy))
    image=Image.fromarray(np.clip(rgb,0,255).astype('uint8'),'RGB')
    pen=ImageDraw.Draw(image)
    if kind=='woodland':
        # Folhas finas aparadas ficam discretas na distância de jogo e somem no mip.
        for _ in range(1800):
            x,y=rng.integers(0,SIZE,2)
            tint=rng.choice([[69,82,52],[58,72,45],[73,83,53]])
            pen.line([(int(x),int(y)),(int(x+rng.integers(-1,2)),int(y-rng.integers(1,4)))],fill=tuple(int(t) for t in tint),width=1)
        # As folhas se juntam em bolsões irregulares de terra, com vegetação mais calma entre eles.
        for cx,cy,sx,sy in clusters:
            for _ in range(37):
                x,y=(np.array([cx,cy])+rng.normal(0,1,2)*[sx*.72,sy*.72])%SIZE
                angle=rng.uniform(0,math.tau); length=rng.uniform(1.3,3.2)
                u=np.array([math.cos(angle),math.sin(angle)])*length
                v=np.array([-u[1],u[0]])*.38
                c=np.array([x,y]); points=[tuple(c-u),tuple(c+v),tuple(c+u),tuple(c-v)]
                tint=rng.choice([[102,89,57],[117,99,64],[84,77,49],[92,75,49]])
                pen.polygon(points,fill=tuple(int(t) for t in tint))
                if length>2.6: pen.line([tuple(c-u*.7),tuple(c+u*.7)],fill=(71,67,45),width=1)
    else:
        for _ in range(210):
            x,y=rng.integers(0,SIZE,2); tint=int(rng.integers(78,112))
            pen.ellipse((x,y,x+1,y+1),fill=(tint,tint-9,tint-22))
    OUT.mkdir(parents=True,exist_ok=True)
    image.save(OUT/(kind+'.png'),optimize=True)
    # O Godot cria remap/deps na primeira importação; mantém compressão VRAM/mips explícitos.
    settings=OUT/(kind+'.png.import')
    if not settings.exists():
        settings.write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\ncompress/mode=2\ncompress/high_quality=false\nmipmaps/generate=true\nprocess/fix_alpha_border=false\ndetect_3d/compress_to=0\n',encoding='utf-8')

if __name__=='__main__':
    # woodland.png é um asset autorado no ImageGen: nunca regenere/sobrescreva.
    bake('earth',92826)
