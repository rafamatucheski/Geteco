extends RefCounted
## Spawn-time Nord geometry pass. Caches contain resources, never scene nodes.
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const RENDER_PROPERTIES := [
	"layers", "cast_shadow", "gi_mode", "transparency", "material_overlay",
	"lod_bias", "extra_cull_margin", "ignore_occlusion_culling",
	"visibility_range_begin", "visibility_range_end",
	"visibility_range_begin_margin", "visibility_range_end_margin",
	"visibility_range_fade_mode",
]

static var _primitives: Dictionary = {}
static var _prepared: Dictionary = {}
static var _merged: Dictionary = {}


static func optimize(model: Node3D) -> void:
	if model.has_meta("nord240_geometry_optimized"):
		return
	var groups: Dictionary = {}
	var replaced: Array[MeshInstance3D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if not _can_merge(part):
			continue
		part.mesh = _simplify(part)
		# Handles and mirrors must remain individually attachable to the opening door.
		if part.get_meta("door_trim", false):
			continue
		var transform := _to_model(part, model)
		var settings: Array = []
		for property in RENDER_PROPERTIES:
			settings.append(part.get(property))
		for surface in part.mesh.get_surface_count():
			var role := ROLES.key(part, surface)
			var group_id := [_assembly(part, surface, role, transform), settings]
			if not groups.has(group_id):
				groups[group_id] = {
					"surfaces": {}, "settings": settings,
					"wheel_meta": _wheel_metadata(part), "assembly": group_id[0],
				}
			var group: Dictionary = groups[group_id]
			var material := part.get_active_material(surface)
			var surface_id := [material, role]
			var surfaces: Dictionary = group["surfaces"]
			if not surfaces.has(surface_id):
				surfaces[surface_id] = []
			surfaces[surface_id].append([part.mesh, surface, transform])
		replaced.append(part)
	for group: Dictionary in groups.values():
		var part := MeshInstance3D.new()
		part.name = "Nord240_" + str(group["assembly"][0])
		part.mesh = _merge(group["surfaces"])
		var roles: Array[String] = []
		for surface_id: Array in group["surfaces"]:
			roles.append(surface_id[1])
		part.set_meta("nord240_surface_material_keys", roles)
		for meta in group["wheel_meta"]:
			part.set_meta(meta, group["wheel_meta"][meta])
		for index in RENDER_PROPERTIES.size():
			part.set(RENDER_PROPERTIES[index], group["settings"][index])
		model.add_child(part)
	for part in replaced:
		part.get_parent().remove_child(part)
		part.free()
	model.set_meta("nord240_geometry_optimized", true)


static func _can_merge(part: MeshInstance3D) -> bool:
	if part.mesh == null or not part.visible or part.get_child_count() != 0:
		return false
	if part.skin != null or part.get_script() != null:
		return false
	if part.mesh is ArrayMesh:
		if part.mesh.get_blend_shape_count() > 0:
			return false
		for surface in part.mesh.get_surface_count():
			if part.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				return false
	elif not part.mesh is PrimitiveMesh:
		return false
	return part.mesh.get_surface_count() > 0


static func _to_model(part: Node3D, model: Node3D) -> Transform3D:
	var transform := part.transform
	var ancestor := part.get_parent()
	while ancestor != model and ancestor != null:
		if ancestor is Node3D:
			transform = ancestor.transform * transform
		ancestor = ancestor.get_parent()
	return transform


static func _wheel_metadata(part: MeshInstance3D) -> Dictionary:
	var result: Dictionary = {}
	var names := part.get_meta_list()
	names.sort()
	for meta in names:
		if str(meta).begins_with("wheel_"):
			result[meta] = part.get_meta(meta)
	return result


static func _assembly(
	part: MeshInstance3D, surface: int, role: String, transform: Transform3D
) -> Array:
	if part.has_meta("wheel_center"):
		# Non-spinning calipers remain in a separate steering assembly at each axle.
		return ["wheel", _wheel_metadata(part)]
	if role in ["headlight", "tail", "tail_light", "indicator"]:
		var center := transform * ROLES.center(part, surface)
		# Equipment locates lights from the center of each surface, not each triangle.
		return [role, signf(center.x), signf(center.z)]
	var bounds: AABB = transform * part.get_aabb()
	if bounds.position.y > 1.48 and bounds.size.y < 0.2:
		if bounds.size.x > 1.0 and bounds.size.z > 0.7:
			return ["roof"]
	return ["body"]


static func _simplify(part: MeshInstance3D) -> Mesh:
	var source := part.mesh
	if not source is CylinderMesh and not source is TorusMesh:
		return source
	var tire := false
	if source is CylinderMesh and part.has_meta("wheel_radius"):
		tire = (
			part.get_meta("wheel_spins", true)
			and is_equal_approx(source.top_radius, float(part.get_meta("wheel_radius")))
			and is_equal_approx(source.top_radius, source.bottom_radius)
			and source.height > 0.1
		)
	var cache_key := [source, tire]
	if _primitives.has(cache_key):
		return _primitives[cache_key]
	var reduced: Mesh
	if tire:
		var cylinder := source as CylinderMesh
		var rounded := _rounded_tire(cylinder.top_radius, cylinder.height)
		rounded.surface_set_material(0, cylinder.material)
		reduced = rounded
	elif source is CylinderMesh:
		var cylinder := source.duplicate() as CylinderMesh
		var radius := maxf(source.top_radius, source.bottom_radius)
		var segments := 32
		if radius <= 0.03:
			segments = 8
		elif radius <= 0.08:
			segments = 12
		elif radius <= 0.22:
			segments = 24
		cylinder.radial_segments = mini(source.radial_segments, segments)
		cylinder.rings = 0
		reduced = cylinder
	else:
		var torus := source.duplicate() as TorusMesh
		torus.rings = mini(source.rings, 24)
		torus.ring_segments = mini(source.ring_segments, 6)
		reduced = torus
	_primitives[cache_key] = reduced
	return reduced


static func _rounded_tire(radius: float, width: float) -> ArrayMesh:
	# Three shoulder/tread bands and two sidewalls: 256 triangles at 32 segments.
	# Full radius and width are unchanged; only the sharp cylinder corners recede.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := [
		Vector2(radius * 0.86, -width * 0.5),
		Vector2(radius, -width * 0.28),
		Vector2(radius, width * 0.28),
		Vector2(radius * 0.86, width * 0.5),
	]
	var tilt := [-0.7, -0.25, 0.25, 0.7]
	var tex_v := [0.0, 0.25, 0.75, 1.0]
	for band in 3:
		for segment in 32:
			var corners: Array[Vector3] = []
			var normals: Array[Vector3] = []
			var uv: Array[Vector2] = []
			for corner: Vector2i in [
				Vector2i(band, segment), Vector2i(band + 1, segment),
				Vector2i(band + 1, segment + 1), Vector2i(band, segment + 1),
			]:
				var angle := TAU * float(corner.y) / 32.0
				var radial := Vector3(cos(angle), 0.0, sin(angle))
				corners.append(radial * profile[corner.x].x + Vector3.UP * profile[corner.x].y)
				normals.append((radial + Vector3.UP * tilt[corner.x]).normalized())
				uv.append(Vector2(float(corner.y) / 32.0, tex_v[corner.x]))
			for index in [0, 2, 1, 0, 3, 2]:
				tool.set_normal(normals[index])
				tool.set_uv(uv[index])
				tool.add_vertex(corners[index])
	for side in [-1.0, 1.0]:
		for segment in 32:
			tool.set_normal(Vector3.UP * side)
			tool.set_uv(Vector2(0.5, 0.5))
			tool.add_vertex(Vector3.UP * width * 0.5 * side)
			var order := [segment, segment + 1] if side > 0 else [segment + 1, segment]
			for edge: int in order:
				var radial := Vector3(cos(TAU * edge / 32.0), 0.0, sin(TAU * edge / 32.0))
				tool.set_uv(Vector2(radial.x, radial.z) * 0.5 + Vector2(0.5, 0.5))
				tool.add_vertex(radial * radius * 0.86 + Vector3.UP * width * 0.5 * side)
	tool.generate_tangents()
	tool.index()
	return tool.commit()


