extends UrbanBuildingBase
class_name HarborManholeExterior3D

## Interactive access hatch. The closed cover supports pedestrians and slides clear
## while the actor enters the carved shaft.

const HATCH_SHIFT := Vector3(-1.42, 0.055, 0.0)
var hatch_pivot: Node3D
var cover: Node3D
var steam: CPUParticles3D
var open_amount := 0.0:
	set(value):
		open_amount = clampf(value, 0.0, 1.0)
		if is_instance_valid(hatch_pivot):
			hatch_pivot.position = HATCH_SHIFT * open_amount
		if is_instance_valid(steam):
			steam.visible = open_amount < 0.08

func set_open_amount(value: float) -> void:
	open_amount = value

func build() -> void:
	var iron := UrbanMaterials.material_for_color(Color("20282b"), 0.64)
	var dark := UrbanMaterials.material_for_color(Color("071014"), 0.70)
	var steel := UrbanMaterials.material_for_color(Color("6f7976"), 0.58)
	_add_ring("ManholeCollar", 0.70, 0.82, 0.028, iron)
	# The bottom of the shaft is well below street level, leaving an actual dark
	# opening between the rim and the sliding lid rather than another cast-iron cap.
	var void_material := StandardMaterial3D.new()
	void_material.albedo_color = Color("010304")
	void_material.roughness = 1.0
	void_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add_disc("ShaftVoid", 0.79, 0.012, 0.052, void_material)
	_add_disc("ShaftBottom", 0.79, 0.018, -1.85, void_material)
	var shaft_wall := UrbanMaterials.material_for_color(Color("10191b"), 0.9)
	for side in [-1.0, 1.0]:
		_add_shaft_wall("ShaftWallX", Vector3(side * 0.55, -0.9, 0.0), Vector3(0.05, 2.0, 1.125), shaft_wall)
		_add_shaft_wall("ShaftWallZ", Vector3(0.0, -0.9, side * 0.55), Vector3(1.125, 2.0, 0.05), shaft_wall)
	_add_ring("ShaftRim", 0.53, 0.61, 0.045, steel)
	var ladder_material := UrbanMaterials.material_for_color(Color("8b927f"), 0.62)
	for x in [-0.27, 0.27]:
		var rail := MeshInstance3D.new()
		rail.name = "ShaftLadderRail"
		var rail_mesh := CylinderMesh.new()
		rail_mesh.top_radius = 0.018
		rail_mesh.bottom_radius = 0.018
		rail_mesh.height = 1.75
		rail.mesh = rail_mesh
		rail.position = Vector3(x, -0.85, 0.0)
		rail.material_override = ladder_material
		visuals_root.add_child(rail)
	for rung in 17:
		var step := MeshInstance3D.new()
		step.name = "ShaftLadderRung"
		var step_mesh := BoxMesh.new()
		step_mesh.size = Vector3(0.56, 0.018, 0.025)
		step.mesh = step_mesh
		step.position = Vector3(0.0, -0.02 - rung * 0.10, 0.0)
		step.material_override = ladder_material
		visuals_root.add_child(step)
	hatch_pivot = Node3D.new()
	hatch_pivot.name = "SlidingHatch"
	visuals_root.add_child(hatch_pivot)
	cover = Node3D.new()
	cover.name = "ManholeCover"
	hatch_pivot.add_child(cover)
	_add_disc_to(cover, "CastIronLid", 0.66, 0.065, 0.070, dark)
	var lid_body := StaticBody3D.new()
	lid_body.name = "ClosedCoverCollision"
	lid_body.collision_layer = 1
	lid_body.collision_mask = 0
	var lid_collider := CollisionShape3D.new()
	var lid_shape := CylinderShape3D.new()
	lid_shape.radius = 0.66
	lid_shape.height = 0.065
	lid_collider.shape = lid_shape
	lid_collider.position.y = 0.070
	lid_body.add_child(lid_collider)
	cover.add_child(lid_body)
	for index in 8:
		var angle := TAU * float(index) / 8.0
		var slot := add_mesh_box(cover, "LidSlot", Vector3(cos(angle) * 0.39, 0.108, sin(angle) * 0.39), Vector3(0.20, 0.018, 0.045), steel)
		slot.rotation.y = -angle
	_add_disc_to(cover, "LidHub", 0.12, 0.025, 0.105, steel)
	steam = preload("res://world/urban_detail/HarborManholeSteam3D.gd").new()
	add_child(steam)

func _add_disc(label: String, radius: float, disc_height: float, y: float, material: Material) -> MeshInstance3D:
	return _add_disc_to(visuals_root, label, radius, disc_height, y, material)

func _add_shaft_wall(label: String, point: Vector3, size: Vector3, material: Material) -> void:
	var wall := add_mesh_box(visuals_root, label, point, size, material)
	var body := StaticBody3D.new()
	body.name = label + "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	wall.add_child(body)

func _add_disc_to(parent: Node3D, label: String, radius: float, disc_height: float, y: float, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = disc_height
	mesh.radial_segments = 24
	instance.mesh = mesh
	instance.position.y = y
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _add_ring(label: String, inner_radius: float, outer_radius: float, y: float, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 32
	mesh.ring_segments = 8
	instance.mesh = mesh
	instance.position.y = y
	instance.material_override = material
	visuals_root.add_child(instance)
	return instance
