extends Node
## V1 boarding rhythm adapted to native 3D: approach, door, step, occlusion, seat.
## Bone presentation stays owned by Actor through its existing animation sampler.

signal entered
signal exited(point: Vector3)
signal cancelled(reason: String, point: Vector3)

var world: Node
var vehicle: CharacterBody3D
var actor: CharacterBody3D
var side := -1
var duration := 1.85
var progress := 0.0
var active := false
var exiting := false
var phase := "idle"
var _start := Vector3.ZERO
var _door := Vector3.ZERO
var _seat := Vector3.ZERO
var _landing := Vector3.ZERO
## Canto por onde o corpo contorna a lataria até a porta (ou da porta até o chão).
var _corner := Vector3.ZERO
var _motion: Tween
var _visual_yaw := 0.0
var _visual_position := Vector3.ZERO
var _finishing := false
var _kind := "car"
var _step := 0.0

func begin_entry(owner_world: Node, car: CharacterBody3D, pedestrian: CharacterBody3D, entry_side: int) -> void:
	world = owner_world
	vehicle = car
	actor = pedestrian
	side = entry_side
	_configure_kind()
	_start = actor.global_position
	_door = vehicle.driver_door_anchor(side)
	_seat = vehicle.driver_seat_anchor()
	_landing = _start
	_corner = _outside_corner(_start)
	_visual_yaw = actor.visual.rotation.y
	_visual_position = actor.visual.position
	active = true
	phase = "approach"
	vehicle.animate_driver_door(side, true, .28)
	_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "progress", 1.0, duration-.28)
	_motion.tween_callback(_begin_close_entry)
	_motion.tween_interval(.28)
	_motion.tween_callback(_finish_entry)
	_apply()

func begin_exit(owner_world: Node, car: CharacterBody3D, pedestrian: CharacterBody3D, destination: Vector3, exit_side: int) -> void:
	world = owner_world
	vehicle = car
	actor = pedestrian
	side = exit_side
	_configure_kind()
	_start = destination
	_landing = destination
	_door = vehicle.driver_door_anchor(side)
	_seat = vehicle.driver_seat_anchor()
	_corner = _outside_corner(_start)
	_visual_yaw = actor.visual.rotation.y
	_visual_position = actor.visual.position
	progress = 1.0
	exiting = true
	active = true
	phase = "open"
	actor.global_position = _seat
	actor.hide()
	vehicle.animate_driver_door(side, true, .28)
	_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "progress", 0.0, duration)
	_motion.tween_callback(_begin_close_exit)
	_motion.tween_interval(.35)
	_motion.tween_callback(_finish_exit)
	_apply()

func reverse_entry_to_exit() -> bool:
	if not active or exiting: return false
	exiting = true
	if is_instance_valid(_motion): _motion.kill()
	var seconds := maxf(.45, (duration-.28) * progress)
	vehicle.animate_driver_door(side, true, .20)
	_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "progress", 0.0, seconds)
	_motion.tween_callback(_begin_close_exit)
	_motion.tween_interval(.35)
	_motion.tween_callback(_finish_exit)
	return true

func abort(reason: String) -> void:
	if _finishing: return
	_finishing = true
	if is_instance_valid(_motion): _motion.kill()
	active = false
	if is_instance_valid(vehicle): vehicle.animate_driver_door(side, false, .18)
	_restore_actor(_landing if _landing.is_finite() else _start)
	cancelled.emit(reason, actor.global_position if is_instance_valid(actor) else _start)
	queue_free()

func _process(_delta: float) -> void:
	if not active: return
	if not is_instance_valid(actor) or not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion():
		abort("vehicle_removed")
		return
	_apply()

## Ritmo por porte (`Vehicle.boarding_class`). Antes todo veículo usava o mesmo trecho
## de "subir escada" enquanto o corpo deslizava de pé para dentro da lataria: no carro
## pequeno parecia escalar a porta, e no ônibus/caminhão entrava pelo meio da carroceria.
func _configure_kind() -> void:
	_kind = str(vehicle.boarding_class()) if vehicle.has_method("boarding_class") else "car"
	_step = float(vehicle.boarding_step_height()) if vehicle.has_method("boarding_step_height") else 0.0
	match _kind:
		"open": duration = 1.05
		"bus": duration = 1.7
		"truck": duration = 2.5
		"tall": duration = 2.0
		_: duration = 1.75 + (.30 if side > 0 else 0.0)

