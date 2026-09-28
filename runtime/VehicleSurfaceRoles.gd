extends RefCounted
## Semantic access for both flattened legacy parts and multi-surface exports.
static var _centers: Dictionary = {}

static func key(part: MeshInstance3D, surface: int) -> String:
	for meta in part.get_meta_list():
		if str(meta).ends_with("surface_material_keys") or str(meta).ends_with("surface_material_roles"):
			var keys: Variant = part.get_meta(meta)
			if surface < keys.size(): return str(keys[surface])
	for meta in part.get_meta_list():
		if str(meta).ends_with("material_key") or str(meta).ends_with("material_role"):
			return str(part.get_meta(meta))
	var material := part.get_active_material(surface)
	return material.resource_name if material != null else ""

static func center(part: MeshInstance3D, surface: int) -> Vector3:
	if part.mesh is PrimitiveMesh: return part.get_aabb().get_center()
	if part.mesh.get_surface_count() == 0: return part.get_aabb().get_center()
	if not _centers.has(part.mesh):
		var centers: Array[Vector3] = []
		for i in part.mesh.get_surface_count():
			var vertices: PackedVector3Array = part.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			var bounds := AABB(vertices[0], Vector3.ZERO) if not vertices.is_empty() else part.get_aabb()
			for vertex in vertices: bounds = bounds.expand(vertex)
			centers.append(bounds.get_center())
		_centers[part.mesh] = centers
	return _centers[part.mesh][surface]
