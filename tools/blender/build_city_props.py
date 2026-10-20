"""Primeira onda de adereços da cidade modelados no Blender (kit CityPropKit).

Rodar (sem abrir a interface):
    D:/Blender/blender.exe -b --factory-startup --python tools/blender/build_city_props.py

Gera assets/city_props/<tipo>.glb (o que o jogo lê) e source/city_props.blend (todas as
peças lado a lado, para abrir e retocar à mão; a pasta tem .gdignore para o Godot não
tentar importar o .blend). A lixeira tem script próprio
(build_city_trash_can.py), que veio antes e serviu de piloto.

Regras que valem para todas as peças (o porquê está em build_city_trash_can.py):
- tamanho, origem no chão e frente (+Z no jogo, -Y aqui) iguais aos da versão
  procedural, para colisão, encaixe na calçada e destroço continuarem valendo;
- exportação sem UV, sem tangente e sem material, só cor por vértice gravada crua em
  sRGB; o jogo põe o material do kit por cima e não nasce shader novo;
- peças "em camadas" (jardineira) saem com um objeto por camada, "<Nome>__<ordem>_<camada>",
  na ordem de CityPropKit.LAYERED; o CityPropsImport.gd junta tudo numa malha com uma
  superfície por camada na importação. Uma malha com dois materiais saía do exportador
  do glTF com a cor da segunda camada toda branca (Blender 5.2);
- o poste sai sem cor de vértice: haste e luminária usam materiais lisos do
  CityChunkDressing, como antes.
"""
import math
import os

import bpy
from mathutils import Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "city_props")


def hex_color(value: str) -> tuple:
    return tuple(int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)) + (1.0,)


def at(x: float, z_up: float, z_game: float = 0.0) -> Vector:
    """Ponto em coordenadas do jogo (x, y para cima, z para a frente) no Blender."""
    return Vector((x, -z_game, z_up))


# --- Construção de peças --------------------------------------------------------

