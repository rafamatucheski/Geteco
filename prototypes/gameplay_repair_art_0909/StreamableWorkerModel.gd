class_name StreamableWorkerModel
extends StreamableActorPresentation

## Modelo 3D do Coveiro / Trabalhador com suporte a Streaming e Compartilhamento.
##
## Caracteristicas:
## 1. Carregamento sob demanda com silhueta fallback em defer_presentation = true.
## 2. Ancoragem de ferramenta (Pa 3D) com suporte a buffering de pose antes do rig estar pronto.
## 3. Poses funcionais: HOLD (ao lado), CARRY (no ombro, sem penetrar o piso) e DIG (escavacao).
## 4. Reciclagem integral com restauracao de materiais e poses neutras.

const SHOVEL_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/ShovelTool3D.gd")

enum WorkerPose {
	HOLD,
	CARRY,
	DIG
}

var current_pose: WorkerPose = WorkerPose.HOLD
var walking: bool = false
var clock: float = 0.0
var dig_cycle_clock: float = 0.0

var torso_node: Node3D
var head_node: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_forearm: Node3D
var right_forearm: Node3D
var left_leg: Node3D
var right_leg: Node3D

var shovel: Node3D
var right_hand_mount: Node3D

# Malhas com suporte a dano / sujeira isolada
var jacket_mesh: MeshInstance3D
var trousers_mesh: MeshInstance3D

func _init(p_defer: bool = false) -> void:
	defer_presentation = p_defer

