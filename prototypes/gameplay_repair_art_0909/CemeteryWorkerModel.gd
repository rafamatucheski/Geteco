extends Node3D

## Modelo 3D do Coveiro / Trabalhador Visitante do cemitério.
## Distinção visual absoluta em relação a Elias e aos visitantes:
##   - Jaqueta utilitária verde musgo de lona pesada com bolsos reforçados
##   - Luvas robustas de couro espesso
##   - Calças reforçadas de trabalho com joelheiras duplas e galochas pesadas
##   - Pá 3D (ShovelTool3D) acoplada diretamente à mão em 3 modos articulados:
##       1. HOLD: Segurar em repouso
##       2. CARRY: Carregar durante a caminhada (com a lâmina suspensa para não cortar o chão)
##       3. DIG: Cavar com duas mãos e tronco articulado

const SHOVEL_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/ShovelTool3D.gd")

enum WorkerPose {
	HOLD,
	CARRY,
	DIG
}

var current_pose: WorkerPose = WorkerPose.HOLD
var walking: bool = false
var clock: float = 0.0
var gait_phase := 0.0
var dig_cycle_clock: float = 0.0

var torso_node: Node3D
var head_node: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_forearm: Node3D
var right_forearm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_knee: Node3D
var right_knee: Node3D

var shovel: Node3D
var right_hand_mount: Node3D

var mat_jacket: StandardMaterial3D
var mat_gloves: StandardMaterial3D
var mat_trousers: StandardMaterial3D
var mat_boots: StandardMaterial3D
var mat_skin: StandardMaterial3D
var mat_hair: StandardMaterial3D
var mat_belt: StandardMaterial3D

func _init() -> void:
	_setup_materials()
	_build_rig()
	_attach_shovel()
	set_worker_pose(WorkerPose.HOLD)

func _setup_materials() -> void:
	mat_jacket = StandardMaterial3D.new()
	mat_jacket.albedo_color = Color("#324436")
	mat_jacket.roughness = 0.85

	mat_gloves = StandardMaterial3D.new()
	mat_gloves.albedo_color = Color("#755331")
	mat_gloves.roughness = 0.70

	mat_trousers = StandardMaterial3D.new()
	mat_trousers.albedo_color = Color("#383e3a")
	mat_trousers.roughness = 0.88

	mat_boots = StandardMaterial3D.new()
	mat_boots.albedo_color = Color("#1e1e20")
	mat_boots.roughness = 0.60

	mat_skin = StandardMaterial3D.new()
	mat_skin.albedo_color = Color("#b3774f")
	mat_skin.roughness = 0.60

	mat_hair = StandardMaterial3D.new()
	mat_hair.albedo_color = Color("#241c17")
	mat_hair.roughness = 0.85

	mat_belt = StandardMaterial3D.new()
	mat_belt.albedo_color = Color("#231e1a")
	mat_belt.roughness = 0.50

