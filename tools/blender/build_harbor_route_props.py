"""Adereços das zonas do porto (HarborRouteProps) modelados no Blender.

Rodar (sem abrir a interface):
    D:/Blender/blender.exe -b --factory-startup --python tools/blender/build_harbor_route_props.py

Gera assets/city_props/harbor_route_props.glb (o que o jogo lê) e
source/harbor_route_props.blend (para retocar à mão). As ferramentas de montagem vêm de
build_city_props.py.

Diferente do kit da cidade, estas peças usam os materiais texturizados do porto
(HarborRouteMaterials: triplanar em espaço de mundo, com relevo). Por isso:
- cada variante sai com um objeto por material, "<Variante>_mat_<função do material>";
  o jogo cria um MeshInstance3D por objeto com aquele material, como a procedural fazia;
- a exportação leva UV (o Godot gera as tangentes na importação), sem cor de vértice e
  sem material: assim o formato de vértice fica igual ao das CylinderMesh e BoxMesh
  antigas e os materiais já compilados servem sem variante nova;
- a parte que acende à noite (lente, globos, lâmpada) sai com a origem no centro dela,
  porque o CityChunkDressing mede a altura da luz pela posição desse nó.

Medidas, origem no chão e direções iguais às da versão procedural: braço do poste para
+X, frente das peças para +Z no jogo (-Y aqui).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_city_props import OUT_DIR, Prop, at  # noqa: E402

WHITE = (1.0, 1.0, 1.0, 1.0)


class Variant:
    """Uma variante: um Prop por material, montados juntos e exportados separados."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.props: dict = {}

    def mat(self, material: str, smooth_angle: float = 35.0) -> Prop:
        if material not in self.props:
            self.props[material] = Prop(f"{self.name}_mat_{material}", smooth_angle)
        return self.props[material]

    def build(self, emissive: str = "lamp_emissive") -> list:
        objects = []
        for material, prop in self.props.items():
            obj = prop.build(color_attribute=False)
            if material == emissive:
                # Origem no centro da peça que acende: o jogo mede a altura da luz por ela.
                center = sum((obj.matrix_world @ Vector(c) for c in obj.bound_box), Vector()) / 8
                obj.data.transform(Matrix.Translation(-center))
                obj.location = center
            objects.append(obj)
        return objects


def streetlight_standard() -> list:
    # create_streetlight(5.4, 1.35, "standard"): haste de aço, braço curvo e cabeça cobra.
    h, arm = 5.4, 1.35
    v = Variant("StreetLightStandard")
    steel = v.mat("steel_galvanized")
    steel.cyl(at(0, 0), .24, .24, .05, WHITE, sides=16, bevel=.01)
    steel.cyl(at(0, .05), .22, .16, .5, WHITE, sides=16, bevel=.01)
    steel.cyl(at(0, .55), .17, .17, .04, WHITE, sides=16, bevel=.008)
    steel.cyl(at(0, .59), .13, .08, h - .59, WHITE, sides=16, bevel=0.0)
    steel.sphere(at(0, h), (.085, .06, .085), WHITE, subdiv=2, flatten_below=h)
    curve = [at(-.0, h - .5 + math.sin(t / 8 * math.pi / 2) * .45, 0) + Vector(((1 - math.cos(t / 8 * math.pi / 2)) * .45, 0, 0))
             for t in range(9)]
    curve.append(at(arm - .25, h - .02, 0))
    steel.tube(curve, .04, WHITE)
    steel.box(at(arm, h - .04, 0), (.6, .1, .26), WHITE, bevel=.04)
    steel.box(at(arm - .05, h + .02, 0), (.4, .05, .18), WHITE, bevel=.02)
    v.mat("lamp_emissive").box(at(arm + .02, h - .1, 0), (.44, .025, .19), WHITE, bevel=.01)
    return v.build()