static func _merge(surfaces: Dictionary) -> ArrayMesh:
	var signature: Array = []
	for surface_id: Array in surfaces:
		signature.append([surface_id, surfaces[surface_id]])
	if _merged.has(signature):
		return _merged[signature]
	var result := ArrayMesh.new()
	for surface_id: Array in surfaces:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for source: Array in surfaces[surface_id]:
			tool.append_from(_prepare(source[0], source[1], source[2]), 0, Transform3D.IDENTITY)
		tool.set_material(surface_id[0])
		tool.index()
		tool.optimize_indices_for_cache()
		tool.commit(result)
	_merged[signature] = result
	return result


static func _prepare(source: Mesh, surface: int, transform: Transform3D) -> ArrayMesh:
	var cache_key := [source, surface, transform]
	if _prepared.has(cache_key):
		return _prepared[cache_key]
	var arrays := source.surface_get_arrays(surface).duplicate()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	arrays[Mesh.ARRAY_VERTEX] = transform * vertices
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		normals = arrays[Mesh.ARRAY_NORMAL]
		var normal_basis := transform.basis.inverse().transposed()
		for index in normals.size():
			normals[index] = (normal_basis * normals[index]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = normals
	var handedness := signf(transform.basis.determinant())
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		for index in tangents.size() / 4:
			var offset: int = index * 4
			var tangent := transform.basis * Vector3(
				tangents[offset], tangents[offset + 1], tangents[offset + 2]
			)
			if index < normals.size():
				tangent -= normals[index] * tangent.dot(normals[index])
			tangent = tangent.normalized()
			tangents[offset] = tangent.x
			tangents[offset + 1] = tangent.y
			tangents[offset + 2] = tangent.z
			tangents[offset + 3] *= handedness
		arrays[Mesh.ARRAY_TANGENT] = tangents
	# append_from does not index unindexed input. Normalize every source first so
	# mixing a primitive and an authored unindexed mesh cannot drop its triangles.
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices.resize(vertices.size())
		for index in vertices.size():
			indices[index] = index
	if handedness < 0.0:
		for index in range(0, indices.size(), 3):
			var swap := indices[index + 1]
			indices[index + 1] = indices[index + 2]
			indices[index + 2] = swap
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_prepared[cache_key] = result
	return result
