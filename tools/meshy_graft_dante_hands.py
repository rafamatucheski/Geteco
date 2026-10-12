#!/usr/bin/env python3
"""Transplanta mãos/morphs autorados do Dante para um candidato NPC, sem motor.

Remove faces das mãos antigas em vez de escondê-las. As mãos transplantadas têm
peso rígido Hand, evitando que a orientação do cotovelo rasgue os dedos. A segunda
superfície conserva UV/albedo do Dante; exige material por superfície no runtime.
"""
import argparse
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image
from meshy_slim_glb import read_glb, read_accessor, append_accessor, collect_garbage, write_glb
from meshy_curl_hands import node_local


def global_matrices(doc):
    parents = {child: i for i, node in enumerate(doc['nodes']) for child in node.get('children', [])}
    cache = {}
    def resolve(index):
        if index not in cache:
            local = np.array(node_local(doc['nodes'][index]))
            cache[index] = resolve(parents[index])@local if index in parents else local
        return cache[index]
    return [resolve(index) for index in range(len(doc['nodes']))]


def influences(doc, blob, attributes):
    result = np.zeros((doc['accessors'][attributes['POSITION']]['count'], len(doc['skins'][0]['joints'])))
    for key in attributes:
        if key.startswith('JOINTS_'):
            joints = np.array(read_accessor(doc, blob, attributes[key]), int)
            weights = np.array(read_accessor(doc, blob, attributes[key.replace('JOINTS', 'WEIGHTS')]))
            for column in range(4):
                result[np.arange(len(result)), joints[:, column]] += weights[:, column]
    return result


def albedo(doc, blob, primitive):
    index = doc['materials'][primitive.get('material', 0)]['pbrMetallicRoughness']['baseColorTexture']['index']
    image = doc['images'][doc['textures'][index]['source']]
    view = doc['bufferViews'][image['bufferView']]
    payload = blob[view.get('byteOffset', 0):view.get('byteOffset', 0)+view['byteLength']]
    return Image.open(io.BytesIO(payload)).convert('RGB')


def samples(image, uvs):
    pixels = np.array(image)/255.0
    x = np.clip((uvs[:, 0]*(image.width-1)).astype(int), 0, image.width-1)
    y = np.clip((uvs[:, 1]*(image.height-1)).astype(int), 0, image.height-1)
    return pixels[y, x]


