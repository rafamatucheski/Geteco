class_name ExtractionDemoRigFactory
extends RefCounted

## Fábrica isolada de modelos demonstrativos com as proporções e rigs reais do projeto GETECO.
## Mantém a construção visual separada do controlador de animação (PoliceDriverExtraction).

const DANTE_ADAPTER := preload("res://scripts/player/DanteVisualAdapter.gd")

static func _create_box(sz: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = sz
	mi.mesh = box
	if mat != null:
		mi.material_override = mat
	return mi

static func _create_cylinder(radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 14
	mi.mesh = cyl
	if mat != null:
		mi.material_override = mat
	return mi

static func _create_ellipsoid(sz: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = sz.x * 0.5
	sph.height = sz.y
	sph.radial_segments = 14
	sph.rings = 7
	mi.mesh = sph
	mi.scale = Vector3(1.0, 1.0, sz.z / sz.x)
	if mat != null:
		mi.material_override = mat
	return mi

## Constrói o Muscle Car com portas dianteiras esquerda e direita articuladas (Hinge em Z = 0.55m)
static func build_muscle_car() -> Dictionary:
	var vehicle_root := Node3D.new()
	vehicle_root.name = "VehicleMuscle"

	var mat_car_body := StandardMaterial3D.new()
	mat_car_body.albedo_color = Color("#b32424") # Vermelho esportivo clássico do Dante
	mat_car_body.roughness = 0.35
	mat_car_body.metallic = 0.40

	var mat_car_glass := StandardMaterial3D.new()
	mat_car_glass.albedo_color = Color("#1e2b33")
	mat_car_glass.roughness = 0.15
	mat_car_glass.metallic = 0.80

	var mat_car_chassis := StandardMaterial3D.new()
	mat_car_chassis.albedo_color = Color("#18191a")
	mat_car_chassis.roughness = 0.90

	# 1. Carroceria principal
	var lower_body := _create_box(Vector3(1.82, 0.44, 4.20), mat_car_body)
	lower_body.position = Vector3(0.0, 0.38, 0.0)
	vehicle_root.add_child(lower_body)

	var cabin_roof := _create_box(Vector3(1.44, 0.46, 1.95), mat_car_body)
	cabin_roof.position = Vector3(0.0, 0.88, -0.15)
	vehicle_root.add_child(cabin_roof)

	var windshield := _create_box(Vector3(1.40, 0.40, 0.08), mat_car_glass)
	windshield.rotation_degrees = Vector3(-35, 0, 0)
	windshield.position = Vector3(0.0, 0.80, 0.92)
	vehicle_root.add_child(windshield)

	# Rodas
	for x in [-0.88, 0.88]:
		for z in [-1.30, 1.30]:
			var wheel := _create_cylinder(0.34, 0.22, mat_car_chassis)
			wheel.rotation_degrees = Vector3(0, 0, 90)
			wheel.position = Vector3(x, 0.34, z)
			vehicle_root.add_child(wheel)

	# Bancos internos
	var seat_l := _create_box(Vector3(0.55, 0.65, 0.55), mat_car_chassis)
	seat_l.position = Vector3(-0.42, 0.55, 0.0)
	vehicle_root.add_child(seat_l)

	var seat_r := _create_box(Vector3(0.55, 0.65, 0.55), mat_car_chassis)
	seat_r.position = Vector3(0.42, 0.55, 0.0)
	vehicle_root.add_child(seat_r)

	var steering_wheel := _create_cylinder(0.18, 0.03, mat_car_chassis)
	steering_wheel.rotation_degrees = Vector3(45, 0, 0)
	steering_wheel.position = Vector3(-0.42, 0.80, 0.42)
	vehicle_root.add_child(steering_wheel)

	# Portas articuladas com dobradiças frontais em Z = 0.55m
	var door_left := _build_door_panel(mat_car_body, mat_car_glass, -1.0)
	door_left.position = Vector3(-0.88, 0.62, 0.55)
	vehicle_root.add_child(door_left)

	var door_right := _build_door_panel(mat_car_body, mat_car_glass, 1.0)
	door_right.position = Vector3(0.88, 0.62, 0.55)
	vehicle_root.add_child(door_right)

	return {
		"vehicle": vehicle_root,
		"door_left": door_left,
		"door_right": door_right
	}

static func _build_door_panel(mat_paint: Material, mat_glass: Material, side: float) -> Node3D:
	var door_pivot := Node3D.new()
	door_pivot.name = "DoorPivot_" + ("Left" if side < 0 else "Right")

	var panel := _create_box(Vector3(0.06, 0.50, 1.05), mat_paint)
	panel.position = Vector3(0.0, 0.0, -0.52)
	door_pivot.add_child(panel)

	var window := _create_box(Vector3(0.03, 0.32, 0.85), mat_glass)
	window.position = Vector3(0.0, 0.38, -0.52)
	door_pivot.add_child(window)

	var mat_chrome := StandardMaterial3D.new()
	mat_chrome.albedo_color = Color("#d0d0d0")
	mat_chrome.metallic = 0.9
	var handle := _create_box(Vector3(0.03, 0.04, 0.14), mat_chrome)
	handle.position = Vector3(side * 0.04, 0.04, -0.92)
	door_pivot.add_child(handle)

	return door_pivot

## Constrói o modelo 3D do Policial com articulações padronizadas (model_root, torso_node, left_upper_arm...)
static func build_police_officer() -> Node3D:
	var officer_root := Node3D.new()
	officer_root.name = "PoliceOfficer"

	var mat_uniform := StandardMaterial3D.new()
	mat_uniform.albedo_color = Color("#1c2438") # Azul marinho polícia oficial
	mat_uniform.roughness = 0.65

	var mat_skin := StandardMaterial3D.new()
	mat_skin.albedo_color = Color("#c89a74")
	mat_skin.roughness = 0.85

	var mat_tactical := StandardMaterial3D.new()
	mat_tactical.albedo_color = Color("#111214")
	mat_tactical.roughness = 0.90

	var mat_badge := StandardMaterial3D.new()
	mat_badge.albedo_color = Color("#e5b82c")
	mat_badge.metallic = 0.9
	mat_badge.roughness = 0.25

	# Torso
	var torso_node := Node3D.new()
	torso_node.name = "torso_node"
	torso_node.position = Vector3(0.0, 0.85, 0.0)
	officer_root.add_child(torso_node)

	var shirt := _create_box(Vector3(0.38, 0.46, 0.22), mat_uniform)
	torso_node.add_child(shirt)

	var badge := _create_box(Vector3(0.06, 0.07, 0.02), mat_badge)
	badge.position = Vector3(-0.10, 0.12, 0.12)
	torso_node.add_child(badge)

	var belt := _create_box(Vector3(0.39, 0.08, 0.23), mat_tactical)
	belt.position = Vector3(0.0, -0.20, 0.0)
	torso_node.add_child(belt)

	var holster := _create_box(Vector3(0.09, 0.16, 0.11), mat_tactical)
	holster.position = Vector3(0.21, -0.22, 0.0)
	torso_node.add_child(holster)

	# Cabeça e quepe
	var head_node := Node3D.new()
	head_node.name = "head_node"
	head_node.position = Vector3(0.0, 1.25, 0.0)
	officer_root.add_child(head_node)

	var head_sph := _create_ellipsoid(Vector3(0.22, 0.26, 0.22), mat_skin)
	head_node.add_child(head_sph)

	var cap_base := _create_cylinder(0.14, 0.08, mat_uniform)
	cap_base.position = Vector3(0.0, 0.12, 0.0)
	head_node.add_child(cap_base)

	var visor := _create_box(Vector3(0.18, 0.02, 0.10), mat_tactical)
	visor.position = Vector3(0.0, 0.10, 0.14)
	head_node.add_child(visor)

	# Braço Esquerdo
	var left_upper_arm := Node3D.new()
	left_upper_arm.name = "left_upper_arm"
	left_upper_arm.position = Vector3(-0.24, 1.05, 0.0)
	officer_root.add_child(left_upper_arm)
	var lu_mesh := _create_box(Vector3(0.09, 0.24, 0.09), mat_uniform)
	lu_mesh.position = Vector3(0.0, -0.12, 0.0)
	left_upper_arm.add_child(lu_mesh)

	var left_lower_arm := Node3D.new()
	left_lower_arm.name = "left_lower_arm"
	left_lower_arm.position = Vector3(0.0, -0.24, 0.0)
	left_upper_arm.add_child(left_lower_arm)
	var ll_mesh := _create_box(Vector3(0.08, 0.22, 0.08), mat_uniform)
	ll_mesh.position = Vector3(0.0, -0.11, 0.0)
	left_lower_arm.add_child(ll_mesh)
	var l_hand := _create_box(Vector3(0.06, 0.07, 0.06), mat_skin)
	l_hand.position = Vector3(0.0, -0.23, 0.0)
	left_lower_arm.add_child(l_hand)

	# Braço Direito
	var right_upper_arm := Node3D.new()
	right_upper_arm.name = "right_upper_arm"
	right_upper_arm.position = Vector3(0.24, 1.05, 0.0)
	officer_root.add_child(right_upper_arm)
	var ru_mesh := _create_box(Vector3(0.09, 0.24, 0.09), mat_uniform)
	ru_mesh.position = Vector3(0.0, -0.12, 0.0)
	right_upper_arm.add_child(ru_mesh)

	var right_lower_arm := Node3D.new()
	right_lower_arm.name = "right_lower_arm"
	right_lower_arm.position = Vector3(0.0, -0.24, 0.0)
	right_upper_arm.add_child(right_lower_arm)
	var rl_mesh := _create_box(Vector3(0.08, 0.22, 0.08), mat_uniform)
	rl_mesh.position = Vector3(0.0, -0.11, 0.0)
	right_lower_arm.add_child(rl_mesh)
	var r_hand := _create_box(Vector3(0.06, 0.07, 0.06), mat_skin)
	r_hand.position = Vector3(0.0, -0.23, 0.0)
	right_lower_arm.add_child(r_hand)

	# Pernas
	var left_upper_leg := Node3D.new()
	left_upper_leg.name = "left_upper_leg"
	left_upper_leg.position = Vector3(-0.11, 0.62, 0.0)
	officer_root.add_child(left_upper_leg)
	var lul_mesh := _create_box(Vector3(0.12, 0.58, 0.13), mat_uniform)
	lul_mesh.position = Vector3(0.0, -0.29, 0.0)
	left_upper_leg.add_child(lul_mesh)

	var right_upper_leg := Node3D.new()
	right_upper_leg.name = "right_upper_leg"
	right_upper_leg.position = Vector3(0.11, 0.62, 0.0)
	officer_root.add_child(right_upper_leg)
	var rul_mesh := _create_box(Vector3(0.12, 0.58, 0.13), mat_uniform)
	rul_mesh.position = Vector3(0.0, -0.29, 0.0)
	right_upper_leg.add_child(rul_mesh)

	return officer_root

## Constrói o modelo 3D de Dante Ribeiro com rig articulado padrão (model_root, torso_node, left_upper_arm...)
static func build_dante_character() -> Node3D:
	var dante_root := Node3D.new()
	dante_root.name = "DanteCharacter"

	var mat_jacket := StandardMaterial3D.new()
	mat_jacket.albedo_texture = DANTE_ADAPTER.get_plaid_texture()
	mat_jacket.uv1_scale = Vector3(2.5, 2.5, 2.5)
	mat_jacket.roughness = 0.85

	var mat_henley := StandardMaterial3D.new()
	mat_henley.albedo_color = Color("#6b1426") # Vinho bordô clássico
	mat_henley.roughness = 0.80

	var mat_pants := StandardMaterial3D.new()
	mat_pants.albedo_color = Color("#222c38") # Jeans escuro
	mat_pants.roughness = 0.85

	var mat_skin := StandardMaterial3D.new()
	mat_skin.albedo_color = Color("#9d6b4d")
	mat_skin.roughness = 0.80

	var mat_hair := StandardMaterial3D.new()
	mat_hair.albedo_color = Color("#111111")
	mat_hair.roughness = 0.95

	# Torso
	var torso_node := Node3D.new()
	torso_node.name = "torso_node"
	torso_node.position = Vector3(0.0, 0.85, 0.0)
	dante_root.add_child(torso_node)

	var jacket_box := _create_box(Vector3(0.38, 0.48, 0.24), mat_jacket)
	torso_node.add_child(jacket_box)

	var henley_chest := _create_box(Vector3(0.18, 0.36, 0.02), mat_henley)
	henley_chest.position = Vector3(0.0, 0.04, -0.125)
	torso_node.add_child(henley_chest)

	# Cabeça
	var head_node := Node3D.new()
	head_node.name = "head_node"
	head_node.position = Vector3(0.0, 1.26, 0.0)
	dante_root.add_child(head_node)

	var head_sph := _create_ellipsoid(Vector3(0.24, 0.28, 0.24), mat_skin)
	head_node.add_child(head_sph)

	var stubble := _create_box(Vector3(0.20, 0.12, 0.16), mat_hair)
	stubble.position = Vector3(0.0, -0.08, -0.06)
	head_node.add_child(stubble)

	var hair_cap := _create_ellipsoid(Vector3(0.36, 0.28, 0.36), mat_hair)
	hair_cap.position = Vector3(0.0, 0.06, 0.02)
	head_node.add_child(hair_cap)

	# Braço Esquerdo
	var left_upper_arm := Node3D.new()
	left_upper_arm.name = "left_upper_arm"
	left_upper_arm.position = Vector3(-0.23, 1.05, 0.0)
	dante_root.add_child(left_upper_arm)
	var lu_mesh := _create_box(Vector3(0.08, 0.24, 0.09), mat_jacket)
	lu_mesh.position = Vector3(0.0, -0.12, 0.0)
	left_upper_arm.add_child(lu_mesh)

	var left_lower_arm := Node3D.new()
	left_lower_arm.name = "left_lower_arm"
	left_lower_arm.position = Vector3(0.0, -0.24, 0.0)
	left_upper_arm.add_child(left_lower_arm)
	var ll_mesh := _create_box(Vector3(0.07, 0.22, 0.08), mat_jacket)
	ll_mesh.position = Vector3(0.0, -0.11, 0.0)
	left_lower_arm.add_child(ll_mesh)
	var l_hand := _create_box(Vector3(0.06, 0.07, 0.06), mat_skin)
	l_hand.position = Vector3(0.0, -0.23, 0.0)
	left_lower_arm.add_child(l_hand)

	# Braço Direito
	var right_upper_arm := Node3D.new()
	right_upper_arm.name = "right_upper_arm"
	right_upper_arm.position = Vector3(0.23, 1.05, 0.0)
	dante_root.add_child(right_upper_arm)
	var ru_mesh := _create_box(Vector3(0.08, 0.24, 0.09), mat_jacket)
	ru_mesh.position = Vector3(0.0, -0.12, 0.0)
	right_upper_arm.add_child(ru_mesh)

	var right_lower_arm := Node3D.new()
	right_lower_arm.name = "right_lower_arm"
	right_lower_arm.position = Vector3(0.0, -0.24, 0.0)
	right_upper_arm.add_child(right_lower_arm)
	var rl_mesh := _create_box(Vector3(0.07, 0.22, 0.08), mat_jacket)
	rl_mesh.position = Vector3(0.0, -0.11, 0.0)
	right_lower_arm.add_child(rl_mesh)
	var r_hand := _create_box(Vector3(0.06, 0.07, 0.06), mat_skin)
	r_hand.position = Vector3(0.0, -0.23, 0.0)
	right_lower_arm.add_child(r_hand)

	# Pernas
	var left_upper_leg := Node3D.new()
	left_upper_leg.name = "left_upper_leg"
	left_upper_leg.position = Vector3(-0.10, 0.62, 0.0)
	dante_root.add_child(left_upper_leg)
	var lul_mesh := _create_box(Vector3(0.12, 0.56, 0.13), mat_pants)
	lul_mesh.position = Vector3(0.0, -0.28, 0.0)
	left_upper_leg.add_child(lul_mesh)

	var right_upper_leg := Node3D.new()
	right_upper_leg.name = "right_upper_leg"
	right_upper_leg.position = Vector3(0.10, 0.62, 0.0)
	dante_root.add_child(right_upper_leg)
	var rul_mesh := _create_box(Vector3(0.12, 0.56, 0.13), mat_pants)
	rul_mesh.position = Vector3(0.0, -0.28, 0.0)
	right_upper_leg.add_child(rul_mesh)

	return dante_root
