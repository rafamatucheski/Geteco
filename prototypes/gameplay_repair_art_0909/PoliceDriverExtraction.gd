class_name PoliceDriverExtraction
extends Node3D

## Controlador desacoplado e puro de animação da retirada policial do motorista (Entrega 3).
## Não constrói malhas internamente: recebe referências aos modelos reais ou da cena via bind_actors().
##
## Compatível com:
##   - Atores 3D diretos (Node3D) ou nós 2D com SubViewport (CharacterBody2D com model_root).
##   - Veículos com portas 3D articuladas (door_left, door_right) ou com método _animate_car_door().
##   - Suporta abordagem esquerda (motorista) e direita (passageiro).
##   - Interrupção segura (interrupt_extraction / cancel) com rollback suave sem poses presas.

signal extraction_started(side: float)
signal door_opened(side: float)
signal driver_extracted()
signal suspect_handcuffed()
signal sequence_completed()
signal extraction_interrupted(reason: String)

enum Phase {
	IDLE,
	APPROACH,
	OPEN_DOOR,
	REACH_IN,
	EXTRACT,
	CUFF,
	COMPLETED,
	INTERRUPTED
}

var current_phase: Phase = Phase.IDLE
var extraction_side: float = -1.0 # -1.0 = Esquerda (Motorista), 1.0 = Direita (Passageiro)
var speed_multiplier: float = 1.0
var vehicle_speed: float = 0.0

# Referências injetadas aos atores da cena
var vehicle_ref: Node
var vehicle_root: Node3D
var door_left: Node3D
var door_right: Node3D
var officer_root: Node3D
var dante_root: Node3D

# Articulações resolvidas do Policial
var officer_torso: Node3D
var officer_arm_l: Node3D
var officer_arm_r: Node3D
var officer_farm_l: Node3D
var officer_farm_r: Node3D
var officer_leg_l: Node3D
var officer_leg_r: Node3D

# Articulações resolvidas de Dante
var dante_torso: Node3D
var dante_arm_l: Node3D
var dante_arm_r: Node3D
var dante_farm_l: Node3D
var dante_farm_r: Node3D
var dante_leg_l: Node3D
var dante_leg_r: Node3D

# Cache de poses originais para restauração perfeita
var initial_rotations: Dictionary = {}
var handcuffs_mesh: MeshInstance3D
var active_tween: Tween

## Injeta os atores e objetos da cena no controlador
func bind_actors(dante: Node, officer: Node, vehicle: Node, door_l: Node = null, door_r: Node = null) -> void:
	if active_tween != null and active_tween.is_running():
		active_tween.kill()

	vehicle_ref = vehicle
	dante_root = dante.get("model_root") if (dante != null and dante.get("model_root") is Node3D) else dante as Node3D
	officer_root = officer.get("model_root") if (officer != null and officer.get("model_root") is Node3D) else officer as Node3D
	vehicle_root = vehicle as Node3D
	door_left = door_l as Node3D
	door_right = door_r as Node3D

	if door_left == null and is_instance_valid(vehicle):
		var dl = vehicle.get_node_or_null("DoorPivot_Left")
		door_left = dl if dl is Node3D else vehicle.find_child("DoorPivot_Left", true, false)
	if door_right == null and is_instance_valid(vehicle):
		var dr = vehicle.get_node_or_null("DoorPivot_Right")
		door_right = dr if dr is Node3D else vehicle.find_child("DoorPivot_Right", true, false)

	_resolve_limbs()
	_cache_initial_transforms()
	_setup_handcuffs()
	reset_poses()

func _resolve_limbs() -> void:
	if is_instance_valid(officer_root):
		officer_torso = _find_limb(officer_root, ["torso_node", "Torso", "officer_torso"])
		officer_arm_l = _find_limb(officer_root, ["left_upper_arm", "officer_arm_l", "Arm_L", "LeftArm"])
		officer_farm_l = _find_limb(officer_root, ["left_lower_arm", "officer_farm_l", "Forearm_L", "LeftForearm"])
		officer_arm_r = _find_limb(officer_root, ["right_upper_arm", "officer_arm_r", "Arm_R", "RightArm"])
		officer_farm_r = _find_limb(officer_root, ["right_lower_arm", "officer_farm_r", "Forearm_R", "RightForearm"])
		officer_leg_l = _find_limb(officer_root, ["left_upper_leg", "officer_leg_l", "Leg_L", "LeftLeg"])
		officer_leg_r = _find_limb(officer_root, ["right_upper_leg", "officer_leg_r", "Leg_R", "RightLeg"])

	if is_instance_valid(dante_root):
		dante_torso = _find_limb(dante_root, ["torso_node", "Torso", "dante_torso"])
		dante_arm_l = _find_limb(dante_root, ["left_upper_arm", "dante_arm_l", "Arm_L", "LeftArm"])
		dante_farm_l = _find_limb(dante_root, ["left_lower_arm", "dante_farm_l", "Forearm_L", "LeftForearm"])
		dante_arm_r = _find_limb(dante_root, ["right_upper_arm", "dante_arm_r", "Arm_R", "RightArm"])
		dante_farm_r = _find_limb(dante_root, ["right_lower_arm", "dante_farm_r", "Forearm_R", "RightForearm"])
		dante_leg_l = _find_limb(dante_root, ["left_upper_leg", "dante_leg_l", "Leg_L", "LeftLeg"])
		dante_leg_r = _find_limb(dante_root, ["right_upper_leg", "dante_leg_r", "Leg_R", "RightLeg"])