class Prop:
    """Junta peças soltas num objeto só, com cor por vértice e quinas chanfradas."""

    def __init__(self, name: str, smooth_angle: float = 35.0) -> None:
        self.name = name
        self.smooth_angle = smooth_angle
        self.parts: list = []

    def _finish_part(self, obj, color, bevel: float, material: str = "", segments: int = 1,
                     limit: float = 30.0) -> None:
        mesh = obj.data
        attr = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        for item in attr.data:
            item.color = color
        if bevel > 0.0:
            mod = obj.modifiers.new("Chanfro", "BEVEL")
            mod.width = bevel
            mod.segments = segments
            mod.limit_method = "ANGLE"
            mod.angle_limit = math.radians(limit)
            mod.harden_normals = False
        if material:
            mat = bpy.data.materials.get(material) or bpy.data.materials.new(material)
            mesh.materials.append(mat)
        self.parts.append(obj)

    def box(self, center: Vector, size: tuple, color, bevel: float = 0.012, rot: tuple = (0, 0, 0),
            material: str = "") -> None:
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=center, rotation=rot)
        obj = bpy.context.active_object
        obj.scale = (size[0], size[2], size[1])  # (x, profundidade, altura) do jogo
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        self._finish_part(obj, color, min(bevel, min(size) * 0.45), material)

    def cyl(self, base: Vector, r0: float, r1: float, height: float, color, sides: int = 16,
            bevel: float = 0.008, axis: str = "Z", material: str = "") -> None:
        """Tronco de cone; base no ponto dado, crescendo no eixo pedido."""
        rot = {"Z": (0, 0, 0), "X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0)}[axis]
        direction = {"Z": Vector((0, 0, 1)), "X": Vector((1, 0, 0)), "Y": Vector((0, -1, 0))}[axis]
        center = base + direction * (height / 2)
        bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r0, radius2=r1, depth=height,
                                        location=center, rotation=rot)
        self._finish_part(bpy.context.active_object, color, min(bevel, height * 0.4, max(r0, r1) * 0.4),
                          material)

    def sphere(self, center: Vector, radii: tuple, color, subdiv: int = 2, jitter: float = 0.0,
               seed: float = 0.0, flatten_below: float = None, material: str = "") -> None:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=1.0, location=(0, 0, 0))
        obj = bpy.context.active_object
        for v in obj.data.vertices:
            co = Vector((v.co.x * radii[0], v.co.y * radii[2], v.co.z * radii[1]))
            if jitter:
                co += noise.noise_vector(co * 6.0 + Vector((seed, seed * 1.7, seed * 2.3))) * jitter
            v.co = co
        obj.location = center
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
        if flatten_below is not None:
            for v in obj.data.vertices:
                v.co.z = max(v.co.z, flatten_below)
        self._finish_part(obj, color, 0.0, material)

    def tube(self, points: list, radius: float, color, sides: int = 10) -> None:
        """Cano curvo passando pelos pontos (para braço de poste)."""
        curve = bpy.data.curves.new(self.name + "Tube", "CURVE")
        curve.dimensions = "3D"
        curve.bevel_depth = radius
        curve.bevel_resolution = max(1, sides // 4 - 1)
        curve.use_fill_caps = True
        spline = curve.splines.new("POLY")
        spline.points.add(len(points) - 1)
        for point, p in zip(spline.points, points):
            point.co = (p.x, p.y, p.z, 1.0)
        obj = bpy.data.objects.new(self.name + "Tube", curve)
        bpy.context.scene.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")
        self._finish_part(bpy.context.active_object, color, 0.0)

    def build(self, color_attribute: bool = True):
        bpy.ops.object.select_all(action="DESELECT")
        for obj in self.parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = self.parts[0]
        bpy.ops.object.convert(target="MESH")
        bpy.ops.object.join()
        obj = bpy.context.active_object
        obj.name = self.name
        obj.data.name = self.name
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        mesh = obj.data
        for poly in mesh.polygons:
            poly.use_smooth = True
        mesh.set_sharp_from_angle(angle=math.radians(self.smooth_angle))
        if color_attribute:
            mesh.color_attributes.active_color = mesh.color_attributes["Col"]
        else:
            mesh.color_attributes.remove(mesh.color_attributes["Col"])
        return obj


# --- As peças -------------------------------------------------------------------

def hydrant() -> list:
    red, dark, brass = hex_color("b8322a"), hex_color("7c2520"), hex_color("d8c24a")
    p = Prop("Hydrant")
    p.cyl(at(0, 0), .17, .165, .05, dark, sides=12)
    p.cyl(at(0, .05), .135, .12, .03, dark, sides=12)
    p.cyl(at(0, .08), .12, .115, .44, red, sides=16)
    p.cyl(at(0, .29), .128, .128, .04, dark, sides=16)
    p.cyl(at(0, .52), .145, .145, .05, red, sides=16)
    p.cyl(at(0, .57), .14, .07, .08, red, sides=16)
    p.cyl(at(0, .65), .04, .035, .045, brass, sides=5, bevel=.004)
    # Bocais laterais e a saída grande da frente (+Z), com tampas de latão.
    for outlet, cap in ((-.17, -.21), (.10, .17)):
        p.cyl(at(outlet, .40), .045, .045, .07, red, sides=12, axis="X")
        p.cyl(at(cap, .40), .055, .055, .04, brass, sides=12, axis="X")
    p.cyl(at(0, .40, .09), .065, .065, .05, red, sides=14, axis="Y")
    p.cyl(at(0, .40, .14), .075, .075, .035, brass, sides=14, axis="Y")
    p.box(at(0, .40, .18), (.04, .04, .02), brass, bevel=.004)
    return [p.build()]


def bench_seat() -> list:
    # Mesmo envelope do BenchFinish (1,7 x 0,44, assento a 0,49, encosto a 0,93).
    wood, frame = hex_color("806044"), hex_color("343d39")
    p = Prop("BenchSeat")
    for i in range(4):
        shade = tuple(min(1.0, c * (1.0 + 0.05 * (i % 3))) for c in wood[:3]) + (1.0,)
        p.box(at(0, .465, -.165 + i * .11), (1.7, .045, .095), shade, bevel=.012)
    for i in range(3):
        y = .58 + i * .12
        lean = -.20 - (y - .58) * .12
        shade = tuple(min(1.0, c * (1.0 + 0.04 * i)) for c in wood[:3]) + (1.0,)
        p.box(at(0, y, lean), (1.7, .095, .04), shade, bevel=.012, rot=(math.radians(-8), 0, 0))
    for x in (-.68, .68):
        # Pé de ferro fundido: pernas abertas, travessa do assento, montante e braço.
        p.box(at(x, .21, .14), (.06, .44, .06), frame, rot=(math.radians(-10), 0, 0))
        p.box(at(x, .21, -.15), (.06, .44, .06), frame, rot=(math.radians(10), 0, 0))
        p.box(at(x, .03, 0), (.08, .06, .44), frame)
        p.box(at(x, .43, 0), (.07, .05, .42), frame)
        p.box(at(x, .68, -.22), (.06, .52, .05), frame, rot=(math.radians(-8), 0, 0))
        p.box(at(x, .68, .0), (.07, .045, .4), frame)
        p.box(at(x, .57, .17), (.05, .2, .05), frame)
    return [p.build()]


LAMP_HEIGHT = 5.4
LAMP_ARM = 1.3


def sidewalk_lamp() -> list:
    # Haste cônica e braço curvo para a via (+Z); a lente (cabeça) fica no mesmo
    # lugar da procedural, porque a mancha de luz no chão é calculada daí.
    white = hex_color("ffffff")
    pole = Prop("LampPole")
    pole.cyl(at(0, 0), .2, .2, .06, white, sides=8, bevel=.01)
    pole.cyl(at(0, .06), .17, .15, .38, white, sides=8, bevel=.01)
    pole.cyl(at(0, .44), .15, .1, .06, white, sides=12)
    pole.cyl(at(0, .5), .085, .06, LAMP_HEIGHT - .6, white, sides=12, bevel=0.0)
    pole.sphere(at(0, LAMP_HEIGHT - .1), (.07, .05, .07), white, subdiv=2, flatten_below=LAMP_HEIGHT - .1)
    # Pescoço de cisne: sai da haste meio metro abaixo do topo e curva até a luminária.
    arm = []
    for i in range(7):
        angle = i / 6 * math.pi / 2
        arm.append(at(0, LAMP_HEIGHT - .45 + math.sin(angle) * .43, (1 - math.cos(angle)) * .45))
    arm.append(at(0, LAMP_HEIGHT - .01, LAMP_ARM - .25))
    pole.tube(arm, .045, white)
    # Luminária achatada, um pouco inclinada para cima na ponta.
    pole.box(at(0, LAMP_HEIGHT + .05, LAMP_ARM + .02), (.36, .1, .64), white, bevel=.035)
    pole.box(at(0, LAMP_HEIGHT + .11, LAMP_ARM - .05), (.24, .04, .38), white, bevel=.018)
    head = Prop("LampHead")
    head.box(at(0, LAMP_HEIGHT - .025, LAMP_ARM + .04), (.3, .04, .52), white, bevel=.015)
    return [pole.build(color_attribute=False), head.build(color_attribute=False)]


def phone_booth() -> list:
    metal, light, roof = hex_color("8a9396"), hex_color("5b6063"), hex_color("c9a634")
    glass, dark, sign = hex_color("3e4b52"), hex_color("2c3134"), hex_color("f3efe0")
    p = Prop("PhoneBooth")
    p.box(at(0, .06, 0), (.9, .12, .9), light, bevel=.02)
    for x in (-.42, .42):
        for z in (-.42, .42):
            p.box(at(x, 1.17, z), (.07, 2.1, .07), metal, bevel=.01)
    # Laterais e fundo: metade de baixo chapa, metade de cima vidro escuro.
    for x in (-.42, .42):
        p.box(at(x, .55, 0), (.04, .86, .78), metal, bevel=.006)
        p.box(at(x, 1.55, 0), (.025, 1.1, .78), glass, bevel=.004)
        p.box(at(x, 1.0, 0), (.05, .05, .8), metal, bevel=.006)
    p.box(at(0, .55, -.42), (.78, .86, .04), metal, bevel=.006)
    p.box(at(0, 1.55, -.42), (.78, 1.1, .025), glass, bevel=.004)
    p.box(at(0, 1.0, -.42), (.8, .05, .05), metal, bevel=.006)
    # Telefone, prateleira e fone.
    p.box(at(0, 1.3, -.36), (.3, .42, .1), dark, bevel=.015)
    p.box(at(0, 1.42, -.305), (.12, .07, .01), hex_color("9fb6b0"), bevel=.003)
    p.box(at(-.1, 1.2, -.3), (.05, .2, .05), hex_color("161a1c"), bevel=.012)
    p.box(at(0, .98, -.33), (.5, .03, .18), metal, bevel=.006)
    # Teto amarelo com aba e placa na frente.
    p.box(at(0, 2.24, 0), (.98, .1, .98), roof, bevel=.03)
    p.box(at(0, 2.33, 0), (.8, .08, .8), roof, bevel=.03)
    p.box(at(0, 2.13, .45), (.72, .14, .03), sign, bevel=.006)
    p.box(at(0, 2.13, .44), (.76, .16, .02), roof, bevel=.004)
    return [p.build()]


def dumpster() -> list:
    body, lid, dark = hex_color("2f6b4f"), hex_color("24523c"), hex_color("1c3c2d")
    wheel, metal = hex_color("222222"), hex_color("55605a")
    p = Prop("Dumpster")
    p.box(at(0, .63, 0), (1.86, 1.02, 1.06), body, bevel=.04)
    p.box(at(0, .15, 0), (1.76, .1, .98), dark, bevel=.02)
    # Nervuras verticais na frente e no fundo, e a cinta de cima.
    for x in (-.6, 0, .6):
        for z in (.545, -.545):
            p.box(at(x, .63, z), (.08, .9, .04), body, bevel=.012)
    p.box(at(0, 1.08, 0), (1.92, .08, 1.12), dark, bevel=.02)
    # Bolsos laterais do garfo do caminhão.
    for x in (-.97, .97):
        p.box(at(x, .7, 0), (.08, .16, .92), dark, bevel=.015)
    # Duas tampas de plástico, levemente caídas para a frente.
    for x in (-.47, .47):
        p.box(at(x, 1.16, -.02), (.9, .06, 1.16), lid, bevel=.025, rot=(math.radians(4), 0, 0))
        p.box(at(x, 1.15, .57), (.6, .05, .04), dark, bevel=.01)
    p.box(at(0, 1.17, -.6), (1.86, .06, .06), metal, bevel=.015)
    # Rodízios.
    for x in (-.78, .78):
        for z in (-.4, .4):
            p.box(at(x, .09, z), (.1, .04, .1), metal, bevel=.01)
            p.cyl(at(x - .02, .045), .045, .045, .04, wheel, sides=10, axis="X")
    return [p.build()]


def news_box() -> list:
    window, legs, dark = hex_color("dfe7e8"), hex_color("2a2e30"), hex_color("1b1e20")
    p = Prop("NewsBox")
    for x, color in ((-.26, hex_color("c63a2f")), (.26, hex_color("2d6fb6"))):
        p.box(at(x, .5, 0), (.46, .64, .42), color, bevel=.02)
        # Tampo inclinado para trás (fica mais alto na frente, como as reais).
        p.box(at(x, .86, -.01), (.46, .1, .44), color, bevel=.02, rot=(math.radians(-6), 0, 0))
        p.box(at(x, .7, .215), (.38, .26, .02), window, bevel=.006)
        p.box(at(x, .7, .21), (.42, .3, .02), dark, bevel=.004)
        p.box(at(x, .52, .218), (.3, .04, .02), dark, bevel=.006)
        p.box(at(x + .15, .4, .218), (.07, .1, .02), hex_color("b8bcbc"), bevel=.006)
        for lx in (x - .19, x + .19):
            p.box(at(lx, .09, 0), (.04, .18, .36), legs, bevel=.008)
    return [p.build()]


def bollard() -> list:
    steel, band = hex_color("2e3336"), hex_color("d6b43c")
    p = Prop("Bollard")
    p.cyl(at(0, 0), .122, .122, .03, steel, sides=12)
    p.cyl(at(0, .03), .11, .105, .74, steel, sides=12, bevel=0.0)
    p.cyl(at(0, .62), .113, .112, .1, band, sides=12, bevel=0.0)
    p.cyl(at(0, .77), .105, .105, .03, steel, sides=12, bevel=0.0)
    p.sphere(at(0, .8), (.105, .06, .105), steel, subdiv=2, flatten_below=.8)
    return [p.build()]


def mailbox() -> list:
    blue, dark_blue, slot = hex_color("27418a"), hex_color("1d2a55"), hex_color("0f152b")
    label = hex_color("e6e2d4")
    p = Prop("Mailbox")
    for x in (-.21, .21):
        for z in (-.18, .18):
            p.box(at(x, .08, z), (.06, .16, .06), dark_blue, bevel=.01)
    p.box(at(0, .19, 0), (.5, .06, .44), dark_blue, bevel=.015)
    p.box(at(0, .57, 0), (.5, .74, .44), blue, bevel=.025)
    # Topo abaulado (meio cilindro deitado no sentido da profundidade).
    p.cyl(at(0, .94, -.22), .25, .25, .44, blue, sides=20, axis="Y", bevel=.02)
    p.box(at(0, .92, .225), (.32, .06, .03), slot, bevel=.01)
    p.box(at(0, .96, .23), (.34, .03, .03), dark_blue, bevel=.008)
    p.box(at(0, .58, .222), (.28, .16, .01), label, bevel=.004)
    p.box(at(0, .4, .222), (.12, .03, .012), dark_blue, bevel=.004)
    return [p.build()]


def trash_bags() -> list:
    # Uma camada só ("plastic"): sacos estufados e caixa de papelão desbotada.
    p = Prop("TrashBags", smooth_angle=80.0)
    for center, radii, color, seed in (
            (at(0, .2), (.3, .22, .27), hex_color("1a1c1e"), 1.0),
            (at(.42, .17, .12), (.25, .19, .23), hex_color("222528"), 4.0),
            (at(.18, .15, -.34), (.24, .17, .22), hex_color("2c3327"), 7.0)):
        p.sphere(center, radii, color, subdiv=2, jitter=.035, seed=seed, flatten_below=0.0)
        top = center + Vector((0, 0, radii[1] - .02))
        p.cyl(top, .07, .02, .1, color, sides=6, bevel=0.0)
        p.sphere(top + Vector((0, 0, .11)), (.035, .03, .035), color, subdiv=1, jitter=.01, seed=seed)
    p.box(at(-.4, .16, .2), (.4, .32, .34), hex_color("7d6a50"), bevel=.01, rot=(0, 0, .4))
    p.box(at(-.4, .325, .2), (.38, .01, .2), hex_color("6c5b44"), bevel=.003, rot=(0, 0, .4))
    return [p.build()]


HARBOR_LEAVES = ["37443b", "3f4b3e", "333f37", "454a39", "3a4636"]


def planter() -> list:
    # Duas camadas na ordem do CityPropKit.LAYERED: "stone" e depois "leaves".
    stone = Prop("Planter__0_stone", smooth_angle=50.0)
    stone.box(at(0, .21, 0), (1.0, .42, 1.0), hex_color("5f625d"), bevel=.03)
    stone.box(at(0, .03, 0), (1.04, .06, 1.04), hex_color("54574f"), bevel=.015)
    stone.box(at(0, .46, 0), (1.1, .08, 1.1), hex_color("71746e"), bevel=.025)
    stone.box(at(0, .505, 0), (.88, .02, .88), hex_color("2a241e"), bevel=0.0)
    p = Prop("Planter__1_leaves", smooth_angle=50.0)
    # Muitos tufos pequenos e tortos, mais altos no meio: os grandes e lisos liam como
    # ovos ou pedras (o mesmo problema que a versão procedural já tinha anotado).
    spots = [(0, 0)]
    for ring, count, radius in ((1, 6, .2), (2, 10, .34)):
        for k in range(count):
            angle = math.tau * k / count + ring * .4
            spots.append((math.cos(angle) * radius, math.sin(angle) * radius))
    for i, (x, z) in enumerate(spots):
        dist = math.hypot(x, z)
        top = .32 - dist * .45 + .05 * (i % 3)
        # Cada tufo é um cacho de bolinhas facetadas: o contorno fica recortado como
        # folhagem, em vez de uma superfície lisa que reflete a luz como pedra.
        for k in range(4):
            jitter = noise.noise_vector(Vector((i * 1.3, k * 2.1, 0.5))) * .07
            size = .075 + .02 * ((i + k) % 3)
            y = .5 + top * (.25 + .22 * k)
            p.sphere(at(x + jitter.x, y, z + jitter.y), (size, size * .85, size),
                     hex_color(HARBOR_LEAVES[(i + k) % len(HARBOR_LEAVES)]), subdiv=1, jitter=.025,
                     seed=i * 3.1 + k, flatten_below=.5)
    return [stone.build(), p.build()]


PROPS = {
    "hydrant": (hydrant, "NONE"),
    "bench_seat": (bench_seat, "NONE"),
    "sidewalk_lamp": (sidewalk_lamp, "NONE"),
    "phone_booth": (phone_booth, "NONE"),
    "dumpster": (dumpster, "NONE"),
    "news_box": (news_box, "NONE"),
    "bollard": (bollard, "NONE"),
    "mailbox": (mailbox, "NONE"),
    "trash_bags": (trash_bags, "NONE"),
    "planter": (planter, "NONE"),
}


def export(kind: str, objects: list, materials: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    has_colors = any(obj.data.color_attributes for obj in objects)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, kind + ".glb"),
        export_format="GLB",
        use_selection=True,
        export_texcoords=False,
        export_normals=True,
        export_tangents=False,
        export_materials=materials,
        export_vertex_color="ACTIVE" if has_colors else "NONE",
        export_yup=True,
        export_apply=True,
    )
    for obj in objects:
        tris = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
        print(f"[city_props] {kind}/{obj.name}: {tris} triângulos")


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Sem cópia .blend1 ao lado do arquivo salvo.
    bpy.context.preferences.filepaths.save_version = 0
    os.makedirs(OUT_DIR, exist_ok=True)
    offset = 0.0
    for kind, (factory, materials) in PROPS.items():
        objects = factory()
        export(kind, objects, materials)
        width = max(obj.dimensions.x for obj in objects)
        for obj in objects:
            obj.location.x = offset + width / 2
        offset += width + .6
    os.makedirs(os.path.join(OUT_DIR, "source"), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "source", "city_props.blend"), compress=True)


main()
