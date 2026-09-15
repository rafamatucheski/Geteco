extends RefCounted

## Cut real wheel wells once at assembly time. Shared mesh cache keeps traffic
## instances cheap; materials, wheel centres and steering angles stay authored.
const SIDES := 16
static var _cache: Dictionary = {}

static func carve(model: Node3D, wells: Array[Dictionary]) -> void:
	for part in model.get_children():
		if not part is MeshInstance3D or part.has_meta("wheel_center") or part.mesh == null:
			continue
		var relevant: Array[Dictionary] = []
		var bounds: AABB = part.transform * part.mesh.get_aabb()
		for well in wells:
			var center: Vector3 = well.center
			var radius: float = well.radius / cos(PI / SIDES)
			var inner: float = well.inner
			if bounds.end.y < center.y - radius or bounds.position.y > center.y + radius: continue
			if bounds.end.z < center.z - radius or bounds.position.z > center.z + radius: continue
			if center.x > 0 and bounds.end.x < inner: continue
			if center.x < 0 and bounds.position.x > -inner: continue
			relevant.append(well)
		if relevant.is_empty(): continue
		var source: Mesh = part.mesh
		var key := str(part.transform, relevant)
		for surface in source.get_surface_count():
			key += str(hash(source.surface_get_arrays(surface)))
		if not _cache.has(key):
			_cache[key] = _cut_mesh(source, part.transform, relevant)
		part.mesh = _cache[key]
		if part.mesh.get_surface_count() == 0:
			part.hide()
			if model.get("originals") is Dictionary: model.originals.erase(part)
			continue
		# Damage/repair must use the carved geometry, or repairs close the wells.
		if model.get("originals") is Dictionary and model.originals.has(part):
			model.originals[part] = part.mesh

static func _planes(well: Dictionary) -> Array[Plane]:
	var center: Vector3 = well.center
	var planes: Array[Plane] = [Plane(Vector3(-signf(center.x), 0, 0), -float(well.inner))]
	for i in SIDES:
		var angle := TAU * i / SIDES
		var normal := Vector3(0, cos(angle), sin(angle))
		planes.append(Plane(normal, normal.dot(center) + float(well.radius)))
	return planes

static func _half(polygon: Array, plane: Plane, inside: bool) -> Array:
	var result: Array = []
	if polygon.is_empty(): return result
	var previous: Dictionary = polygon.back()
	var previous_distance := plane.distance_to(previous.p)
	for vertex: Dictionary in polygon:
		var distance := plane.distance_to(vertex.p)
		var keep := distance <= 0 if inside else distance >= 0
		var keep_previous := previous_distance <= 0 if inside else previous_distance >= 0
		if keep != keep_previous:
			var weight := previous_distance / (previous_distance - distance)
			result.append({"p": previous.p.lerp(vertex.p, weight),
				"n": previous.n.lerp(vertex.n, weight).normalized(),
				"uv": previous.uv.lerp(vertex.uv, weight)})
		if keep: result.append(vertex)
		previous = vertex
		previous_distance = distance
	return result

static func _cut_mesh(source: Mesh, transform: Transform3D, wells: Array[Dictionary]) -> ArrayMesh:
	var output := ArrayMesh.new()
	var inverse := transform.affine_inverse()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i in points.size(): indices.append(i)
		var polygons: Array = []
		for i in range(0, indices.size(), 3):
			var triangle: Array = []
			for offset in 3:
				var index := indices[i + offset]
				triangle.append({"p": transform * points[index], "n": normals[index],
					"uv": uvs[index] if index < uvs.size() else Vector2.ZERO})
			polygons.append(triangle)
		for well in wells:
			var remaining: Array = []
			var planes := _planes(well)
			for polygon: Array in polygons:
				# Convex subtraction: retain each outside piece, then clip the
				# still-inside remainder against the next plane.
				var inner := polygon
				for plane in planes:
					var outer := _half(inner, plane, false)
					if outer.size() >= 3: remaining.append(outer)
					inner = _half(inner, plane, true)
					if inner.size() < 3: break
			polygons = remaining
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var emitted := 0
		for polygon: Array in polygons:
			for i in range(1, polygon.size() - 1):
				var triangle := [polygon[0], polygon[i], polygon[i + 1]]
				if (triangle[1].p - triangle[0].p).cross(triangle[2].p - triangle[0].p).length_squared() < 0.0000000001: continue
				for vertex: Dictionary in triangle:
					tool.set_normal(vertex.n)
					tool.set_uv(vertex.uv)
					tool.add_vertex(inverse * vertex.p)
					emitted += 1
		if emitted > 0:
			tool.set_material(source.surface_get_material(surface))
			tool.index()
			tool.commit(output)
	return output
