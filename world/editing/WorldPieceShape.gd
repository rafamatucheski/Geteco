extends RefCounted
## Constructor-only deformation: bodies stay rigid and shapes contain their scale.
const GROUND_KEYS := ["cobra_dry_meadow", "cobra_approach_ground", "cobra_footpath_edge", "cobra_footpath", "cobra_garden_path", "cobra_entrance_path", "cobra_secret_drive", "cobra_home_gravel", "cobra_workshop_forecourt", "cobra_secret_parking", "cobra_parking_stripe", "cobra_parking_oil_wear"]

static func is_shape_editable(id: String) -> bool:
	var bits := id.trim_prefix("piece/").split("/")
	return bits.size() == 3 and bits[0] == "cobra" and bits[1] in GROUND_KEYS and bits[2].is_valid_int()

static func shape_info(node: Node3D) -> Dictionary:
	if node.has_meta("world_edit_shape_info"): return node.get_meta("world_edit_shape_info")
	if node.get_meta("world_edit_locked", false) or not is_shape_editable(str(node.get_meta("world_edit_piece_id", ""))): return {}
	var meshes: Array[MeshInstance3D] = []
	_find_meshes(node, meshes)
	if meshes.size() != 1 or not meshes[0].mesh is BoxMesh: return {}
	var mesh := meshes[0]
	var box := mesh.mesh as BoxMesh
	if absf(mesh.global_basis.y.normalized().dot(Vector3.UP)) < .9999 or box.size.y * mesh.global_basis.y.length() > .1: return {}
	var outline: Array = []
	var half := box.size * .5
	for p in [Vector3(-half.x, 0, -half.z), Vector3(half.x, 0, -half.z), Vector3(half.x, 0, half.z), Vector3(-half.x, 0, half.z)]:
		var offset: Vector3 = mesh.global_transform * p - node.global_position
		outline.append([offset.x, offset.z])
	return {"outline":outline, "mesh":mesh, "bottom":mesh.global_position.y-node.global_position.y-half.y*mesh.global_basis.y.length(), "top":mesh.global_position.y-node.global_position.y+half.y*mesh.global_basis.y.length()}

static func _find_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null: meshes.append(node)
	for child in node.get_children(): _find_meshes(child, meshes)

static func _snapshot(node: Node, entries: Array) -> void:
	if node is Node3D:
		var entry := {"node":node, "transform":node.global_transform}
		if node is MeshInstance3D: entry.mesh = node.mesh
		if node is CollisionShape3D: entry.shape = node.shape
		entries.append(entry)
	for child in node.get_children(): _snapshot(child, entries)

static func apply(node: Node3D, row: Dictionary, origin: Transform3D, target: Transform3D) -> void:
	var data: Array = row.get("stretch", [1.0, 1.0])
	var stretch := Vector3(clampf(float(data[0]), .1, 4.0), clampf(float(row.get("height_stretch",1)),.1,4.0), clampf(float(data[1]), .1, 4.0))
	var outline: Array = row.get("outline", [])
	var deform := not stretch.is_equal_approx(Vector3.ONE) or not outline.is_empty()
	if not deform and not node.has_meta("world_edit_geometry"):
		node.global_transform = target
		return
	if not node.has_meta("world_edit_geometry"):
		node.global_transform = origin
		node.set_meta("world_edit_shape_info", shape_info(node))
		var source: Array = []
		_snapshot(node, source)
		node.set_meta("world_edit_geometry", source)
	var entries: Array = node.get_meta("world_edit_geometry")
	var rigid := target * origin.affine_inverse()
	var warp := Transform3D(rigid.basis * Basis.from_scale(stretch), target.origin) * Transform3D(Basis.IDENTITY, -origin.origin)
	for entry in entries:
		var child: Node3D = entry.node
		child.global_transform = rigid * (entry.transform as Transform3D)
		if child is MeshInstance3D: child.mesh = entry.mesh
		if child is CollisionShape3D: child.shape = entry.shape
	if not deform: return
	for entry in entries:
		var child: Node3D = entry.node
		if child == node: continue
		var desired: Transform3D = warp * (entry.transform as Transform3D)
		if child is CollisionObject3D or (row.get("rigid_pivots",false) and not child is VisualInstance3D and not child is CollisionShape3D):
			desired.basis = (rigid.basis * (entry.transform as Transform3D).basis).orthonormalized()
			child.global_transform = desired
		elif child is CollisionShape3D:
			var local := (child.get_parent() as Node3D).global_transform.affine_inverse() * desired
			child.shape = _bake_shape(entry.shape, local.basis)
			child.transform = Transform3D(Basis.IDENTITY, local.origin)
		else:
			child.global_transform = desired
	var info: Dictionary = node.get_meta("world_edit_shape_info")
	if outline.size() >= 3 and not info.is_empty():
		var replacement := _ground_mesh(outline, float(info.bottom), float(info.top))
		if replacement == null: return
		var mesh: MeshInstance3D = info.mesh
		if mesh.mesh.get_surface_count() > 0: replacement.surface_set_material(0, mesh.mesh.surface_get_material(0))
		mesh.mesh = replacement
		mesh.global_transform = warp * Transform3D(Basis.IDENTITY, origin.origin)
		for entry in entries:
			if entry.node is CollisionShape3D:
				var collider: CollisionShape3D = entry.node
				var local := (collider.get_parent() as Node3D).global_transform.affine_inverse() * mesh.global_transform
				collider.shape = _bake_shape(replacement.create_trimesh_shape(), local.basis)
				collider.transform = Transform3D(Basis.IDENTITY, local.origin)

