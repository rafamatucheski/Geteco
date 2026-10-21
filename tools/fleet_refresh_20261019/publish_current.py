from pathlib import Path
from PIL import Image, ImageDraw
root = Path('D:/geteco/game/artifacts/car-fleet-implementation-20261019/refreshed')
ids=['sedan_classic','union_sedan','aurora_executive','metro_hatch','station_wagon','desert_faisca','desert_faisca_rally','ranch_single','ranch_pickup']
for view in ['front','rear','side','top']:
    board=Image.new('RGB',(1440,966),'#171b1e')
    d=ImageDraw.Draw(board)
    for i,id in enumerate(ids):
        at=((i%3)*480,(i//3)*322)
        frame=Image.open(root/f'{id}-{view}.png').convert('RGB').resize((480,300))
        board.paste(frame,(at[0],at[1]+22)); d.text((at[0]+10,at[1]+5),id,fill='white')
    board.save(root/f'grid-{view}.jpg',quality=91)
board=Image.new('RGB',(1280,2112),'#171b1e'); d=ImageDraw.Draw(board)
for i,id in enumerate(['sedan_classic','union_sedan','aurora_executive','metro_hatch','desert_faisca']):
    for col,prefix in enumerate(['before-','']):
        frame=Image.open(root/f'{prefix}{id}-side.png').convert('RGB').resize((640,400))
        board.paste(frame,(col*640,i*422+22)); d.text((col*640+10,i*422+5),id+(' | antes' if prefix else ' | agora'),fill='white')
board.save(root/'side-comparison.jpg',quality=92)