func _setup_fallback_silhouette() -> void:
	if _presentation_fallback != null or is_presentation_ready:
		return
	_presentation_fallback = Node3D.new()
	_presentation_fallback.name = "WorkerSilhouette"
	add_child(_presentation_fallback)

	# Silhueta de lona verde
	var mi := MeshInstance3D.new()
	mi.mesh = ArtPresentationCache.get_unit_box()
	mi.scale = Vector3(0.40, 1.68, 0.26)
	mi.position = Vector3(0.0, 0.84, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#324436")
	mi.material_override = mat
	_presentation_fallback.add_child(mi)

	# Indicador de pa vertical
	var shovel_proxy := MeshInstance3D.new()
	shovel_proxy.mesh = ArtPresentationCache.get_unit_cylinder()
	shovel_proxy.scale = Vector3(0.04, 1.45, 0.04)
	shovel_proxy.position = Vector3(0.30, 0.72, 0.0)
	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color("#8b6947")
	shovel_proxy.material_override = mat_wood
	_presentation_fallback.add_child(shovel_proxy)

func _build_presentation_rig() -> void:
	var mat_jacket := ArtPresentationCache.get_worker_jacket_material()
	var mat_gloves := ArtPresentationCache.get_worker_gloves_material()
	var mat_trousers := ArtPresentationCache.get_worker_trousers_material()
	var mat_boots := ArtPresentationCache.get_worker_boots_material()
	var mat_skin := ArtPresentationCache.get_skin_material(1)
	var mat_hair := ArtPresentationCache.get_hair_material(1)

	# 1. Torso
	torso_node = Node3D.new()
	torso_node.name = "Torso"
	torso_node.position = Vector3(0.0, 0.86, 0.0)
	add_child(torso_node)

	jacket_mesh = _create_box_part(Vector3(0.40, 0.52, 0.26), mat_jacket)
	torso_node.add_child(jacket_mesh)

	var belt := _create_box_part(Vector3(0.41, 0.08, 0.27), mat_boots)
	belt.position = Vector3(0.0, -0.22, 0.0)
	torso_node.add_child(belt)

	# 2. Cabeca
	head_node = Node3D.new()
	head_node.name = "Head"
	head_node.position = Vector3(0.0, 1.28, 0.0)
	add_child(head_node)

	var head_mesh := _create_sphere_part(Vector3(0.24, 0.28, 0.24), mat_skin)
	head_node.add_child(head_mesh)

	var hair_mesh := _create_sphere_part(Vector3(0.26, 0.16, 0.26), mat_hair)
	hair_mesh.position = Vector3(0.0, 0.08, -0.01)
	head_node.add_child(hair_mesh)

	# 3. Bracos
	left_arm = Node3D.new()
	left_arm.name = "LeftArm"
	left_arm.position = Vector3(-0.25, 1.05, 0.0)
	add_child(left_arm)

	var l_uarm := _create_box_part(Vector3(0.10, 0.26, 0.11), mat_jacket)
	l_uarm.position = Vector3(0.0, -0.13, 0.0)
	left_arm.add_child(l_uarm)

	left_forearm = Node3D.new()
	left_forearm.name = "LeftForearm"
	left_forearm.position = Vector3(0.0, -0.26, 0.0)
	left_arm.add_child(left_forearm)

	var l_farm := _create_box_part(Vector3(0.09, 0.24, 0.10), mat_jacket)
	l_farm.position = Vector3(0.0, -0.12, 0.0)
	left_forearm.add_child(l_farm)

	var l_glove := _create_box_part(Vector3(0.08, 0.10, 0.08), mat_gloves)
	l_glove.position = Vector3(0.0, -0.25, 0.0)
	left_forearm.add_child(l_glove)

	right_arm = Node3D.new()
	right_arm.name = "RightArm"
	right_arm.position = Vector3(0.25, 1.05, 0.0)
	add_child(right_arm)

	var r_uarm := _create_box_part(Vector3(0.10, 0.26, 0.11), mat_jacket)
	r_uarm.position = Vector3(0.0, -0.13, 0.0)
	right_arm.add_child(r_uarm)

	right_forearm = Node3D.new()
	right_forearm.name = "RightForearm"
	right_forearm.position = Vector3(0.0, -0.26, 0.0)
	right_arm.add_child(right_forearm)

	var r_farm := _create_box_part(Vector3(0.09, 0.24, 0.10), mat_jacket)
	r_farm.position = Vector3(0.0, -0.12, 0.0)
	right_forearm.add_child(r_farm)

	var r_glove := _create_box_part(Vector3(0.08, 0.10, 0.08), mat_gloves)
	r_glove.position = Vector3(0.0, -0.25, 0.0)
	right_forearm.add_child(r_glove)

	right_hand_mount = Node3D.new()
	right_hand_mount.name = "RightHandMount"
	right_hand_mount.position = Vector3(0.0, -0.26, 0.0)
	right_forearm.add_child(right_hand_mount)

	# 4. Pernas
	left_leg = Node3D.new()
	left_leg.name = "LeftLeg"
	left_leg.position = Vector3(-0.12, 0.60, 0.0)
	add_child(left_leg)

	trousers_mesh = _create_box_part(Vector3(0.13, 0.56, 0.13), mat_trousers)
	trousers_mesh.position = Vector3(0.0, -0.28, 0.0)
	left_leg.add_child(trousers_mesh)

	var l_boot := _create_box_part(Vector3(0.14, 0.14, 0.22), mat_boots)
	l_boot.position = Vector3(0.0, -0.56, -0.03)
	left_leg.add_child(l_boot)

	right_leg = Node3D.new()
	right_leg.name = "RightLeg"
	right_leg.position = Vector3(0.12, 0.60, 0.0)
	add_child(right_leg)

	var r_leg_mesh := _create_box_part(Vector3(0.13, 0.56, 0.13), mat_trousers)
	r_leg_mesh.position = Vector3(0.0, -0.28, 0.0)
	right_leg.add_child(r_leg_mesh)

	var r_boot := _create_box_part(Vector3(0.14, 0.14, 0.22), mat_boots)
	r_boot.position = Vector3(0.0, -0.56, -0.03)
	right_leg.add_child(r_boot)

	# 5. Acoplamento da Pa
	_attach_shovel()

func _attach_shovel() -> void:
	if shovel != null:
		return
	shovel = SHOVEL_SCRIPT.new()
	shovel.name = "WorkerShovel"
	right_hand_mount.add_child(shovel)

func _create_box_part(box_scale: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ArtPresentationCache.get_unit_box()
	mi.scale = box_scale
	mi.material_override = mat
	return mi

func _create_sphere_part(sphere_scale: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ArtPresentationCache.get_unit_sphere()
	mi.scale = sphere_scale
	mi.material_override = mat
	return mi

func set_worker_pose(pose: WorkerPose) -> void:
	current_pose = pose
	if not is_presentation_ready:
		_buffered_pose = pose as int
		return

	if shovel != null and shovel.has_method("set_pose"):
		shovel.set_pose(pose as int)

	match current_pose:
		WorkerPose.HOLD:
			torso_node.rotation_degrees = Vector3.ZERO
			right_arm.rotation_degrees = Vector3(12.0, 0.0, -8.0)
			right_forearm.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
			left_arm.rotation_degrees = Vector3(8.0, 0.0, 8.0)
			left_forearm.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
			head_node.rotation_degrees = Vector3.ZERO
		WorkerPose.CARRY:
			torso_node.rotation_degrees = Vector3.ZERO
			right_arm.rotation_degrees = Vector3(-135.0, 15.0, -12.0)
			right_forearm.rotation_degrees = Vector3(-65.0, 0.0, 0.0)
			left_arm.rotation_degrees = Vector3(12.0, 0.0, 10.0)
			left_forearm.rotation_degrees = Vector3(-20.0, 0.0, 0.0)
			head_node.rotation_degrees = Vector3.ZERO
		WorkerPose.DIG:
			torso_node.rotation_degrees = Vector3(25.0, 10.0, 0.0)
			right_arm.rotation_degrees = Vector3(-15.0, 10.0, -15.0)
			right_forearm.rotation_degrees = Vector3(-45.0, 10.0, 0.0)
			left_arm.rotation_degrees = Vector3(35.0, -20.0, 20.0)
			left_forearm.rotation_degrees = Vector3(-70.0, 25.0, 0.0)
			head_node.rotation_degrees = Vector3(18.0, -5.0, 0.0)

func _apply_pose_to_rig(pose_idx: int) -> void:
	set_worker_pose(pose_idx as WorkerPose)

func update_animation(delta: float, moving: bool) -> void:
	walking = moving
	if not is_presentation_ready:
		_buffered_walking = moving
		return

	if walking:
		clock += delta * 4.0
		var swing := sin(clock) * 20.0
		left_leg.rotation_degrees.x = swing
		right_leg.rotation_degrees.x = -swing
		if current_pose == WorkerPose.CARRY:
			left_arm.rotation_degrees.x = -swing * 0.8
		elif current_pose == WorkerPose.HOLD:
			left_arm.rotation_degrees.x = -swing * 0.6
	else:
		left_leg.rotation_degrees.x = lerpf(left_leg.rotation_degrees.x, 0.0, 8.0 * delta)
		right_leg.rotation_degrees.x = lerpf(right_leg.rotation_degrees.x, 0.0, 8.0 * delta)

# --- ISOLAMENTO DE DANO / SUJEIRA E RESTAURACAO ---

func _apply_damage_to_rig(damage_type: String, intensity: float, _affected_part: String) -> void:
	var base_jacket := ArtPresentationCache.get_worker_jacket_material()
	var dmg_mat := ArtPresentationCache.create_damage_material(base_jacket, damage_type, intensity)
	if jacket_mesh != null:
		jacket_mesh.material_override = dmg_mat

func _restore_shared_materials() -> void:
	if jacket_mesh != null:
		jacket_mesh.material_override = ArtPresentationCache.get_worker_jacket_material()
	if trousers_mesh != null:
		trousers_mesh.material_override = ArtPresentationCache.get_worker_trousers_material()

func _on_recycled_custom() -> void:
	current_pose = WorkerPose.HOLD
	walking = false
	clock = 0.0
	dig_cycle_clock = 0.0
	if shovel != null and shovel.has_method("set_pose"):
		shovel.set_pose(WorkerPose.HOLD as int)