func _build_rig() -> void:
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.86, 0.0)
	add_child(torso_node)

	var jacket_chest := _create_ellipsoid(Vector3(0.46, 0.57, 0.29), mat_jacket)
	torso_node.add_child(jacket_chest)

	for s in [-1.0, 1.0]:
		var pocket := _create_box(Vector3(0.11, 0.14, 0.03), mat_jacket)
		pocket.position = Vector3(s * 0.12, -0.06, -0.13)
		torso_node.add_child(pocket)

	for s in [-1.0, 1.0]:
		var col := _create_box(Vector3(0.08, 0.12, 0.03), mat_jacket)
		col.position = Vector3(s * 0.12, 0.21, -0.11)
		col.rotation_degrees = Vector3(14.0, s * -15.0, s * 20.0)
		torso_node.add_child(col)

	var belt := _create_box(Vector3(0.41, 0.06, 0.25), mat_belt)
	belt.position = Vector3(0.0, -0.23, 0.0)
	torso_node.add_child(belt)

	var tool_ring := _create_box(Vector3(0.02, 0.06, 0.06), mat_gloves)
	tool_ring.position = Vector3(-0.19, -0.26, 0.0)
	torso_node.add_child(tool_ring)

	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.26, 0.0)
	add_child(head_node)

	var head_mesh := _create_ellipsoid(Vector3(0.24, 0.28, 0.24), mat_skin)
	head_node.add_child(head_mesh)

	var hair_mesh := _create_ellipsoid(Vector3(0.26, 0.16, 0.26), mat_hair)
	hair_mesh.position = Vector3(0.0, 0.08, -0.01)
	head_node.add_child(hair_mesh)

	var cap_dome := _create_ellipsoid(Vector3(0.27, 0.11, 0.28), mat_jacket)
	cap_dome.position = Vector3(0.0, 0.12, 0.0)
	head_node.add_child(cap_dome)

	var cap_brim := _create_box(Vector3(0.18, 0.015, 0.10), mat_jacket)
	cap_brim.position = Vector3(0.0, 0.09, -0.15)
	cap_brim.rotation_degrees = Vector3(10.0, 0.0, 0.0)
	head_node.add_child(cap_brim)

	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.24, 1.04, 0.0)
	add_child(left_arm)

	var l_uarm := _create_ellipsoid(Vector3(0.09, 0.24, 0.10), mat_jacket)
	l_uarm.position = Vector3(0.0, -0.12, 0.0)
	left_arm.add_child(l_uarm)

	left_forearm = Node3D.new()
	left_forearm.position = Vector3(0.0, -0.24, 0.0)
	left_arm.add_child(left_forearm)

	var l_farm := _create_ellipsoid(Vector3(0.08, 0.22, 0.09), mat_jacket)
	l_farm.position = Vector3(0.0, -0.11, 0.0)
	left_forearm.add_child(l_farm)

	var l_glove := _create_ellipsoid(Vector3(0.07, 0.10, 0.07), mat_gloves)
	l_glove.position = Vector3(0.0, -0.23, 0.0)
	left_forearm.add_child(l_glove)

	right_arm = Node3D.new()
	right_arm.position = Vector3(0.24, 1.04, 0.0)
	add_child(right_arm)

	var r_uarm := _create_ellipsoid(Vector3(0.09, 0.24, 0.10), mat_jacket)
	r_uarm.position = Vector3(0.0, -0.12, 0.0)
	right_arm.add_child(r_uarm)

	right_forearm = Node3D.new()
	right_forearm.position = Vector3(0.0, -0.24, 0.0)
	right_arm.add_child(right_forearm)

	var r_farm := _create_ellipsoid(Vector3(0.08, 0.22, 0.09), mat_jacket)
	r_farm.position = Vector3(0.0, -0.11, 0.0)
	right_forearm.add_child(r_farm)

	var r_glove := _create_ellipsoid(Vector3(0.07, 0.10, 0.07), mat_gloves)
	r_glove.position = Vector3(0.0, -0.23, 0.0)
	right_forearm.add_child(r_glove)

	right_hand_mount = Node3D.new()
	right_hand_mount.name = "RightHandMount"
	right_hand_mount.position = Vector3(0.0, -0.24, 0.0)
	right_forearm.add_child(right_hand_mount)

	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.11, 0.60, 0.0)
	add_child(left_leg)

	left_knee = _build_leg(left_leg)
	right_leg = Node3D.new()
	right_leg.position = Vector3(0.11, 0.60, 0.0)
	add_child(right_leg)
	right_knee = _build_leg(right_leg)
	_build_face()

func _build_leg(hip: Node3D) -> Node3D:
	var thigh := _create_ellipsoid(Vector3(.16,.32,.18), mat_trousers)
	thigh.position.y = -.13
	hip.add_child(thigh)
	var knee := Node3D.new()
	knee.position.y = -.27
	hip.add_child(knee)
	var calf := _create_ellipsoid(Vector3(.14,.29,.15), mat_trousers)
	calf.position.y = -.12
	knee.add_child(calf)
	var boot := _create_ellipsoid(Vector3(.15,.15,.24), mat_boots)
	boot.position = Vector3(0,-.28,-.035)
	knee.add_child(boot)
	preload("res://world/harbor/cemetery/CemeteryStride.gd").ankle(knee, .28)
	return knee

func _build_face() -> void:
	var nose := _create_ellipsoid(Vector3(.055,.08,.065), mat_skin)
	nose.position = Vector3(0,-.01,-.12)
	head_node.add_child(nose)
	for side in [-1.0,1.0]:
		var ear := _create_ellipsoid(Vector3(.045,.08,.05), mat_skin)
		ear.position = Vector3(side*.119,0,0)
		head_node.add_child(ear)
		var eye_white := StandardMaterial3D.new()
		eye_white.albedo_color = Color("b6a08a")
		eye_white.roughness = .65
		var eye := _create_ellipsoid(Vector3(.034,.018,.018), eye_white)
		eye.position = Vector3(side*.045,.025,-.116)
		head_node.add_child(eye)
		var pupil := _create_ellipsoid(Vector3(.014,.014,.01), mat_hair)
		pupil.position = Vector3(side*.045,.025,-.126)
		head_node.add_child(pupil)
		var brow := _create_box(Vector3(.038,.012,.015), mat_hair)
		brow.position = Vector3(side*.046,.047,-.108)
		brow.rotation.z = side*.12
		head_node.add_child(brow)
	var moustache := _create_ellipsoid(Vector3(.078,.025,.018), mat_hair)
	moustache.position = Vector3(0,-.048,-.116)
	head_node.add_child(moustache)
	var neck := _create_ellipsoid(Vector3(.12,.17,.13),mat_skin)
	neck.position = Vector3(0,1.12,0)
	add_child(neck)

