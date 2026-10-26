extends RefCounted
## Fragmentos presos à moldura, em vez de uma janela que simplesmente desaparece.
## Só trabalha durante a quebra/restauração. Arestas internas não ganham fragmentos.

static func build(source: Array, kept: PackedInt32Array, removed: Dictionary, scale_basis: Basis, shots: Array) -> Array:
	var result := source.duplicate(true)
	result[Mesh.ARRAY_INDEX] = kept.duplicate()
	# Os veículos são estáticos, sem atributos customizados nem skinning. Se um modelo
	# futuro os usar, preserve seus dados sem inventar atributos para novos vértices.
	for channel in range(Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_INDEX):
		if result[channel] != null and not result[channel].is_empty(): return result
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX] if source[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in indices.size(): indices[i] = i
	var edges: Dictionary = {}
	var triangles: Dictionary = {}
	for triangle in removed:
		var corners: Array[int] = [indices[triangle], indices[triangle + 1], indices[triangle + 2]]
		var keys: Array[String] = [_key(vertices[corners[0]]), _key(vertices[corners[1]]), _key(vertices[corners[2]])]
		var sorted := keys.duplicate()
		sorted.sort()
		var triangle_key := "|".join(sorted)
		if triangles.has(triangle_key): continue
		triangles[triangle_key] = true
		for side in 3:
			var next := (side + 1) % 3
			var key := keys[side] + "|" + keys[next] if keys[side] < keys[next] else keys[next] + "|" + keys[side]
			if edges.has(key): edges[key].count += 1
			else: edges[key] = {"count": 1, "ids": [corners[side], corners[next], corners[(side + 2) % 3]]}
	for key in edges:
		var edge: Dictionary = edges[key]
		if edge.count != 1: continue
		var ids: Array = edge.ids
		var a := vertices[ids[0]]
		var b := vertices[ids[1]]
		var c := vertices[ids[2]]
		var length := (scale_basis * (b - a)).length()
		if length < .025: continue
		var count := clampi(ceili(length / .12), 1, 24)
		for segment in count:
			var serial := absi((str(key) + ":" + str(segment)).hash())
			var start := float(segment) / count
			var end := float(segment + 1) / count
			var along := lerpf(start, end, .3 + float(serial % 41) / 100.0)
			var edge_point := a.lerp(b, along)
			var depth := .016 + float((serial / 41) % 39) / 1000.0
			var inward := minf(.22, depth / maxf(.001, (scale_basis * (c - edge_point)).length()))
			var weights: Array[Vector3] = [Vector3(1.0 - start, start, 0), Vector3(1.0 - end, end, 0), Vector3((1.0 - along) * (1.0 - inward), along * (1.0 - inward), inward)]
			var points: Array[Vector3] = []
			for weight in weights: points.append(a * weight.x + b * weight.y + c * weight.z)
			var blocked := false
			for shot in shots:
				if Geometry3D.segment_intersects_triangle(shot[0], shot[1], points[0], points[1], points[2]) != null:
					blocked = true
					break
			if blocked: continue
			for weight in weights: _append_vertex(result, ids, weight)
	return result

static func _key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 1000.0), roundi(point.y * 1000.0), roundi(point.z * 1000.0)]

static func _append_vertex(arrays: Array, ids: Array, weight: Vector3) -> void:
	var index: int = arrays[Mesh.ARRAY_VERTEX].size()
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[channel] == null or arrays[channel].is_empty(): continue
		var data: Variant = arrays[channel]
		var value: Variant = data[ids[0]] * weight.x + data[ids[1]] * weight.y + data[ids[2]] * weight.z
		if channel == Mesh.ARRAY_NORMAL: value = (value as Vector3).normalized()
		data.append(value)
		arrays[channel] = data
	if arrays[Mesh.ARRAY_TANGENT] != null and not arrays[Mesh.ARRAY_TANGENT].is_empty():
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var tangent := Vector3.ZERO
		var handedness := 0.0
		for corner in 3:
			var offset: int = ids[corner] * 4
			tangent += Vector3(tangents[offset], tangents[offset + 1], tangents[offset + 2]) * weight[corner]
			handedness += tangents[offset + 3] * weight[corner]
		var normal := Vector3.ZERO
		if arrays[Mesh.ARRAY_NORMAL] != null and not arrays[Mesh.ARRAY_NORMAL].is_empty():
			normal = arrays[Mesh.ARRAY_NORMAL][index]
			tangent -= normal * normal.dot(tangent)
		if tangent.length_squared() < .00000001:
			tangent = normal.cross(Vector3.UP if absf(normal.y) < .9 else Vector3.RIGHT) if normal.length_squared() > .5 else Vector3.RIGHT
		tangent = tangent.normalized()
		tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, -1.0 if handedness < 0.0 else 1.0]))
		arrays[Mesh.ARRAY_TANGENT] = tangents
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	indices.append(index)
	arrays[Mesh.ARRAY_INDEX] = indices
