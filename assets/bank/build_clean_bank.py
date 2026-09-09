import trimesh, numpy as np
from pathlib import Path
scene=trimesh.Scene()
colors={'stone':[153,147,130,255],'floor':[118,111,94,255],'wood':[74,43,27,255],'trim':[108,75,43,255],'steel':[77,88,99,255],'dark':[28,34,38,255],'light':[244,218,162,255],'screen':[37,83,91,255]}
def box(name,size,pos,mat):
 m=trimesh.creation.box(extents=size);m.apply_translation(pos);m.visual=trimesh.visual.ColorVisuals(m,face_colors=colors[mat]);scene.add_geometry(m,node_name=name,geom_name=name)
box('Floor',(14,.16,10),(0,-.09,0),'floor')
for x in range(-7,7):
 for z in range(-5,5):box(f'Tile_{x}_{z}',(.985,.018,.985),(x+.5,.002,z+.5),'stone')
for x in [-7,7]:
 box(f'Wall_{x}',(.18,2.5,10),(x,1.2,0),'stone')
 box(f'Baseboard_{x}',(.22,.22,10),(x,.12,0),'wood')
 box(f'Cornice_{x}',(.26,.12,10),(x,2.45,0),'trim')
box('BackWall',(14,2.5,.18),(0,1.2,-5),'stone')
for x in [-4.05,4.05]:
 box(f'VaultPartition_{x}',(5.9,2.6,.22),(x,1.3,-3.2),'stone')
 box(f'PartitionPanel_{x}',(5.9,.8,.25),(x,.4,-3.2),'wood')
for x in [-1.18,1.18]:box(f'VaultFrame_{x}',(.16,2.7,.38),(x,1.35,-3.2),'steel')
box('VaultLintel',(2.52,.17,.38),(0,2.7,-3.2),'steel')
for x in [-4.5,4.5]:
 box(f'Counter_{x}',(2.6,1.1,1.2),(x,.55,-1),'wood')
 box(f'CounterTop_{x}',(2.76,.12,1.32),(x,1.12,-1),'dark')
 for dx in [-.85,0,.85]:
  box(f'Panel_{x}_{dx}',(.73,.72,.035),(x+dx,.58,-.385),'trim')
  box(f'PanelInset_{x}_{dx}',(.63,.62,.04),(x+dx,.58,-.36),'wood')
 box(f'Monitor_{x}',(.52,.36,.10),(x,1.43,-1),'dark')
 box(f'Screen_{x}',(.44,.28,.012),(x,1.43,-1.06),'screen')
 box(f'Stand_{x}',(.10,.16,.10),(x,1.24,-1),'steel')
 box(f'Keyboard_{x}',(.43,.025,.16),(x,1.20,-1.35),'dark')
for x in [-5,5]:
 box(f'BenchSeat_{x}',(2,.15,.6),(x,.48,2.8),'dark')
 box(f'BenchBack_{x}',(2,.55,.12),(x,.80,3.05),'dark')
 for dx in [-.8,.8]:box(f'BenchLeg_{x}_{dx}',(.09,.42,.48),(x+dx,.21,2.8),'steel')
for x in [-6.8,6.8]:
 for z in [-2,1,4]:
  box(f'Pilaster_{x}_{z}',(.28,2.45,.32),(x,1.2,z),'stone')
  box(f'LampBase_{x}_{z}',(.13,.40,.18),(x*.985,1.8,z),'dark')
  box(f'LampGlass_{x}_{z}',(.15,.28,.12),(x*.975,1.8,z),'light')
# Clean separate animated door geometry, authored around its left hinge.
box('VaultDoor',(2.16,2.57,.20),(0,1.29,-3.2),'steel')
box('VaultDoorInset',(1.94,2.30,.045),(0,1.29,-3.075),'dark')
box('VaultDoorFace',(1.84,2.20,.05),(0,1.29,-3.04),'steel')
for x in [-.9,.9]:
 for y in [.25,.8,1.4,2,2.4]:box(f'DoorBolt_{x}_{y}',(.07,.07,.06),(x,y,-2.995),'trim')
# Raised continuous wheel, spokes, lock housing and heavy hinge blocks.
ring=trimesh.creation.annulus(r_min=.30,r_max=.39,height=.08,sections=40)
ring.apply_translation((0,1.3,-2.83));ring.visual.face_colors=colors['dark'];scene.add_geometry(ring,node_name='WheelRing')
for a in [0,np.pi/2]:
 m=trimesh.creation.box(extents=(.64,.055,.065));m.apply_transform(trimesh.transformations.rotation_matrix(a,[0,0,1]));m.apply_translation((0,1.3,-2.83));m.visual.face_colors=colors['dark'];scene.add_geometry(m,node_name=f'Spoke_{a}')
box('DoorBoltLock',(.24,.32,.12),(.55,1.3,-2.94),'dark')
box('DoorBoltKeySlot',(.045,.10,.025),(.55,1.3,-2.867),'trim')
for y in [.4,2.15]:box(f'DoorBoltHinge_{y}',(.20,.35,.38),(-1.02,y,-3.16),'steel')
for geometry in scene.geometry.values():
 color=geometry.visual.face_colors[0].copy()
 geometry.unmerge_vertices()
 geometry.visual=trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(baseColorFactor=color,metallicFactor=0.0,roughnessFactor=.85))
out=Path('D:/geteco/game/assets/bank/bank-finished.glb');out.write_bytes(scene.export(file_type='glb',include_normals=True));print(out, 'triangles',sum(len(m.faces) for m in scene.geometry.values()))


