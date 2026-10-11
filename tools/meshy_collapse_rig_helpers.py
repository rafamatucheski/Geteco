#!/usr/bin/env python3
"""Colapsa helpers explicitamente autorizados entre UpLeg e Leg, preservando repouso/pele.

O driver do jogo não dirige esses helpers; removê-los offline evita pais sem base
calculada e não acrescenta custo por frame. Auxiliares dos pés ficam preservados.
O escopo é deliberadamente estreito: GLB podado sem animações, helper Bone_NNN com
pai UpLeg no skin e um único filho Leg no skin. --helpers é obrigatório.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from meshy_shoulder_weights import global_matrices
from meshy_slim_glb import read_glb, read_accessor, append_accessor, collect_garbage, write_glb

MARKER = 'rig_helpers_collapsed_v1'
ALLOWED_HELPERS = {'Bone_002', 'Bone_004'}


def collapse(source, destination, helper_names):
    source, destination = Path(source), Path(destination)
    if source.resolve() == destination.resolve():
        raise ValueError('O destino deve preservar o original.')
    if destination.exists():
        raise FileExistsError('O destino já existe; escolha outro para preservar evidência.')
    if not helper_names or len(helper_names) != len(set(helper_names)):
        raise ValueError('Forneça allowlist explícita sem nomes repetidos.')
    if not set(helper_names).issubset(ALLOWED_HELPERS):
        raise ValueError('Este reparo permite somente Bone_002 e Bone_004; os helpers dos pés ficam preservados.')
    doc, blob = read_glb(source)
    report = {'source': str(source), 'destination': str(destination), 'helpers': helper_names,
              'already_collapsed': False, 'changes': []}
    extras = doc.setdefault('asset', {}).setdefault('extras', {})
    previous = extras.get(MARKER, [])
    if all(name in previous for name in helper_names):
        report['already_collapsed'] = True
        destination.parent.mkdir(parents=True, exist_ok=True)
        write_glb(destination, doc, blob)
        return report
    if doc.get('animations'):
        raise ValueError('O candidato deve estar sem animações; colapsar curvas exigiria outro contrato.')
    if len(doc.get('skins', [])) != 1:
        raise ValueError('Esta ferramenta exige um único skin.')
    nodes = doc['nodes']
    parents = {child: index for index, node in enumerate(nodes) for child in node.get('children', [])}
    matrices = global_matrices(doc)
    skin = doc['skins'][0]
    joints = skin['joints']
    names = {node.get('name'): index for index, node in enumerate(nodes)}
    drop = set()
    replacements = {}
    for name in helper_names:
        if name in previous:
            continue
        if not name.startswith('Bone_') or name not in names:
            raise ValueError('Helper não autorizado ou ausente: ' + name)
        index = names[name]
        parent = parents.get(index)
        children = nodes[index].get('children', [])
        if index not in joints or parent not in joints or len(children) != 1 or children[0] not in joints:
            raise ValueError('Helper deve ligar dois ossos do skin com um único filho: ' + name)
        child = children[0]
        parent_name, child_name = nodes[parent]['name'], nodes[child]['name']
        if not parent_name.endswith('UpLeg') or not child_name.endswith('Leg'):
            raise ValueError('Escopo permite apenas UpLeg → helper → Leg: ' + name)
        # O local concatenado mantém exatamente o global do filho após remover o helper.
        merged = np.linalg.inv(matrices[parent]) @ matrices[child]
        for key in ('translation', 'rotation', 'scale'):
            nodes[child].pop(key, None)
        nodes[child]['matrix'] = merged.T.ravel().tolist()
        siblings = nodes[parent]['children']
        position = siblings.index(index)
        siblings[position:position + 1] = [child]
        drop.add(index)
        replacements[index] = parent
        report['changes'].append({'helper': name, 'parent': parent_name, 'child': child_name})
    kept_joints = [index for index in joints if index not in drop]
    new_joint_index = {node: index for index, node in enumerate(kept_joints)}
    joint_remap = [new_joint_index[replacements.get(node, node)] for node in joints]
    new_blob = bytearray(blob)
    ibm = read_accessor(doc, blob, skin['inverseBindMatrices'])
    skin['inverseBindMatrices'] = append_accessor(
        doc, new_blob, [ibm[index] for index, node in enumerate(joints) if node not in drop], 5126, 'MAT4')
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            attributes = primitive['attributes']
            sets = sorted(int(key.split('_')[1]) for key in attributes if key.startswith('JOINTS_'))
            if not sets:
                continue
            joint_rows = [read_accessor(doc, blob, attributes[f'JOINTS_{index}']) for index in sets]
            weight_rows = [read_accessor(doc, blob, attributes[f'WEIGHTS_{index}']) for index in sets]
            rows = []
            for vertex in range(len(joint_rows[0])):
                influences = {}
                old_sum = 0.0
                for js, ws in zip(joint_rows, weight_rows):
                    for old_joint, weight in zip(js[vertex], ws[vertex]):
                        old_sum += weight
                        if weight > 0:
                            target = joint_remap[int(old_joint)]
                            influences[target] = influences.get(target, 0.0) + weight
                ordered = sorted(influences.items(), key=lambda value: -value[1])
                assert len(ordered) <= 4 * len(sets)
                assert abs(sum(weight for _, weight in ordered) - old_sum) < 1e-6
                rows.append(ordered + [(0, 0.0)] * (4 * len(sets) - len(ordered)))
            for offset, set_index in enumerate(sets):
                chunk = [row[offset*4:offset*4+4] for row in rows]
                attributes[f'JOINTS_{set_index}'] = append_accessor(doc, new_blob, [tuple(j for j, _ in row) for row in chunk], 5123, 'VEC4')
                attributes[f'WEIGHTS_{set_index}'] = append_accessor(doc, new_blob, [tuple(w for _, w in row) for row in chunk], 5126, 'VEC4')
    # Reindexar evita deixar nós auxiliares órfãos no arquivo e referências ambíguas.
    node_remap = {old: new for new, old in enumerate(index for index in range(len(nodes)) if index not in drop)}
    new_nodes = []
    for old_index, node in enumerate(nodes):
        if old_index in drop:
            continue
        if 'children' in node:
            node['children'] = [node_remap[child] for child in node['children']]
        new_nodes.append(node)
    doc['nodes'] = new_nodes
    skin['joints'] = [node_remap[index] for index in kept_joints]
    if 'skeleton' in skin:
        skin['skeleton'] = node_remap[skin['skeleton']]
    for scene in doc.get('scenes', []):
        scene['nodes'] = [node_remap[index] for index in scene.get('nodes', [])]
    extras[MARKER] = sorted(set(previous) | set(helper_names))
    report['bones_before'] = len(joints)
    report['bones_after'] = len(kept_joints)
    destination.parent.mkdir(parents=True, exist_ok=True)
    write_glb(destination, doc, collect_garbage(doc, bytes(new_blob)))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--helpers', required=True, help='Allowlist de nomes separados por vírgula.')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if args.report and args.report.resolve() in {args.source.resolve(), args.destination.resolve()}:
        parser.error('O relatório não pode substituir o GLB de origem ou destino.')
    result = collapse(args.source, args.destination, args.helpers.split(','))
    output = json.dumps(result, ensure_ascii=False, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output + '\n', encoding='utf-8')
    print(output)
