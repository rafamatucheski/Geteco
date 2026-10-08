extends Node3D
## Native solid volumes and batched detail; no viewport or gameplay hooks.
const MATERIALS := preload("res://world/places/ShopInteriorMaterials.gd")
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var solid_bodies: Array[StaticBody3D] = []
var solid_bounds: Array[AABB] = []
var detail_instances := 0
var static_draw_batches := 0

func surface(color: String, kind := "stone") -> StandardMaterial3D:
	var key := color+kind
	if _materials.has(key): return _materials[key]
	var material: StandardMaterial3D
	if kind in ["stone","wood","cloth"]:
		material = MATERIALS.material(kind,Color(color))
	else:
		material = StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = .36 if kind == "metal" else .86
		material.metallic = .6 if kind == "metal" else 0.0
		if kind == "glow":
			material.emission_enabled = true
			material.emission = Color(color)
			material.emission_energy_multiplier = 1.3
	_materials[key] = material
	return material

func box(label: String, at: Vector3, size: Vector3, color: String, solid := false, kind := "stone", rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.position = at
	node.rotation = rotation
	node.material_override = surface(color,kind)
	if solid: node.set_meta("interior_solid_id",label)
	add_child(node)
	if solid: blocking_box(label,at,size,rotation)
	return node

func blocking_box(label: String, at: Vector3, size: Vector3, rotation := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label+"Body"
	body.position = at
	body.rotation = rotation
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id",label)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	solid_bodies.append(body)
	var bounds := Transform3D(Basis.from_euler(rotation),at)*AABB(-size*.5,size)
	body.set_meta("bounds",bounds)
	if label != "UnbrokenFloor": solid_bounds.append(bounds)
	return body

func piece(shape: String, at: Vector3, size: Vector3, color: String, kind := "stone", rotation := Vector3.ZERO) -> void:
	var key := shape+color+kind
	if not _batches.has(key): _batches[key] = {"shape":shape,"color":color,"kind":kind,"transforms":[]}
	_batches[key].transforms.append(Transform3D(Basis.from_euler(rotation).scaled(size),at))
	detail_instances += 1

static func primitive(shape: String) -> PrimitiveMesh:
	if shape in ["round","taper"]:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = .08 if shape == "taper" else .5
		cylinder.bottom_radius = .5
		cylinder.height = 1
		cylinder.radial_segments = 7
		cylinder.rings = 1
		return cylinder
	if shape == "rock":
		var sphere := SphereMesh.new()
		sphere.radius = .5
		sphere.height = 1
		sphere.radial_segments = 6
		sphere.rings = 3
		return sphere
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	return cube

func flush_batches() -> void:
	for key in _batches:
		var data: Dictionary = _batches[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = primitive(data.shape)
		multi.instance_count = data.transforms.size()
		for index in data.transforms.size(): multi.set_instance_transform(index,data.transforms[index])
		var node := MultiMeshInstance3D.new()
		node.name = "RuinDetail_"+key
		node.multimesh = multi
		node.material_override = surface(data.color,data.kind)
		add_child(node)
		static_draw_batches += 1
	_batches.clear()
