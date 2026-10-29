"""Terceira onda de adereços da cidade (kit CityPropKit) modelados no Blender.

Rodar (sem abrir a interface), um lote ou todos:
    D:/Blender/blender.exe -b --factory-startup --python tools/blender/build_city_props_wave3.py -- [calcada|sinal|telhado|fachada]

Cada lote gera assets/city_props/wave3_<lote>.glb, e todos juntos vão para
source/city_props_wave3.blend. As regras são as de build_city_props.py: mesmo envelope,
origem e frente (+Z no jogo, -Y aqui) da versão procedural; sem UV, tangente nem material;
cor de vértice crua em sRGB. Camadas (árvore, vaso) saem como "<tipo>__<ordem>_<camada>",
e o CityPropsImport.gd junta tudo na importação.

Cores que mudam por cópia: as partes "pintáveis" saem em PAINT (cinza bem claro) e o jogo
multiplica pela cor da paleta de CityPropKit.VARIATION. Metal, borracha e madeira saem na
cor de verdade, escura, e quase não mudam com a tinta.
"""
import math
import os
import sys

import bpy
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_city_props import OUT_DIR, Prop, at, hex_color  # noqa: E402

PAINT = hex_color("ececec")
PAINT_SHADE = hex_color("cfcfcf")
STEEL = hex_color("8a9396")
DARK = hex_color("2b2f31")
RUBBER = hex_color("1a1b1c")
WOOD = hex_color("8a6a44")
WOOD_DARK = hex_color("5e4a33")
CRATE = hex_color("9a7a4f")


