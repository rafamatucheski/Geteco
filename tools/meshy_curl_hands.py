#!/usr/bin/env python3
"""Fecha levemente a mão dos GLBs humanoides do Meshy (relaxada, dedos curvados para a palma).

O Meshy exporta a mão aberta, de dedos esticados e afastados, e o jogo poda os ossos dos dedos
(`meshy_slim_glb.py --prune-unposed`), então a mão fica "de garra" andando e não segura arma. Esta ferramenta
trabalha direto no GLB já podado: os vértices cujo peso dominante é o osso `Hand` e que estão na metade distal da
mão (os dedos) são dobrados em arco em torno de um eixo na altura dos nós dos dedos, com ângulo crescente até
a ponta. O resultado é geometria fixa, rígida com o osso da mão, sem custo em tempo de execução.

Uso: python tools/meshy_curl_hands.py <entrada.glb> <saida.glb> [--degrees 55] [--palm 0,0,1]
`--palm` é a direção da palma na pose de repouso do arquivo (o Meshy exporta em A-pose com a palma para a frente).
"""
import argparse, math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_slim_glb as slim


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def node_local(node):
    if "matrix" in node:
        m = node["matrix"]  # coluna-major
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = node.get("translation", [0, 0, 0])
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    s = node.get("scale", [1, 1, 1])
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[r[i][0] * s[0], r[i][1] * s[1], r[i][2] * s[2], t[i]] for i in range(3)] + [[0, 0, 0, 1]]


def world_origins(doc):
    nodes = doc["nodes"]
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    cache = {}

    def world(i):
        if i in cache: return cache[i]
        local = node_local(nodes[i])
        cache[i] = mat_mul(world(parent[i]), local) if i in parent else local
        return cache[i]
    return {i: (world(i)[0][3], world(i)[1][3], world(i)[2][3]) for i in range(len(nodes))}


def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def norm(a):
    length = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / length, a[1] / length, a[2] / length)


def rotate(v, axis, angle):
    c, s = math.cos(angle), math.sin(angle)
    k = cross(axis, v)
    d = dot(axis, v) * (1 - c)
    return (v[0] * c + k[0] * s + axis[0] * d, v[1] * c + k[1] * s + axis[1] * d, v[2] * c + k[2] * s + axis[2] * d)


def curl(doc, blob, degrees, palm):
    extras = doc.setdefault("asset", {}).setdefault("extras", {})
    if extras.get("hands_curled"):
        print("já curvado (%s°), nada a fazer" % extras["hands_curled"])
        return blob
    extras["hands_curled"] = degrees
    nodes = doc["nodes"]
    joints = doc["skins"][0]["joints"]
    origin = world_origins(doc)
    name_of = lambda j: nodes[j]["name"].replace("mixamorig:", "").replace("mixamorig_", "")
    index_of = {name_of(j): k for k, j in enumerate(joints)}
    primitive = doc["meshes"][0]["primitives"][0]
    attributes = primitive["attributes"]
    positions = slim.read_accessor(doc, blob, attributes["POSITION"])
    normals = slim.read_accessor(doc, blob, attributes["NORMAL"])
    sets = sorted(int(k.split("_")[1]) for k in attributes if k.startswith("JOINTS_"))
    joint_rows = [slim.read_accessor(doc, blob, attributes["JOINTS_%d" % s]) for s in sets]
    weight_rows = [slim.read_accessor(doc, blob, attributes["WEIGHTS_%d" % s]) for s in sets]
    new_positions, new_normals = list(positions), list(normals)
    palm = norm(palm)
    for side in ("Left", "Right"):
        hand_k = index_of[side + "Hand"]
        hand = origin[joints[hand_k]]
        direction = norm(sub(origin[joints[hand_k]], origin[joints[index_of[side + "ForeArm"]]]))
        axis = norm(cross(direction, palm))
        picked = []
        for v in range(len(positions)):
            weight = sum(w for s in range(len(sets)) for j, w in zip(joint_rows[s][v], weight_rows[s][v]) if int(j) == hand_k)
            if weight >= 0.6: picked.append(v)
        length = max(dot(sub(positions[v], hand), direction) for v in picked)
        knuckle = 0.42 * length
        hinge = (hand[0] + direction[0] * knuckle, hand[1] + direction[1] * knuckle, hand[2] + direction[2] * knuckle)
        moved = 0
        for v in picked:
            s = dot(sub(positions[v], hand), direction)
            t = min(max((s - knuckle) / max(length - knuckle, 1e-6), 0.0), 1.0)
            if t <= 0.0: continue
            angle = math.radians(degrees) * t
            rel = sub(positions[v], hinge)
            r = rotate(rel, axis, angle)
            new_positions[v] = (hinge[0] + r[0], hinge[1] + r[1], hinge[2] + r[2])
            new_normals[v] = rotate(normals[v], axis, angle)
            moved += 1
        print("%s: mão %d vértices, dedos dobrados %d (comprimento %.3f)" % (side, len(picked), moved, length))
    new_blob = bytearray(blob)
    attributes["POSITION"] = slim.append_accessor(doc, new_blob, new_positions, 5126, "VEC3")
    attributes["NORMAL"] = slim.append_accessor(doc, new_blob, new_normals, 5126, "VEC3")
    acc = doc["accessors"][attributes["POSITION"]]
    acc["min"] = [min(p[i] for p in new_positions) for i in range(3)]
    acc["max"] = [max(p[i] for p in new_positions) for i in range(3)]
    return bytes(new_blob)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("src"); parser.add_argument("dst")
    parser.add_argument("--degrees", type=float, default=55.0)
    parser.add_argument("--palm", default="0,0,1")
    args = parser.parse_args()
    doc, blob = slim.read_glb(args.src)
    blob = curl(doc, blob, args.degrees, tuple(float(x) for x in args.palm.split(",")))
    blob = slim.collect_garbage(doc, blob)
    slim.write_glb(args.dst, doc, blob)
    print("ok", args.dst)
