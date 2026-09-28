from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json
p=Path(__file__).parent
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',15)
def sheet(name,rows):
    w,h=224,278
    cols=max(len(files) for title,files in rows)
    out=Image.new('RGB',(w*cols,h*len(rows)), '#18212b')
    d=ImageDraw.Draw(out)
    for y,(title,files) in enumerate(rows):
        d.text((8,y*h+3),title,font=font,fill='white')
        for x,f in enumerate(files):
            im=Image.open(f).convert('RGB'); im.thumbnail((w,245))
            out.paste(im,(x*w+(w-im.width)//2,y*h+26))
            d.text((x*w+6,y*h+253),f.stem.split('_')[-1],font=small,fill='white')
    out.save(p/(name+'.jpg'),quality=92)
def rows(prefixes,frames=None):
    result=[]
    for prefix in prefixes:
        files=sorted(f for f in p.glob(prefix+'_*.png') if f.stem.rsplit('_',1)[0] == prefix)
        if frames is not None: files=[f for f in files if int(f.stem.split('_')[-1]) in frames]
        result.append((prefix,files))
    return result
sheet('locomotion',rows(['runtime_idle','runtime_walk','runtime_run','runtime_side_fast','runtime_turn','runtime_death']))
sheet('punches',rows(['combat_fists_0_attack','combat_fists_1_attack','combat_fists_0_attackfront','combat_fists_0_attackside'],[0,3,6,9,12,18,24,35]))
sheet('knuckles',rows(['combat_knuckles_0_attack','combat_knuckles_1_attack','combat_knuckles_2_attack','combat_knuckles_3_attack','combat_knuckles_0_attackside'],[0,3,6,9,12,18,24,35]))
sheet('melee',rows(['combat_knife_0_attack','combat_knife_1_attack','combat_knife_2_attack','combat_axe_0_attack','combat_bat_0_attack','combat_grenade_0_attack'],[0,6,12,18,24,35]))
ids=['pistol','magnum','smg','shotgun','sawed_off','ak47','m4a1','hunting_rifle','rpg','flamethrower']
for mode in ['attack','reload']:
    for page in range(2):
        sheet(mode+str(page+1),rows(['combat_'+id+'_0_'+mode for id in ids[page*5:(page+1)*5]],[0,6,12,24,35,59]))
j=json.loads((p/'review.json').read_text())
clips=[c['name'] for c in j['clips']]
for page in range(3): sheet('clips'+str(page+1),rows(['clip_'+c for c in clips[page*6:(page+1)*6]]))
for k,v in j['combat'].items(): print(k, v['max_frame_jump'])
print('seams',j['seams'],'death joints',j['death_articulated_joints'])
