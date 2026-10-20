"""Objetos do editor de mundo (WorldPropFactory) modelados no Blender.

Rodar (sem abrir a interface):
    D:/Blender/blender.exe -b --factory-startup --python tools/blender/build_editor_props.py

Gera assets/city_props/editor_props.glb e source/editor_props.blend. Como no porto, cada
modelo sai com um objeto por material: "<modelo>_mat_main" leva a cor que quem posiciona
escolhe no editor (row.color) e "<modelo>_mat_<hex>" as partes de cor fixa (ferragem,
tampa, borracha). Sai com UV e o Godot gera as tangentes, para o formato de vértice ser o
das BoxMesh/CylinderMesh antigas. Medidas e colisão iguais às de WorldPropFactory.SIZES.
"""
import math
import os
import sys

import bpy
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_city_props import OUT_DIR, at  # noqa: E402
from build_harbor_route_props import Variant  # noqa: E402
from build_city_props_wave3 import Kit  # noqa: E402

WHITE = (1.0, 1.0, 1.0, 1.0)


class EditorVariant(Variant):
    def mat(self, material: str, smooth_angle: float = 35.0):
        if material not in self.props:
            self.props[material] = Kit(f"{self.name}_mat_{material}", smooth_angle)
        return self.props[material]


def _pallet(v: EditorVariant, y: float) -> None:
    # Palete de madeira: as três cores das peças antigas, em tábuas com quina.
    for x in (-.45, 0, .45):
        v.mat("705237").box(at(x, y + .09, 0), (.14, .14, 1.0), WHITE, bevel=.008)
    for k, z in enumerate((-.4, -.2, 0, .2, .4)):
        v.mat("b99768").box(at(0, y + .195, z), (1.2, .06, .14), WHITE, bevel=.006, rot=(0, 0, .004 * (k - 2)))
    for z in (-.4, 0, .4):
        v.mat("937149").box(at(0, y + .025, z), (1.2, .045, .14), WHITE, bevel=.006)


def pallet() -> list:
    v = EditorVariant("pallet")
    _pallet(v, 0)
    return v.build(emissive="")


def pallet_stack() -> list:
    v = EditorVariant("pallet_stack")
    for i in range(4):
        _pallet(v, i * .25)
    return v.build(emissive="")


def crate() -> list:
    # Caixote de 1 m: tábuas na cor escolhida, travessas e cantoneiras mais escuras.
    v = EditorVariant("crate")
    main = v.mat("main")
    main.box(at(0, .5, 0), (.94, .94, .94), WHITE, bevel=.01)
    for face in range(4):
        rot = (0, 0, face * math.pi / 2)
        for k in range(5):
            y = .12 + k * .19
            c, s = math.cos(face * math.pi / 2), math.sin(face * math.pi / 2)
            main.box(at(s * .48, y, c * .48), (.96, .16, .03), WHITE, bevel=.006, rot=rot)
        v.mat("6b4f33").box(at(s * .5, .5, c * .5), (.08, 1.0, .04), WHITE, bevel=.008, rot=(0, 0, face * math.pi / 2 + math.pi / 4))
    for y in (.02, .98):
        v.mat("6b4f33").box(at(0, y, 0), (1.0, .05, 1.0), WHITE, bevel=.01)
    for x in (-.49, .49):
        for z in (-.49, .49):
            v.mat("464c48").box(at(x, .5, z), (.05, 1.0, .05), WHITE, bevel=.006)
    return v.build(emissive="")


def barrel() -> list:
    # Tambor de 200 L: corpo na cor escolhida, frisos e aros escuros, tampa com bujões.
    v = EditorVariant("barrel")
    main, dark = v.mat("main"), v.mat("464c48")
    main.cyl(at(0, .02), .31, .31, .88, WHITE, sides=20, bevel=.012)
    for y in (.3, .62):
        main.torus(at(0, y), .31, .012, WHITE, axis="Z", segments=20, ring=4)
    for y in (.03, .89):
        dark.torus(at(0, y), .315, .02, WHITE, axis="Z", segments=20, ring=4)
    dark.cyl(at(0, .9), .29, .29, .006, WHITE, sides=20, bevel=0.0)
    for x, r in ((.17, .04), (-.15, .025)):
        dark.cyl(at(x, .9), r, r, .02, WHITE, sides=10, bevel=.003)
    return v.build(emissive="")