func _attach_shovel() -> void:
	shovel = SHOVEL_SCRIPT.new()
	shovel.name = "GravediggerShovel"
	right_hand_mount.add_child(shovel)

func set_worker_pose(pose: WorkerPose) -> void:
	current_pose = pose
	match current_pose:
		WorkerPose.HOLD:
			torso_node.rotation_degrees = Vector3.ZERO
			head_node.rotation_degrees = Vector3.ZERO
			right_arm.rotation_degrees = Vector3(12.0, 0.0, -10.0)
			right_forearm.rotation_degrees = Vector3(-15.0, 0.0, 0.0)
			left_arm.rotation_degrees = Vector3(0.0, 0.0, 8.0)
			left_forearm.rotation_degrees = Vector3.ZERO
			shovel.set_pose(0) # ShovelPose.HOLD

		WorkerPose.CARRY:
			torso_node.rotation_degrees = Vector3.ZERO
			head_node.rotation_degrees = Vector3.ZERO
			right_arm.rotation_degrees = Vector3(-35.0, 18.0, -22.0)
			right_forearm.rotation_degrees = Vector3(-45.0, 10.0, 0.0)
			left_arm.rotation_degrees = Vector3(0.0, 0.0, 8.0)
			left_forearm.rotation_degrees = Vector3.ZERO
			shovel.set_pose(1) # ShovelPose.CARRY

		WorkerPose.DIG:
			torso_node.rotation_degrees = Vector3(18.0, 0.0, 0.0)
			head_node.rotation_degrees = Vector3(15.0, 0.0, 0.0)
			right_arm.rotation_degrees = Vector3(25.0, 15.0, -15.0)
			right_forearm.rotation_degrees = Vector3(-40.0, 0.0, 0.0)
			left_arm.rotation_degrees = Vector3(32.0, -22.0, 25.0)
			left_forearm.rotation_degrees = Vector3(-65.0, 20.0, 0.0)
			shovel.set_pose(2) # ShovelPose.DIG

func set_dig_pose(active: bool) -> void:
	if active:
		set_worker_pose(WorkerPose.DIG)
	else:
		set_worker_pose(WorkerPose.CARRY if walking else WorkerPose.HOLD)

func update_animation(delta: float, moving: bool, travel_metres: float = -1.0) -> void:
	walking = moving
	if not walking:
		left_leg.position.y = .60
		right_leg.position.y = .60
		left_knee.get_node("StrideFoot").rotation.x = 0
		right_knee.get_node("StrideFoot").rotation.x = 0
	clock += delta * 4.0
	if walking:
		if current_pose == WorkerPose.HOLD:
			set_worker_pose(WorkerPose.CARRY)

		gait_phase = fposmod(gait_phase + (travel_metres if travel_metres >= 0 else delta * 1.2) * TAU / .8, TAU)
		left_leg.position.y = .585
		right_leg.position.y = .585
		var gait = preload("res://world/harbor/cemetery/CemeteryStride.gd")
		gait.pose(left_leg, left_knee, gait_phase, .27, .28, .075, -1.0)
		gait.pose(right_leg, right_knee, gait_phase + PI, .27, .28, .075, -1.0)
		torso_node.rotation.z = sin(gait_phase)*.018
		head_node.rotation.y = sin(gait_phase*.5)*.035
		left_arm.rotation.x = -cos(gait_phase) * .25
	elif current_pose == WorkerPose.DIG:
		dig_cycle_clock += delta * 2.8
		var dig_phase := fmod(dig_cycle_clock, TAU)
		var bend := sin(dig_phase) * 14.0
		torso_node.rotation_degrees.x = 18.0 + bend
		head_node.rotation_degrees.x = 15.0 + bend * 0.5
		right_arm.rotation_degrees.x = 25.0 + bend * 0.8
		left_arm.rotation_degrees.x = 32.0 + bend * 0.8
	else:
		torso_node.scale = Vector3(1.0,1.0+sin(clock*.42)*.007,1.0)
		torso_node.rotation.z = sin(clock*.23)*.015
		head_node.rotation.y = sin(clock*.19)*.09
		head_node.rotation.x = sin(clock*.31)*.025
		left_knee.rotation.x = lerpf(left_knee.rotation.x,0.0,minf(1.0,delta*8.0))
		right_knee.rotation.x = lerpf(right_knee.rotation.x,0.0,minf(1.0,delta*8.0))
		left_leg.rotation_degrees.x = lerpf(left_leg.rotation_degrees.x, 0.0, 8.0 * delta)
		right_leg.rotation_degrees.x = lerpf(right_leg.rotation_degrees.x, 0.0, 8.0 * delta)

func _create_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	return mi

func _create_ellipsoid(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = 24
	sph.rings = 12
	mi.mesh = sph
	mi.material_override = mat
	mi.scale = size
	return mi