func _find_limb(actor: Node3D, candidates: Array[String]) -> Node3D:
	for cand in candidates:
		var n := actor.get_node_or_null(cand)
		if n is Node3D:
			return n
		var found := actor.find_child(cand, true, false)
		if found is Node3D:
			return found
		var val = actor.get(cand)
		if val is Node3D:
			return val
	return null

func _cache_initial_transforms() -> void:
	initial_rotations.clear()
	var all_limbs := [
		dante_torso, dante_arm_l, dante_arm_r, dante_farm_l, dante_farm_r, dante_leg_l, dante_leg_r,
		officer_torso, officer_arm_l, officer_arm_r, officer_farm_l, officer_farm_r, officer_leg_l, officer_leg_r
	]
	for limb in all_limbs:
		if is_instance_valid(limb):
			initial_rotations[limb] = limb.rotation_degrees

func _setup_handcuffs() -> void:
	if is_instance_valid(handcuffs_mesh):
		handcuffs_mesh.queue_free()
		handcuffs_mesh = null

	var mat_steel := StandardMaterial3D.new()
	mat_steel.albedo_color = Color("#bdc3c7")
	mat_steel.metallic = 0.95
	mat_steel.roughness = 0.25

	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.24, 0.04, 0.06)
	mi.mesh = box
	mi.material_override = mat_steel
	mi.name = "Handcuffs"
	mi.visible = false

	if is_instance_valid(dante_root):
		dante_root.add_child(mi)
		handcuffs_mesh = mi
	else:
		add_child(mi)
		handcuffs_mesh = mi

## Restaura todas as poses para a posição inicial de direção e prontidão
func reset_poses() -> void:
	if active_tween != null and active_tween.is_running():
		active_tween.kill()

	current_phase = Phase.IDLE
	if is_instance_valid(handcuffs_mesh):
		handcuffs_mesh.visible = false

	if is_instance_valid(door_left):
		door_left.rotation_degrees.y = 0.0
	if is_instance_valid(door_right):
		door_right.rotation_degrees.y = 0.0

	# Dante sentado no banco do carro
	if is_instance_valid(dante_root):
		var seat_pos := Vector3(extraction_side * 0.42, 0.28, 0.0)
		dante_root.position = seat_pos
		dante_root.rotation_degrees = Vector3.ZERO

	if is_instance_valid(dante_torso):
		dante_torso.rotation_degrees = Vector3.ZERO
	if is_instance_valid(dante_leg_l):
		dante_leg_l.rotation_degrees = Vector3(85.0, 0.0, 0.0)
	if is_instance_valid(dante_leg_r):
		dante_leg_r.rotation_degrees = Vector3(85.0, 0.0, 0.0)
	if is_instance_valid(dante_arm_l):
		dante_arm_l.rotation_degrees = Vector3(-45.0, 15.0, -10.0)
	if is_instance_valid(dante_farm_l):
		dante_farm_l.rotation_degrees = Vector3(-40.0, 0.0, 0.0)
	if is_instance_valid(dante_arm_r):
		dante_arm_r.rotation_degrees = Vector3(-45.0, -15.0, 10.0)
	if is_instance_valid(dante_farm_r):
		dante_farm_r.rotation_degrees = Vector3(-40.0, 0.0, 0.0)

	# Policial a postos na retaguarda lateral
	if is_instance_valid(officer_root):
		officer_root.position = Vector3(extraction_side * 2.2, 0.0, 1.6)
		if officer_root.is_inside_tree():
			officer_root.look_at(Vector3(extraction_side * 0.9, 0.6, 0.2), Vector3.UP)
		else:
			officer_root.rotation_degrees.y = -140.0 if extraction_side < 0 else 140.0

	if is_instance_valid(officer_torso):
		officer_torso.rotation_degrees = Vector3.ZERO
	if is_instance_valid(officer_arm_l):
		officer_arm_l.rotation_degrees = Vector3.ZERO
	if is_instance_valid(officer_farm_l):
		officer_farm_l.rotation_degrees = Vector3.ZERO
	if is_instance_valid(officer_arm_r):
		officer_arm_r.rotation_degrees = Vector3(18.0, 0.0, -12.0)
	if is_instance_valid(officer_farm_r):
		officer_farm_r.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
	if is_instance_valid(officer_leg_l):
		officer_leg_l.rotation_degrees = Vector3.ZERO
	if is_instance_valid(officer_leg_r):
		officer_leg_r.rotation_degrees = Vector3.ZERO

