#!/usr/bin/env python3
"""Repara mãos presas ao antebraço em um candidato separado; exige validação visual.

A mão do terno masculino tinha maioria dos dedos pesada em ForeArm, de modo que
girar Hand e fechar dedos pelo limiar Hand >= 0,6 deixava quase toda a mão imóvel.
O reparo usa transição junto ao punho e só curva os vértices recém-elegíveis.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from meshy_shoulder_weights import global_matrices, smoothstep
from meshy_slim_glb import read_glb, read_accessor, append_accessor, collect_garbage, write_glb
from meshy_curl_hands import rotate

MARKER = 'hand_weights_repaired_v1'


def repair(source, destination, degrees=55.0):
    source, destination = Path(source), Path(destination)
    if source.resolve() == destination.resolve():
        raise ValueError('O reparo deve ir para outro arquivo, preservando o original.')
    if destination.exists():
        raise FileExistsError('O destino já existe; escolha outro para preservar evidência.')
    doc, blob = read_glb(source)
    report = {'source': str(source), 'destination': str(destination), 'already_repaired': False, 'sides': []}
    extras = doc.setdefault('asset', {}).setdefault('extras', {})
    if extras.get(MARKER):
        report['already_repaired'] = True
        destination.parent.mkdir(parents=True, exist_ok=True)
        write_glb(destination, doc, blob)
        return report
    if extras.get('hands_curled') != degrees:
        raise ValueError('Este reparo incremental exige a marca hands_curled igual ao ângulo pedido.')
    if len(doc['skins']) != 1 or len(doc['meshes']) != 1 or len(doc['meshes'][0]['primitives']) != 1:
        raise ValueError('O reparo exige um corpo, uma primitive e um skin para evitar alterações ambíguas.')
    matrices = global_matrices(doc)
    skin = doc['skins'][0]
    names = [doc['nodes'][node]['name'].replace('mixamorig_', '').replace('mixamorig:', '')
             for node in skin['joints']]
    attributes = doc['meshes'][0]['primitives'][0]['attributes']
    positions = np.array(read_accessor(doc, blob, attributes['POSITION']))
    normals = np.array(read_accessor(doc, blob, attributes['NORMAL']))
    original_positions, original_normals = positions.copy(), normals.copy()
    scale = 1.76 / np.ptp(positions[:, 1])
    sets = sorted(int(key.split('_')[1]) for key in attributes if key.startswith('JOINTS_'))
    joints = np.concatenate([np.array(read_accessor(doc, blob, attributes[f'JOINTS_{s}']), int)
                             for s in sets], axis=1)
    weights = np.concatenate([np.array(read_accessor(doc, blob, attributes[f'WEIGHTS_{s}']))
                              for s in sets], axis=1)
    original_joints, original_weights = joints.copy(), weights.copy()
    curled_indices = []
    changed_indices = []
    for side in ('Left', 'Right'):
        hand, forearm = [names.index(side + suffix) for suffix in ('Hand', 'ForeArm')]
        hand_origin = matrices[skin['joints'][hand]][:3, 3]
        fore_origin = matrices[skin['joints'][forearm]][:3, 3]
        direction = hand_origin - fore_origin
        direction /= np.linalg.norm(direction)
        offsets = (original_positions - hand_origin) * scale
        axial = offsets @ direction
        radial = np.linalg.norm(offsets - axial[:, None] * direction, axis=1)
        # Dedos devem seguir Hand; a queda radial evita capturar uma superfície vizinha.
        mask = (smoothstep(-0.005, 0.025, axial)
                * (1 - smoothstep(0.080, 0.110, radial))
                * (1 - smoothstep(0.170, 0.200, axial)))
        old_hand = np.sum(np.where(original_joints == hand, original_weights, 0), axis=1)
        old_fore = np.sum(np.where(original_joints == forearm, original_weights, 0), axis=1)
        changed, skipped, transferred = [], 0, 0.0
        for vertex in np.flatnonzero(mask * old_fore > 1e-7):
            slots = np.flatnonzero(joints[vertex] == hand)
            if len(slots):
                target_slot = int(slots[0])
            else:
                available = np.flatnonzero(weights[vertex] < 1e-9)
                if not len(available):
                    skipped += 1
                    continue
                target_slot = int(available[0])
                joints[vertex, target_slot] = hand
            amount = 0.0
            for slot in np.flatnonzero(joints[vertex] == forearm):
                delta = weights[vertex, slot] * mask[vertex]
                weights[vertex, slot] -= delta
                amount += delta
            weights[vertex, target_slot] += amount
            if amount > 0:
                changed.append(int(vertex))
                transferred += float(amount)
        new_hand = np.sum(np.where(joints == hand, weights, 0), axis=1)
        eligible = new_hand >= 0.6
        newly_eligible = eligible & (old_hand < 0.6)
        # A geometria dos elegíveis antigos já foi curvada no import; não dobrá-la novamente.
        length = float(np.max((original_positions[eligible] - hand_origin) @ direction))
        knuckle = 0.42 * length
        hinge = hand_origin + direction * knuckle
        axis = np.cross(direction, np.array([0.0, 0.0, 1.0]))
        axis /= np.linalg.norm(axis)
        curled = []
        for vertex in np.flatnonzero(newly_eligible):
            distance = float((original_positions[vertex] - hand_origin) @ direction)
            fraction = min(max((distance - knuckle) / max(length - knuckle, 1e-6), 0), 1)
            if fraction <= 0:
                continue
            angle = np.radians(degrees) * fraction
            positions[vertex] = hinge + np.array(rotate(original_positions[vertex] - hinge, axis, angle))
            normals[vertex] = rotate(original_normals[vertex], axis, angle)
            curled.append(int(vertex))
        changed_indices.extend(changed)
        curled_indices.extend(curled)
        distal = (axial > 0.025) & (axial < 0.160) & (radial < 0.090)
        report['sides'].append({
            'side': side, 'weights_changed_indices': changed, 'curled_indices': curled,
            'old_eligible_vertices': int((old_hand >= 0.6).sum()),
            'new_eligible_vertices': int(eligible.sum()), 'newly_eligible_vertices': int(newly_eligible.sum()),
            'curled_vertices': len(curled), 'skipped_full_influences': skipped,
            'transferred_weight_total': transferred, 'hand_length_mm': length * scale * 1000,
            'distal_vertices': int(distal.sum()),
            'distal_old_hand_mean': float(old_hand[distal].mean()),
            'distal_new_hand_mean': float(new_hand[distal].mean()),
            'max_geometry_displacement_mm': float(np.linalg.norm(positions[curled] - original_positions[curled], axis=1).max() * scale * 1000) if curled else 0.0,
        })
    assert np.max(np.abs(weights.sum(axis=1) - original_weights.sum(axis=1))) < 1e-6
    assert weights.min() >= -1e-9
    assert np.all((joints == original_joints) | (original_weights < 1e-9))
    untouched = np.ones(len(positions), dtype=bool)
    untouched[curled_indices] = False
    assert np.array_equal(positions[untouched], original_positions[untouched])
    assert np.array_equal(normals[untouched], original_normals[untouched])
    extras[MARKER] = {'degrees': degrees, 'newly_eligible_only': True,
                      'changed_vertices': len(set(changed_indices)), 'curled_vertices': len(set(curled_indices))}
    new_blob = bytearray(blob)
    for offset, set_index in enumerate(sets):
        attributes[f'JOINTS_{set_index}'] = append_accessor(doc, new_blob, [tuple(row) for row in joints[:, offset*4:offset*4+4]], 5123, 'VEC4')
        attributes[f'WEIGHTS_{set_index}'] = append_accessor(doc, new_blob, [tuple(row) for row in weights[:, offset*4:offset*4+4]], 5126, 'VEC4')
    attributes['POSITION'] = append_accessor(doc, new_blob, [tuple(row) for row in positions], 5126, 'VEC3')
    attributes['NORMAL'] = append_accessor(doc, new_blob, [tuple(row) for row in normals], 5126, 'VEC3')
    doc['accessors'][attributes['POSITION']]['min'] = positions.min(axis=0).tolist()
    doc['accessors'][attributes['POSITION']]['max'] = positions.max(axis=0).tolist()
    destination.parent.mkdir(parents=True, exist_ok=True)
    write_glb(destination, doc, collect_garbage(doc, bytes(new_blob)))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--degrees', type=float, default=55.0)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if args.report and args.report.resolve() in {args.source.resolve(), args.destination.resolve()}:
        parser.error('O relatório não pode substituir o GLB de origem ou destino.')
    result = repair(args.source, args.destination, args.degrees)
    output = json.dumps(result, ensure_ascii=False, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output + '\n', encoding='utf-8')
    print(output)