def bin() -> list:
    # Lixeira de rua quadrada (editor): corpo na cor escolhida, tampa e boca escuras.
    v = EditorVariant("bin")
    main = v.mat("main")
    main.box(at(0, .45, 0), (.54, .84, .54), WHITE, bevel=.025)
    main.box(at(0, .04, 0), (.5, .08, .5), WHITE, bevel=.01)
    for side in range(4):
        c, s = math.cos(side * math.pi / 2), math.sin(side * math.pi / 2)
        main.box(at(s * .275, .45, c * .275), (.42, .62, .02), WHITE, bevel=.006, rot=(0, 0, side * math.pi / 2))
    v.mat("364d3c").box(at(0, .92, 0), (.62, .06, .62), WHITE, bevel=.02)
    v.mat("364d3c").box(at(0, .97, 0), (.5, .04, .5), WHITE, bevel=.015)
    v.mat("1b2420").box(at(0, .78, .29), (.32, .08, .03), WHITE, bevel=.006)
    v.mat("839185").box(at(0, .6, .286), (.2, .12, .01), WHITE, bevel=.003)
    return v.build(emissive="")


def barrier() -> list:
    # Barreira new jersey de concreto: perfil em degrau, olhais e faixas refletivas.
    v = EditorVariant("barrier")
    main = v.mat("main")
    main.box(at(0, .12, 0), (2.0, .24, .5), WHITE, bevel=.02)
    main.box(at(0, .3, 0), (2.0, .16, .4), WHITE, bevel=.02, rot=(0, 0, 0))
    main.box(at(0, .62, 0), (2.0, .6, .26), WHITE, bevel=.02)
    for side in (-1, 1):
        main.box(at(0, .26, .19 * side), (2.0, .12, .08), WHITE, bevel=.02, rot=(math.radians(-35 * side), 0, 0))
    for x in (-.65, 0, .65):
        v.mat("d0ad52").box(at(x, .7, .133), (.25, .14, .01), WHITE, bevel=.003)
    for x in (-.9, .9):
        v.mat("464c48").torus(at(x, .93, 0), .05, .012, WHITE, axis="Y", segments=10, ring=4)
    v.mat("464c48").box(at(-.95, .1, 0), (.08, .12, .2), WHITE, bevel=.01)
    return v.build(emissive="")


def dumpster() -> list:
    v = EditorVariant("dumpster")
    main = v.mat("main")
    main.box(at(0, .63, 0), (1.76, 1.0, .96), WHITE, bevel=.04)
    for x in (-.55, 0, .55):
        for z in (.49, -.49):
            main.box(at(x, .63, z), (.07, .86, .03), WHITE, bevel=.01)
    lid = v.mat("313d36")
    for x in (-.45, .45):
        lid.box(at(x, 1.17, -.01), (.88, .06, 1.08), WHITE, bevel=.025, rot=(math.radians(4), 0, 0))
    lid.box(at(0, 1.1, 0), (1.84, .06, 1.02), WHITE, bevel=.015)
    for x in (-.82, .82):
        v.mat("232927").box(at(x, .18, 0), (.17, .3, .85), WHITE, bevel=.015)
        v.mat("89948b").box(at(x, .85, .53), (.3, .09, .1), WHITE, bevel=.015)
    for x in (-.7, .7):
        for z in (-.35, .35):
            v.mat("232927").wheel(at(x, .06, z), .06, .04, WHITE, WHITE)
    return v.build(emissive="")


def trash_bags() -> list:
    v = EditorVariant("trash_bags", )
    bags = v.mat("303b36", smooth_angle=80.0)
    for i in range(3):
        center = at((i - 1) * .29, .3, -.12 if i == 1 else .12)
        bags.sphere(center, (.29, .3, .27), WHITE, subdiv=2, jitter=.035, seed=i * 2.1, flatten_below=0.0)
        top = center + Vector((0, 0, .27))
        bags.cyl(top, .06, .02, .09, WHITE, sides=6, bevel=0.0)
        v.mat("424b44").sphere(top + Vector((0, 0, .1)), (.04, .035, .04), WHITE, subdiv=1, jitter=.01, seed=i)
    return v.build(emissive="")


MODELS = [pallet, pallet_stack, crate, barrel, bin, barrier, dumpster, trash_bags]


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    groups = [factory() for factory in MODELS]
    bpy.ops.object.select_all(action="DESELECT")
    for objects in groups:
        for obj in objects:
            obj.select_set(True)
            print(f"[editor] {obj.name}: {sum(len(p.vertices) - 2 for p in obj.data.polygons)} triângulos")
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, "editor_props.glb"), export_format="GLB", use_selection=True,
        export_texcoords=True, export_normals=True, export_tangents=False, export_materials="NONE",
        export_vertex_color="NONE", export_yup=True, export_apply=True)
    offset = 0.0
    for objects in groups:
        width = max(o.dimensions.x for o in objects) + .8
        for obj in objects:
            obj.location.x += offset + width / 2
        offset += width
    os.makedirs(os.path.join(OUT_DIR, "source"), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "source", "editor_props.blend"), compress=True)


main()
