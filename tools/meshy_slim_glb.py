#!/usr/bin/env python3
"""Deixa um GLB humanoide do Meshy leve para uso em multidão, sem mudar a geometria nem a pele.

1. Textura: reduz a imagem embutida (o Meshy exporta 2048 px, ~3,6 MB) para --size.
2. --prune-unposed: remove do esqueleto os ossos que o jogo nunca anima (dedos, pontas e as cadeias
   auxiliares `Bone_NNN`). O peso de cada vértice nesses ossos passa para o ancestral mantido mais
   próximo; como um osso que nunca roda sozinho se move rigidamente com o pai, a pele fica idêntica.
   A pele passa de até 24 influências por vértice para as 8 maiores, renormalizadas (limite do motor).
   Remove também as animações embutidas (o corpo é posado pelas juntas do `CivilianModel`).

Motivo medido: com 40 NPCs, o custo do `Skeleton3D` de 78 ossos reprocessado a cada quadro era ~1 ms por
quadro; os 40 ossos só de dedos não influenciam nenhuma pose do jogo.

Uso: python tools/meshy_slim_glb.py <entrada.glb> <saida.glb> [--size 1024] [--quality 88] [--prune-unposed]
"""
import argparse, io, json, re, struct
from PIL import Image

JSON_CHUNK, BIN_CHUNK = 0x4E4F534A, 0x004E4942
COMPONENT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
PRUNE_NAME = re.compile(r"Hand(Pinky|Ring|Thumb|Index|Middle)\d|HeadTop_End|headfront|Toe_End")


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _ = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67 and version == 2, "não é um GLB 2.0"
    offset, doc, blob = 12, None, b""
    while offset < len(data):
        length, kind = struct.unpack("<II", data[offset:offset + 8])
        chunk = data[offset + 8:offset + 8 + length]
        if kind == JSON_CHUNK: doc = json.loads(chunk)
        elif kind == BIN_CHUNK: blob = chunk
        offset += 8 + length
    return doc, blob


def write_glb(path, doc, blob):
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    blob += b"\0" * (-len(blob) % 4)
    total = 12 + 8 + len(text) + 8 + len(blob)
    with open(path, "wb") as out:
        out.write(struct.pack("<III", 0x46546C67, 2, total))
        out.write(struct.pack("<II", len(text), JSON_CHUNK) + text)
        out.write(struct.pack("<II", len(blob), BIN_CHUNK) + blob)


def read_accessor(doc, blob, index):
    """Devolve a lista de tuplas do acessor, já com o `normalized` aplicado."""
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    fmt, size = COMPONENT[acc["componentType"]]
    width = TYPE_COUNT[acc["type"]]
    stride = view.get("byteStride", size * width)
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    scale = {5121: 255.0, 5123: 65535.0}.get(acc["componentType"], 1.0) if acc.get("normalized") else 1.0
    rows = []
    for i in range(acc["count"]):
        row = struct.unpack_from("<" + fmt * width, blob, base + i * stride)
        rows.append(tuple(v / scale for v in row) if scale != 1.0 else row)
    return rows


def append_accessor(doc, new_blob, rows, component, type_name):
    fmt, size = COMPONENT[component]
    width = TYPE_COUNT[type_name]
    payload = b"".join(struct.pack("<" + fmt * width, *row) for row in rows)
    new_blob += b"\0" * (-len(new_blob) % 4)
    doc["bufferViews"].append({"buffer": 0, "byteOffset": len(new_blob), "byteLength": len(payload)})
    new_blob += payload
    doc["accessors"].append({"bufferView": len(doc["bufferViews"]) - 1, "componentType": component, "count": len(rows), "type": type_name})
    return len(doc["accessors"]) - 1


def prune_unposed(doc, blob):
    nodes = doc["nodes"]
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    skin = doc["skins"][0]
    joints = skin["joints"]
    joint_set = set(joints)
    drop = {n for n in joints if PRUNE_NAME.search(nodes[n]["name"])}
    # Cadeias auxiliares `Bone_NNN` sem filhos mantidos: removidas de folha para raiz até estabilizar.
    changed = True
    while changed:
        changed = False
        for n in joints:
            if n in drop or not nodes[n]["name"].startswith("Bone_"): continue
            if all(c in drop or c not in joint_set for c in nodes[n].get("children", [])):
                drop.add(n); changed = True
    kept = [n for n in joints if n not in drop]
    new_index = {n: i for i, n in enumerate(kept)}

    def heir(node):
        while node not in new_index: node = parent[node]
        return new_index[node]

    remap = [heir(n) for n in joints]
    new_blob = bytearray(blob)
    ibm = read_accessor(doc, blob, skin["inverseBindMatrices"])
    skin["inverseBindMatrices"] = append_accessor(doc, new_blob, [ibm[joints.index(n)] for n in kept], 5126, "MAT4")
    skin["joints"] = kept
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            attributes = primitive["attributes"]
            sets = sorted(int(k.split("_")[1]) for k in attributes if k.startswith("JOINTS_"))
            joint_rows = [read_accessor(doc, blob, attributes["JOINTS_%d" % s]) for s in sets]
            weight_rows = [read_accessor(doc, blob, attributes["WEIGHTS_%d" % s]) for s in sets]
            out_joints, out_weights = [], []
            for v in range(len(joint_rows[0])):
                acc = {}
                for s in range(len(sets)):
                    for j, w in zip(joint_rows[s][v], weight_rows[s][v]):
                        if w > 0.0: acc[remap[int(j)]] = acc.get(remap[int(j)], 0.0) + w
                top = sorted(acc.items(), key=lambda kv: -kv[1])[:8]
                total = sum(w for _, w in top) or 1.0
                top = [(j, w / total) for j, w in top] + [(0, 0.0)] * (8 - len(top))
                out_joints.append(top)
                out_weights.append(top)
            for s in sets:
                del attributes["JOINTS_%d" % s]
                del attributes["WEIGHTS_%d" % s]
            for half in range(2):
                chunk = [row[half * 4:half * 4 + 4] for row in out_joints]
                attributes["JOINTS_%d" % half] = append_accessor(doc, new_blob, [tuple(j for j, _ in r) for r in chunk], 5123, "VEC4")
                attributes["WEIGHTS_%d" % half] = append_accessor(doc, new_blob, [tuple(w for _, w in r) for r in chunk], 5126, "VEC4")
    for n in drop:
        if n in parent: nodes[parent[n]]["children"].remove(n)
    doc["animations"] = []
    print("ossos: %d -> %d" % (len(joints), len(kept)))
    return bytes(new_blob)