class Kit(Prop):
    def bar(self, a: Vector, b: Vector, radius: float, color, sides: int = 8) -> None:
        self.tube([a, b], radius, color, sides)

    def torus(self, center: Vector, major: float, minor: float, color, axis: str = "X",
              segments: int = 18, ring: int = 6) -> None:
        rot = {"X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
        bpy.ops.mesh.primitive_torus_add(major_segments=segments, minor_segments=ring, major_radius=major,
                                         minor_radius=minor, location=center, rotation=rot)
        self._finish_part(bpy.context.active_object, color, 0.0)

    def wheel(self, hub: Vector, radius: float, width: float, color=RUBBER, rim=STEEL) -> None:
        """Roda de frente para X (gira em torno do eixo Z do jogo = -Y aqui)."""
        self.torus(hub, radius - width * .5, width * .5, color, axis="Y", segments=16, ring=6)
        self.cyl(hub + Vector((0, width * .3, 0)), radius * .35, radius * .35, width * .6, rim, sides=12,
                 axis="Y", bevel=.004)


def tones(base: str, count: int, spread: float = .06) -> list:
    """Variações leves de um tom, para tábuas, caixas e folhas não saírem idênticas."""
    color = hex_color(base)
    out = []
    for i in range(count):
        k = 1.0 + spread * (((i * 7) % 5) / 2.0 - 1.0)
        out.append(tuple(min(1.0, c * k) for c in color[:3]) + (1.0,))
    return out


# ================================================================================
# Lote "calçada"
# ================================================================================

def _chair(p: Kit, base: Vector, yaw: float, color=PAINT) -> None:
    # Cadeira de bar empilhável: assento com borda, encosto vazado e quatro pés.
    c, s = math.cos(yaw), math.sin(yaw)
    def local(x, y, z):
        return base + Vector((x * c + z * s, -(-x * s + z * c), y))
    p.box(local(0, .44, 0), (.42, .04, .42), color, bevel=.012, rot=(0, 0, yaw))
    p.box(local(0, .62, .19), (.42, .06, .035), color, bevel=.01, rot=(0, 0, yaw))
    p.box(local(0, .8, .19), (.42, .08, .035), color, bevel=.012, rot=(0, 0, yaw))
    for x in (-.18, .18):
        p.box(local(x, .7, .19), (.035, .26, .03), color, bevel=.008, rot=(0, 0, yaw))
        for z in (-.18, .18):
            p.box(local(x, .21, z), (.032, .42, .032), PAINT_SHADE, bevel=.008, rot=(0, 0, yaw))


def _table(p: Kit, center: Vector, chairs: list) -> None:
    p.cyl(center, .22, .2, .03, STEEL, sides=12, bevel=.006)
    p.cyl(center + Vector((0, 0, .03)), .035, .03, .69, STEEL, sides=8, bevel=0.0)
    p.cyl(center + Vector((0, 0, .72)), .4, .4, .03, hex_color("f2efe6"), sides=24, bevel=.01)
    for angle in chairs:
        _chair(p, center + Vector((math.sin(angle) * .62, -math.cos(angle) * .62, 0)), angle)


def cafe_set() -> list:
    p = Kit("cafe_set")
    _table(p, at(0, 0), [math.pi * .5, -math.pi * .5, math.pi])
    p.box(at(.55, .15, -.5), (.4, .3, .3), hex_color("c9a634"), bevel=.015, rot=(0, 0, .2))
    p.box(at(.55, .29, -.5), (.34, .02, .24), hex_color("3b2a1c"), bevel=0.0, rot=(0, 0, .2))
    return [p.build()]


def _umbrella(p: Kit, rim: Vector, radius: float, rise: float, segments: int = 8) -> None:
    # Copa em gomos alternando dois tons de "tinta" (a paleta pinta os dois) e aba curta.
    for i in range(segments):
        a0, a1 = math.tau * i / segments, math.tau * (i + 1) / segments
        color = PAINT if i % 2 == 0 else hex_color("f7f4ec")
        mesh = bpy.data.meshes.new("Gomo")
        apex = rim + Vector((0, 0, rise))
        p0 = rim + Vector((math.cos(a0) * radius, math.sin(a0) * radius, 0))
        p1 = rim + Vector((math.cos(a1) * radius, math.sin(a1) * radius, 0))
        mid = (p0 + p1) / 2
        mid.z += rise * .12
        d0, d1 = p0 - Vector((0, 0, radius * .11)), p1 - Vector((0, 0, radius * .11))
        verts = [apex, p0, mid, p1, d0, d1]
        faces = [(0, 1, 2), (0, 2, 3), (1, 4, 5, 3, 2)]
        mesh.from_pydata(verts, [], [(0, 1, 2), (0, 2, 3), (4, 5, 3, 1)])
        obj = bpy.data.objects.new("Gomo", mesh)
        bpy.context.scene.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        sol = obj.modifiers.new("Espessura", "SOLIDIFY")
        sol.thickness = .015
        p._finish_part(obj, color, 0.0)
    p.cyl(rim + Vector((0, 0, rise - .02)), .04, .01, .08, STEEL, sides=8, bevel=0.0)


def _parasol(name: str) -> list:
    p = Kit(name)
    _table(p, at(0, 0), [math.pi * .5, -math.pi * .5])
    p.cyl(at(0, .75), .02, .02, 1.6, hex_color("cfcfc8"), sides=8, bevel=0.0)
    for k in range(8):
        a = math.tau * k / 8
        p.bar(at(0, 1.85) , at(math.cos(a) * .9, 2.03, math.sin(a) * .9), .008, STEEL, sides=4)
    _umbrella(p, at(0, 2.05), 1.25, .4)
    return [p.build()]


def cafe_parasol() -> list:
    return _parasol("cafe_parasol")


def cafe_parasol_b() -> list:
    # Mesmo envelope, guarda-sol de 6 gomos e mesa um pouco mais alta.
    p = Kit("cafe_parasol_b")
    _table(p, at(0, 0), [math.pi * .5, -math.pi * .5])
    p.cyl(at(0, .75), .025, .025, 1.6, hex_color("cfcfc8"), sides=8, bevel=0.0)
    _umbrella(p, at(0, 2.08), 1.25, .34, segments=6)
    p.cyl(at(0, 2.42), .05, .05, .06, PAINT, sides=8, bevel=.01)
    return [p.build()]


def produce_stand() -> list:
    p = Kit("produce_stand")
    for x in (-.75, .75):
        for z in (-.32, .32):
            p.box(at(x, .36, z), (.05, .72, .05), WOOD_DARK, bevel=.01)
    p.box(at(0, .74, 0), (1.7, .04, .8), WOOD, bevel=.01)
    p.box(at(0, 1.1, -.36), (1.7, .04, .04), WOOD_DARK, bevel=.008)
    for x in (-.8, .8):
        p.box(at(x, .92, -.36), (.04, .4, .04), WOOD_DARK, bevel=.008)
    fruit = ["e0862a", "c0392b", "86ad3c", "e3c53a", "7b3f6e", "d9692b"]
    for row in range(2):
        for column in range(3):
            cx, cy, cz = -.55 + column * .55, .88 + row * .16, .16 - row * .34
            p.box(at(cx, cy, cz), (.5, .12, .32), CRATE, bevel=.01, rot=(math.radians(-12), 0, 0))
            for k in range(6):
                j = noise.noise_vector(Vector((column, row, k))) * .04
                p.sphere(at(cx - .16 + (k % 3) * .16 + j.x, cy + .08, cz - .06 + (k // 3) * .12 + j.y),
                         (.06, .055, .06), hex_color(fruit[(row * 3 + column) % 6]), subdiv=1)
    for i in range(3):
        p.box(at(-.45 + i * .45, .14, -.05), (.42, .28, .32), CRATE, bevel=.01, rot=(0, 0, .05 * (i - 1)))
    return [p.build()]


def a_frame() -> list:
    p = Kit("a_frame")
    for side in (-1, 1):
        tilt = (math.radians(14 * side), 0, 0)
        p.box(at(0, .45, .11 * side), (.58, .9, .03), WOOD, bevel=.008, rot=tilt)
        p.box(at(0, .47, .125 * side), (.48, .74, .01), hex_color("2b302d"), bevel=0.0, rot=tilt)
        for line in range(4):
            width = .34 - (line % 2) * .12
            color = hex_color("e3b54a") if line == 0 else hex_color("e8e4d6")
            p.box(at(-.04 + (line % 2) * .03, .68 - line * .12, (.135 + line * .03 * .24) * side), (width, .025, .006),
                  color, bevel=0.0, rot=tilt)
    p.box(at(0, .9, 0), (.6, .04, .05), WOOD_DARK, bevel=.01)
    return [p.build()]


def beer_crates() -> list:
    p = Kit("beer_crates")
    spots = [(-.22, 0, 0), (.22, 0, 0), (-.22, .3, 0), (.2, .3, .02)]
    for i, (x, y, z) in enumerate(spots):
        yaw = .06 * (i % 3 - 1)
        p.box(at(x, y + .15, z), (.42, .29, .31), PAINT, bevel=.015, rot=(0, 0, yaw))
        p.box(at(x, y + .29, z), (.36, .01, .25), hex_color("3b2a1c"), bevel=0.0, rot=(0, 0, yaw))
        # Garrafas aparecendo na boca do engradado.
        for k in range(6):
            p.cyl(at(x - .12 + (k % 3) * .12, y + .2, z - .06 + (k // 3) * .12), .028, .02, .12,
                  hex_color("5a3a1a"), sides=6, bevel=0.0)
        p.box(at(x, y + .2, z + .156), (.2, .05, .01), RUBBER, bevel=0.0, rot=(0, 0, yaw))
    return [p.build()]


def wheelie_bins() -> list:
    p = Kit("wheelie_bins")
    for i in range(2):
        x, yaw = -.34 + i * .68, .08 * (i * 2 - 1)
        p.box(at(x, .5, .01), (.56, .86, .6), PAINT, bevel=.03, rot=(math.radians(-2), 0, yaw))
        p.box(at(x, .96, -.01), (.6, .05, .7), PAINT_SHADE, bevel=.02, rot=(math.radians(-3), 0, yaw))
        p.box(at(x, .92, -.36), (.5, .04, .05), DARK, bevel=.01, rot=(0, 0, yaw))
        for side in (-.22, .22):
            p.wheel(at(x + side, .08, -.28), .08, .05)
        p.box(at(x, .55, .31), (.3, .2, .01), PAINT_SHADE, bevel=.004, rot=(0, 0, yaw))
    return [p.build()]


def _bike(p: Kit, base: Vector, paint=PAINT) -> None:
    for wx in (-.52, .52):
        p.wheel(base + Vector((wx, 0, .34)), .33, .035)
    pts = {"rear": (-.52, .34), "crank": (0, .38), "head": (.4, .72), "seat": (-.15, .72), "front": (.52, .34)}
    def v(name):
        x, y = pts[name]
        return base + Vector((x, 0, y))
    for a, b in (("rear", "crank"), ("crank", "head"), ("seat", "head"), ("seat", "crank"), ("rear", "seat"), ("head", "front")):
        p.bar(v(a), v(b), .018, paint)
    p.box(base + Vector((-.17, 0, .8)), (.22, .05, .09), RUBBER, bevel=.015)
    p.bar(base + Vector((-.15, 0, .72)), base + Vector((-.17, 0, .79)), .012, STEEL)
    p.bar(base + Vector((.4, 0, .72)), base + Vector((.42, 0, .86)), .014, STEEL)
    p.bar(base + Vector((.42, -.25, .86)), base + Vector((.42, .25, .86)), .012, DARK)
    p.cyl(base + Vector((0, .02, .38)), .07, .07, .02, STEEL, sides=12, axis="Y", bevel=0.0)


def bike_rack() -> list:
    p = Kit("bike_rack")
    for x in (-.9, 0, .9):
        pts = [at(x - .32, 0), at(x - .32, .62)]
        for t in range(1, 8):
            a = math.pi - t / 8 * math.pi
            pts.append(at(x + math.cos(a) * .32, .62 + math.sin(a) * .18))
        pts += [at(x + .32, .62), at(x + .32, 0)]
        p.tube(pts, .025, STEEL, sides=10)
    _bike(p, at(-.45, 0, .18))
    _bike(p, at(.5, 0, -.16), hex_color("c63a2f"))
    return [p.build()]


def pallet_stack() -> list:
    p = Kit("pallet_stack")
    for i in range(4):
        y, yaw = i * .15, .05 * (((i * 3) % 5) - 2)
        for x in (-.5, 0, .5):
            p.box(at(x, y + .055, 0), (.12, .11, 1.0), hex_color("6f5236"), bevel=.006, rot=(0, 0, yaw))
        for k, z in enumerate((-.42, -.21, 0, .21, .42)):
            p.box(at(0, y + .125, z), (1.2, .025, .13), tones("b39466", 5)[k], bevel=.004, rot=(0, 0, yaw))
    return [p.build()]


def tire_stack() -> list:
    p = Kit("tire_stack", smooth_angle=60.0)
    for (sx, sz), count in (((-.36, 0), 4), ((.38, .05), 2)):
        for i in range(count):
            center = at(sx + .02 * (i % 2), .105 + i * .215, sz)
            p.torus(center, .22, .1, RUBBER, axis="Z", segments=20, ring=8)
            p.cyl(center - Vector((0, 0, .1)), .13, .13, .2, hex_color("0c0d0e"), sides=12, bevel=0.0)
    return [p.build()]


def drums() -> list:
    p = Kit("drums")
    for (x, z), color in (((-.33, 0), PAINT), ((.32, -.05), PAINT_SHADE), ((0, .25), PAINT)):
        p.cyl(at(x, 0, z), .28, .28, .86, color, sides=18, bevel=.012)
        for y in (.28, .58):
            p.cyl(at(x, y, z), .292, .292, .03, color, sides=18, bevel=.006)
        p.cyl(at(x, .86, z), .25, .25, .005, hex_color("3a3a3a"), sides=18, bevel=0.0)
        p.cyl(at(x + .12, .865, z), .035, .035, .02, DARK, sides=8, bevel=0.0)
    return [p.build()]


def food_cart() -> list:
    p = Kit("food_cart")
    p.box(at(0, .62, 0), (1.3, .5, .65), hex_color("b9bec0"), bevel=.025)
    p.box(at(0, .9, 0), (1.36, .05, .7), hex_color("8d9294"), bevel=.015)
    p.box(at(0, .62, .33), (1.1, .3, .01), PAINT, bevel=.004)
    for x in (-.25, .25):
        p.box(at(x, .97, .05), (.36, .08, .26), hex_color("d9d6cc"), bevel=.015)
    for side in (-.36, .36):
        p.wheel(at(-.3, .22, side), .22, .06)
    p.box(at(.45, .2, 0), (.05, .4, .05), STEEL, bevel=.008)
    for z in (-.25, .25):
        p.bar(at(.65, .8, z), at(1.0, .85, z), .015, STEEL)
    p.bar(at(1.0, .85, -.25), at(1.0, .85, .25), .018, RUBBER)
    p.cyl(at(.2, .93), .02, .02, 1.15, hex_color("cfcfc8"), sides=8, bevel=0.0)
    _umbrella(p, at(.2, 2.05), .95, .3)
    return [p.build()]


def ice_freezer() -> list:
    p = Kit("ice_freezer")
    p.box(at(0, .42, 0), (1.1, .78, .62), hex_color("e8ebe9"), bevel=.04)
    p.box(at(0, .82, 0), (1.04, .03, .56), hex_color("3a5566"), bevel=.01)
    for x in (-.26, .26):
        # Tampa 6 mm acima da moldura (topo 0,835): coplanar, piscava em listras no jogo.
        p.box(at(x, .846, .02), (.48, .01, .5), hex_color("9fb6c2"), bevel=.003)
    p.box(at(0, .55, .315), (1.0, .22, .01), PAINT, bevel=.004)
    for x in (-.45, .45):
        for z in (-.24, .24):
            p.wheel(at(x, .03, z), .03, .03, RUBBER, DARK)
    return [p.build()]


def clothes_rack() -> list:
    p = Kit("clothes_rack")
    for x in (-.7, .7):
        p.cyl(at(x, .05), .018, .018, 1.43, STEEL, sides=8, bevel=0.0)
        p.box(at(x, .03, 0), (.06, .04, .5), STEEL, bevel=.01)
        for z in (-.22, .22):
            p.wheel(at(x, .03, z), .03, .02, RUBBER, DARK)
    p.bar(at(-.7, 1.48), at(.7, 1.48), .016, STEEL)
    cloth = ["c0392b", "2e6fb0", "e3c53a", "2f2f33", "d27aa6", "4f8a5b", "e8e4d6", "7b3f6e"]
    for i in range(9):
        x = -.6 + i * .15
        length = .75 + .2 * ((i * 5) % 3)
        p.bar(at(x, 1.48), at(x, 1.42), .006, STEEL, sides=4)
        p.box(at(x, 1.42 - length * .5, 0), (.05, length, .42), hex_color(cloth[i % 8]), bevel=.015,
              rot=(0, 0, .06 * (i % 3 - 1)))
        p.box(at(x, 1.4, 0), (.07, .06, .44), hex_color(cloth[i % 8]), bevel=.02)
    return [p.build()]


def flower_buckets() -> list:
    p = Kit("flower_buckets", smooth_angle=60.0)
    flowers = ["d8354a", "f2c230", "e98bb7", "f2efe6", "8e5bc2", "e8722a"]
    spots = [(-.5, .05), (-.17, -.08), (.17, .08), (.5, -.05), (-.33, .2), (.33, .22)]
    for i, (x, z) in enumerate(spots):
        height = .38 if i < 4 else .26
        p.cyl(at(x, 0, z), .12, .155, height, PAINT, sides=12, bevel=.008)
        p.cyl(at(x, height - .02, z), .158, .158, .025, PAINT_SHADE, sides=12, bevel=.004)
        for k in range(5):
            a = k * 1.3 + i
            p.sphere(at(x + math.cos(a) * .06, height + .06, z + math.sin(a) * .06), (.07, .07, .07),
                     hex_color("4c6a3c"), subdiv=1, jitter=.015, seed=i + k)
        for k in range(6):
            a = k * 1.05 + i * .7
            p.sphere(at(x + math.cos(a) * .07, height + .2 + .03 * (k % 2), z + math.sin(a) * .07),
                     (.045, .035, .045), hex_color(flowers[i % 6]), subdiv=1, jitter=.01, seed=i * 7 + k)
    return [p.build()]


def gas_cylinders() -> list:
    p = Kit("gas_cylinders")
    for i in range(3):
        x, z = -.36 + i * .36, .02 * (i % 2)
        p.cyl(at(x, 0, z), .15, .16, .06, DARK, sides=12, bevel=.006)
        p.cyl(at(x, .06, z), .17, .17, .34, PAINT if i != 1 else PAINT_SHADE, sides=16, bevel=.01)
        p.sphere(at(x, .4, z), (.17, .09, .17), PAINT if i != 1 else PAINT_SHADE, subdiv=2, flatten_below=.4)
        p.cyl(at(x, .47, z), .09, .09, .1, DARK, sides=10, bevel=.006)
        p.box(at(x, .6, z), (.05, .05, .05), hex_color("d8a62a"), bevel=.008)
        p.torus(at(x, .55, z), .07, .012, DARK, axis="Z", segments=12, ring=4)
    return [p.build()]


def door_bench() -> list:
    p = Kit("door_bench")
    for k in range(3):
        p.box(at(-.15, .44, -.11 + k * .11), (1.0, .045, .1), tones("8a6a44", 3)[k], bevel=.008)
    for x in (-.58, .28):
        p.box(at(x, .21, 0), (.05, .42, .3), hex_color("6a5034"), bevel=.008)
    p.cyl(at(.48, 0, .05), .13, .15, .4, hex_color("4e5458"), sides=10, bevel=.008)
    p.cyl(at(.48, .4, .05), .16, .16, .04, PAINT, sides=12, bevel=.01)
    return [p.build()]


def motorcycle() -> list:
    p = Kit("motorcycle")
    for wx in (-.68, .68):
        p.wheel(at(wx, .32), .32, .1)
        p.torus(at(wx, .32), .2, .012, STEEL, axis="Y", segments=16, ring=4)
    p.box(at(-.05, .5), (.62, .3, .22), DARK, bevel=.03)
    p.cyl(at(-.05, .38, -.12), .1, .1, .24, STEEL, sides=10, axis="Y", bevel=.01)
    p.sphere(at(.24, .82), (.27, .13, .16), PAINT, subdiv=2)
    p.box(at(-.3, .84), (.62, .08, .26), RUBBER, bevel=.03)
    p.box(at(-.66, .74), (.32, .07, .24), PAINT, bevel=.025, rot=(0, math.radians(-8), 0))
    p.bar(at(.5, .72), at(.68, .32), .025, STEEL)
    p.bar(at(.5, .72, -.06), at(.68, .32, -.06), .022, STEEL)
    p.bar(at(.5, .72), at(.42, 1.0), .02, STEEL)
    p.bar(at(.42, 1.02, -.33), at(.42, 1.02, .33), .016, DARK)
    p.sphere(at(.6, .86), (.07, .07, .07), hex_color("e8e4d6"), subdiv=2)
    p.bar(at(-.2, .36, -.13), at(-.75, .4, -.15), .035, STEEL)
    p.bar(at(-.05, .3, -.14), at(-.15, .02, -.36), .015, STEEL)
    p.box(at(.68, .62), (.32, .03, .16), PAINT, bevel=.01, rot=(0, math.radians(30), 0))
    return [p.build()]


def _trunk(p: Kit, height: float, lean: float) -> None:
    bark = hex_color("6b5440")
    p.cyl(at(0, 0), .2, .13, .25, bark, sides=10, bevel=0.0)
    pts = [at(0, .2), at(lean * .3, height * .5), at(lean, height)]
    p.tube(pts, .12, bark, sides=10)
    for k, (dx, dz, up) in enumerate(((.7, .2, .8), (-.6, -.3, .9), (.1, .7, .7), (-.2, -.7, .85))):
        start = at(lean, height - .1)
        p.tube([start, at(lean + dx * .5, height + up * .5, dz * .5), at(lean + dx, height + up, dz)], .05 - .004 * k,
               bark, sides=6)


def _crown(p: Kit, top: float, lobes: list, greens: list, seed: float) -> None:
    # Copa feita de muitos tufos: contorno recortado e luz entre eles, sem cara de pedra.
    for li, ((lx, ly, lz), radius) in enumerate(lobes):
        center = Vector((lx, -lz, top + ly))
        # Casca de tufos pequenos (facetados) e um miolo escuro que tapa os buracos.
        p.sphere(center, (radius * .72, radius * .62, radius * .72), hex_color("3b4a30"), subdiv=2,
                 jitter=radius * .08, seed=seed + li)
        count = int(26 * radius)
        for k in range(count):
            # Pontos espalhados na casca pela espiral de Fibonacci, com ruído.
            t = (k + .5) / count
            phi, theta = math.acos(1 - 2 * t), math.pi * (1 + 5 ** .5) * k
            d = Vector((math.sin(phi) * math.cos(theta), math.sin(phi) * math.sin(theta), math.cos(phi) * .8))
            d += noise.noise_vector(Vector((seed + li, k * .37, 1.1))) * .18
            size = radius * (.2 + .06 * (k % 3))
            p.sphere(center + d * radius * .78, (size, size * .85, size), hex_color(greens[(k + li) % len(greens)]),
                     subdiv=1, jitter=size * .3, seed=seed * 10 + li * 3 + k)


CROWN_GREENS = ["4f6340", "566b45", "48593b", "5c6e46", "4b5e3f"]


def street_tree() -> list:
    bark = Kit("street_tree__0_bark", smooth_angle=60.0)
    _trunk(bark, 2.9, .05)
    leaves = Kit("street_tree__1_leaves", smooth_angle=80.0)
    _crown(leaves, 3.75, [((-.62, 0, .05), 1.15), ((.55, .22, .12), 1.1), ((0, .5, -.4), 1.05), ((.08, -.08, .62), 1.0)],
           CROWN_GREENS, 1.0)
    return [bark.build(), leaves.build()]


def street_tree_b() -> list:
    bark = Kit("street_tree_b__0_bark", smooth_angle=60.0)
    _trunk(bark, 3.3, -.08)
    leaves = Kit("street_tree_b__1_leaves", smooth_angle=80.0)
    _crown(leaves, 4.2, [((-.3, 0, .1), 1.2), ((.35, .35, -.15), 1.15), ((-.05, .95, .05), .95)], CROWN_GREENS, 2.0)
    return [bark.build(), leaves.build()]


def pot_plant() -> list:
    pot = Kit("pot_plant__0_stone")
    pot.cyl(at(0, 0), .24, .32, .5, PAINT, sides=16, bevel=.01)
    pot.cyl(at(0, .5), .35, .35, .07, PAINT_SHADE, sides=16, bevel=.015)
    pot.cyl(at(0, .55), .3, .3, .015, hex_color("2a241e"), sides=16, bevel=0.0)
    leaves = Kit("pot_plant__1_leaves", smooth_angle=60.0)
    for k in range(14):
        a = k * 2.4
        dist = .2 * math.sqrt(k / 14)
        size = .09 + .02 * (k % 3)
        y = .6 + (.42 - dist * 1.4) * (.5 + .5 * ((k * 7) % 5) / 4)
        leaves.sphere(at(math.cos(a) * dist, y, math.sin(a) * dist), (size, size * 1.1, size),
                      hex_color(["37443b", "3f4b3e", "333f37", "454a39", "3a4636"][k % 5]), subdiv=1, jitter=.02,
                      seed=k * 1.3)
    return [pot.build(), leaves.build()]


# ================================================================================
# Lote "sinal": semáforo, placa de pare, tampa de bueiro, grelha, cerca viva
# ================================================================================

IRON = hex_color("2b2f31")
IRON_LIGHT = hex_color("3d4346")
POLE = hex_color("2d3437")


def signal_pole() -> list:
    # Haste e braço sobre a via (-X). A caixa do sinal fica onde estava: as lentes são
    # outra MultiMesh do CityChunkDressing, posta na frente dela (z ≈ 0,19).
    p = Kit("signal_pole")
    p.cyl(at(0, 0), .16, .16, .06, hex_color("3c4447"), sides=12, bevel=.01)
    p.cyl(at(0, .06), .14, .12, .3, hex_color("3c4447"), sides=12, bevel=.01)
    p.cyl(at(0, .36), .1, .085, 4.84, POLE, sides=12, bevel=0.0)
    p.sphere(at(0, 5.2), (.09, .05, .09), POLE, subdiv=2, flatten_below=5.2)
    p.cyl(at(-4.2, 5.05), .045, .07, 4.2, POLE, sides=10, axis="X", bevel=0.0)
    p.bar(at(-.05, 4.6), at(-1.4, 5.04), .03, POLE)
    p.box(at(-.05, 5.05), (.16, .2, .16), POLE, bevel=.02)
    # Caixa do sinal com pala em cima de cada lente.
    p.bar(at(-3.3, 5.04), at(-3.3, 5.1), .03, POLE)
    p.box(at(-3.3, 4.55, 0), (.36, 1.0, .3), hex_color("1f2426"), bevel=.03)
    p.box(at(-3.3, 4.55, .17), (.5, 1.14, .04), hex_color("15191a"), bevel=.01)
    for y in (4.88, 4.55, 4.22):
        p.box(at(-3.3, y + .12, .215), (.26, .02, .07), hex_color("15191a"), bevel=.004,
              rot=(math.radians(-15), 0, 0))
    # Placa com nome de rua e botoeira de pedestre.
    p.box(at(0, 3.2), (1.3, .26, .03), hex_color("1f6b3e"), bevel=.008)
    p.box(at(0, 3.2), (1.22, .18, .035), hex_color("2a8a50"), bevel=.004)
    p.box(at(0, 3.36), (.08, .08, .08), POLE, bevel=.01)
    p.box(at(.13, 1.1), (.1, .2, .12), hex_color("c9a634"), bevel=.015)
    p.cyl(at(.13, 1.12, .06), .025, .025, .015, hex_color("e8e4d6"), sides=10, axis="Y", bevel=0.0)
    return [p.build()]


def stop_sign() -> list:
    p = Kit("stop_sign")
    p.cyl(at(0, 0), .04, .035, 2.2, hex_color("8a9396"), sides=8, bevel=0.0)
    # Octógono de verdade, de pé, virado para +Z, com borda branca.
    p.cyl(at(0, 2.2, .03), .385, .385, .02, hex_color("f4f1e8"), sides=8, axis="Y", bevel=.003)
    p.cyl(at(0, 2.2, .045), .355, .355, .012, hex_color("c0231e"), sides=8, axis="Y", bevel=0.0)
    for x in (-.21, -.07, .07, .21):
        p.box(at(x, 2.2, .06), (.1, .13, .006), hex_color("f4f1e8"), bevel=0.0)
    for y in (2.05, 2.35):
        p.box(at(0, y, .0), (.06, .04, .05), hex_color("6c7274"), bevel=.006)
    return [p.build()]


def manhole() -> list:
    p = Kit("manhole")
    p.cyl(at(0, 0), .42, .42, .012, hex_color("2a2c2c"), sides=24, bevel=.003)
    p.cyl(at(0, .012), .36, .36, .008, hex_color("3d403f"), sides=24, bevel=.002)
    for r in (.12, .24):
        p.torus(at(0, .02), r, .012, hex_color("2a2c2c"), axis="Z", segments=24, ring=4)
    for k in range(6):
        a = math.tau * k / 6
        p.box(at(math.cos(a) * .18, .021, math.sin(a) * .18), (.2, .006, .025), hex_color("2a2c2c"), bevel=0.0,
              rot=(0, 0, a))
    return [p.build()]


def drain() -> list:
    p = Kit("drain")
    p.box(at(0, .006, 0), (.9, .012, .4), hex_color("2c2f30"), bevel=.003)
    p.box(at(0, .004, 0), (.82, .01, .32), hex_color("0b0d0e"), bevel=0.0)
    for k in range(9):
        p.box(at(-.36 + k * .09, .014, 0), (.035, .01, .32), hex_color("2c2f30"), bevel=.002)
    p.box(at(0, .016, 0), (.82, .008, .03), hex_color("2c2f30"), bevel=.002)
    return [p.build()]


HARBOR_LEAVES = ["37443b", "3f4b3e", "333f37", "454a39", "3a4636"]


def hedge() -> list:
    # Camada única "leaves" (textura de folhagem): fileira de tufos pequenos.
    p = Kit("hedge", smooth_angle=60.0)
    for k in range(44):
        x = -.72 + (k % 11) * .144 + noise.noise(Vector((k, .3, .1))) * .03
        row = k // 11
        z = -.12 + row * .08
        h = .1 + .07 * row + .03 * ((k * 7) % 3)
        size = .085 + .015 * (k % 3)
        p.sphere(at(x, h, z), (size, size * .9, size), hex_color(HARBOR_LEAVES[k % 5]), subdiv=1, jitter=.02,
                 seed=k * .7, flatten_below=0.0)
    return [p.build()]


# ================================================================================
# Lote "telhado"
# ================================================================================

def ac_unit() -> list:
    p = Kit("ac_unit")
    p.box(at(0, .05, 0), (1.3, .1, 1.0), hex_color("5a5f61"), bevel=.015)
    p.box(at(0, .45, 0), (1.2, .7, .9), PAINT, bevel=.03)
    for k in range(7):
        p.box(at(.605, .2 + k * .07, 0), (.02, .03, .72), hex_color("6c7274"), bevel=.004)
    p.cyl(at(-.2, .8), .3, .3, .04, hex_color("3a3f41"), sides=20, bevel=.006)
    p.torus(at(-.2, .845), .28, .015, hex_color("5a5f61"), axis="Z", segments=20, ring=4)
    for k in range(3):
        p.box(at(-.2, .85), (.5, .01, .06), hex_color("8a8f90"), bevel=0.0, rot=(0, 0, k * math.pi / 3))
    p.bar(at(-.5, .3, .45), at(-.5, .3, .52), .03, hex_color("6c7274"))
    return [p.build()]


def vent() -> list:
    p = Kit("vent")
    p.cyl(at(0, 0), .2, .2, .04, hex_color("7e8486"), sides=12, bevel=.006)
    p.cyl(at(0, .04), .15, .15, .62, hex_color("9aa0a2"), sides=14, bevel=0.0)
    p.cyl(at(0, .66), .2, .2, .03, hex_color("7e8486"), sides=14, bevel=.004)
    p.cyl(at(0, .7), .3, .08, .1, hex_color("7e8486"), sides=14, bevel=.006)
    for k in range(4):
        a = math.tau * k / 4 + .4
        p.bar(at(math.cos(a) * .14, .66, math.sin(a) * .14), at(math.cos(a) * .22, .72, math.sin(a) * .22), .01,
              hex_color("6c7274"), sides=4)
    return [p.build()]


def antenna() -> list:
    p = Kit("antenna")
    p.cyl(at(0, 0), .04, .04, .04, hex_color("4a4f52"), sides=8, bevel=.004)
    p.cyl(at(0, .04), .025, .02, 2.56, hex_color("5a6063"), sides=8, bevel=0.0)
    for y in (1.6, 2.0, 2.35):
        w = 1.0 - (y - 1.6) * .6
        p.bar(at(-w / 2, y), at(w / 2, y), .012, hex_color("5a6063"), sides=4)
        for k in range(5):
            x = -w / 2 + k * w / 4
            p.bar(at(x, y, -.035), at(x, y, .035), .006, hex_color("6c7274"), sides=4)
    for x in (-.4, .4):
        p.bar(at(0, 1.0), at(x, 0, 0), .006, hex_color("8a8f90"), sides=4)
    return [p.build()]


def _dish_bowl(p: Kit, center: Vector, radius: float, tilt_deg: float, color) -> None:
    # Prato côncavo: calota de esfera com espessura, virada para o céu e para a frente.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=18, ring_count=8, radius=radius, location=(0, 0, 0))
    obj = bpy.context.active_object
    cut = radius * .72
    for v in obj.data.vertices:
        v.co.z = max(v.co.z, cut) - cut
    obj.rotation_euler = (math.radians(tilt_deg), 0, 0)
    obj.location = center
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.modifiers.new("Espessura", "SOLIDIFY").thickness = .012
    p._finish_part(obj, color, 0.0)


def dish() -> list:
    p = Kit("dish")
    p.box(at(0, .02, 0), (.3, .04, .3), hex_color("5a5f61"), bevel=.008)
    p.cyl(at(0, .04), .035, .03, .45, hex_color("6c7274"), sides=8, bevel=0.0)
    # Prato raso virado para o céu, um pouco inclinado para a frente, como o antigo.
    _dish_bowl(p, at(0, .55, .05), .42, -165, hex_color("dfe0dc"))
    p.bar(at(0, .47, .1), at(0, .58, .3), .012, hex_color("8a8f90"), sides=6)
    p.box(at(0, .58, .31), (.05, .05, .07), hex_color("3a3f41"), bevel=.008)
    return [p.build()]


def roof_hatch() -> list:
    p = Kit("roof_hatch")
    p.box(at(0, .2, 0), (1.0, .4, 1.0), hex_color("7d8284"), bevel=.02)
    p.box(at(0, .43, 0), (.92, .06, .92), hex_color("4b5052"), bevel=.015)
    for x in (-.25, .25):
        p.box(at(x, .47, .44), (.12, .03, .04), hex_color("2b2f31"), bevel=.006)
    p.bar(at(-.15, .47, -.38), at(.15, .47, -.38), .012, hex_color("8a8f90"))
    return [p.build()]


def pipe_run() -> list:
    p = Kit("pipe_run")
    for x, color in ((-.12, hex_color("8f5a3a")), (.12, hex_color("6f7577"))):
        p.cyl(at(x, .14, -2.0), .055, .055, 4.0, color, sides=10, axis="Y", bevel=0.0)
        for z in (-1.0, 1.0):
            p.cyl(at(x, .14, z - .03), .068, .068, .06, color, sides=10, axis="Y", bevel=.004)
    for z in (-1.8, 0.0, 1.8):
        p.box(at(0, .05, z), (.5, .1, .12), hex_color("4b5052"), bevel=.012)
        p.box(at(0, .1, z), (.42, .02, .14), hex_color("3a3f41"), bevel=.004)
    return [p.build()]


def billboard_frame() -> list:
    # Estrutura do outdoor; o painel com a marca vem por cima (CityBrands) no mesmo lugar.
    steel = hex_color("3a4043")
    p = Kit("billboard_frame")
    for x in (-2.4, 2.4):
        p.box(at(x, 1.2, 0), (.14, 2.4, .14), steel, bevel=.01)
        p.box(at(x, 1.0, -.8), (.1, 2.0, .1), steel, bevel=.01)
        p.bar(at(x, .1, -.8), at(x, 2.3, 0), .03, steel)
        p.box(at(x, .03, -.4), (.3, .06, 1.0), steel, bevel=.01)
    p.box(at(0, 1.2, .18), (5.4, .04, .5), hex_color("2a2f31"), bevel=.006)
    for k in range(12):
        p.box(at(-2.6 + k * .47, 1.23, .18), (.02, .02, .5), steel, bevel=0.0)
    p.box(at(0, 1.55, .42), (5.4, .03, .03), steel, bevel=.004)
    for x in (-2.6, 0, 2.6):
        p.box(at(x, 1.4, .42), (.03, .35, .03), steel, bevel=.004)
    p.box(at(0, 2.4, 0), (6.2, 3.1, .12), hex_color("1d2123"), bevel=.02)
    p.box(at(0, 3.93, 0), (6.3, .04, .16), steel, bevel=.006)
    for x in (-2.0, 0.0, 2.0):
        p.bar(at(x, 1.25, .2), at(x, 1.55, .55), .02, steel)
        p.box(at(x, 1.58, .58), (.2, .12, .16), hex_color("55595b"), bevel=.02, rot=(math.radians(-30), 0, 0))
    return [p.build()]


def water_tank() -> list:
    p = Kit("water_tank")
    for x in (-.7, .7):
        for z in (-.7, .7):
            p.box(at(x, 1.0, z), (.1, 2.0, .1), IRON, bevel=.01)
    for z in (-.7, .7):
        p.bar(at(-.7, .2, z), at(.7, 1.8, z), .02, IRON)
        p.bar(at(.7, .2, z), at(-.7, 1.8, z), .02, IRON)
    p.box(at(0, 2.02, 0), (1.8, .08, 1.8), hex_color("4a3b2e"), bevel=.01)
    # Cuba de aduelas (tábuas verticais em tons diferentes) com cintas de ferro.
    staves = 20
    for k in range(staves):
        a = math.tau * k / staves
        p.box(at(math.cos(a) * .92, 2.96, math.sin(a) * .92), (.29, 1.8, .06), tones("6b4f36", 5)[k % 5],
              bevel=.006, rot=(0, 0, -a + math.pi / 2))
    p.cyl(at(0, 2.06), .9, .9, 1.78, hex_color("4a3b2e"), sides=20, bevel=0.0)
    for y in (2.4, 3.0, 3.55):
        p.torus(at(0, y), .97, .022, IRON, axis="Z", segments=24, ring=4)
    p.cyl(at(0, 3.86), 1.0, .08, .5, hex_color("3f3a35"), sides=20, bevel=.01)
    p.sphere(at(0, 4.36), (.08, .06, .08), IRON, subdiv=1)
    for k in range(10):
        p.box(at(.97, .2 + k * .38, 0), (.03, .03, .3), IRON_LIGHT, bevel=0.0)
    for z in (-.15, .15):
        p.box(at(.97, 1.9, z), (.03, 3.8, .03), IRON_LIGHT, bevel=0.0)
    return [p.build()]


def skylight() -> list:
    p = Kit("skylight")
    p.box(at(0, .2, 0), (1.6, .4, 1.1), hex_color("8a8f90"), bevel=.02)
    for side in (-1, 1):
        p.box(at(0, .47, .24 * side), (1.45, .02, .5), hex_color("7fa6b8"), bevel=.004,
              rot=(math.radians(-14 * side), 0, 0))
    p.box(at(0, .53, 0), (1.5, .04, .05), hex_color("5a5f61"), bevel=.008)
    for x in (-.36, 0, .36):
        p.box(at(x, .47, 0), (.03, .1, .98), hex_color("5a5f61"), bevel=.004)
    return [p.build()]


def solar_row() -> list:
    p = Kit("solar_row")
    tilt = (math.radians(-15), 0, 0)
    for i in range(3):
        x = -1.3 + i * 1.3
        p.box(at(x, .2, -.3), (.05, .4, .05), hex_color("9aa0a2"), bevel=.008)
        p.box(at(x, .08, .3), (.05, .16, .05), hex_color("9aa0a2"), bevel=.008)
        p.box(at(x, .02, 0), (.08, .04, .8), hex_color("9aa0a2"), bevel=.008)
        p.box(at(x, .3, 0), (1.22, .03, .92), hex_color("b8bcbc"), bevel=.004, rot=tilt)
        p.box(at(x, .315, 0), (1.18, .02, .88), hex_color("1d2e4a"), bevel=.003, rot=tilt)
        for c in range(3):
            p.box(at(x - .4 + c * .4, .328, 0), (.012, .006, .86), hex_color("8fa3bf"), bevel=0.0, rot=tilt)
    return [p.build()]


def cooling_tower() -> list:
    p = Kit("cooling_tower")
    p.box(at(0, .9, 0), (2.2, 1.8, 1.8), hex_color("9ea3a0"), bevel=.04)
    for side in (-1, 1):
        for k in range(8):
            p.box(at(0, .3 + k * .14, .905 * side), (2.0, .05, .03), hex_color("5f666a"), bevel=.006,
                  rot=(math.radians(25 * side), 0, 0))
    p.cyl(at(0, 1.8), .8, .75, .3, hex_color("6f7577"), sides=24, bevel=.01)
    p.torus(at(0, 2.1), .74, .03, hex_color("2b2f31"), axis="Z", segments=24, ring=4)
    p.cyl(at(0, 2.0), .7, .7, .02, hex_color("2b2f31"), sides=24, bevel=0.0)
    for k in range(5):
        p.box(at(0, 2.03), (1.3, .015, .16), hex_color("4a5052"), bevel=0.0, rot=(0, math.radians(8), k * math.pi / 5))
    p.bar(at(-1.0, 1.8, .9), at(-1.0, 2.1, .9), .02, hex_color("5f666a"))
    return [p.build()]


def roof_shed() -> list:
    p = Kit("roof_shed")
    p.box(at(0, 1.0, 0), (2.0, 2.0, 1.6), PAINT, bevel=.02)
    p.box(at(0, 2.07, .05), (2.2, .14, 1.8), hex_color("6e7577"), bevel=.01, rot=(math.radians(-3), 0, 0))
    for k in range(9):
        p.box(at(-1.0 + k * .25, 2.15, .05), (.03, .03, 1.8), hex_color("5a6062"), bevel=0.0, rot=(math.radians(-3), 0, 0))
    p.box(at(.4, .85, .81), (.8, 1.7, .04), hex_color("5a4a3c"), bevel=.01)
    p.box(at(.4, .85, .825), (.7, 1.6, .02), hex_color("4a3c30"), bevel=.004)
    p.sphere(at(.7, .9, .85), (.03, .03, .03), hex_color("c9a634"), subdiv=1)
    p.box(at(-.55, 1.4, .81), (.5, .4, .03), hex_color("2e3a40"), bevel=.004)
    p.box(at(-.55, 1.4, .815), (.56, .46, .02), hex_color("6e7577"), bevel=.004)
    return [p.build()]


def roof_chairs() -> list:
    p = Kit("roof_chairs")
    for x in (-.45, .45):
        # Cadeira de praia: armação e lona (a lona leva a tinta da paleta).
        p.box(at(x, .22, .05), (.55, .03, .8), PAINT, bevel=.008, rot=(math.radians(-5), 0, 0))
        p.box(at(x, .45, -.4), (.55, .5, .03), PAINT, bevel=.008, rot=(math.radians(-20), 0, 0))
        for side in (-.27, .27):
            p.bar(at(x + side, 0, .4), at(x + side, .25, -.35), .012, hex_color("cfcfc8"), sides=4)
            p.bar(at(x + side, 0, -.3), at(x + side, .7, -.48), .012, hex_color("cfcfc8"), sides=4)
    p.box(at(0, .15, .6), (.4, .3, .3), hex_color("d8453c"), bevel=.03)
    p.box(at(0, .31, .6), (.42, .04, .32), hex_color("f2efe6"), bevel=.015)
    return [p.build()]


def roof_garden() -> list:
    p = Kit("roof_garden")
    for x in (-.9, .9):
        for k in range(4):
            p.box(at(x, .05 + k * .1, 0), (1.4, .09, .7), tones("7a5537", 4)[k], bevel=.008)
        p.box(at(x, .42, 0), (1.3, .02, .6), hex_color("4a3524"), bevel=0.0)
        for q in range(4):
            px = x - .5 + q * .33
            hgt = .34 + ((q * .17) % .2)
            for k in range(4):
                a = k * 1.6 + q
                p.sphere(at(px + math.cos(a) * .06, .45 + hgt * (.3 + .2 * k), math.sin(a) * .06),
                         (.09 - k * .012, .09, .09 - k * .012),
                         hex_color(["4f8a45", "6aa04f", "3f7a3a"][(q + k) % 3]), subdiv=1, jitter=.015, seed=q * 4 + k + x)
    p.cyl(at(0, 0, .8), .03, .03, 1.9, hex_color("8a8f90"), sides=8, bevel=0.0)
    p.cyl(at(0, 0, .8), .2, .2, .05, hex_color("5a5f61"), sides=10, bevel=.008)
    _umbrella(p, at(0, 1.75, .8), .9, .18)
    return [p.build()]


# ================================================================================
# Lote "fachada" (presas na parede: frente para +Z, parede em z = 0)
# ================================================================================

def window_ac() -> list:
    p = Kit("window_ac")
    p.box(at(0, .2, .2), (.66, .42, .44), PAINT, bevel=.025)
    p.box(at(0, .2, .425), (.56, .32, .02), hex_color("7c817f"), bevel=.006)
    for k in range(8):
        p.box(at(0, .07 + k * .035, .44), (.54, .012, .015), hex_color("5b605f"), bevel=0.0)
    for x in (-.3, .3):
        p.bar(at(x, -.04, .02), at(x, .0, .36), .012, IRON)
        p.bar(at(x, -.3, .005), at(x, -.04, .3), .012, IRON)
    p.box(at(0, -.06, .12), (.5, .03, .3), IRON, bevel=.006)
    p.box(at(.18, -.5, .005), (.06, .9, .01), hex_color("3b3f40"), bevel=0.0)
    return [p.build()]


def flower_box() -> list:
    p = Kit("flower_box")
    p.box(at(0, .1, .14), (.95, .2, .24), PAINT, bevel=.015)
    p.box(at(0, .195, .14), (.9, .01, .2), hex_color("3a2a1c"), bevel=0.0)
    petals = ["d8454b", "f2c14e", "e8e3d8", "c05ab0"]
    for k in range(7):
        x = -.39 + k * .13
        p.sphere(at(x, .25, .14), (.07, .06, .07), hex_color("3f7a3a"), subdiv=1, jitter=.015, seed=k)
        for j in range(3):
            p.sphere(at(x + (j - 1) * .035, .32 + .02 * (j % 2), .14 + (j - 1) * .03), (.03, .025, .03),
                     hex_color(petals[(k + j) % 4]), subdiv=1)
    return [p.build()]


def fe_platform() -> list:
    p = Kit("fe_platform")
    p.box(at(0, 0, .5), (2.6, .04, .95), IRON, bevel=.006)
    for k in range(25):
        p.box(at(-1.25 + k * .104, .025, .5), (.012, .012, .9), IRON_LIGHT, bevel=0.0)
    p.bar(at(-1.29, .95, .96), at(1.29, .95, .96), .02, IRON)
    p.bar(at(-1.29, .5, .96), at(1.29, .5, .96), .014, IRON)
    for k in range(14):
        x = -1.28 + k * (2.56 / 13)
        p.bar(at(x, 0, .96), at(x, .95, .96), .008 if k % 3 else .016, IRON, sides=6)
    for side in (-1.29, 1.29):
        p.bar(at(side, .95, .02), at(side, .95, .96), .02, IRON)
        p.bar(at(side, 0, .96), at(side, .95, .96), .016, IRON)
        p.bar(at(side, .5, .02), at(side, .5, .96), .012, IRON)
    for x in (-1.1, 1.1):
        p.bar(at(x, -.58, .02), at(x, -.02, .9), .02, IRON)
    return [p.build()]


FE_RUN, FE_RISE, FE_Z = 2.6, 2.5, 1.3


def _fe_stair(name: str, sign: float) -> list:
    p = Kit(name)
    steps = 10
    for i in range(steps):
        f = (i + .5) / steps
        p.box(at((-FE_RUN * .5 + f * FE_RUN) * sign, f * FE_RISE, FE_Z), (.24, .03, .6), IRON_LIGHT, bevel=.004)
        p.box(at((-FE_RUN * .5 + f * FE_RUN) * sign, f * FE_RISE - .015, FE_Z), (.2, .01, .56), IRON, bevel=0.0)
    for z in (FE_Z - .32, FE_Z + .32):
        p.bar(at(-FE_RUN * .5 * sign, -.05, z), at(FE_RUN * .5 * sign, FE_RISE - .05, z), .045, IRON, sides=6)
    p.bar(at(-FE_RUN * .5 * sign, .85, FE_Z + .32), at(FE_RUN * .5 * sign, FE_RISE + .85, FE_Z + .32), .018, IRON)
    for k in range(5):
        f = (k + .5) / 5
        x, y = (-FE_RUN * .5 + f * FE_RUN) * sign, f * FE_RISE
        p.bar(at(x, y - .05, FE_Z + .32), at(x, y + .85, FE_Z + .32), .01, IRON, sides=6)
    return [p.build()]


def fe_stair() -> list:
    return _fe_stair("fe_stair", 1.0)


def fe_stair_m() -> list:
    return _fe_stair("fe_stair_m", -1.0)


def fe_ladder() -> list:
    p = Kit("fe_ladder")
    for x in (-.22, .22):
        p.box(at(x, -.8, .8), (.04, 1.6, .03), IRON, bevel=.004)
    for i in range(6):
        p.bar(at(-.22, -.1 - i * .28, .8), at(.22, -.1 - i * .28, .8), .012, IRON_LIGHT, sides=6)
    return [p.build()]


def drainpipe() -> list:
    # Unidade de 1 m: o jogo estica em Y conforme a altura da fachada.
    p = Kit("drainpipe")
    p.cyl(at(0, 0, .1), .055, .055, 1.0, hex_color("56595a"), sides=10, bevel=0.0)
    p.box(at(0, .5, .05), (.14, .03, .1), hex_color("3e4142"), bevel=.006)
    p.torus(at(0, .5, .1), .058, .01, hex_color("3e4142"), axis="Z", segments=10, ring=4)
    return [p.build()]


def pigeons() -> list:
    p = Kit("pigeons", smooth_angle=60.0)
    offsets = [-.9, -.55, -.1, .35, .8]
    shades = ["7d8288", "8e939a", "6c7076", "9aa0a6", "777b80"]
    for i, x in enumerate(offsets):
        yaw = i * 1.7
        fx, fz = math.sin(yaw), math.cos(yaw)
        p.sphere(at(x, .07, 0), (.06, .055, .1), hex_color(shades[i]), subdiv=2)
        p.sphere(at(x + fx * .08, .13, fz * .08), (.035, .035, .035), hex_color("4d6a63"), subdiv=1)
        p.bar(at(x + fx * .11, .13, fz * .11), at(x + fx * .135, .125, fz * .135), .008, hex_color("c9a634"), sides=4)
        p.box(at(x - fx * .1, .06, -fz * .1), (.07, .015, .08), hex_color("4a4d51"), bevel=.004, rot=(0, 0, -yaw))
        for side in (-.02, .02):
            p.bar(at(x + side, .02, 0), at(x + side, 0, 0), .005, hex_color("c97a5a"), sides=4)
    return [p.build()]


def laundry() -> list:
    p = Kit("laundry")
    for x in (-1.6, 1.6):
        p.cyl(at(x, 0), .025, .025, 1.6, hex_color("8a8f90"), sides=8, bevel=0.0)
        p.bar(at(x, 1.58, -.2), at(x, 1.58, .2), .02, hex_color("8a8f90"))
    p.bar(at(-1.6, 1.55), at(1.6, 1.55), .005, hex_color("c9c9c0"), sides=4)
    cloth = ["e8e4d8", "3f6fb0", "d44b4b", "f0c75a", "5ba36b", "e8e4d8", "9a5bb5"]
    x0 = -1.35
    for i, c in enumerate(cloth):
        w = .3 + (i * .37) % .22
        h = .35 + (i * .53) % .3
        # Pano com caimento, prendedores em cima.
        p.box(at(x0 + w / 2, 1.55 - h / 2, 0), (w, h, .015), hex_color(c), bevel=.004,
              rot=(math.radians(4 * (1 if i % 2 else -1)), 0, 0))
        for side in (-.4, .4):
            p.box(at(x0 + w / 2 + side * w, 1.56, 0), (.015, .04, .02), hex_color("c9a634"), bevel=0.0)
        x0 += w + .08
    return [p.build()]


def posters() -> list:
    p = Kit("posters")
    colors = ["e9d34a", "d6453f", "f1ede2", "3d6fb6", "e98a3a", "f1ede2"]
    sizes = [(.55, .8), (.5, .7), (.6, .85), (.45, .65), (.55, .75), (.5, .7)]
    x = -1.4
    for i, (c, (sx, sy)) in enumerate(zip(colors, sizes)):
        y = 1.35 + (i * .21) % .25
        p.box(at(x + sx / 2, y, .006), (sx, sy, .006), hex_color(c), bevel=0.0, rot=(0, math.radians(2 * (i % 3 - 1)), 0))
        p.box(at(x + sx / 2, y + sy * .28, .011), (sx * .8, .09, .003), hex_color("1f1f22"), bevel=0.0)
        p.box(at(x + sx / 2, y - sy * .1, .011), (sx * .6, .2, .003), hex_color(colors[(i + 2) % 6]), bevel=0.0)
        x += sx - .08 if i % 2 == 0 else sx + .04
    return [p.build()]


def beacon_mast() -> list:
    # A lente vermelha piscante é outra MultiMesh, no topo (1,8 m).
    p = Kit("beacon_mast")
    p.box(at(0, .05, 0), (.4, .1, .4), hex_color("5a5f61"), bevel=.015)
    p.cyl(at(0, .1), .05, .035, 1.66, hex_color("9aa0a2"), sides=10, bevel=0.0)
    p.cyl(at(0, 1.74), .06, .06, .06, hex_color("5a5f61"), sides=10, bevel=.006)
    for k in range(3):
        a = math.tau * k / 3
        p.bar(at(0, 1.0), at(math.cos(a) * .18, .1, math.sin(a) * .18), .008, hex_color("8a8f90"), sides=4)
    return [p.build()]


def satellite_row() -> list:
    p = Kit("satellite_row")
    for x in (-.8, 0, .8):
        p.box(at(x, .02, 0), (.15, .04, .15), hex_color("5a5f61"), bevel=.006)
        p.cyl(at(x, .04), .025, .02, .3, hex_color("6c7274"), sides=8, bevel=0.0)
        _dish_bowl(p, at(x, .36, .1), .27, -105, hex_color("e3e4df"))
        p.bar(at(x, .32, .08), at(x, .4, .32), .008, hex_color("8a8f90"), sides=4)
    return [p.build()]


def awning_small() -> list:
    # Toldo de lona em gomos (tinta da paleta) com franja na frente.
    p = Kit("awning_small")
    for i in range(6):
        color = PAINT if i % 2 == 0 else hex_color("f7f4ec")
        p.box(at(-.75 + i * .3, -.08, .45), (.3, .035, .92), color, bevel=.004, rot=(math.radians(-10), 0, 0))
    for i in range(12):
        color = PAINT if (i // 2) % 2 == 0 else hex_color("f7f4ec")
        p.box(at(-.825 + i * .15, -.2, .9), (.15, .1, .02), color, bevel=.003)
    for x in (-.88, .88):
        p.bar(at(x, .02, .02), at(x, -.16, .88), .01, hex_color("5a5f61"), sides=6)
    return [p.build()]


LOTS = {
    "calcada": [cafe_set, cafe_parasol, cafe_parasol_b, produce_stand, a_frame, beer_crates, wheelie_bins, bike_rack,
                pallet_stack, tire_stack, drums, food_cart, ice_freezer, clothes_rack, flower_buckets, gas_cylinders,
                door_bench, motorcycle, street_tree, street_tree_b, pot_plant],
    "sinal": [signal_pole, stop_sign, manhole, drain, hedge],
    "telhado": [ac_unit, vent, antenna, dish, roof_hatch, pipe_run, billboard_frame, water_tank, skylight, solar_row,
                cooling_tower, roof_shed, roof_chairs, roof_garden],
    "fachada": [window_ac, flower_box, fe_platform, fe_stair, fe_stair_m, fe_ladder, drainpipe, pigeons, laundry,
                posters, beacon_mast, satellite_row, awning_small],
}


def export(name: str, objects: list) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, f"wave3_{name}.glb"), export_format="GLB", use_selection=True,
        export_texcoords=False, export_normals=True, export_tangents=False, export_materials="NONE",
        export_vertex_color="ACTIVE", export_yup=True, export_apply=True)


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    lots = args or list(LOTS)
    row = 0.0
    for lot in lots:
        built = []
        offset = 0.0
        for factory in LOTS[lot]:
            objects = factory()
            for obj in objects:
                tris = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
                print(f"[wave3] {lot}/{obj.name}: {tris} triângulos")
            built.append(objects)
        export(lot, [o for group in built for o in group])
        # No .blend, cada lote numa fileira, peças lado a lado.
        for objects in built:
            width = max(o.dimensions.x for o in objects)
            for obj in objects:
                obj.location = (offset + width / 2, row, 0)
            offset += width + .8
        row += 6.0
    os.makedirs(os.path.join(OUT_DIR, "source"), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "source", "city_props_wave3.blend"), compress=True)


# Só monta quando rodado direto: outros scripts importam as ferramentas daqui.
if __name__ == "__main__":
    main()