def graft(source, donor, destination, palm_sign=-1, wrist_style='suit'):
    if wrist_style not in ('suit', 'skin', 'sleeve'):
        raise ValueError('wrist_style deve ser suit, skin ou sleeve.')
    source, donor, destination = map(Path, (source, donor, destination))
    if destination.exists() or destination.resolve() in (source.resolve(), donor.resolve()):
        raise ValueError('O destino deve ser novo e preservar as entradas.')
    doc, blob = read_glb(source)
    dante, donor_blob = read_glb(donor)
    if len(doc.get('meshes', [])) != 1 or len(doc['meshes'][0]['primitives']) != 1 or len(doc.get('skins', [])) != 1 or doc['meshes'][0]['primitives'][0].get('targets'):
        raise ValueError('Use o corpo original com uma malha/superfície/skin; não um transplante já aplicado.')
    if doc.get('asset', {}).get('extras', {}).get('dante_hands_grafted_v1'):
        raise ValueError('Este arquivo já recebeu transplante; preserve-o e use o corpo original para outro candidato.')
    primitive, dp = doc['meshes'][0]['primitives'][0], dante['meshes'][0]['primitives'][0]
    attributes, da = primitive['attributes'], dp['attributes']
    p = np.array(read_accessor(doc, blob, attributes['POSITION']))
    dpos = np.array(read_accessor(dante, donor_blob, da['POSITION']))
    dnormal = np.array(read_accessor(dante, donor_blob, da['NORMAL']))
    duv = np.array(read_accessor(dante, donor_blob, da['TEXCOORD_0']))
    npc_image, donor_image = albedo(doc, blob, primitive), albedo(dante, donor_blob, dp)
    npc_uv = np.array(read_accessor(doc, blob, attributes['TEXCOORD_0']))
    npc_colors, donor_colors = samples(npc_image, npc_uv), samples(donor_image, duv)
    npc_skin = (npc_colors[:, 0] > npc_colors[:, 1]*1.15) & (npc_colors[:, 0] > npc_colors[:, 2]*1.25) & (npc_colors[:, 0] > 0.30)
    donor_skin = (donor_colors[:, 0] > donor_colors[:, 1]*1.02) & (donor_colors[:, 1] > donor_colors[:, 2]*1.07) & (donor_colors[:, 0] > 0.25)
    w, dw = influences(doc, blob, attributes), influences(dante, donor_blob, da)
    ng, dg = global_matrices(doc), global_matrices(dante)
    skin, ds = doc['skins'][0], dante['skins'][0]
    names = [doc['nodes'][i]['name'].replace('mixamorig:', '').replace('mixamorig_', '') for i in skin['joints']]
    dnames = [dante['nodes'][i]['name'] for i in ds['joints']]
    scale = 1.76 / np.ptp(p[:, 1])
    source_tris = np.array(read_accessor(doc, blob, primitive['indices']), int).ravel().reshape(-1, 3)
    donor_tris = np.array(read_accessor(dante, donor_blob, dp['indices']), int).ravel().reshape(-1, 3)
    remove_faces = np.zeros(len(source_tris), dtype=bool)
    hand_envelope = np.zeros(len(p), dtype=bool)
    hand_points, hand_normals, hand_uvs, hand_joints, hand_tris = [], [], [], [], []
    hand_weights = []
    hand_delta = [[], []]
    hand_normal_delta = [[], []]
    donor_shape_names = dante['meshes'][0]['extras']['targetNames']
    donor_deltas = [np.array(read_accessor(dante, donor_blob, dp['targets'][donor_shape_names.index(name)]['POSITION']))
                    for name in ('GripRight', 'GripLeft')]
    donor_normal_deltas = [np.array(read_accessor(dante, donor_blob, dp['targets'][donor_shape_names.index(name)]['NORMAL']))
                           for name in ('GripRight', 'GripLeft')]
    report = {'source': str(source), 'donor': str(donor), 'destination': str(destination), 'sides': []}
    profile = []
    vertex_offset = 0
    cuff_points, cuff_normals, cuff_uvs, cuff_joints, cuff_triangles = [], [], [], [], []
    body_weights = w.copy()
    body_rows = {key: list(read_accessor(doc, blob, accessor)) for key, accessor in attributes.items()
                 if not key.startswith(('JOINTS_', 'WEIGHTS_'))}
    body_extra_weights = []
    body_polygons = [list(triangle) for triangle in source_tris]
    clipped_vertices = []
    hand_tint_samples = []
    source_triangle_uv = npc_uv[source_tris].mean(axis=1)
    source_triangle_colors = samples(npc_image, source_triangle_uv)
    source_triangle_skin = ((source_triangle_colors[:, 0] > source_triangle_colors[:, 1]*1.15)
                            & (source_triangle_colors[:, 0] > source_triangle_colors[:, 2]*1.25)
                            & (source_triangle_colors[:, 0] > 0.22))
    for side in ('Right', 'Left'):
        cuff_triangle_start = len(cuff_triangles)
        hand, fore = [names.index(side+suffix) for suffix in ('Hand', 'ForeArm')]
        dh, de = [dnames.index(side+suffix) for suffix in ('Hand', 'Hand_End')]
        origin = ng[skin['joints'][hand]][:3, 3]
        finger = origin-ng[skin['joints'][fore]][:3, 3]
        finger /= np.linalg.norm(finger)
        normal = np.array([0.0, 0.0, 1.0])
        normal -= finger*finger.dot(normal)
        normal /= np.linalg.norm(normal)
        lateral = np.cross(finger, normal)
        frame = np.column_stack([lateral, finger, normal])
        dorigin = dg[ds['joints'][dh]][:3, 3]
        dfinger = dg[ds['joints'][de]][:3, 3]-dorigin
        dfinger /= np.linalg.norm(dfinger)
        dnormal_axis = np.array([0.0, float(palm_sign), 0.0])
        dnormal_axis -= dfinger*dfinger.dot(dnormal_axis)
        dnormal_axis /= np.linalg.norm(dnormal_axis)
        dlateral = np.cross(dfinger, dnormal_axis)
        donor_frame = np.column_stack([dlateral, dfinger, dnormal_axis])
        rotation = frame@donor_frame.T
        donor_to_asset_scale = 1.03*0.95/scale
        offset = (p-origin)*scale
        axial = offset@finger
        radial = np.linalg.norm(offset-axial[:, None]*finger, axis=1)
        # A seleção é estritamente distal/local. Peso Hand alto não autoriza apagar
        # tecido do punho; a cor no centro da face distingue pele de camisa/paletó.
        envelope = ((np.linalg.norm(offset, axis=1) <= 0.220) & (axial > -0.040) & (radial < 0.160))
        hand_envelope |= envelope
        remove_faces |= envelope[source_tris].any(axis=1)
        # A superfície do paletó não deve girar junto da nova mão rígida.
        body_weights[:, fore] += body_weights[:, hand]
        body_weights[:, hand] = 0.0
        # Cortar no plano conserva os trechos proximais dos triângulos grandes;
        # apagar a face inteira deixava bordas até 20 cm antes do punho.
        intersection_cache = {}
        side_intersections = []
        cut_edges = []
        def axial_distance(index):
            return float((np.array(body_rows['POSITION'][index])-origin).dot(finger)*scale + 0.040)
        def intersection(a, b):
            key = tuple(sorted((a, b)))
            if key in intersection_cache:
                return intersection_cache[key]
            da, db = axial_distance(a), axial_distance(b)
            amount = da/(da-db)
            index = len(body_rows['POSITION'])
            for attribute, rows in body_rows.items():
                value = np.array(rows[a])*(1-amount)+np.array(rows[b])*amount
                if attribute == 'NORMAL':
                    value /= np.linalg.norm(value)
                rows.append(tuple(value))
            wa = body_weights[a] if a < len(body_weights) else body_extra_weights[a-len(body_weights)]
            wb = body_weights[b] if b < len(body_weights) else body_extra_weights[b-len(body_weights)]
            border_weights = np.zeros(len(names))
            border_weights[fore] = 1.0
            body_extra_weights.append(border_weights)
            intersection_cache[key] = index
            side_intersections.append(index)
            clipped_vertices.append({'index': index, 'from': [int(a), int(b)], 'amount': amount, 'side': side})
            return index
        for face_index in np.flatnonzero(envelope[source_tris].any(axis=1)):
            polygon = body_polygons[face_index]
            if not polygon:
                continue
            result = []
            for a, b in zip(polygon, polygon[1:]+polygon[:1]):
                inside_a, inside_b = axial_distance(a) <= 1e-9, axial_distance(b) <= 1e-9
                if inside_a:
                    result.append(a)
                if inside_a != inside_b:
                    result.append(intersection(a, b))
            body_polygons[face_index] = result
            if len(result) >= 3:
                for a, b in zip(result, result[1:]+result[:1]):
                    if abs(axial_distance(a)) < 1e-8 and abs(axial_distance(b)) < 1e-8:
                        cut_edges.append((a, b))
        dweight = dw[:, dh]+dw[:, de]
        donor_axial = (dpos-dorigin)@dfinger
        # Sem limiar de cor: sombras/unhas não podem abrir buracos nos dedos.
        candidate_faces = ((dweight[donor_tris] > 0.01).any(axis=1)
                           & (donor_axial[donor_tris] > 0.020).any(axis=1))
        dp_rows, dn_rows, duv_rows = dpos.tolist(), dnormal.tolist(), duv.tolist()
        ddelta_rows = [rows.tolist() for rows in donor_deltas]
        dndelta_rows = [rows.tolist() for rows in donor_normal_deltas]
        donor_intersections = {}
        def donor_distance(index):
            return float((np.array(dp_rows[index])-dorigin).dot(dfinger)-0.020)
        def donor_intersection(a, b):
            key = tuple(sorted((int(a), int(b))))
            if key in donor_intersections:
                return donor_intersections[key]
            amount = donor_distance(a)/(donor_distance(a)-donor_distance(b))
            index = len(dp_rows)
            for rows in [dp_rows, dn_rows, duv_rows]+ddelta_rows+dndelta_rows:
                value = np.array(rows[a])*(1-amount)+np.array(rows[b])*amount
                if rows is dn_rows:
                    value /= np.linalg.norm(value)
                rows.append(value.tolist())
            donor_intersections[key] = index
            return index
        donor_triangles = []
        for face_index in np.flatnonzero(candidate_faces):
            original = donor_tris[face_index].tolist()
            polygon = []
            for a, b in zip(original, original[1:]+original[:1]):
                inside_a, inside_b = donor_distance(a) >= -1e-9, donor_distance(b) >= -1e-9
                if inside_a:
                    polygon.append(a)
                if inside_a != inside_b:
                    polygon.append(donor_intersection(a, b))
            for index in range(1, len(polygon)-1):
                donor_triangles.append([polygon[0], polygon[index], polygon[index+1]])
        selected_tris = np.array(donor_triangles, int)
        side_dpos, side_dnormal, side_duv = np.array(dp_rows), np.array(dn_rows), np.array(duv_rows)
        side_deltas, side_normal_deltas = [np.array(rows) for rows in ddelta_rows], [np.array(rows) for rows in dndelta_rows]
        side_donor_axial = (side_dpos-dorigin)@dfinger
        original_picked = np.unique(selected_tris)
        hand_tint_samples.extend(samples(donor_image, side_duv[original_picked]).tolist())
        remap = {int(old): i for i, old in enumerate(original_picked)}
        local_triangles = np.array([[remap[int(index)] for index in triangle] for triangle in selected_tris])
        # A camisa do Dante ainda ocupava alguns pixels proximais. Recolorir por
        # face com vértices UV duplicados elimina a borda sem cortar pele/morphs
        # ou interpolar através da ilha de textura do tecido.
        palm_candidates = np.flatnonzero(donor_skin & (dweight > 0.8) & (donor_axial > 0.030) & (donor_axial < 0.090))
        if not len(palm_candidates):
            raise ValueError('Não foi encontrada pele no centro da palma do Dante.')
        palm_color = np.median(donor_colors[palm_candidates], axis=0)
        nearest_skin = palm_candidates[np.argmin(np.linalg.norm(donor_colors[palm_candidates]-palm_color, axis=1))]
        skin_uv = duv[nearest_skin]
        face_colors = samples(donor_image, side_duv[selected_tris].mean(axis=1))
        face_skin = ((face_colors[:, 0] > face_colors[:, 1]*1.02) & (face_colors[:, 1] > face_colors[:, 2]*1.07)
                     & (face_colors[:, 0] > 0.25))
        repair_faces = np.flatnonzero((side_donor_axial[selected_tris].max(axis=1) < 0.060) & ~face_skin)
        donor_indices = original_picked.tolist()
        transplanted_uvs = side_duv[original_picked].tolist()
        for face_index in repair_faces:
            start = len(donor_indices)
            donor_indices.extend(selected_tris[face_index].tolist())
            transplanted_uvs.extend([skin_uv.tolist()]*3)
            local_triangles[face_index] = [start, start+1, start+2]
        picked = np.array(donor_indices, int)
        transformed_points = origin+(side_dpos[picked]-dorigin)@rotation.T*donor_to_asset_scale
        transformed_normals = side_dnormal[picked]@rotation.T
        hand_points.extend(transformed_points.tolist())
        hand_normals.extend(transformed_normals.tolist())
        hand_uvs.extend(transplanted_uvs)
        hand_joints.extend([(hand, 0, 0, 0)]*len(picked))
        hand_weights.extend([(1.0, 0.0, 0.0, 0.0)]*len(picked))
        hand_tris.extend((local_triangles+vertex_offset).tolist())
        for shape in range(2):
            hand_delta[shape].extend((side_deltas[shape][picked]@rotation.T*donor_to_asset_scale).tolist())
            hand_normal_delta[shape].extend((side_normal_deltas[shape][picked]@rotation.T).tolist())
        # As bordas irregulares do recorte de textura não são extrudadas: elas
        # criavam tiras. Uma ponte tubular regular permanece dentro da manga.
        rounded = np.round(side_dpos[picked], 5)
        _, geometric_ids = np.unique(rounded, axis=0, return_inverse=True)
        representatives = {int(group): int(np.flatnonzero(geometric_ids == group)[0]) for group in np.unique(geometric_ids)}
        geometric_edges = np.sort(geometric_ids[np.vstack([local_triangles[:, [0, 1]], local_triangles[:, [1, 2]], local_triangles[:, [2, 0]]])], axis=1)
        edge_values, edge_counts = np.unique(geometric_edges, axis=0, return_counts=True)
        wrist_edges = [(representatives[int(a)], representatives[int(b)]) for (a, b), count in zip(edge_values, edge_counts)
                       if count == 1 and side_donor_axial[picked[representatives[int(a)]]] < 0.025
                       and side_donor_axial[picked[representatives[int(b)]]] < 0.025]
        ring_count = 18
        palm_candidates = np.flatnonzero(donor_skin & (dweight > 0.8) & (donor_axial > 0.030) & (donor_axial < 0.090))
        if not len(palm_candidates):
            raise ValueError('Não foi encontrada pele no centro da palma do Dante.')
        palm_color = np.median(donor_colors[palm_candidates], axis=0)
        nearest_skin = palm_candidates[np.argmin(np.linalg.norm(donor_colors[palm_candidates]-palm_color, axis=1))]
        skin_uv = duv[nearest_skin]
        # A mão tem uma seção assimétrica mais larga que o antigo tubo 27/20 mm.
        # Fechar diretamente cada aresta real elimina os até 17 mm descobertos,
        # sem alterar dedos, forma autorada ou a borda distal do morph.
        boundary_vertices = sorted({index for edge in wrist_edges for index in edge})
        proximal_ring, middle_ring, distal_ring = {}, {}, {}
        for old_index in boundary_vertices:
            distal = transformed_points[old_index]
            co = frame.T@(distal-origin)*scale
            theta = np.arctan2(co[2]/0.020, co[0]/0.027)
            proximal = origin+(finger*(-0.040)+lateral*np.cos(theta)*0.027+normal*np.sin(theta)*0.020)/scale
            for amount, target, point in [(0.0, proximal_ring, proximal), (0.5, middle_ring, (proximal+distal)*0.5),
                                          (1.0, distal_ring, distal)]:
                target[old_index] = len(hand_points)
                hand_points.append(point.tolist())
                hand_normals.append(transformed_normals[old_index].tolist())
                hand_uvs.append(skin_uv.tolist())
                hand_joints.append((fore, hand, 0, 0))
                hand_weights.append((1.0-amount, amount, 0.0, 0.0))
                for shape in range(2):
                    hand_delta[shape].append((side_deltas[shape][picked[old_index]]@rotation.T*donor_to_asset_scale*amount).tolist())
                    hand_normal_delta[shape].append((side_normal_deltas[shape][picked[old_index]]@rotation.T*amount).tolist())
        bridge_faces_start = len(hand_tris)
        # A costura UV exige duplicar os vértices distais: posição, pesos e deltas
        # idênticos mantêm a conexão, UV constante evita atravessar tecido do atlas.
        for a, b in wrist_edges:
            for start_a, start_b, end_a, end_b in [(proximal_ring[a], proximal_ring[b], middle_ring[a], middle_ring[b]),
                                                 (middle_ring[a], middle_ring[b], distal_ring[a], distal_ring[b])]:
                for triangle in [[start_a, start_b, end_a], [start_b, end_b, end_a]]:
                    positions = np.array([hand_points[index] for index in triangle])
                    assigned_normal = np.mean([hand_normals[index] for index in triangle], axis=0)
                    geometric_normal = np.cross(positions[1]-positions[0], positions[2]-positions[0])
                    if geometric_normal.dot(assigned_normal) < 0:
                        triangle = [triangle[0], triangle[2], triangle[1]]
                    hand_tris.append(triangle)
        # Todo o cuff antigo distal é removido. O substituto é um tubo curto em
        # ForeArm, evitando que o punho da mão abra a camisa como papel.
        local = np.linalg.norm(offset, axis=1) < 0.180
        luminance = npc_colors.mean(axis=1)
        saturated = npc_colors.max(axis=1)-npc_colors.min(axis=1)
        cloth_candidates = np.flatnonzero(local & (luminance < 0.45) & (saturated < 0.10))
        white_candidates = np.flatnonzero(local & (luminance > 0.65) & (saturated < 0.12))
        if wrist_style == 'suit':
            if not len(cloth_candidates):
                raise ValueError('Não foi encontrada uma amostra local do paletó para reconstruir o cuff.')
            if not len(white_candidates):
                white_candidates = np.flatnonzero((luminance > 0.75) & (saturated < 0.10))
            dark_uv = npc_uv[cloth_candidates[np.argmin(np.linalg.norm(offset[cloth_candidates], axis=1))]]
            white_uv = npc_uv[white_candidates[np.argmin(np.linalg.norm(offset[white_candidates], axis=1))]]
        else:
            # Sample sleeve fabric proximal to the cut, not a pale seam or
            # misclassified skin vertex immediately beside the old hand.
            candidates = np.flatnonzero(local & (npc_skin if wrist_style == 'skin'
                                                  else ((axial < -0.050) & (axial > -0.120)
                                                        & (w[:, fore] + w[:, hand] > 0.5))))
            if not len(candidates):
                raise ValueError('Não foi encontrada amostra local para o acabamento do punho.')
            if wrist_style == 'sleeve':
                fabric_color = np.median(npc_colors[candidates], axis=0)
                nearest = candidates[np.argmin(np.linalg.norm(npc_colors[candidates]-fabric_color, axis=1))]
            else:
                nearest = candidates[np.argmin(np.linalg.norm(offset[candidates], axis=1))]
            dark_uv = white_uv = npc_uv[nearest]
        cuff_x, cuff_z = (.028, .021) if wrist_style == 'skin' else (.038, .031)
        # O início do paletó segue a borda REAL do recorte, incluindo seu centro
        # lateral. A borda e o cuff usam ForeArm para coincidirem também posados.
        seen_cut_edges = set()
        for a, b in cut_edges:
            pa, pb = np.array(body_rows['POSITION'][a]), np.array(body_rows['POSITION'][b])
            edge_key = tuple(sorted((tuple(np.round(pa, 6)), tuple(np.round(pb, 6)))))
            if edge_key in seen_cut_edges or np.linalg.norm(pa-pb) < 1e-6:
                continue
            seen_cut_edges.add(edge_key)
            ends = []
            for point in (pa, pb):
                co = frame.T@(point-origin)*scale
                theta = np.arctan2(co[2]/cuff_z, co[0]/cuff_x)
                ends.append(origin+(finger*(-0.014)+lateral*np.cos(theta)*cuff_x+normal*np.sin(theta)*cuff_z)/scale)
            quad = [pa, pb, ends[1], ends[0]]
            radial_outward = np.mean(quad, axis=0)-origin
            radial_outward -= finger*radial_outward.dot(finger)
            geo = np.cross(quad[1]-quad[0], quad[2]-quad[0])
            if geo.dot(radial_outward) < 0:
                quad = [quad[1], quad[0], quad[3], quad[2]]
            geo = np.cross(quad[1]-quad[0], quad[2]-quad[0])+np.cross(quad[2]-quad[0], quad[3]-quad[0])
            if np.linalg.norm(geo) < 1e-9:
                continue
            geo /= np.linalg.norm(geo)
            start_index = len(cuff_points)
            cuff_points.extend([point.tolist() for point in quad])
            cuff_normals.extend([geo.tolist()]*4)
            cuff_uvs.extend([dark_uv.tolist()]*4)
            cuff_joints.extend([(fore, 0, 0, 0)]*4)
            cuff_triangles.extend([[start_index, start_index+1, start_index+2], [start_index, start_index+2, start_index+3]])
        for start, end, uv in [(-0.014, -0.003, white_uv)]:
            cuff_start = len(cuff_points)
            for length in (start, end):
                for segment in range(ring_count):
                    theta = 2*np.pi*segment/ring_count
                    radial_direction = lateral*np.cos(theta) + normal*np.sin(theta)
                    cuff_points.append((origin+(finger*length+lateral*np.cos(theta)*cuff_x+normal*np.sin(theta)*cuff_z)/scale).tolist())
                    cuff_normals.append(radial_direction.tolist())
                    cuff_uvs.append(uv.tolist())
                    cuff_joints.append((fore, 0, 0, 0))
            for segment in range(ring_count):
                a = cuff_start+segment
                b = cuff_start+(segment+1)%ring_count
                cuff_triangles.extend([[a, a+ring_count, b], [b, a+ring_count, b+ring_count]])
        cap_start = len(cuff_points)
        for radius_x, radius_z in [(cuff_x, cuff_z), (0.028, 0.021)]:
            for segment in range(ring_count):
                theta = 2*np.pi*segment/ring_count
                cuff_points.append((origin+(finger*(-0.003)+lateral*np.cos(theta)*radius_x+normal*np.sin(theta)*radius_z)/scale).tolist())
                cuff_normals.append(finger.tolist())
                cuff_uvs.append(white_uv.tolist())
                cuff_joints.append((fore, 0, 0, 0))
        for segment in range(ring_count):
            a, b = cap_start+segment, cap_start+(segment+1)%ring_count
            cuff_triangles.extend([[a, a+ring_count, b], [b, a+ring_count, b+ring_count]])
        # Usa o mesmo ponto de palma aprovado no Actor, convertido para o novo quadro anatômico.
        donor_palm = dg[ds['joints'][dh]][:3, :3]@np.array([0.0, 0.065, 0.0])*1.03*0.95
        anatomical_offset = donor_frame.T@donor_palm
        roll = 0.358 if side == 'Right' else -0.392
        rx = np.array([[1., 0., 0.], [0., 0., 1.], [0., -1., 0.]])
        ry = np.array([[np.cos(roll), 0., -np.sin(roll)], [0., 1., 0.], [np.sin(roll), 0., np.cos(roll)]])
        weapon_frame = rx@ry@dg[ds['joints'][dh]][:3, :3].T@donor_frame
        profile.append({'fingers': finger.tolist(), 'normal': normal.tolist(), 'palm_offset': anatomical_offset.tolist(),
                        'weapon_frame': weapon_frame.T.tolist()})
        report['sides'].append({'side': side, 'vertices': len(picked), 'triangles': len(selected_tris),
                                'palm_offset': anatomical_offset.tolist(), 'donor_palm_sign': palm_sign,
                                'wrist_bridge_edges': len(wrist_edges), 'wrist_bridge_length_mm': 59.57,
                                'wrist_bridge_triangles': len(hand_tris)-bridge_faces_start,
                                'wrist_boundary_vertex_indices': [index+vertex_offset for index in boundary_vertices],
                                'wrist_boundary_duplicate_pairs': [[index+vertex_offset, distal_ring[index]] for index in boundary_vertices],
                                'new_cuff_triangles': len(cuff_triangles)-cuff_triangle_start,
                                'wrist_faces_uv_repaired': len(repair_faces),
                                'palmar_bridge_sample_rgb': donor_colors[nearest_skin].tolist(),
                                'clipped_boundary_vertices': len(side_intersections),
                                'clipped_boundary_axial_mm': [float((np.array(body_rows['POSITION'][index])-origin).dot(finger)*scale*1000) for index in side_intersections],
                                'donor_vertex_indices': picked.tolist()})
        report['sides'][-1]['donor_clip_plane_mm'] = 20.0
        report['sides'][-1]['donor_clipped_boundary_vertices'] = len(donor_intersections)
        vertex_offset = len(hand_points)
    body_output_source_faces = []
    triangle_rows = []
    for face_index, polygon in enumerate(body_polygons):
        for index in range(1, len(polygon)-1):
            triangle_rows.append([polygon[0], polygon[index], polygon[index+1]])
            body_output_source_faces.append(face_index)
    kept_tris = np.array(triangle_rows, int)
    assert not np.any(remove_faces & ~hand_envelope[source_tris].any(axis=1))
    kept_vertices = np.unique(kept_tris)
    vertex_remap = {int(old): new for new, old in enumerate(kept_vertices)}
    kept_indices = [(vertex_remap[int(index)],) for index in kept_tris.ravel()]
    kept_indices.extend([(len(kept_vertices)+index,) for triangle in cuff_triangles for index in triangle])
    new_blob = bytearray(blob)
    for key, accessor in list(attributes.items()):
        if key.startswith(('JOINTS_', 'WEIGHTS_')):
            continue
        rows = body_rows[key]
        acc = doc['accessors'][accessor]
        additions = {'POSITION': cuff_points, 'NORMAL': cuff_normals, 'TEXCOORD_0': cuff_uvs}.get(key)
        if additions is None:
            raise ValueError('Atributo adicional do corpo não suportado pelo cuff: '+key)
        attributes[key] = append_accessor(doc, new_blob, [rows[index] for index in kept_vertices]+[tuple(row) for row in additions], acc['componentType'], acc['type'])
    sets = sorted(int(key.split('_')[1]) for key in attributes if key.startswith('JOINTS_'))
    weight_rows, joint_rows = [], []
    for vertex in kept_vertices:
        weights = body_weights[vertex] if vertex < len(body_weights) else body_extra_weights[vertex-len(body_weights)]
        nonzero = np.flatnonzero(weights > 0)
        ordered = sorted([(int(index), float(weights[index])) for index in nonzero], key=lambda pair: -pair[1])
        assert len(ordered) <= 4*len(sets)
        ordered += [(0, 0.0)]*(4*len(sets)-len(ordered))
        joint_rows.append([index for index, _ in ordered])
        weight_rows.append([weight for _, weight in ordered])
    for row in cuff_joints:
        joint_rows.append(list(row)+[0]*(4*len(sets)-4))
        weight_rows.append([1.0]+[0.0]*(4*len(sets)-1))
    for offset, set_index in enumerate(sets):
        attributes[f'JOINTS_{set_index}'] = append_accessor(doc, new_blob, [tuple(row[offset*4:offset*4+4]) for row in joint_rows], 5123, 'VEC4')
        attributes[f'WEIGHTS_{set_index}'] = append_accessor(doc, new_blob, [tuple(row[offset*4:offset*4+4]) for row in weight_rows], 5126, 'VEC4')
    primitive['indices'] = append_accessor(doc, new_blob, kept_indices, 5125, 'SCALAR')
    texture_index = dante['materials'][dp.get('material', 0)]['pbrMetallicRoughness']['baseColorTexture']['index']
    image = dante['images'][dante['textures'][texture_index]['source']]
    view = dante['bufferViews'][image['bufferView']]
    npc_hand_region = npc_skin & hand_envelope
    target_color = np.median(npc_colors[npc_hand_region], axis=0)
    source_color = np.median(np.array(hand_tint_samples), axis=0)
    if not np.all(np.isfinite(target_color)) or not np.all(np.isfinite(source_color)):
        raise ValueError('Não foi encontrada uma amostra válida de pele para ajustar a textura.')
    # A textura é exclusiva desta superfície; a multiplicação preserva detalhes e
    # iguala o tom ao rosto/mãos do NPC sem novo custo de shader por personagem.
    tint = target_color/np.maximum(source_color, 1e-6)
    pixels = np.array(donor_image).astype(float)/255.0
    pixels = np.clip(pixels*tint, 0, 1)
    baked = Image.fromarray(np.round(pixels*255).astype(np.uint8))
    encoded = io.BytesIO()
    baked.save(encoded, format='PNG', optimize=True)
    payload = encoded.getvalue()
    new_blob += b'\0'*(-len(new_blob)%4)
    doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(new_blob), 'byteLength': len(payload)})
    new_blob += payload
    doc['images'].append({'bufferView': len(doc['bufferViews'])-1, 'mimeType': 'image/png'})
    doc['textures'].append({'source': len(doc['images'])-1})
    doc['materials'].append({'name': 'DanteHands', 'doubleSided': True,
                             'pbrMetallicRoughness': {'baseColorTexture': {'index': len(doc['textures'])-1},
                                                     'metallicFactor': 0, 'roughnessFactor': 0.8}})
    hands = {'attributes': {}, 'material': len(doc['materials'])-1}
    for key, rows in [('POSITION', hand_points), ('NORMAL', hand_normals), ('TEXCOORD_0', hand_uvs),
                      ('JOINTS_0', hand_joints), ('WEIGHTS_0', hand_weights)]:
        hands['attributes'][key] = append_accessor(doc, new_blob, [tuple(row) for row in rows], 5123 if key=='JOINTS_0' else 5126, 'VEC2' if key=='TEXCOORD_0' else ('VEC4' if key.startswith(('JOINTS', 'WEIGHTS')) else 'VEC3'))
    hands['indices'] = append_accessor(doc, new_blob, [(int(index),) for triangle in hand_tris for index in triangle], 5125, 'SCALAR')
    for surface, position_deltas, normal_deltas in [(primitive, [np.zeros((len(kept_vertices)+len(cuff_points), 3))]*2, [np.zeros((len(kept_vertices)+len(cuff_points), 3))]*2),
                                                     (hands, hand_delta, hand_normal_delta)]:
        surface['targets'] = []
        for shape in range(2):
            target = {}
            for key, rows in [('POSITION', position_deltas[shape]), ('NORMAL', normal_deltas[shape])]:
                accessor = append_accessor(doc, new_blob, [tuple(row) for row in rows], 5126, 'VEC3')
                surface['attributes'][f'_MORPH_{shape}_{key}'] = accessor
                target[key] = accessor
            surface['targets'].append(target)
    doc['meshes'][0]['primitives'] = [primitive, hands]
    doc['meshes'][0]['weights'] = [0.0, 0.0]
    doc['meshes'][0].setdefault('extras', {})['targetNames'] = ['GripRight', 'GripLeft']
    for node in doc['nodes']:
        if node.get('mesh') == 0:
            node.setdefault('extras', {})['npc_hand_profile'] = profile
    doc.setdefault('asset', {}).setdefault('extras', {})['dante_hands_grafted_v1'] = {'donor': donor.name, 'rigid_hand_weights': True, 'palm_sign': palm_sign}
    compact = collect_garbage(doc, bytes(new_blob))
    for surface in doc['meshes'][0]['primitives']:
        for shape, target in enumerate(surface['targets']):
            for key in list(target):
                target[key] = surface['attributes'].pop(f'_MORPH_{shape}_{key}')
        for key in ('POSITION',):
            accessor = doc['accessors'][surface['attributes'][key]]
            rows = np.array(read_accessor(doc, compact, surface['attributes'][key]))
            accessor['min'], accessor['max'] = rows.min(axis=0).tolist(), rows.max(axis=0).tolist()
    report.update({'body_triangles_removed': len(source_tris)-len(kept_tris), 'body_triangles_kept': len(kept_tris),
                   'new_cuff_triangles': len(cuff_triangles),
                   'hand_triangles': len(hand_tris), 'total_triangles': len(kept_tris)+len(cuff_triangles)+len(hand_tris),
                   'body_vertices': len(kept_vertices)+len(cuff_points), 'hand_vertices': len(hand_points), 'surfaces': 2, 'bones': len(skin['joints'])})
    report['body_source_vertex_indices'] = kept_vertices.tolist()
    report['body_clipped_vertices'] = clipped_vertices
    report['body_output_source_faces'] = body_output_source_faces
    report['removed_source_triangle_indices'] = np.flatnonzero(remove_faces).tolist()
    report['hand_texture_color_multiplier_srgb'] = tint.tolist()
    report['wrist_style'] = wrist_style
    report['body_has_hand_influence'] = bool(body_weights[:, [names.index('RightHand'), names.index('LeftHand')]].max() > 0)
    report['removed_faces_outside_hand_envelope'] = int((remove_faces & ~hand_envelope[source_tris].any(axis=1)).sum())
    destination.parent.mkdir(parents=True, exist_ok=True)
    write_glb(destination, doc, compact)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--donor', type=Path, default=Path('assets/dante.glb'))
    parser.add_argument('--palm-sign', type=int, choices=(-1, 1), default=-1)
    parser.add_argument('--wrist-style', choices=('suit', 'skin', 'sleeve'), default='suit')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if args.report and (args.report.resolve() in (args.source.resolve(), args.donor.resolve(), args.destination.resolve()) or args.report.exists()):
        parser.error('--report deve ser novo e diferente dos arquivos GLB de entrada/saída.')
    result = graft(args.source, args.donor, args.destination, args.palm_sign, args.wrist_style)
    output = json.dumps(result, ensure_ascii=False, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output+'\n', encoding='utf-8')
    print(output)