def collect_garbage(doc, blob):
    """Descarta acessores e bufferViews que nenhum recurso usa mais, e recompacta o blob."""
    used = set()
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            used.update(primitive["attributes"].values())
            if "indices" in primitive: used.add(primitive["indices"])
    for skin in doc.get("skins", []):
        if "inverseBindMatrices" in skin: used.add(skin["inverseBindMatrices"])
    for animation in doc.get("animations", []):
        for sampler in animation["samplers"]:
            used.update((sampler["input"], sampler["output"]))
    acc_map = {old: new for new, old in enumerate(sorted(used))}
    accessors = [doc["accessors"][old] for old in sorted(used)]
    view_ids = sorted({a["bufferView"] for a in accessors} | {i["bufferView"] for i in doc.get("images", []) if "bufferView" in i})
    view_map = {old: new for new, old in enumerate(view_ids)}
    new_views, new_blob = [], bytearray()
    for old in view_ids:
        view = doc["bufferViews"][old]
        start = view.get("byteOffset", 0)
        payload = blob[start:start + view["byteLength"]]
        new_blob += b"\0" * (-len(new_blob) % 4)
        entry = dict(view)
        entry["byteOffset"] = len(new_blob)
        new_views.append(entry)
        new_blob += payload
    for a in accessors: a["bufferView"] = view_map[a["bufferView"]]
    for image in doc.get("images", []):
        if "bufferView" in image: image["bufferView"] = view_map[image["bufferView"]]
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            primitive["attributes"] = {k: acc_map[v] for k, v in primitive["attributes"].items()}
            if "indices" in primitive: primitive["indices"] = acc_map[primitive["indices"]]
    for skin in doc.get("skins", []):
        if "inverseBindMatrices" in skin: skin["inverseBindMatrices"] = acc_map[skin["inverseBindMatrices"]]
    for animation in doc.get("animations", []):
        for sampler in animation["samplers"]:
            sampler["input"], sampler["output"] = acc_map[sampler["input"]], acc_map[sampler["output"]]
    doc["accessors"], doc["bufferViews"] = accessors, new_views
    doc["buffers"][0]["byteLength"] = len(new_blob)
    return bytes(new_blob)


def slim_texture(doc, blob, size, quality):
    image_views = {image["bufferView"]: index for index, image in enumerate(doc.get("images", [])) if "bufferView" in image}
    new_blob = bytearray()
    for index, view in enumerate(doc["bufferViews"]):
        start, length = view.get("byteOffset", 0), view["byteLength"]
        payload = blob[start:start + length]
        if index in image_views:
            image = Image.open(io.BytesIO(payload)).convert("RGB")
            if max(image.size) > size: image = image.resize((size, size), Image.LANCZOS)
            buffer = io.BytesIO()
            image.save(buffer, "JPEG", quality=quality, optimize=True)
            payload = buffer.getvalue()
            doc["images"][image_views[index]]["mimeType"] = "image/jpeg"
        new_blob += b"\0" * (-len(new_blob) % 4)
        view["byteOffset"] = len(new_blob)
        view["byteLength"] = len(payload)
        new_blob += payload
    doc["buffers"][0]["byteLength"] = len(new_blob)
    return bytes(new_blob)


def slim(src, dst, size, quality, prune):
    doc, blob = read_glb(src)
    if prune: blob = prune_unposed(doc, blob)
    blob = collect_garbage(doc, blob)
    blob = slim_texture(doc, blob, size, quality)
    write_glb(dst, doc, blob)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("src"); parser.add_argument("dst")
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--quality", type=int, default=88)
    parser.add_argument("--prune-unposed", action="store_true")
    args = parser.parse_args()
    slim(args.src, args.dst, args.size, args.quality, args.prune_unposed)
    print("ok", args.dst)