static func _bake_shape(source: Shape3D, basis: Basis) -> Shape3D:
	if source == null: return null
	if source is BoxShape3D and absf(basis.x.y)+absf(basis.x.z)+absf(basis.y.x)+absf(basis.y.z)+absf(basis.z.x)+absf(basis.z.y) < .00001:
		var box := source.duplicate() as BoxShape3D
		box.size *= basis.get_scale().abs()
		return box
	if source is ConcavePolygonShape3D:
		var result := ConcavePolygonShape3D.new()
		var faces: PackedVector3Array = source.get_faces()
		for i in faces.size(): faces[i] = basis * faces[i]
		result.set_faces(faces)
		result.backface_collision = source.backface_collision
		return result
	var points := PackedVector3Array()
	if source is BoxShape3D:
		var bounds := AABB(-source.size*.5, source.size)
		for i in 8: points.append(basis * bounds.get_endpoint(i))
	elif source is ConvexPolygonShape3D:
		for point in source.points: points.append(basis * point)
	else:
		var debug := source.get_debug_mesh()
		for surface in debug.get_surface_count():
			for point in debug.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]: points.append(basis * point)
	if points.is_empty(): return source
	var result := ConvexPolygonShape3D.new()
	result.points = points
	result.margin = source.margin
	return result

static func _ground_mesh(outline: Array, bottom: float, top: float) -> ArrayMesh:
	if outline.size() > 32: return null
	var polygon := PackedVector2Array()
	for p in outline:
		if not p is Array or p.size() != 2: return null
		var point := Vector2(float(p[0]), float(p[1]))
		if not point.is_finite(): return null
		polygon.append(point)
	if Geometry2D.is_polygon_clockwise(polygon): polygon.reverse()
	var indices := Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty(): return null
	var vertices := PackedVector3Array()
	for i in range(0, indices.size(), 3):
		for j in [0, 1, 2]:
			var p := polygon[indices[i+j]]
			vertices.append(Vector3(p.x, top, p.y))
		for j in [2, 1, 0]:
			var p := polygon[indices[i+j]]
			vertices.append(Vector3(p.x, bottom, p.y))
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		var points := [Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(a.x, bottom, a.y), Vector3(b.x, bottom, b.y)]
		for j in [0, 2, 1, 1, 2, 3]: vertices.append(points[j])
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in range(0, vertices.size(), 3):
		var normal := (vertices[i+2]-vertices[i]).cross(vertices[i+1]-vertices[i]).normalized()
		for j in 3:
			normals.append(normal)
			uvs.append(Vector2(vertices[i+j].x, vertices[i+j].z))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