def streetlight_police() -> list:
    # create_streetlight(4.8, ..., "police"): ferro fundido, base azul e dois globos.
    h = 4.8
    v = Variant("StreetLightPolice")
    navy, iron = v.mat("police_navy"), v.mat("cast_iron_dark")
    navy.cyl(at(0, 0), .26, .26, .06, WHITE, sides=8, bevel=.012)
    navy.cyl(at(0, .06), .22, .17, .42, WHITE, sides=8, bevel=.012)
    navy.cyl(at(0, .48), .19, .19, .07, WHITE, sides=8, bevel=.01)
    iron.cyl(at(0, .55), .11, .075, h - .75, WHITE, sides=12, bevel=0.0)
    for y in (1.2, 2.6):
        iron.cyl(at(0, y), .1, .1, .05, WHITE, sides=12, bevel=.01)
    iron.box(at(0, h - .15, 0), (1.42, .07, .07), WHITE, bevel=.02)
    # Volutas sob o braço e suportes dos globos.
    for side in (-1, 1):
        scroll = [at(side * (.08 + .5 * math.sin(t / 8 * math.pi / 2)), h - .55 + .4 * (t / 8) ** 1.6, 0) for t in range(9)]
        iron.tube(scroll, .02, WHITE, sides=8)
        iron.cyl(at(side * .6, h - .12), .05, .07, .06, WHITE, sides=12, bevel=.008)
        iron.cyl(at(side * .6, h + .29), .09, .03, .08, WHITE, sides=12, bevel=.006)
        iron.sphere(at(side * .6, h + .4), (.025, .025, .025), WHITE, subdiv=1)
    iron.cyl(at(0, h - .2), .07, .04, .12, WHITE, sides=12)
    iron.sphere(at(0, h - .02), (.05, .07, .05), WHITE, subdiv=2)
    glow = v.mat("lamp_emissive", smooth_angle=80.0)
    for side in (-1, 1):
        glow.sphere(at(side * .6, h + .1), (.18, .2, .18), WHITE, subdiv=2)
    return v.build()


def streetlight_industrial() -> list:
    # create_streetlight(5.2, ..., "industrial"): base quadrada pesada, pescoço e cúpula.
    h = 5.2
    v = Variant("StreetLightIndustrial")
    iron = v.mat("cast_iron_dark")
    iron.box(at(0, .25, 0), (.46, .5, .46), WHITE, bevel=.03)
    iron.box(at(0, .53, 0), (.36, .06, .36), WHITE, bevel=.015)
    iron.cyl(at(0, .56), .1, .085, h - .76, WHITE, sides=12, bevel=0.0)
    neck = [at(0, h - .2, 0)]
    for t in range(1, 9):
        a = t / 8 * math.pi / 2
        neck.append(at(math.sin(a) * .45, h - .2 + (1 - math.cos(a)) * 0 + math.sin(a * 2) * .12, 0))
    neck.append(at(.7, h - .3, 0))
    iron.tube(neck, .045, WHITE)
    iron.cyl(at(.7, h - .5), .28, .08, .22, WHITE, sides=20, bevel=.01)
    iron.cyl(at(.7, h - .29), .05, .05, .06, WHITE, sides=12)
    v.mat("lamp_emissive", smooth_angle=80.0).sphere(at(.7, h - .56), (.1, .1, .1), WHITE, subdiv=2)
    return v.build()


def bollard(style: str) -> list:
    # create_bollard(style), altura 0,88 e raio 0,11.
    h, r = .88, .11
    main = {"civic": "cast_iron_dark", "police": "police_navy", "hazard": "hazard_yellow"}[style]
    v = Variant("Bollard" + style.capitalize())
    body, iron = v.mat(main), v.mat("cast_iron_dark")
    iron.cyl(at(0, 0), r * 1.45, r * 1.35, .06, WHITE, sides=16, bevel=.01)
    body.cyl(at(0, .06), r * 1.08, r, h - .1, WHITE, sides=16, bevel=0.0)
    cap = iron if style == "hazard" else body
    cap.cyl(at(0, h - .04), r * 1.06, r * 1.06, .03, WHITE, sides=16, bevel=.006)
    cap.sphere(at(0, h - .01), (r, r * .7, r), WHITE, subdiv=2, flatten_below=h - .01)
    if style == "civic":
        # Caneluras: anéis finos que pegam luz no ferro escuro.
        for y in (.2, .62):
            body.cyl(at(0, y), r * 1.12, r * 1.12, .025, WHITE, sides=16, bevel=.005)
    else:
        band = v.mat("pavement_white" if style == "police" else "cast_iron_dark")
        band.cyl(at(0, h * .8 - .05), r * 1.05, r * 1.05, .1, WHITE, sides=16, bevel=0.0)
        if style == "hazard":
            band.cyl(at(0, h * .55 - .05), r * 1.06, r * 1.06, .06, WHITE, sides=16, bevel=0.0)
    return v.build()