func _apply() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(vehicle): return
	if phase == "close":
		actor.hide()
		return
	if phase == "close_outside":
		actor.global_position = _landing
		actor.show()
		return
	var t := clampf(progress, 0.0, 1.0)
	var face_car: float = _car_yaws()[0]
	var yaw := face_car
	var drop := 0.0
	var hidden_after := .82
	if t < .22:
		phase = "approach"
		var walk := _walk_along(smoothstep(0.0, .22, t))
		_pose_cycle("Walking", t / .22 * 1.5)
		walk.y = 0
		if walk.length_squared() > .01: yaw = lerp_angle(atan2(-walk.x, -walk.z), face_car, smoothstep(.12, .22, t))
	else:
		match _kind:
			"open": hidden_after = _apply_open(t)
			"bus": hidden_after = _apply_bus(t)
			"truck", "tall": hidden_after = _apply_climb(t)
			_: hidden_after = _apply_car(t)
		yaw = _yaw
		drop = _drop
	actor.visual.position = _visual_position + Vector3.UP * drop
	actor.visual.rotation.y = yaw
	actor.visible = t < hidden_after

var _yaw := 0.0
var _drop := 0.0

## De frente para a porta, perpendicular à lateral. Antes mirava o centro do veículo:
## no caminhão a cabine fica na ponta, e o corpo parava na porta olhando para a carga.
func _car_yaws() -> Array:
	var inward := -vehicle.global_basis.x * float(side)
	return [atan2(-inward.x, -inward.z), vehicle.global_rotation.y]

## Ponto de fora da lataria alinhado à porta. Quem está na frente ou atrás do veículo
## vai primeiro até a lateral e depois acompanha a lataria, em vez de atravessá-la.
func _outside_corner(from: Vector3) -> Vector3:
	var local: Vector3 = vehicle.to_local(from)
	var door_local: Vector3 = vehicle.to_local(_door)
	var lateral := absf(door_local.x)
	if signf(local.x) == float(side) and absf(local.x) >= float(vehicle.half_width) + .10: return _door.lerp(from, .5)
	var margin := float(vehicle.half_length) + .45
	var z := clampf(local.z, -margin, margin)
	if absf(local.z) < margin:
		# Do lado errado e ao lado da lataria: contorna pela ponta mais próxima da porta.
		z = -margin if door_local.z < 0 else margin
	var corner: Vector3 = vehicle.to_global(Vector3(float(side) * lateral, door_local.y, z))
	corner.y = _door.y
	return corner

## Caminho em dois trechos (início → canto → porta), com velocidade constante.
func _walk_along(k: float) -> Vector3:
	var first := _start.distance_to(_corner)
	var total := first + _corner.distance_to(_door)
	if total < .001:
		actor.global_position = _door
		return Vector3.ZERO
	var travelled := k * total
	if travelled <= first:
		actor.global_position = _start.lerp(_corner, travelled / maxf(first, .001))
		return _corner - _start
	actor.global_position = _corner.lerp(_door, (travelled - first) / maxf(total - first, .001))
	return _door - _corner

## Carro baixo: para na porta, vira de costas para o banco, abaixa e desliza sentado.
func _apply_car(t: float) -> float:
	var yaws := _car_yaws()
	if t < .38:
		phase = "reach"
		actor.global_position = _door
		_pose_idle()
		actor.pose_vehicle(0.0, 0.0, side, smoothstep(.22, .38, t))
		_yaw = lerp_angle(yaws[0], yaws[1], smoothstep(.22, .38, t))
		_drop = 0.0
	else:
		phase = "step"
		var k := smoothstep(.38, .80, t)
		actor.global_position = _door.lerp(_seat, k)
		_pose_idle()
		_yaw = yaws[1]
		# Dobra os joelhos: o quadril desce até a altura do banco antes de sumir na porta.
		_drop = -.42 * smoothstep(.38, .60, t)
		actor.pose_vehicle(smoothstep(.38, .66, t))
	return .80

## Caminhonete e caminhão: de frente para a cabine, sobe pelo estribo (ciclo de escada
## do próprio esqueleto, só na subida) e entra de lado ao alcançar o piso.
func _apply_climb(t: float) -> float:
	var yaws := _car_yaws()
	var inside := _door.lerp(_seat, .45)
	inside.y = _seat.y
	var climb_end := .66 if _kind == "truck" else .52
	if t < climb_end:
		phase = "reach"
		var k := smoothstep(.22, climb_end, t)
		var point := _door.lerp(inside, k * .35)
		point.y = lerpf(_door.y, _seat.y, k)
		actor.global_position = point
		_pose_transition(.05 + k * (.55 if _kind == "truck" else .30))
		_yaw = yaws[0]
		_drop = 0.0
	else:
		phase = "step"
		var k := smoothstep(climb_end, .84, t)
		actor.global_position = _door.lerp(inside, .35).lerp(_seat, k)
		actor.global_position.y = _seat.y
		_pose_idle()
		_yaw = lerp_angle(yaws[0], yaws[1], k)
		_drop = -.36 * k
		actor.pose_vehicle(k)
		var seated: Array = actor._capture_pose()
		_pose_transition(.60 if _kind == "truck" else .35)
		actor._apply_blend(actor._capture_pose(), seated, smoothstep(0.0, .30, k))
	return .84

