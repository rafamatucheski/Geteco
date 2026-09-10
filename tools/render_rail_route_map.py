"""Desenha o trajeto exportado pelo teste, sem inventar pontos de ligação."""
from pathlib import Path
import json
import math
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1] / 'docs/measurements/rail-route-0910'
data = json.loads((OUT / 'route.json').read_text(encoding='utf-8'))
image = Image.new('RGB', (1600, 1100), '#0c1821')
draw = ImageDraw.Draw(image)
font_path = Path('C:/Windows/Fonts/segoeui.ttf')
bold_path = Path('C:/Windows/Fonts/segoeuib.ttf')
def font(size, bold=False):
    return ImageFont.truetype(str(bold_path if bold else font_path), size)
def text(x, y, value, size=20, color='#dce7eb', bold=False):
    draw.text((x, y), value, fill=color, font=font(size, bold))
def project(point):
    return (75 + (point[0] + 1800) * .063, 188 + (point[1] + 9000) * .063)
def line(points, color, width=3):
    draw.line([project(p) for p in points], fill=color, width=width, joint='curve')
def dashed(points, color, width=2):
    phase = 0.0
    for a, b in zip(points, points[1:]):
        a, b = project(a), project(b)
        length = math.dist(a, b)
        steps = max(1, math.ceil(length))
        for i in range(steps):
            if int(phase) % 15 < 7:
                t, u = i/steps, (i+1)/steps
                draw.line((a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t,
                           a[0]+(b[0]-a[0])*u, a[1]+(b[1]-a[1])*u), fill=color, width=width)
            phase += length/steps
def arrow(points, color):
    i = len(points)//2
    a, b = project(points[max(0,i-2)]), project(points[min(len(points)-1,i+2)])
    x, y = project(points[i])
    angle = math.atan2(b[1]-a[1], b[0]-a[0])
    tri = [(x+math.cos(angle)*10,y+math.sin(angle)*10),
           (x+math.cos(angle+2.5)*10,y+math.sin(angle+2.5)*10),
           (x+math.cos(angle-2.5)*10,y+math.sin(angle-2.5)*10)]
    draw.polygon(tri, fill=color)

text(58, 38, 'FERROVIA PORTO–SERRA', 40, bold=True)
text(60, 96, 'Uma composição • Três trechos a céu aberto • Circuito contínuo', 22, '#9bb4c2')
draw.rounded_rectangle((50,160,1105,1040), radius=22, fill='#142733', outline='#29414e', width=2)
draw.rounded_rectangle((1140,160,1550,1040), radius=22, fill='#1d303c')
for x in range(110,1080,95): draw.line((x,185,x,1016),fill='#1c3441')
for y in range(210,1030,95): draw.line((70,y,1085,y),fill='#1c3441')

line(data['mountain_road'], '#456174', 4)
dashed(data['route'], '#7790a0', 2)
colors = {'harbor':'#f0ac62','bay':'#72d1e9','mountain':'#85d3ad'}
for section in data['sections']:
    line(section['points'], '#0c1821', 10)
    line(section['points'], colors[section['id']], 5)
    arrow(section['points'], '#f4f7e8')

text(93,218,'N',20,'#bdd0da',True)
draw.line((103,279,103,250),fill='#bdd0da',width=2)
draw.polygon([(103,242),(98,252),(108,252)],fill='#bdd0da')
text(145,875,'PORTO',21,'#f0ac62',True)
text(844,254,'SERRA',21,'#85d3ad',True)
text(585,570,'BAÍA',18,'#588598')
text(225,360,'RETORNO EM TÚNEL',15,'#8ba1ad')

for i, marker in enumerate(data['landmarks'], 1):
    x,y = project(marker['position'])
    draw.ellipse((x-14,y-14,x+14,y+14),fill='#0d1a24',outline='#ecdbad',width=2)
    label=str(i)
    box=draw.textbbox((0,0),label,font=font(15,True))
    draw.text((x-(box[2]-box[0])/2,y-11),label,fill='#f4e5bd',font=font(15,True))

text(1172,194,'O PERCURSO',22,'#f4e6bf',True)
labels = ['Viaduto do porto','Túnel de ligação','Ponte da serra','Túnel da encosta',
          'Passagem pela serraria','Contorno da floresta','Encosta nevada','Túnel norte e retorno']
for i,label in enumerate(labels,1):
    y=256+(i-1)*57
    draw.ellipse((1172,y,1200,y+28),outline='#77929e',width=1)
    text(1180,y+2,str(i),16,'#f4e6bf',True)
    text(1216,y+1,label,19)

draw.line((1170,748,1520,748),fill='#3c505b',width=1)
text(1172,774,'LEGENDA',16,'#8faab8',True)
for i,(label,color) in enumerate([('Porto',colors['harbor']),('Ponte ferroviária',colors['bay']),('Montanha',colors['mountain']),('Ligação subterrânea','#7790a0')]):
    y=816+i*36
    if i==3:
        for x in range(1174,1220,12): draw.line((x,y+9,x+6,y+9),fill=color,width=2)
    else: draw.line((1174,y+9,1218,y+9),fill=color,width=4)
    text(1233,y-2,label,17,'#c2d3dd')
seconds=round(data['cycle_seconds'])
text(1172,981,f'Volta completa: ~{seconds//60}min{seconds%60:02d}s',19,'#f4e6bf',True)
text(62,1057,'Traçado extraído da rota implementada. Estrada da serra em azul escuro.',17,'#8faab8')
image.save(OUT/'rota-porto-serra.png')
print(OUT/'rota-porto-serra.png')