def bench(length: float) -> list:
    # create_bench(length): três tábuas de assento, encosto, pés de ferro fundido.
    v = Variant("PublicBench" + str(length).replace(".", "_"))
    iron, wood = v.mat("cast_iron_dark"), v.mat("bench_wood")
    for i in range(4):
        wood.box(at(0, .44, -.16 + i * .105), (length, .035, .09), WHITE, bevel=.01)
    for i in range(3):
        y = .58 + i * .11
        wood.box(at(0, y, -.235 - (y - .58) * .18), (length, .085, .03), WHITE, bevel=.01,
                 rot=(math.radians(-10), 0, 0))
    for side in (-1, 1):
        x = side * (length * .5 - .12)
        iron.box(at(x, .21, .17), (.06, .42, .06), WHITE, bevel=.012, rot=(math.radians(-8), 0, 0))
        iron.box(at(x, .21, -.17), (.06, .42, .06), WHITE, bevel=.012, rot=(math.radians(8), 0, 0))
        iron.box(at(x, .025, 0), (.08, .05, .5), WHITE, bevel=.012)
        iron.box(at(x, .41, 0), (.07, .04, .46), WHITE, bevel=.01)
        iron.box(at(x, .64, -.25), (.06, .5, .05), WHITE, bevel=.012, rot=(math.radians(-10), 0, 0))
        iron.box(at(x, .64, -.02), (.07, .04, .44), WHITE, bevel=.012)
        iron.box(at(x, .53, .18), (.05, .2, .05), WHITE, bevel=.01)
    if length > 2.1:
        # Pé do meio nos bancos compridos (2,2 m), como os de praça.
        iron.box(at(0, .21, 0), (.05, .42, .05), WHITE, bevel=.01)
        iron.box(at(0, .41, 0), (.05, .03, .4), WHITE, bevel=.008)
    return v.build()


def trash_bin() -> list:
    # create_trash_bin(): poste, corpo e chapéu contra chuva.
    v = Variant("TrashBin")
    iron, metal = v.mat("cast_iron_dark"), v.mat("trash_bin_metal")
    iron.cyl(at(0, 0), .12, .12, .03, WHITE, sides=12, bevel=.006)
    iron.cyl(at(0, .03), .05, .04, .82, WHITE, sides=12, bevel=0.0)
    metal.cyl(at(0, .25), .19, .22, .6, WHITE, sides=20, bevel=.01)
    # Aros de reforço no cesto (ripas verticais sobravam embaixo, onde o cesto afina).
    for y, radius in ((.4, .2), (.62, .213)):
        metal.cyl(at(0, y), radius + .012, radius + .012, .03, WHITE, sides=20, bevel=.005)
    iron.cyl(at(0, .26), .2, .2, .03, WHITE, sides=20, bevel=.006)
    iron.cyl(at(0, .82), .235, .235, .03, WHITE, sides=20, bevel=.006)
    iron.sphere(at(0, .87), (.24, .09, .24), WHITE, subdiv=2, flatten_below=.87)
    iron.cyl(at(0, .85), .245, .245, .02, WHITE, sides=20, bevel=.004)
    return v.build()


def bike_rack(loops: int = 4, spacing: float = .85) -> list:
    # create_bike_rack(4, 0.85): alças em U invertido de tubo, presas num trilho.
    v = Variant(f"BikeRack{loops}")
    steel = v.mat("steel_galvanized")
    span = (loops - 1) * spacing
    for i in range(loops):
        x0 = -span / 2 + i * spacing
        points = [at(x0 - .28, 0, 0), at(x0 - .28, .62, 0)]
        for t in range(1, 8):
            a = math.pi - t / 8 * math.pi
            points.append(at(x0 + math.cos(a) * .28, .62 + math.sin(a) * .18, 0))
        points += [at(x0 + .28, .62, 0), at(x0 + .28, 0, 0)]
        steel.tube(points, .032, WHITE, sides=12)
        for leg in (-.28, .28):
            steel.cyl(at(x0 + leg, 0), .06, .06, .015, WHITE, sides=12, bevel=.004)
    steel.box(at(0, .035, 0), (span + .7, .04, .06), WHITE, bevel=.012)
    return v.build()


def fire_hydrant() -> list:
    # create_fire_hydrant(): corpo vermelho, bocais e porca de latão.
    v = Variant("FireHydrant")
    red, brass = v.mat("hydrant_red"), v.mat("hydrant_brass")
    red.cyl(at(0, 0), .17, .17, .05, WHITE, sides=12, bevel=.01)
    red.cyl(at(0, .05), .15, .13, .4, WHITE, sides=16, bevel=0.0)
    red.cyl(at(0, .26), .145, .145, .035, WHITE, sides=16, bevel=.006)
    red.cyl(at(0, .45), .15, .15, .05, WHITE, sides=16, bevel=.01)
    red.sphere(at(0, .5), (.14, .1, .14), WHITE, subdiv=2, flatten_below=.5)
    brass.cyl(at(0, .59), .04, .035, .07, WHITE, sides=5, bevel=.004)
    for outlet, cap in ((-.21, -.25), (.13, .21)):
        red.cyl(at(outlet, .35), .05, .05, .08, WHITE, sides=12, axis="X")
        brass.cyl(at(cap, .35), .058, .058, .04, WHITE, sides=12, axis="X")
    brass.box(at(-.27, .35, 0), (.02, .03, .03), WHITE, bevel=.004)
    brass.box(at(.27, .35, 0), (.02, .03, .03), WHITE, bevel=.004)
    return v.build()


