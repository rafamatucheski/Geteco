class_name MountainSkiLift3D
extends Node3D

## Terminal / Estação de teleférico alpino em 3D.
## Inclui grande roda motriz (bullwheel) giratória no topo,
## cabine de controle do operador, plataforma de embarque com gradis
## e iluminação de serviço.

var bullwheel: MeshInstance3D
var is_operating := true
var is_lit := false
var floodlight: OmniLight3D
var wheels: Array[MeshInstance3D] = []

func _ready() -> void:
	_build_station()

func set_operating(active: bool) -> void:
	is_operating = active

func set_lit(lit: bool) -> void:
	is_lit = lit
	if is_instance_valid(floodlight):
		floodlight.visible = lit

func _process(delta: float) -> void:
	if is_operating and is_instance_valid(bullwheel):
		bullwheel.rotation.y += delta * 1.4
		for w in wheels:
			w.rotation.x += delta * 2.2

func _build_station() -> void:
	var steel := _mat(Color("44545e"), 0.45, 0.72)
	var dark := _mat(Color("202b31"), 0.75)
	var yellow := _mat(Color("d9a738"), 0.50)
	var bullwheel_mat := _mat(Color("306888"), 0.40, 0.60)
	var glass := _mat(Color(0.35, 0.67, 0.78, 0.72), 0.16)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var snow := preload("res://world/mountain_pass/MountainGroundMaterials.gd").material_3d("snow")

	# 1. Plataforma de piso
	_box("Platform", Vector3(0, 0.1, 0), Vector3(7.5, 0.2, 5.5), dark)

	# 2. Pórticos de aço verticais
	for side in [-1.0, 1.0]:
		_box("Pylon_%s" % side, Vector3(side * 2.5, 2.15, 0), Vector3(0.28, 4.3, 0.28), steel)
	_box("HeaderBeam", Vector3(0, 4.2, 0), Vector3(5.5, 0.35, 0.35), steel)

	# 3. Grande Roda Motriz (Bullwheel horizontal de tração do cabo)
	bullwheel = MeshInstance3D.new()
	bullwheel.name = "DriveBullwheel"
	var bw_mesh := CylinderMesh.new()
	bw_mesh.top_radius = 1.35
	bw_mesh.bottom_radius = 1.35
	bw_mesh.height = 0.22
	bw_mesh.radial_segments = 24
	bullwheel.mesh = bw_mesh
	bullwheel.position = Vector3(0, 4.35, 0.6)
	bullwheel.material_override = bullwheel_mat
	add_child(bullwheel)

	# Raios do bullwheel
	for angle in [0.0, 45.0, 90.0, 135.0]:
		_box_to(bullwheel, "Spoke_%s" % angle, Vector3.ZERO, Vector3(2.5, 0.14, 0.12), steel, Vector3(0, angle, 0))

	# 4. Roldanas de desvio de cabo
	for side in [-1.0, 1.0]:
		var wheel := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.65
		mesh.bottom_radius = 0.65
		mesh.height = 0.18
		mesh.radial_segments = 20
		wheel.mesh = mesh
		wheel.position = Vector3(side * 2.25, 4.2, 0)
		wheel.rotation_degrees = Vector3(90, 0, 0)
		wheel.material_override = steel
		add_child(wheel)
		wheels.append(wheel)

	# 5. Cabine de controle do operador
	_box("ControlCabin", Vector3(0, 1.25, -1.2), Vector3(3.0, 2.3, 2.2), dark)
	_box("CabinWindow", Vector3(0, 1.45, -2.32), Vector3(2.5, 1.25, 0.08), glass)
	# Painel de controle interno com botões luminosos
	_box("ControlConsole", Vector3(0, 1.0, -1.85), Vector3(1.2, 0.65, 0.45), steel)

	# 6. Telhado com neve acumulada
	for side in [-1.0, 1.0]:
		var roof := _box("Roof_%s" % side, Vector3(side * 1.8, 3.0, -1.2), Vector3(4.0, 0.16, 3.0), snow)
		roof.rotation_degrees.z = side * -16.0

	# 7. Gradis de fila e catraca de embarque
	for x in [-1.8, 1.8]:
		_box("QueueRail_%s" % x, Vector3(x, 0.55, 1.6), Vector3(0.06, 0.9, 2.2), yellow)
	_box("Turnstile", Vector3(0, 0.55, 2.4), Vector3(1.1, 0.9, 0.18), steel)

	# 8. Holofote de serviço
	floodlight = OmniLight3D.new()
	floodlight.position = Vector3(0, 3.8, 1.2)
	floodlight.light_color = Color("fff0db")
	floodlight.light_energy = 2.0
	floodlight.omni_range = 16.0
	floodlight.visible = is_lit
	add_child(floodlight)

func _mat(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _box(name_str: String, point: Vector3, size: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	return _box_to(self, name_str, point, size, material, rotation)

func _box_to(parent: Node3D, name_str: String, point: Vector3, size: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_str
	if name_str.begins_with("Pylon") or name_str.begins_with("QueueRail") or name_str in ["ControlCabin","Turnstile"]: node.set_meta("interior_solid_id",StringName(name_str))
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	node.rotation_degrees = rotation
	node.material_override = material
	parent.add_child(node)
	return node
