extends Node3D
## Shared immutable materials and batched trim; solids stay explicit meshes.
const MATERIALS := preload("res://world/places/ShopInteriorMaterials.gd")
var _materials: Dictionary = {}
var _batches: Dictionary = {}

func material(color: String, kind := "paint") -> StandardMaterial3D:
	var key := color + kind
	if _materials.has(key): return _materials[key]
	var result: StandardMaterial3D
	if kind in ["wood", "stone", "cloth"]:
		result = MATERIALS.material(kind, Color(color))
	else:
		result = StandardMaterial3D.new()
		result.albedo_color = Color(color)
		result.roughness = .34 if kind == "metal" else .78
		result.metallic = .48 if kind == "metal" else 0.0
		if kind == "screen":
			result.emission_enabled = true
			result.emission = Color(color)
			result.emission_energy_multiplier = .48
	_materials[key] = result
	return result

func box(label: String, at: Vector3, size: Vector3, color: String, solid := "", kind := "paint", yaw := 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var shape := BoxMesh.new()
	shape.size = size
	node.mesh = shape
	node.position = at
	node.rotation.y = yaw
	node.material_override = material(color, kind)
	if not solid.is_empty(): node.set_meta("interior_solid_id", solid)
	add_child(node)
	return node

func detail(at: Vector3, size: Vector3, color: String, kind := "paint", detail_rotation := Vector3.ZERO, round_shape := false) -> void:
	var key := color + kind + str(round_shape)
	if not _batches.has(key): _batches[key] = {"color":color,"kind":kind,"round":round_shape,"transforms":[]}
	_batches[key].transforms.append(Transform3D(Basis.from_euler(detail_rotation).scaled(size), at))

func flush() -> void:
	for key in _batches:
		var row: Dictionary = _batches[key]
		var shape: PrimitiveMesh
		if row.round:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = .5
			cylinder.bottom_radius = .5
			cylinder.height = 1.0
			cylinder.radial_segments = 12
			cylinder.rings = 1
			shape = cylinder
		else:
			var cube := BoxMesh.new()
			cube.size = Vector3.ONE
			shape = cube
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = shape
		multi.instance_count = row.transforms.size()
		for index in row.transforms.size(): multi.set_instance_transform(index, row.transforms[index])
		var node := MultiMeshInstance3D.new()
		node.name = "ArcadeDetails_" + key
		node.multimesh = multi
		node.material_override = material(row.color, row.kind)
		add_child(node)
	_batches.clear()
