extends Node3D
@export var character_name: String = "Atendente"
@export var title_color: Color = Color("#f1c40f")
@export var shirt_color: Color = Color("#2980b9")
@export var pants_color: Color = Color("#1a5276")
@export var skin_color: Color = Color("#d2b48c")
@export var hat_color: Color = Color("#2c3e50")
@export var has_hat: bool = false
@export var is_female: bool = false
@export var resting_facing_y: float = 0.0

var model_root: Node3D
var torso_node: Node3D
var head_node: Node3D
var left_upper_arm: Node3D
var left_lower_arm: Node3D
var right_upper_arm: Node3D
var right_lower_arm: Node3D
var torso_rest_height := 0.75
var head_rest_height := 1.14

func _ready() -> void:
	_build_model()
	preload("res://assets/regions/source/characters/pedestrians/CitizenDetails.gd").finish_rig(self,"clerk")
	model_root.scale = Vector3.ONE * 1.28
	model_root.rotation.y = PI
	# Corpo articulado dos pedestres no lugar da geometria antiga; diferido para
	# subclasses (médico, Neco) terminarem os próprios acessórios antes.
	_install_body.call_deferred()

var body: Node3D

func _install_body() -> void:
	if is_instance_valid(body) or not is_inside_tree(): return
	body = preload("res://assets/civilians/RigBodySwap.gd").install(self, _body_look(), [], true)

func _body_look() -> Dictionary:
	return {"variant": 7000 + hash(character_name) % 997, "female": is_female, "top": 5, "bottom": 0, "shoe": 2,
		"hat": 1 if has_hat else 0, "backpack": false, "bag": 0,
		"top_color": shirt_color, "bottom_color": pants_color, "skin": skin_color, "accent": hat_color}

func _make_mat(color: Color, roughness: float = 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.shading_mode = StandardMaterial3D.SHADING_MODE_PER_PIXEL
	return m

func _build_model() -> void:
	model_root = Node3D.new()
	add_child(model_root)

	var mat_shirt := _make_mat(shirt_color, 0.85)
	var mat_pants := _make_mat(pants_color, 0.5)
	var mat_skin := _make_mat(skin_color, 0.5)
	var mat_hat := _make_mat(hat_color, 0.3)

	# Torso
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.75, 0.0)
	model_root.add_child(torso_node)

	var torso_mesh := MeshInstance3D.new()
	var cap_t := CapsuleMesh.new()
	cap_t.radius = 0.16
	cap_t.height = 0.46
	torso_mesh.mesh = load("res://assets/regions/source/characters/pedestrians/CitizenAppearance.gd").tailored_body(is_female, false)
	torso_mesh.material_override = mat_shirt
	torso_node.add_child(torso_mesh)

	# Head
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.14, 0.0)
	model_root.add_child(head_node)

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.14
	sph_h.height = 0.28
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)
	head_node.scale=Vector3.ONE*.85
	var detail=preload("res://assets/regions/source/characters/pedestrians/CitizenDetails.gd")
	detail.piece(torso_node,Vector3(.11,.20,.115),Vector3(0,.285,.01),skin_color,true)
	detail.piece(torso_node,Vector3(.27,.13,.23),Vector3(0,-.25,0),pants_color)

	if has_hat:
		var cap := MeshInstance3D.new()
		var cyl_c := CylinderMesh.new()
		cyl_c.top_radius = 0.16
		cyl_c.bottom_radius = 0.17
		cyl_c.height = 0.08
		cap.mesh = cyl_c
		cap.material_override = mat_hat
		cap.position = Vector3(0.0, 0.12, 0.0)
		head_node.add_child(cap)

		var visor := MeshInstance3D.new()
		var box_v := BoxMesh.new()
		box_v.size = Vector3(0.14, 0.02, 0.10)
		visor.mesh = box_v
		visor.material_override = mat_hat
		visor.position = Vector3(0.0, 0.08, -0.15)
		head_node.add_child(visor)

	# Arms
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.21, 0.98, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.045, 0.20, mat_shirt, Vector3(0, -0.10, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.20, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.038, 0.18, mat_skin, Vector3(0, -0.09, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.21, 0.98, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.045, 0.20, mat_shirt, Vector3(0, -0.10, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.20, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.038, 0.18, mat_skin, Vector3(0, -0.09, 0)))

	# Legs
	for side in [-0.09, 0.09]:
		var leg := Node3D.new()
		leg.position = Vector3(side, 0.50, 0.0)
		model_root.add_child(leg)
		leg.add_child(_create_limb(0.050, 0.44, mat_pants, Vector3(0, -0.22, 0)))
		preload("res://assets/regions/source/characters/pedestrians/CitizenDetails.gd").piece(leg,Vector3(.11,.08,.20),Vector3(0,-.46,-.04),Color("34414a"),true)

func _create_limb(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 0.9
	cyl.height = height
	m.mesh = cyl
	m.material_override = mat
	m.position = offset
	return m