## Ônibus: porta de serviço sem folha; sobe os degraus andando e vira para o volante.
func _apply_bus(t: float) -> float:
	var yaws := _car_yaws()
	phase = "step" if t > .30 else "reach"
	var k := smoothstep(.22, .84, t)
	var point := _door.lerp(_seat, k)
	point.y = lerpf(_door.y, _seat.y, smoothstep(.22, .6, t))
	actor.global_position = point
	_pose_cycle("Walking", t * 3.0)
	var walk := _seat - _door
	walk.y = 0
	_yaw = lerp_angle(atan2(-walk.x, -walk.z), yaws[1], smoothstep(.6, .84, t))
	_drop = -.3 * smoothstep(.72, .88, t)
	if t > .72:
		var walking: Array = actor._capture_pose()
		actor.pose_vehicle(smoothstep(.72, .88, t))
		actor._apply_blend(walking, actor._capture_pose(), smoothstep(.72, .84, t))
	return .9

## Moto, buggy e empilhadeira: sem porta, passa a perna por cima e assenta.
func _apply_open(t: float) -> float:
	var yaws := _car_yaws()
	phase = "step"
	var k := smoothstep(.22, .85, t)
	actor.global_position = _door.lerp(_seat, k)
	_pose_idle()
	_yaw = lerp_angle(yaws[0], yaws[1], smoothstep(.22, .5, t))
	_drop = -.3 * smoothstep(.5, .85, t)
	actor.pose_vehicle(smoothstep(.50, .85, t), sin(smoothstep(.22, .65, t) * PI), side, smoothstep(.22, .36, t))
	return .92

func _pose_idle() -> void:
	var pose: Array = actor.get("_idle_pose") if actor.get("_idle_pose") != null else []
	if pose.is_empty() and actor.has_method("_build_idle_pose"):
		actor._build_idle_pose()
		pose = actor.get("_idle_pose")
	if not pose.is_empty() and actor.has_method("_apply_pose"): actor._apply_pose(pose)
	else: _pose_cycle("Walking", 0.0)

func _begin_close_entry() -> void:
	if not active or exiting: return
	phase = "close"
	actor.hide()
	vehicle.animate_driver_door(side, false, .28)

func _begin_close_exit() -> void:
	if not active: return
	phase = "close_outside"
	_restore_actor(_landing)
	vehicle.animate_driver_door(side, false, .32)

func _pose_cycle(clip: String, normalized: float) -> void:
	if not is_instance_valid(actor.animation) or not actor.animation.has_animation(clip): return
	actor._pose_cycle(clip, normalized, actor.WALK_START if clip == "Walking" else 0.0)
	var hip: Vector3 = actor.skeleton.get_bone_pose_position(actor.hips)
	hip.x = actor.hip_rest.x
	hip.z = actor.hip_rest.z
	actor.skeleton.set_bone_pose_position(actor.hips, hip)

func _pose_transition(normalized: float) -> void:
	var clip := "Fast_Ladder_Climb"
	if not is_instance_valid(actor.animation) or not actor.animation.has_animation(clip):
		_pose_cycle("Walking", normalized)
		return
	actor._pose_clip(clip, clampf(normalized, 0.0, 1.0) * actor.animation.get_animation(clip).length)

func _finish_entry() -> void:
	if _finishing or not is_instance_valid(actor) or not is_instance_valid(vehicle):
		abort("invalid_entry")
		return
	_finishing = true
	active = false
	# The crouch belongs to this presentation only. Keeping it on the hidden
	# actor made the next exit use an already lowered baseline, sinking each trip.
	actor.visual.position = _visual_position
	actor.visual.rotation.y = _visual_yaw
	actor.hide()
	actor.global_position = vehicle.global_position
	vehicle.animate_driver_door(side, false, 0.0)
	entered.emit()
	queue_free()

func _finish_exit() -> void:
	if _finishing: return
	_finishing = true
	active = false
	if is_instance_valid(vehicle): vehicle.animate_driver_door(side, false, 0.0)
	_restore_actor(_landing)
	exited.emit(_landing)
	queue_free()

func _restore_actor(point: Vector3) -> void:
	if not is_instance_valid(actor): return
	actor.teleport(point)
	actor.visual.position = _visual_position
	actor.visual.rotation.y = _visual_yaw
	actor.show()

func _exit_tree() -> void:
	if active and not _finishing:
		if is_instance_valid(_motion): _motion.kill()
		if is_instance_valid(vehicle): vehicle.animate_driver_door(side, false, 0.0)
		_restore_actor(_landing if _landing.is_finite() else _start)
