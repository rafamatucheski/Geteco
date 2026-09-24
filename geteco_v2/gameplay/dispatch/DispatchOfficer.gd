extends "res://gameplay/PoliceAgent.gd"
## O policial original (PoliceAgent: corpo, colisão, busca, tiro, saúde por
## patamar) com um modo a mais: voltar andando até a porta da viatura e
## embarcar. Em modo "combat" delega tudo ao PoliceAgent, sem cópia de regra.

signal boarded(officer: CharacterBody3D)

var mode := "combat"
var vehicle: CharacterBody3D
var dispatch_controller: Node3D
var _path_clock := 0.0
var door_side := 1.0
## Desembarque (V1 `PoliceOfficer.service_disembark_active` +
## `EmergencyCrewTransition`): nasce dentro da carroceria, a porta abre, anda até
## o ponto livre ao lado e espera a porta fechar antes de agir. Assim ninguém
## "aparece" do lado da viatura nem atravessa a lataria para um alvo do outro lado.
const DISEMBARK_SPEED := 2.4
const DOOR_CLOSE_TIME := 0.45
var _disembark_target := Vector3.INF
var _door_close_elapsed := -1.0

func begin_disembark(p_vehicle: CharacterBody3D, exit_point: Vector3, side: float) -> void:
	vehicle = p_vehicle
	door_side = side
	_disembark_target = exit_point
	_door_close_elapsed = -1.0
	mode = "disembark"
	if is_instance_valid(vehicle) and vehicle.has_method("animate_driver_door"):
		vehicle.animate_driver_door(int(signf(side)), true)

## Ponto logo dentro da silhueta, na altura da porta do lado escolhido: a pessoa
## atravessa a porta aberta de verdade antes de seguir.
static func inside_point(car: CharacterBody3D, exit_point: Vector3, side: float) -> Vector3:
	var local := car.to_local(exit_point)
	var inside := car.to_global(Vector3(side * car.half_width * 0.35, 0.0, local.z))
	inside.y = exit_point.y
	return inside

func begin_return(p_vehicle: CharacterBody3D) -> void:
	if dead: return
	vehicle = p_vehicle
	mode = "return"
	navigation = PackedVector3Array()
	nav_index = 0
	_path_clock = 0.0

## Ponto ao lado da porta que a equipe usa para entrar e sair.
static func door_point(car: CharacterBody3D, side: float = 1.0) -> Vector3:
	return car.to_global(Vector3(side * (car.half_width + 0.75), 0.0, 0.3))

func _physics_process(delta: float) -> void:
	if dead: return
	if mode == "combat" and is_instance_valid(dispatch_controller) and dispatch_controller.player_position_override != Vector3.INF:
		# An exterior squad waits outside. Interior technical coordinates are
		# never a walk target or a line-of-sight shortcut between maps.
		sees_player = false
		last_known = dispatch_controller.player_position_override
		navigation.clear()
		velocity.x = 0
		velocity.z = 0
		velocity.y = -1.0 if is_on_floor() else velocity.y-20.0*delta
		move_and_slide()
		return
	if mode == "disembark":
		_disembark(delta)
		return
	if mode == "combat":
		super._physics_process(delta)
		return
	if dead or mode != "return": return
	if not is_instance_valid(vehicle):
		mode = "orphan"
		boarded.emit(self)
		return
	var door := door_point(vehicle, door_side)
	if global_position.distance_to(door) < 1.6 and absf(vehicle.speed) < 0.6:
		mode = "boarded"
		boarded.emit(self)
		return
	_path_clock -= delta
	if _path_clock <= 0.0:
		_path_clock = 1.2
		if not is_instance_valid(controller):
			mode = "orphan"
			boarded.emit(self)
			return
		navigation = controller.find_path(global_position, door)
		nav_index = 0
	var next := door
	if nav_index < navigation.size():
		next = navigation[nav_index]
		if global_position.distance_to(next) < 0.65: nav_index += 1
	var direction := next - global_position
	direction.y = 0.0
	direction = direction.normalized()
	if direction.length_squared() > 0.01: direction = _steering.steer(self, direction, delta)
	if direction.length_squared() > 0.01: visual.rotation.y = atan2(-direction.x, -direction.z)
	velocity.x = direction.x * 3.6
	velocity.z = direction.z * 3.6
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	gait += Vector2(velocity.x, velocity.z).length() * delta * 3.4
	visual.left_upper_leg.rotation.x = sin(gait) * 0.55
	visual.right_upper_leg.rotation.x = -sin(gait) * 0.55

func _disembark(delta: float) -> void:
	if not is_instance_valid(vehicle) or _disembark_target == Vector3.INF:
		mode = "combat"
		return
	var offset := _disembark_target - global_position
	offset.y = 0.0
	if _door_close_elapsed < 0.0 and offset.length() > 0.12:
		var direction := offset.normalized()
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), minf(1.0, 14.0 * delta))
		velocity.x = direction.x * DISEMBARK_SPEED
		velocity.z = direction.z * DISEMBARK_SPEED
		velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
		move_and_slide()
		gait += Vector2(velocity.x, velocity.z).length() * delta * 3.4
		visual.left_upper_leg.rotation.x = sin(gait) * 0.55
		visual.right_upper_leg.rotation.x = -sin(gait) * 0.55
		return
	# Parado na porta até o painel fechar, depois retoma a lógica normal.
	velocity = Vector3.ZERO
	visual.left_upper_leg.rotation.x = 0.0
	visual.right_upper_leg.rotation.x = 0.0
	if _door_close_elapsed < 0.0:
		_door_close_elapsed = 0.0
		if vehicle.has_method("animate_driver_door"): vehicle.animate_driver_door(int(signf(door_side)), false)
	_door_close_elapsed += delta
	if _door_close_elapsed >= DOOR_CLOSE_TIME:
		_disembark_target = Vector3.INF
		mode = "combat"
