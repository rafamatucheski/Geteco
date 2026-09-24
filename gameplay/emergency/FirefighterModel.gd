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
var hose_muzzle: Marker3D
func _ready() -> void:
	model_root = self
	scale = Vector3.ONE * 1.28
	mat_uniform = _make_mat(Color(0.85, 0.68, 0.10), 0.6)
	var mat_helmet := _make_mat(Color(0.88, 0.15, 0.15), 0.3)
	var mat_skin := _make_mat(Color(0.85, 0.68, 0.52), 0.5)
	var mat_black := _make_mat(Color(0.08, 0.08, 0.10), 0.4)
	var mat_silver := _make_mat(Color(0.85, 0.88, 0.92), 0.2)

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

	var stripe := MeshInstance3D.new()
	var box_st := BoxMesh.new()
	box_st.size = Vector3(0.36, 0.06, 0.35)
	stripe.mesh = box_st
	stripe.material_override = mat_silver
	stripe.position = Vector3(0.0, 0.04, 0.0)
	torso_node.add_child(stripe)

	# Cabeça com Capacete de Bombeiro com Aba
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.25, 0.0)
	head_node.scale = Vector3.ONE * 0.80
	model_root.add_child(head_node)

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.17
	sph_h.height = 0.34
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	var helm := MeshInstance3D.new()
	var sph_hl := SphereMesh.new()
	sph_hl.radius = 0.19
	sph_hl.height = 0.28
	helm.mesh = sph_hl
	helm.material_override = mat_helmet
	helm.position = Vector3(0.0, 0.06, 0.0)
	head_node.add_child(helm)

	var brim := MeshInstance3D.new()
	var cyl_br := CylinderMesh.new()
	cyl_br.top_radius = 0.23
	cyl_br.bottom_radius = 0.23
	cyl_br.height = 0.02
	brim.mesh = cyl_br
	brim.material_override = mat_helmet
	brim.position = Vector3(0.0, -0.02, 0.0)
	head_node.add_child(brim)

	# Braços 3D
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.24, 1.05, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.050, 0.22, mat_uniform, Vector3(0, -0.11, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.042, 0.18, mat_black, Vector3(0, -0.09, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.24, 1.05, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.050, 0.22, mat_uniform, Vector3(0, -0.11, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.042, 0.18, mat_black, Vector3(0, -0.09, 0)))

	# Bico de Mangueira 3D nas Mãos
	var hose_nozzle := MeshInstance3D.new()
	var cyl_noz := CylinderMesh.new()
	cyl_noz.top_radius = 0.022
	cyl_noz.bottom_radius = 0.035
	cyl_noz.height = 0.20
	hose_nozzle.mesh = cyl_noz
	hose_nozzle.material_override = mat_silver
	hose_nozzle.rotation_degrees = Vector3(90, 0, 0)
	hose_nozzle.position = Vector3(0.0, -0.18, -0.12)
	right_lower_arm.add_child(hose_nozzle)
	hose_muzzle = Marker3D.new()
	hose_muzzle.position = Vector3(0, -0.10, 0)
	hose_nozzle.add_child(hose_muzzle)

	# Pernas 3D
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.11, 0.65, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.068, 0.28, mat_uniform, Vector3(0, -0.14, 0)))

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.28, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb(0.058, 0.26, mat_uniform, Vector3(0, -0.13, 0)))
	left_lower_leg.add_child(_create_shoe(mat_black, Vector3(0, -0.26, -0.02)))

	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.11, 0.65, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.068, 0.28, mat_uniform, Vector3(0, -0.14, 0)))

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.28, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb(0.058, 0.26, mat_uniform, Vector3(0, -0.13, 0)))
	right_lower_leg.add_child(_create_shoe(mat_black, Vector3(0, -0.26, -0.02)))
	# Corpo articulado dos pedestres no lugar da geometria antiga; a maca continua.
	_install_body.call_deferred()

var body: Node3D

func _install_body() -> void:
	if is_instance_valid(body) or not is_inside_tree(): return
	var keep: Array = [get("stretcher_mesh")]
	body = preload("res://assets/civilians/RigBodySwap.gd").install(self, {"variant": 6100 + get_instance_id() % 97, "top": 7, "bottom": 3, "shoe": 1, "hat": 5, "backpack": false, "bag": 0, "glasses": false, "beard": 0, "top_color": Color(0.80, 0.64, 0.14), "bottom_color": Color(0.74, 0.59, 0.13), "inner": Color("e6eac9"), "accent": Color(0.82, 0.14, 0.12), "shoe_color": Color("141416")}, keep)
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