## Inicia a sequência de retirada na porta especificada (-1.0 = motorista/esquerda, 1.0 = passageiro/direita)
func start_extraction(side: float = -1.0) -> bool:
	if vehicle_speed > 5.0:
		extraction_interrupted.emit("Veículo em movimento. Retirada bloqueada por segurança.")
		return false

	extraction_side = side
	reset_poses()
	current_phase = Phase.APPROACH
	extraction_started.emit(extraction_side)

	var spd: float = maxf(0.1, speed_multiplier)
	if active_tween != null and active_tween.is_running():
		active_tween.kill()

	active_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	# FASE 1: Policial se desloca até a porta do carro
	var door_approach_pos := Vector3(extraction_side * 1.35, 0.0, 0.15)
	if is_instance_valid(officer_root):
		active_tween.tween_property(officer_root, "position", door_approach_pos, 1.8 / spd)

	# FASE 2: Policial alcança a maçaneta e abre a porta
	active_tween.tween_callback(func():
		current_phase = Phase.OPEN_DOOR
		if is_instance_valid(vehicle_ref) and vehicle_ref.has_method("_animate_car_door"):
			vehicle_ref.call("_animate_car_door", extraction_side, 2.5 / spd)

		if extraction_side < 0:
			if is_instance_valid(officer_arm_r): officer_arm_r.rotation_degrees = Vector3(-48.0, 12.0, -18.0)
			if is_instance_valid(officer_farm_r): officer_farm_r.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
		else:
			if is_instance_valid(officer_arm_l): officer_arm_l.rotation_degrees = Vector3(-48.0, -12.0, 18.0)
			if is_instance_valid(officer_farm_l): officer_farm_l.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
	)

	var door_node := door_left if extraction_side < 0 else door_right
	var open_angle_deg := -64.0 * extraction_side
	if is_instance_valid(door_node):
		active_tween.tween_property(door_node, "rotation_degrees:y", open_angle_deg, 0.6 / spd)
	active_tween.tween_callback(func():
		door_opened.emit(extraction_side)
	)

	# FASE 3: Policial alcança a cabine com comando de voz
	active_tween.tween_callback(func():
		current_phase = Phase.REACH_IN
		if is_instance_valid(dante_arm_l): dante_arm_l.rotation_degrees = Vector3(-65.0, 15.0, -25.0)
		if is_instance_valid(dante_farm_l): dante_farm_l.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
		if is_instance_valid(dante_arm_r): dante_arm_r.rotation_degrees = Vector3(-65.0, -15.0, 25.0)
		if is_instance_valid(dante_farm_r): dante_farm_r.rotation_degrees = Vector3(-60.0, 0.0, 0.0)

		if extraction_side < 0:
			if is_instance_valid(officer_arm_r): officer_arm_r.rotation_degrees = Vector3(-60.0, 32.0, -12.0)
			if is_instance_valid(officer_farm_r): officer_farm_r.rotation_degrees = Vector3(-45.0, 0.0, 0.0)
		else:
			if is_instance_valid(officer_arm_l): officer_arm_l.rotation_degrees = Vector3(-60.0, -32.0, 12.0)
			if is_instance_valid(officer_farm_l): officer_farm_l.rotation_degrees = Vector3(-45.0, 0.0, 0.0)
	)
	active_tween.tween_interval(0.8 / spd)

	# FASE 4: Policial conduz Dante para fora do carro até o solo
	active_tween.tween_callback(func():
		current_phase = Phase.EXTRACT
	)

	var ground_dante_pos := Vector3(extraction_side * 1.15, 0.0, 0.15)
	if is_instance_valid(dante_root):
		active_tween.tween_property(dante_root, "position", ground_dante_pos, 1.4 / spd)
	if is_instance_valid(dante_leg_l):
		active_tween.parallel().tween_property(dante_leg_l, "rotation_degrees:x", 0.0, 1.4 / spd)
	if is_instance_valid(dante_leg_r):
		active_tween.parallel().tween_property(dante_leg_r, "rotation_degrees:x", 0.0, 1.4 / spd)

	active_tween.tween_callback(func():
		driver_extracted.emit()
	)

	# FASE 5: Policial posiciona Dante contra o veículo e aplica algemas
	active_tween.tween_callback(func():
		current_phase = Phase.CUFF
		if is_instance_valid(dante_root):
			dante_root.rotation_degrees.y = 90.0 * extraction_side
		if is_instance_valid(dante_torso):
			dante_torso.rotation_degrees = Vector3(15.0, 0.0, 0.0)
		if is_instance_valid(dante_arm_l):
			dante_arm_l.rotation_degrees = Vector3(25.0, 10.0, 20.0)
		if is_instance_valid(dante_farm_l):
			dante_farm_l.rotation_degrees = Vector3(75.0, 0.0, 0.0)
		if is_instance_valid(dante_arm_r):
			dante_arm_r.rotation_degrees = Vector3(25.0, -10.0, -20.0)
		if is_instance_valid(dante_farm_r):
			dante_farm_r.rotation_degrees = Vector3(75.0, 0.0, 0.0)

		if is_instance_valid(officer_root):
			officer_root.position = Vector3(extraction_side * 1.55, 0.0, 0.15)
			officer_root.rotation_degrees.y = -90.0 * extraction_side
		if is_instance_valid(officer_arm_l):
			officer_arm_l.rotation_degrees = Vector3(-35.0, 0.0, 15.0)
		if is_instance_valid(officer_farm_l):
			officer_farm_l.rotation_degrees = Vector3(-45.0, 0.0, 0.0)
		if is_instance_valid(officer_arm_r):
			officer_arm_r.rotation_degrees = Vector3(-35.0, 0.0, -15.0)
		if is_instance_valid(officer_farm_r):
			officer_farm_r.rotation_degrees = Vector3(-45.0, 0.0, 0.0)

		if is_instance_valid(handcuffs_mesh):
			handcuffs_mesh.position = Vector3(0.0, 0.72, 0.14)
			handcuffs_mesh.visible = true

		suspect_handcuffed.emit()
	)
	active_tween.tween_interval(1.0 / spd)

	# FASE 6: Conclusão da prisão
	active_tween.tween_callback(func():
		current_phase = Phase.COMPLETED
		sequence_completed.emit()
	)

	return true

