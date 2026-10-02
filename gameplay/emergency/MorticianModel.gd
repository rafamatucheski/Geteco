extends Node3D
var model_root: Node3D
var torso_node: Node3D
var head_node: Node3D
var left_upper_arm: Node3D
var right_upper_arm: Node3D
var left_lower_arm: Node3D
var right_lower_arm: Node3D
var left_upper_leg: Node3D
var right_upper_leg: Node3D
var left_lower_leg: Node3D
var right_lower_leg: Node3D
var mat_uniform: StandardMaterial3D
var stretcher_mesh: MeshInstance3D
var is_stretcher_bearer := false
var body_bag_mesh: MeshInstance3D
func _ready() -> void:
	model_root = self
	scale = Vector3.ONE * 1.28
	var mat_suit := _make_mat(Color(0.14, 0.15, 0.18), 0.5) # Terno Chumbo/Preto IML

	var mat_tie := _make_mat(Color(0.05, 0.05, 0.06), 0.7) # Gravata Preta
	var mat_skin := _make_mat(Color(0.88, 0.74, 0.62), 0.4) # Pele
	var mat_gloves := _make_mat(Color(0.22, 0.48, 0.88), 0.2) # Luvas Cirúrgicas Azuis
	var mat_shoes := _make_mat(Color(0.06, 0.06, 0.08), 0.8) # Sapatos Pretos

	# Tronco (Paletó Preto)
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.75, 0.0)
	model_root.add_child(torso_node)

	var torso_mesh := MeshInstance3D.new()
	var box_t := BoxMesh.new()
	box_t.size = Vector3(0.38, 0.52, 0.22)
	torso_mesh.mesh = box_t
	torso_mesh.material_override = mat_suit
	torso_node.add_child(torso_mesh)

	# Gravata & Colarinho
	var tie_mesh := MeshInstance3D.new()
	var box_tie := BoxMesh.new()
	box_tie.size = Vector3(0.08, 0.28, 0.03)
	tie_mesh.mesh = box_tie
	tie_mesh.material_override = mat_tie
	tie_mesh.position = Vector3(0.0, 0.08, -0.12)
	torso_node.add_child(tie_mesh)

	# Cabeça
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.22, 0.0)
	model_root.add_child(head_node)

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.16
	sph_h.height = 0.32
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	# Óculos / Máscara Protetora
	var mask_mesh := MeshInstance3D.new()
	var box_m := BoxMesh.new()
	box_m.size = Vector3(0.18, 0.09, 0.06)
	mask_mesh.mesh = box_m
	mask_mesh.material_override = _make_mat(Color(0.85, 0.90, 0.95), 0.1)
	mask_mesh.position = Vector3(0.0, -0.04, -0.14)
	head_node.add_child(mask_mesh)

	# Braços (com luvas cirúrgicas)
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.24, 1.02, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.050, 0.22, mat_suit, Vector3(0, -0.11, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.044, 0.18, mat_gloves, Vector3(0, -0.09, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.24, 1.02, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.050, 0.22, mat_suit, Vector3(0, -0.11, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.044, 0.18, mat_gloves, Vector3(0, -0.09, 0)))

	# Pernas & Calça Social
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.11, 0.50, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.058, 0.24, mat_suit, Vector3(0, -0.12, 0)))

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.24, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb(0.050, 0.24, mat_shoes, Vector3(0, -0.12, 0)))

	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.11, 0.50, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.058, 0.24, mat_suit, Vector3(0, -0.12, 0)))

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.24, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb(0.050, 0.24, mat_shoes, Vector3(0, -0.12, 0)))

	# Maca Retrátil com Saco de Cadáver (se for carregador)
	if is_stretcher_bearer:
		_build_stretcher()
	# Corpo articulado dos pedestres no lugar da geometria antiga; a maca continua.
	_install_body.call_deferred()

var body: Node3D

func _install_body() -> void:
	if is_instance_valid(body) or not is_inside_tree(): return
	var keep: Array = [get("stretcher_mesh")]
	body = preload("res://assets/civilians/RigBodySwap.gd").install(self, {"variant": 6300 + get_instance_id() % 97, "top": 2, "bottom": 0, "shoe": 2, "hat": 0, "backpack": false, "bag": 0, "top_color": Color(0.14, 0.15, 0.18), "bottom_color": Color(0.13, 0.14, 0.16), "inner": Color(0.92, 0.94, 0.96), "shoe_color": Color("101012")}, keep)
	body.hand_provider = preload("res://assets/civilians/RigBodySwap.gd").stretcher_hands(self)

func _build_stretcher() -> void:
	var mat_metal := _make_mat(Color(0.65, 0.68, 0.72), 0.8)
	stretcher_mesh = MeshInstance3D.new()
	var box_s := BoxMesh.new()
	box_s.size = Vector3(0.42, 0.06, 0.85)
	stretcher_mesh.mesh = box_s
	stretcher_mesh.material_override = mat_metal
	stretcher_mesh.position = Vector3(0.0, 0.55, -0.55)
	model_root.add_child(stretcher_mesh)

	# Saco preto de cadáver (inicialmente invisível, aparece após ensacar)
	var mat_bag := _make_mat(Color(0.06, 0.06, 0.08), 0.9)
	body_bag_mesh = MeshInstance3D.new()
	var box_b := BoxMesh.new()
	box_b.size = Vector3(0.36, 0.16, 0.78)
	body_bag_mesh.mesh = box_b
	body_bag_mesh.material_override = mat_bag
	body_bag_mesh.position = Vector3(0.0, 0.10, 0.0)
	body_bag_mesh.visible = false
	stretcher_mesh.add_child(body_bag_mesh)

func _create_limb(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mesh_inst.mesh = cyl
	mesh_inst.material_override = mat
	mesh_inst.position = offset
	return mesh_inst

func _make_mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	return m