def planter_box(size=(1.8, .45, .85)) -> list:
    # create_planter_box(Vector3(1.8, 0.45, 0.85)): muro de pedra, terra e arbustos.
    sx, sy, sz = size
    v = Variant("PlanterBox")
    stone, soil = v.mat("planter_stone"), v.mat("workshop_apron")
    leaves = v.mat("shrub_foliage", smooth_angle=50.0)
    stone.box(at(0, sy / 2 - .02, 0), (sx - .04, sy - .04, sz - .04), WHITE, bevel=.03)
    stone.box(at(0, sy - .02, 0), (sx, .06, sz), WHITE, bevel=.02)
    stone.box(at(0, .03, 0), (sx + .02, .06, sz + .02), WHITE, bevel=.015)
    soil.box(at(0, sy - .01, 0), (sx - .18, .04, sz - .18), WHITE, bevel=0.0)
    # Duas moitas (como a procedural) feitas de tufos pequenos e tortos.
    for cx in (-sx * .24, sx * .24):
        for k in range(14):
            a = k * 2.4
            dist = .3 * math.sqrt(k / 14)
            jitter = noise.noise_vector(Vector((cx, k * 1.7, .3))) * .04
            size_k = .1 + .03 * (k % 3)
            y = sy + .08 + (.22 - dist * .45) * (.6 + .4 * ((k * 7) % 5) / 4)
            leaves.sphere(at(cx + math.cos(a) * dist * 1.1 + jitter.x, y, math.sin(a) * dist * .8 + jitter.y),
                          (size_k, size_k * .85, size_k), WHITE, subdiv=1, jitter=.025, seed=k + cx,
                          flatten_below=sy)
    return v.build()


def drain_grate(size=(.85, .45)) -> list:
    # create_drain_grate(): moldura de ferro e barras, rente ao asfalto.
    sx, sz = size
    v = Variant("DrainGrate")
    iron = v.mat("drain_grate")
    iron.box(at(0, .008, 0), (sx, .016, sz), WHITE, bevel=.004)
    for z in (-sz / 2 + .025, sz / 2 - .025):
        iron.box(at(0, .022, z), (sx, .014, .05), WHITE, bevel=.004)
    for x in (-sx / 2 + .025, sx / 2 - .025):
        iron.box(at(x, .022, 0), (.05, .014, sz), WHITE, bevel=.004)
    bars = 7
    for i in range(bars):
        x = -sx / 2 + .06 + i * (sx - .12) / (bars - 1)
        iron.box(at(x, .024, 0), (.03, .018, sz - .08), WHITE, bevel=.004)
    iron.box(at(0, .024, 0), (sx - .1, .016, .03), WHITE, bevel=.004)
    return v.build(emissive="")


VARIANTS = [streetlight_standard, streetlight_police, streetlight_industrial,
            lambda: bollard("civic"), lambda: bollard("police"), lambda: bollard("hazard"),
            lambda: bench(2.0), lambda: bench(2.2), trash_bin, bike_rack, fire_hydrant,
            planter_box, drain_grate]


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    groups = [factory() for factory in VARIANTS]
    bpy.ops.object.select_all(action="DESELECT")
    for objects in groups:
        for obj in objects:
            obj.select_set(True)
            tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
            print(f"[harbor_props] {obj.name}: {tris} triângulos")
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, "harbor_route_props.glb"),
        export_format="GLB",
        use_selection=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_materials="NONE",
        export_vertex_color="NONE",
        export_yup=True,
        export_apply=True,
    )
    # No .blend, as variantes ficam lado a lado para dar para ver e editar.
    offset = 0.0
    for objects in groups:
        width = max(max(abs(Vector(c).x) for c in o.bound_box) * 2 for o in objects) + .8
        for obj in objects:
            obj.location.x += offset + width / 2
        offset += width
    os.makedirs(os.path.join(OUT_DIR, "source"), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "source", "harbor_route_props.blend"), compress=True)


# Só monta quando rodado direto: outros scripts importam as ferramentas daqui.
if __name__ == "__main__":
    main()