## Interrupção imediata a qualquer momento com rollback limpo e seguro
func interrupt_extraction(reason: String = "Interrupção solicitada.") -> void:
	if current_phase == Phase.IDLE or current_phase == Phase.COMPLETED:
		return

	if active_tween != null and active_tween.is_running():
		active_tween.kill()

	current_phase = Phase.INTERRUPTED
	var spd: float = maxf(0.1, speed_multiplier)

	var rollback_tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Fecha a porta suavemente
	var door_node := door_left if extraction_side < 0 else door_right
	if is_instance_valid(door_node):
		rollback_tween.tween_property(door_node, "rotation_degrees:y", 0.0, 0.45 / spd)

	# Retorna o policial para posição tática de recuo
	var retreat_pos := Vector3(extraction_side * 2.0, 0.0, 1.4)
	if is_instance_valid(officer_root):
		rollback_tween.parallel().tween_property(officer_root, "position", retreat_pos, 0.6 / spd)

	# Se Dante estava sendo extraído, retorna-o ao assento
	if is_instance_valid(dante_root):
		var seat_pos := Vector3(extraction_side * 0.42, 0.28, 0.0)
		rollback_tween.parallel().tween_property(dante_root, "position", seat_pos, 0.6 / spd)
		rollback_tween.parallel().tween_property(dante_root, "rotation_degrees", Vector3.ZERO, 0.5 / spd)

	if is_instance_valid(handcuffs_mesh):
		handcuffs_mesh.visible = false

	rollback_tween.tween_callback(func():
		reset_poses()
		current_phase = Phase.IDLE
		extraction_interrupted.emit(reason)
	)

## Alias conveniente para a Astra integrar com a mesma convenção de PoliceVehicleStop
func cancel() -> void:
	interrupt_extraction("Cancelamento da abordagem policial.")

func is_running() -> bool:
	return current_phase != Phase.IDLE and current_phase != Phase.COMPLETED
