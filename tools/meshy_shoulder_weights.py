#!/usr/bin/env python3
"""Diagnostica e produz candidatos de pesos do ombro, sem sobrescrever o GLB original.

O Shoulder imóvel pode prender a manga enquanto Arm desce. Transferir somente a
influência exterior para Arm preserva os pivôs usados pela IK e não custa runtime.
O resultado é um candidato: métricas offline não substituem captura em movimento.
Requer numpy e reutiliza o leitor/escritor de meshy_slim_glb.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from meshy_slim_glb import read_glb, read_accessor, append_accessor, collect_garbage, write_glb


def smoothstep(start, end, value):
    amount = np.clip((value - start) / (end - start), 0, 1)
    return amount * amount * (3 - 2 * amount)


def global_matrices(doc):
    nodes = doc['nodes']
    parents = {child: i for i, node in enumerate(nodes) for child in node.get('children', [])}
    cache = {}

    def resolve(index):
        if index in cache:
            return cache[index]
        node = nodes[index]
        if 'matrix' in node:
            local = np.array(node['matrix']).reshape(4, 4).T
        else:
            x, y, z, w = node.get('rotation', [0, 0, 0, 1])
            local = np.eye(4)
            local[:3, :3] = np.array([
                [1 - 2*y*y - 2*z*z, 2*x*y - 2*z*w, 2*x*z + 2*y*w],
                [2*x*y + 2*z*w, 1 - 2*x*x - 2*z*z, 2*y*z - 2*x*w],
                [2*x*z - 2*y*w, 2*y*z + 2*x*w, 1 - 2*x*x - 2*y*y],
            ]) @ np.diag(node.get('scale', [1, 1, 1]))
            local[:3, 3] = node.get('translation', [0, 0, 0])
        cache[index] = resolve(parents[index]) @ local if index in parents else local
        return cache[index]

    return [resolve(i) for i in range(len(nodes))]


def process(source, destination=None, strength=0.55, mode='shoulder-to-arm'):
    if destination and source.resolve() == destination.resolve():
        raise ValueError('O destino deve ser diferente do original.')
    if not 0 <= strength <= 1:
        raise ValueError('A intensidade deve ficar entre 0 e 1.')
    doc, blob = read_glb(source)
    matrices = global_matrices(doc)
    mesh_nodes = {node['mesh']: node for node in doc['nodes'] if 'mesh' in node}
    report = {'source': str(source), 'destination': str(destination) if destination else None,
              'strength': strength, 'mode': mode, 'primitives': []}
    if mode not in ('shoulder-to-arm', 'proximal-forearm'):
        raise ValueError('Modo de reparo desconhecido.')
    new_blob = bytearray(blob)
    for mesh_index, mesh in enumerate(doc['meshes']):
        mesh_node = mesh_nodes[mesh_index]
        if 'skin' not in mesh_node:
            continue
        skin = doc['skins'][mesh_node['skin']]
        names = [doc['nodes'][node]['name'].replace('mixamorig_', '').replace('mixamorig:', '')
                 for node in skin['joints']]
        for primitive_index, primitive in enumerate(mesh['primitives']):
            attributes = primitive['attributes']
            positions = np.array(read_accessor(doc, blob, attributes['POSITION']))
            scale = 1.76 / np.ptp(positions[:, 1])
            sets = sorted(int(key.split('_')[1]) for key in attributes if key.startswith('JOINTS_'))
            joints = np.concatenate([np.array(read_accessor(doc, blob, attributes[f'JOINTS_{s}']), int)
                                     for s in sets], axis=1)
            weights = np.concatenate([np.array(read_accessor(doc, blob, attributes[f'WEIGHTS_{s}']))
                                      for s in sets], axis=1)
            original_weights = weights.copy()
            original_joints = joints.copy()
            metrics = {'mesh': mesh_index, 'primitive': primitive_index, 'vertices': len(positions),
                       'triangles': len(read_accessor(doc, blob, primitive['indices'])) // 3,
                       'bones': len(skin['joints']), 'sides': []}
            for side in ('Left', 'Right'):
                shoulder, arm, forearm = [names.index(side + suffix)
                                          for suffix in ('Shoulder', 'Arm', 'ForeArm')]
                clavicle, origin, elbow = [matrices[skin['joints'][index]][:3, 3]
                                          for index in (shoulder, arm, forearm)]
                direction = elbow - origin
                direction /= np.linalg.norm(direction)
                offsets = (positions - origin) * scale
                axial = offsets @ direction
                radial = np.linalg.norm(offsets - axial[:, None] * direction, axis=1)
                outward = offsets[:, 0] * (1 if origin[0] > clavicle[0] else -1)
                # A transição mantém a gola/tronco; a manga ganha influência gradualmente.
                influence = (smoothstep(-0.025, 0.075, outward)
                             * smoothstep(-0.060, 0.120, axial)
                             * (1 - smoothstep(0.140, 0.200, axial))
                             * (1 - smoothstep(0.110, 0.170, radial)))
                if mode == 'proximal-forearm':
                    # ForeArm no topo do paletó arrasta a roupa até o cotovelo: reparar apenas a faixa proximal.
                    influence = ((1 - smoothstep(0.025, 0.130, axial))
                                 * (1 - smoothstep(0.150, 0.270, np.linalg.norm(offsets, axis=1))))
                shoulder_weight = np.sum(np.where(joints == shoulder, weights, 0), axis=1)
                arm_weight = np.sum(np.where(joints == arm, weights, 0), axis=1)
                donor = forearm if mode == 'proximal-forearm' else shoulder
                donor_weight = np.sum(np.where(joints == donor, weights, 0), axis=1)
                region = np.linalg.norm(offsets, axis=1) < 0.15
                changed, skipped, transfer_total, changed_indices = 0, 0, 0.0, []
                for vertex in np.flatnonzero(influence * donor_weight > 1e-7):
                    if mode == 'proximal-forearm':
                        spine = names.index('Spine2')
                        spine_part = 0.85 * float(smoothstep(0.020, 0.110, -outward[vertex]))
                        shoulder_part = (1 - spine_part) * 0.75 * (1 - float(smoothstep(-0.005, 0.090, axial[vertex])))
                        targets = [(spine, spine_part), (shoulder, shoulder_part),
                                   (arm, 1 - spine_part - shoulder_part)]
                        slots = {}
                        occupied = set()
                        for target, fraction in targets:
                            if fraction < 1e-9:
                                continue
                            existing = np.flatnonzero(joints[vertex] == target)
                            free = [int(slot) for slot in np.flatnonzero(weights[vertex] < 1e-9) if int(slot) not in occupied]
                            if len(existing):
                                slot = int(existing[0])
                            elif free:
                                slot = free[0]
                            else:
                                slots = None
                                break
                            slots[target] = slot
                            occupied.add(slot)
                        if slots is None:
                            skipped += 1
                            continue
                        transfer = 0.0
                        for slot in np.flatnonzero(joints[vertex] == donor):
                            delta = weights[vertex, slot] * influence[vertex] * strength
                            weights[vertex, slot] -= delta
                            transfer += delta
                        for target, fraction in targets:
                            if fraction < 1e-9:
                                continue
                            slot = slots[target]
                            joints[vertex, slot] = target
                            weights[vertex, slot] += transfer * fraction
                        changed += 1
                        changed_indices.append(int(vertex))
                        transfer_total += float(transfer)
                        continue
                    arm_slots = np.flatnonzero(joints[vertex] == arm)
                    if len(arm_slots):
                        arm_slot = int(arm_slots[0])
                    else:
                        free = np.flatnonzero(weights[vertex] < 1e-9)
                        if not len(free):
                            skipped += 1
                            continue
                        arm_slot = int(free[0])
                        joints[vertex, arm_slot] = arm
                    transfer = 0.0
                    for slot in np.flatnonzero(joints[vertex] == shoulder):
                        delta = weights[vertex, slot] * influence[vertex] * strength
                        weights[vertex, slot] -= delta
                        transfer += delta
                    weights[vertex, arm_slot] += transfer
                    if transfer > 0:
                        changed += 1
                        changed_indices.append(int(vertex))
                        transfer_total += float(transfer)
                metrics['sides'].append({
                    'side': side, 'rest_arm_angle_deg': float(np.degrees(np.arccos(np.clip(-direction[1], -1, 1)))),
                    'clavicle_length_mm': float(np.linalg.norm(origin - clavicle) * scale * 1000),
                    'region_vertices': int(region.sum()),
                    'region_mean_shoulder_weight': float(shoulder_weight[region].mean()),
                    'region_mean_arm_weight': float(arm_weight[region].mean()),
                    'region_mean_forearm_weight': float(np.sum(np.where(joints == forearm, original_weights, 0), axis=1)[region].mean()),
                    'affected_vertices': changed, 'affected_indices': changed_indices,
                    'skipped_full_influences': skipped, 'weight_transferred_total': transfer_total,
                })
            metrics['max_sum_error'] = float(np.max(np.abs(weights.sum(axis=1) - original_weights.sum(axis=1))))
            assert metrics['max_sum_error'] < 1e-6
            assert weights.min() >= -1e-9
            metrics['max_vertex_weight_delta'] = float(np.abs(weights - original_weights).max())
            # Slots novos usam apenas influência zero, sem descartar contribuições anteriores.
            assert np.all((joints == original_joints) | (original_weights < 1e-9))
            report['primitives'].append(metrics)
            if destination:
                for offset, set_index in enumerate(sets):
                    attributes[f'JOINTS_{set_index}'] = append_accessor(
                        doc, new_blob, [tuple(row) for row in joints[:, offset*4:offset*4+4]], 5123, 'VEC4')
                    attributes[f'WEIGHTS_{set_index}'] = append_accessor(
                        doc, new_blob, [tuple(row) for row in weights[:, offset*4:offset*4+4]], 5126, 'VEC4')
    if destination:
        if destination.exists():
            raise FileExistsError('O candidato já existe; escolha outro destino para preservar evidência.')
        destination.parent.mkdir(parents=True, exist_ok=True)
        write_glb(destination, doc, collect_garbage(doc, bytes(new_blob)))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--destination', type=Path)
    parser.add_argument('--strength', type=float, default=0.55)
    parser.add_argument('--mode', choices=['shoulder-to-arm', 'proximal-forearm'], default='shoulder-to-arm')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    protected_paths = {args.source.resolve()}
    if args.destination:
        protected_paths.add(args.destination.resolve())
    if args.report and args.report.resolve() in protected_paths:
        parser.error('O relatório não pode substituir o GLB de origem ou destino.')
    result = process(args.source, args.destination, args.strength, args.mode)
    output = json.dumps(result, ensure_ascii=False, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output + '\n', encoding='utf-8')
    print(output)
