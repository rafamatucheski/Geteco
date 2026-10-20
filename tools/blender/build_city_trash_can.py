"""Lixeira municipal da cidade (kind "trash_can" do CityPropKit), montada no Blender.

Rodar (sem abrir a interface):
    D:/Blender/blender.exe -b --factory-startup --python tools/blender/build_city_trash_can.py

Gera assets/city_props/trash_can.glb (o que o jogo lê) e source/trash_can.blend (para
abrir e retocar à mão). Se editar o .blend, exporte de novo com as mesmas opções do fim deste
arquivo: sem UV, sem tangentes e sem material, só cor por vértice.

Por que assim: o kit da cidade desenha cada tipo como UMA malha com cor por vértice e um
material compartilhado, em MultiMesh por chunk. A malha daqui entra no mesmo lugar e
herda o mesmo material, então não cria shader novo nem chamada de desenho a mais.

As cores são gravadas cruas (valor sRGB do hex, sem converter para linear): o material
do kit usa vertex_color_is_srgb e espera exatamente isso.

Eixos: Blender Z para cima; o exportador do glTF converte para Y para cima. A frente do
objeto no jogo é +Z, que aqui é -Y (a plaquinha fica desse lado).
"""
import math
import os

import bmesh
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "city_props")
SIDES = 16


def hex_color(value: str) -> tuple:
    return tuple(int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)) + (1.0,)


# Mesmos verdes da versão procedural, para a cidade não mudar de cara.
GREEN = hex_color("2f5a43")
GREEN_BAND = hex_color("284d39")
GREEN_DARK = hex_color("1f3a2c")
LID = hex_color("16261e")
SLOT = hex_color("0b120e")
FOOT = hex_color("1c2420")
PLATE = hex_color("c9c4ab")
PLATE_MARK = hex_color("2f5a43")


class Builder:
    def __init__(self) -> None:
        self.bm = bmesh.new()
        self.color = self.bm.loops.layers.float_color.new("Col")

    def _face(self, verts: list, color: tuple) -> None:
        face = self.bm.faces.new(verts)
        for loop in face.loops:
            loop[self.color] = color

    def ring(self, z: float, radius: float) -> list:
        verts = []
        for i in range(SIDES):
            a = math.tau * i / SIDES
            verts.append(self.bm.verts.new((math.cos(a) * radius, math.sin(a) * radius, z)))
        return verts

    def frustum(self, z0: float, r0: float, z1: float, r1: float, color: tuple,
                bottom_cap: bool = False, top_cap: bool = True) -> None:
        low = self.ring(z0, r0)
        high = self.ring(z1, r1)
        for i in range(SIDES):
            j = (i + 1) % SIDES
            self._face([low[i], low[j], high[j], high[i]], color)
        if top_cap:
            self._face(high, color)
        if bottom_cap:
            self._face(list(reversed(low)), color)

    def box(self, center: tuple, size: tuple, color: tuple) -> None:
        cx, cy, cz = center
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        v = [self.bm.verts.new((cx + sx * hx, cy + sy * hy, cz + sz * hz))
             for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
        for quad in ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)):
            self._face([v[k] for k in quad], color)

    def to_object(self, name: str, origin_z: float = 0.0) -> bpy.types.Object:
        if origin_z:
            bmesh.ops.translate(self.bm, verts=self.bm.verts, vec=(0.0, 0.0, -origin_z))
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for poly in mesh.polygons:
            poly.use_smooth = True
        # Lateral redonda e lisa, quinas das bordas vivas (sem cara de sabonete).
        mesh.set_sharp_from_angle(angle=math.radians(35.0))
        mesh.color_attributes.active_color = mesh.color_attributes["Col"]
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def build_body(b: Builder) -> None:
    # Pé escuro e um pouco recuado: a lata parece apoiada, não brotando do chão.
    b.frustum(0.0, 0.235, 0.05, 0.235, FOOT, bottom_cap=True, top_cap=False)
    b.frustum(0.05, 0.235, 0.06, 0.26, FOOT, top_cap=False)
    # Corpo levemente cônico, com duas cintas salientes (reforço de lata de rua).
    b.frustum(0.06, 0.26, 0.20, 0.267, GREEN, top_cap=False)
    b.frustum(0.20, 0.272, 0.25, 0.274, GREEN_BAND, top_cap=False)
    b.frustum(0.25, 0.269, 0.60, 0.283, GREEN, top_cap=False)
    b.frustum(0.60, 0.288, 0.65, 0.290, GREEN_BAND, top_cap=False)
    b.frustum(0.65, 0.285, 0.80, 0.29, GREEN, top_cap=False)
    # Aro da boca, mais largo, e a fenda escura onde se joga o lixo.
    b.frustum(0.80, 0.31, 0.85, 0.31, GREEN_DARK, bottom_cap=True, top_cap=False)
    b.frustum(0.85, 0.25, 0.89, 0.25, SLOT, bottom_cap=False, top_cap=True)
    b.frustum(0.85, 0.31, 0.85, 0.25, GREEN_DARK, top_cap=False)
    # Plaquinha na frente (-Y aqui, +Z no jogo) para a lata ter um lado.
    b.box((0.0, -0.281, 0.45), (0.17, 0.012, 0.13), PLATE)
    b.box((0.0, -0.288, 0.45), (0.05, 0.004, 0.06), PLATE_MARK)


def build_lid(b: Builder) -> None:
    # Chapéu contra chuva: aba que cobre a fenda e cúpula baixa com pegador.
    b.frustum(0.89, 0.30, 0.91, 0.30, LID, bottom_cap=True, top_cap=False)
    b.frustum(0.91, 0.30, 0.96, 0.20, LID, top_cap=False)
    b.frustum(0.96, 0.20, 0.97, 0.12, LID, top_cap=True)
    b.box((0.0, 0.0, 0.985), (0.10, 0.03, 0.03), GREEN_DARK)


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Sem cópia .blend1 ao lado do arquivo salvo.
    bpy.context.preferences.filepaths.save_version = 0
    os.makedirs(OUT_DIR, exist_ok=True)

    whole = Builder()
    build_body(whole)
    build_lid(whole)
    whole.to_object("TrashCan")

    body = Builder()
    build_body(body)
    body.to_object("TrashCanBody")

    # Tampa solta (destroço) com origem no próprio centro, para girar em torno dele.
    lid = Builder()
    build_lid(lid)
    lid.to_object("TrashCanLid", origin_z=0.935)

    # As peças do destroço ficam ao lado no .blend, só para não se sobreporem na vista.
    bpy.data.objects["TrashCanBody"].location.x = 1.0
    bpy.data.objects["TrashCanLid"].location.x = 2.0

    os.makedirs(os.path.join(OUT_DIR, "source"), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "source", "trash_can.blend"), compress=True)
    for obj in bpy.data.objects:
        obj.location.x = 0.0
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, "trash_can.glb"),
        export_format="GLB",
        export_texcoords=False,
        export_normals=True,
        export_tangents=False,
        export_materials="NONE",
        export_vertex_color="ACTIVE",
        export_yup=True,
        export_apply=True,
    )
    for obj in bpy.data.objects:
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        print(f"[trash_can] {obj.name}: {tris} triângulos")


main()
