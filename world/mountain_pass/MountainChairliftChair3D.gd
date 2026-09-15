class_name MountainChairliftChair3D
extends Node3D

## Cadeirinha de teleférico alpino em 3D.
## Inclui garra de fixação no cabo, haste suspensa curvada, assento duplo,
## barra de segurança, apoio de pés e passageiro esquiador 3D opcional.

var has_rider := false
var rider_color := Color("c95444")
var chair_swing := 0.0
var chair_root: Node3D

func _ready() -> void:
	_build_chair()

func set_rider(active: bool, color: Color = Color("c95444")) -> void:
	has_rider = active
	rider_color = color
	if not is_instance_valid(chair_root): return
	var old := chair_root.get_node_or_null("SeatedSkier")
	if old: old.free()
	if active: _build_seated_skier()

func _build_chair() -> void:
	chair_root = Node3D.new()
	chair_root.name = "ChairRoot"
	add_child(chair_root)

	var steel := _mat(Color("4a5660"), 0.50, 0.70)
	var dark_iron := _mat(Color("222b32"), 0.65, 0.50)
	var seat_mat := _mat(Color("2d4b68"), 0.75)
	var safety_bar_mat := _mat(Color("d99834"), 0.40, 0.30)
	var ski_mat := _mat(Color("b33d32"), 0.60)

	# 1. Garra de fixação ao cabo (Grip)
	_box("CableGrip", Vector3(0, 3.2, 0), Vector3(0.26, 0.32, 0.22), dark_iron)

	# 2. Haste de suspensão (Hanger Arm) curvada
	_cylinder("HangerVertical", Vector3(0, 2.1, 0), 0.045, 2.0, steel)
	_box("HangerCurve", Vector3(0, 1.05, -0.22), Vector3(0.08, 0.08, 0.52), steel)
	_cylinder("HangerBack", Vector3(0, 0.52, -0.48), 0.04, 1.1, steel)

	# 3. Assento e Encosto (Bench)
	_box("SeatBench", Vector3(0, 0.05, -0.15), Vector3(1.35, 0.10, 0.62), seat_mat)
	_box("Backrest", Vector3(0, 0.50, -0.44), Vector3(1.35, 0.72, 0.08), seat_mat)
	_box("SeatFrame", Vector3(0, -0.02, -0.15), Vector3(1.42, 0.06, 0.68), dark_iron)

	# 4. Barra de segurança frontal (Safety Bar)
	_box("SafetyBarFront", Vector3(0, 0.42, 0.22), Vector3(1.38, 0.06, 0.06), safety_bar_mat)
	for side in [-0.66, 0.66]:
		_box("SafetyBarSide_%s" % side, Vector3(side, 0.42, -0.11), Vector3(0.05, 0.05, 0.66), dark_iron)

	# 5. Apoio de pés (Footrest)
	_box("FootrestBar", Vector3(0, -0.45, 0.18), Vector3(1.25, 0.05, 0.08), dark_iron)
	for side in [-0.55, 0.55]:
		_cylinder("FootrestDrop_%s" % side, Vector3(side, -0.20, 0.18), 0.025, 0.55, steel)

	# 6. Esquiador passageiro 3D (se ativo)
	if has_rider:
		_build_seated_skier()

func _build_seated_skier() -> void:
	var skier := preload("res://world/mountain_pass/WinterResidentModel.gd").new()
	skier.name = "SeatedSkier"
	skier.coat_color = rider_color
	skier.role = "visitor"
	skier.appearance_variant = 2
	chair_root.add_child(skier)
	skier.set_process(false)
	skier.position = Vector3(.22,-.35,-.12)
	skier.set_seat_pose(1.0,.45,0)
	skier._process(0.0)
	for knee in skier.knees:
		_box_to(knee,"Ski",Vector3(0,-.43,.04),Vector3(.11,.04,1.5),_mat(rider_color,.65))

func set_swing(angle_rad: float) -> void:
	chair_swing = angle_rad
	if is_instance_valid(chair_root):
		chair_root.rotation.z = angle_rad
		var grip := Vector3(0,3.2,0)
		chair_root.position = grip-chair_root.basis*grip

func _mat(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m

func _box(name_str: String, point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	return _box_to(chair_root, name_str, point, size, material)

func _box_to(parent: Node3D, name_str: String, point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_str
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	node.material_override = material
	parent.add_child(node)
	return node

func _cylinder(name_str: String, point: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	return _cylinder_to(chair_root, name_str, point, radius, height, material)

func _cylinder_to(parent: Node3D, name_str: String, point: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_str
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	node.position = point
	node.material_override = material
	parent.add_child(node)
	return node
