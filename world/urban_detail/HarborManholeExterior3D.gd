extends UrbanBuildingBase
class_name HarborManholeExterior3D

## Interactive access hatch. The closed cover supports pedestrians and slides clear
## while the actor enters the carved shaft.

const HATCH_SHIFT := Vector3(-1.42, 0.055, 0.0)
const LADDER_Z := -0.48
var descent := {"style": "ladder", "ladder_stand": Vector3(0, 0, -0.19)}
var hatch_pivot: Node3D
var cover: Node3D
var ladder_handles: Node3D
var ladder_handle_collision: StaticBody3D
var steam: CPUParticles3D
var open_amount := 0.0:
	set(value):
		open_amount = clampf(value, 0.0, 1.0)
		if is_instance_valid(hatch_pivot):
			hatch_pivot.position = HATCH_SHIFT * open_amount
		if is_instance_valid(steam):
			steam.visible = open_amount < 0.08
		if is_instance_valid(ladder_handles):
			ladder_handles.visible = open_amount > 0
			ladder_handles.scale.y = maxf(.001, open_amount)
		if is_instance_valid(ladder_handle_collision):
			ladder_handle_collision.collision_layer = 1 if open_amount > .999 else 0

func set_open_amount(value: float) -> void:
	open_amount = value

func ladder_handhold(palm: Vector3) -> Vector3:
	var local := to_local(palm)
	return to_global(Vector3(.27 if local.x >= 0 else -.27, clampf(local.y, -1.65, 1.85), LADDER_Z))

func build() -> void:
	var iron := UrbanSurfaces.material("manhole_iron", "metal", Color("20282b"), 0.64, 0.5, 0.6)
	var dark := UrbanMaterials.material_for_color(Color("071014"), 0.70)
	var steel := UrbanSurfaces.material("manhole_steel", "metal", Color("6f7976"), 0.58, 0.5, 0.6)
	var collar := _add_ring("ManholeCollar", 0.70, 0.82, 0.029, iron)
	collar.scale.y = .15
	# The bottom of the shaft is well below street level, leaving an actual dark
	# opening between the rim and the sliding lid rather than another cast-iron cap.
	var void_material := StandardMaterial3D.new()
	void_material.albedo_color = Color("010304")
	void_material.roughness = 1.0
	void_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Darkness belongs at the bottom: a disc at street level hid the entire ladder.
	_add_disc("ShaftBottom", 0.79, 0.018, -1.85, void_material)
	var shaft_wall := UrbanMaterials.material_for_color(Color("10191b"), 0.9)
	for side in [-1.0, 1.0]:
		_add_shaft_wall("ShaftWallX", Vector3(side * 0.55, -0.95, 0.0), Vector3(0.05, 1.9, 1.125), shaft_wall)
		_add_shaft_wall("ShaftWallZ", Vector3(0.0, -0.95, side * 0.55), Vector3(1.125, 1.9, 0.05), shaft_wall)
	var rim := _add_ring("ShaftRim", 0.53, 0.61, 0.029, steel)
	rim.scale.y = .15
	var ladder_material := UrbanMaterials.material_for_color(Color("8b927f"), 0.62)
	for x in [-0.27, 0.27]:
		var rail := MeshInstance3D.new()
		rail.name = "ShaftLadderRail"
		var rail_mesh := CylinderMesh.new()
		rail_mesh.top_radius = 0.018
		rail_mesh.bottom_radius = 0.018
		rail_mesh.height = 1.75
		rail.mesh = rail_mesh
		rail.position = Vector3(x, -0.85, LADDER_Z)
		rail.material_override = ladder_material
		visuals_root.add_child(rail)
	for rung in 17:
		var step := MeshInstance3D.new()
		step.name = "ShaftLadderRung"
		var step_mesh := BoxMesh.new()
		step_mesh.size = Vector3(0.56, 0.018, 0.025)
		step.mesh = step_mesh
		step.position = Vector3(0.0, -0.02 - rung * 0.10, LADDER_Z)
		step.material_override = ladder_material
		visuals_root.add_child(step)
	# Retractable upper section gives hands real rails above the street during
	# entry. It folds into the shaft with the lid closed, leaving cars clear.
	ladder_handles = Node3D.new()
	ladder_handles.name = "RetractableLadder"
	visuals_root.add_child(ladder_handles)
	ladder_handle_collision = StaticBody3D.new()
	ladder_handle_collision.name = "OpenLadderCollision"
	ladder_handle_collision.collision_mask = 0
	visuals_root.add_child(ladder_handle_collision)
	for x in [-.27, .27]:
		var rail := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = .018
		mesh.bottom_radius = .018
		mesh.height = 1.85
		rail.mesh = mesh
		rail.position = Vector3(x, .925, LADDER_Z)
		rail.material_override = ladder_material
		ladder_handles.add_child(rail)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(.036, 1.85, .036)
		collider.shape = shape
		collider.position = rail.position
		ladder_handle_collision.add_child(collider)
	for y in [.3, .6, .9, 1.2, 1.5, 1.8]:
		add_mesh_box(ladder_handles, "UpperLadderRung", Vector3(0, y, LADDER_Z), Vector3(.56, .018, .025), ladder_material)
	hatch_pivot = Node3D.new()
	hatch_pivot.name = "SlidingHatch"
	visuals_root.add_child(hatch_pivot)
	cover = Node3D.new()
	cover.name = "ManholeCover"
	hatch_pivot.add_child(cover)
	# Render above the road's 0.026 m surface, while support remains at physical ground.
	_add_disc_to(cover, "CastIronLid", 0.66, 0.065, 0.0015, dark)
	var lid_body := StaticBody3D.new()
	lid_body.name = "ClosedCoverCollision"
	lid_body.collision_layer = 1
	lid_body.collision_mask = 0
	var lid_collider := CollisionShape3D.new()
	var lid_shape := CylinderShape3D.new()
	lid_shape.radius = 0.66
	lid_shape.height = 0.065
	lid_collider.shape = lid_shape
	# The cap supports the shaft at street height; its sides never form a curb.
	lid_collider.position.y = -lid_shape.height * 0.5
	lid_body.add_child(lid_collider)
	cover.add_child(lid_body)
	for index in 8:
		var angle := TAU * float(index) / 8.0
		var slot := add_mesh_box(cover, "LidSlot", Vector3(cos(angle) * 0.39, 0.039, sin(angle) * 0.39), Vector3(0.20, 0.008, 0.045), steel)
		slot.rotation.y = -angle
	_add_disc_to(cover, "LidHub", 0.12, 0.012, 0.040, steel)
	steam = preload("res://world/urban_detail/HarborManholeSteam3D.gd").new()
	add_child(steam)
	set_open_amount(open_amount)
	var instancing := preload("res://world/urban_detail/HarborPropInstancing.gd")
	instancing.batch_children(visuals_root)
	instancing.batch_children(ladder_handles)
	instancing.batch_children(cover)

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
