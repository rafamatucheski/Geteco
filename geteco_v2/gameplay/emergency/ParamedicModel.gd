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
var medical_kit: MeshInstance3D
func _ready() -> void:
	model_root = self
	scale = Vector3.ONE * 1.28
	mat_uniform = _make_mat(Color(0.67, 0.74, 0.76), 0.9)
	var mat_pants := _make_mat(Color(0.20, 0.35, 0.55), 0.6)
	var mat_skin := _make_mat(Color(0.85, 0.68, 0.52), 0.5)
	var mat_red := _make_mat(Color(0.88, 0.15, 0.15), 0.3)
	var mat_black := _make_mat(Color(0.08, 0.08, 0.10), 0.4)
	var mat_kit := _make_mat(Color(0.90, 0.20, 0.20), 0.3)

	# Torso 3D
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.85, 0.0)
	model_root.add_child(torso_node)

	var torso_mesh := MeshInstance3D.new()
	var cap_t := CapsuleMesh.new()
	cap_t.radius = 0.17
	cap_t.height = 0.48
	torso_mesh.mesh = cap_t
	torso_mesh.material_override = mat_uniform
	torso_node.add_child(torso_mesh)

	# Cruz Vermelha no Peito
	var cross_v := MeshInstance3D.new()
	var box_cv := BoxMesh.new()
	box_cv.size = Vector3(0.03, 0.09, 0.02)
	cross_v.mesh = box_cv
	cross_v.material_override = mat_red
	cross_v.position = Vector3(0.0, 0.10, -0.165)
	torso_node.add_child(cross_v)

	var cross_h := MeshInstance3D.new()
	var box_ch := BoxMesh.new()
	box_ch.size = Vector3(0.09, 0.03, 0.02)
	cross_h.mesh = box_ch
	cross_h.material_override = mat_red
	cross_h.position = Vector3(0.0, 0.10, -0.165)
	torso_node.add_child(cross_h)

	# Estetoscópio no Pescoço
	var steth := MeshInstance3D.new()
	var box_st := BoxMesh.new()
	box_st.size = Vector3(0.22, 0.12, 0.03)
	steth.mesh = box_st
	steth.material_override = mat_black
	steth.position = Vector3(0.0, 0.18, -0.15)
	torso_node.add_child(steth)

	# Cabeça 3D
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.25, 0.0)
	model_root.add_child(head_node)

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.17
	sph_h.height = 0.34
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	# Braços 3D
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.185, 1.05, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.050, 0.22, mat_uniform, Vector3(0, -0.11, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.042, 0.18, mat_skin, Vector3(0, -0.09, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.185, 1.05, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.050, 0.22, mat_uniform, Vector3(0, -0.11, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.042, 0.18, mat_skin, Vector3(0, -0.09, 0)))

	# Maleta de Primeiros Socorros 3D na Mão Direita
	var med_kit := MeshInstance3D.new()
	medical_kit = med_kit
	var box_mk := BoxMesh.new()
	box_mk.size = Vector3(0.08, 0.16, 0.22)
	med_kit.mesh = box_mk
	med_kit.material_override = mat_kit
	med_kit.position = Vector3(0.05, -0.22, 0.0)
	right_lower_arm.add_child(med_kit)

	# Pernas 3D
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.11, 0.65, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.068, 0.28, mat_pants, Vector3(0, -0.14, 0)))

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.28, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb(0.058, 0.26, mat_pants, Vector3(0, -0.13, 0)))
	left_lower_leg.add_child(_create_shoe(mat_black, Vector3(0, -0.26, -0.02)))

	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.11, 0.65, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.068, 0.28, mat_pants, Vector3(0, -0.14, 0)))

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.28, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb(0.058, 0.26, mat_pants, Vector3(0, -0.13, 0)))
	right_lower_leg.add_child(_create_shoe(mat_black, Vector3(0, -0.26, -0.02)))

	# Maca retrátil (se for o paramédico carregador) -- mesmo padrão de
	# Mortician.gd._build_stretcher(), lençol claro em vez de saco preto.
	if is_stretcher_bearer:
		_build_stretcher()
	# Corpo articulado dos pedestres no lugar da geometria antiga; a maca continua.
	_install_body.call_deferred()

var body: Node3D

func _install_body() -> void:
	if is_instance_valid(body) or not is_inside_tree(): return
	var keep: Array = [get("stretcher_mesh")]
	body = preload("res://assets/civilians/RigBodySwap.gd").install(self, {"variant": 6200 + get_instance_id() % 97, "top": 6, "bottom": 0, "shoe": 1, "hat": 0, "backpack": not is_stretcher_bearer, "bag": 0, "top_color": Color(0.67, 0.74, 0.76), "bottom_color": Color(0.20, 0.35, 0.55), "inner": Color("e6eac9"), "accent": Color(0.85, 0.18, 0.16), "shoe_color": Color("141416")}, keep)
	body.hand_provider = preload("res://assets/civilians/RigBodySwap.gd").stretcher_hands(self)

func _make_mat(col: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = roughness
	return mat

func _create_limb(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 0.85
	cyl.height = height
	m.mesh = cyl
	m.material_override = mat
	m.position = offset
	return m

func _create_shoe(mat: Material, offset: Vector3) -> MeshInstance3D:
	var shoe := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.065, 0.16)
	shoe.mesh = box
	shoe.material_override = mat
	shoe.position = offset
	return shoe

func _build_stretcher() -> void:
	var mat_metal := _make_mat(Color(0.65, 0.68, 0.72), 0.8)
	stretcher_mesh = MeshInstance3D.new()
	var box_s := BoxMesh.new()
	box_s.size = Vector3(0.42, 0.06, 0.85)
	stretcher_mesh.mesh = box_s
	stretcher_mesh.material_override = mat_metal
	stretcher_mesh.position = Vector3(0.0, 0.55, -0.55)
	model_root.add_child(stretcher_mesh)

	# Lençol/cobertor claro sobre a maca -- a mesma peça que em Mortician.gd
	# aparece como saco de cadáver preto, aqui é o paciente sendo salvo.
	var mat_blanket := _make_mat(Color(0.88, 0.90, 0.94), 0.6)
	var blanket := MeshInstance3D.new()
	var box_b := BoxMesh.new()
	box_b.size = Vector3(0.36, 0.10, 0.78)
	blanket.mesh = box_b
	blanket.material_override = mat_blanket
	blanket.position = Vector3(0.0, 0.08, 0.0)
	stretcher_mesh.add_child(blanket)
