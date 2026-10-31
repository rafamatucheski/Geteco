extends RefCounted
## Acesso semântico tanto para peças antigas achatadas quanto para exports com várias superfícies.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
static var _centers: Dictionary = {}

## A role is a semantic identifier, not arbitrary text: "detail" contains "tail".
## Offline exports may append a # discriminator while retaining the same role.
static func is_tail_lens(value: String) -> bool:
	return value.get_slice("#",0) in ["tail","taillight","tail_light","taillight_vert","rear_lens","brake_light","brake"]

static func is_headlight_lens(value: String) -> bool:
	return value.get_slice("#",0) in ["headlight","headlight_left","headlight_right"]

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
			var vertices: PackedVector3Array = MESH_ARRAYS.arrays_of(part.mesh, i)[Mesh.ARRAY_VERTEX]
			var bounds := AABB(vertices[0], Vector3.ZERO) if not vertices.is_empty() else part.get_aabb()
			for vertex in vertices: bounds = bounds.expand(vertex)
			centers.append(bounds.get_center())
		_centers[part.mesh] = centers
	return _centers[part.mesh][surface]
