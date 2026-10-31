extends "res://gameplay/urban_v1/CobraLocalGuard.gd"
## O ocupante sentado mantém o corpo e sai pela própria porta aberta.
var exiting := false
var _car: CharacterBody3D
var _landing := Vector3.ZERO
var _side := 1
var _elapsed := 0.0
var _closing := -1.0
var _seat_scale := Vector3.ONE

func begin_exit(car: CharacterBody3D, occupant: Node3D, landing: Vector3, side: int) -> void:
	_car = car
	_landing = landing
	_side = side
	exiting = true
	if visual != occupant: visual.queue_free()
	global_position = occupant.global_position
	occupant.reparent(self, true)
	visual = occupant
	visual.seated = false
	visual.body.hand_provider = Callable()
	visual.body.hand_targets = [null, null]
	visual.weapon.hide()
	weapon_id = visual.weapon_id
	magazine = int(CATALOG.get_weapon(weapon_id).magazine_size)
	_seat_scale = visual.body.scale
	add_collision_exception_with(car)
	car.animate_driver_door(side, true)

func _physics_process(delta: float) -> void:
	if dead:
		_finish_exit()
		return
	if not exiting:
		super._physics_process(delta)
		return
	if not is_instance_valid(_car):
		_finish_exit()
		return
	_elapsed += delta
	# Espera o painel abrir antes de passar pelo vão da porta.
	if _elapsed < .28: return
	var offset := _landing - global_position
	offset.y = 0.0
	if _closing < 0.0 and offset.length() > .12:
		var direction := offset.normalized()
		var vertical_speed := velocity.y
		velocity = direction * minf(2.4, offset.length() / maxf(delta, .001))
		velocity.y = -1.0 if is_on_floor() else vertical_speed - 20.0 * delta
		move_and_slide()
		var outside := clampf((absf(_car.to_local(global_position).x) - _car.half_width * .35) / maxf(_car.half_width, .1), 0.0, 1.0)
		visual.body.sit_amount = 1.0 - outside
		visual.body.scale = _seat_scale.lerp(visual.standing_body_scale, outside)
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z) - rotation.y, minf(1.0, delta * 14.0))
		return
	velocity = Vector3.ZERO
	if _closing < 0.0:
		_closing = 0.0
		_car.animate_driver_door(_side, false)
	_closing += delta
	if _closing >= .45: _finish_exit()

func _finish_exit() -> void:
	if not exiting: return
	exiting = false
	visual.body.sit_amount = 0.0
	visual.body.scale = visual.standing_body_scale
	visual.weapon.show()
	visual.update_pose(0.0, false, false, 0.0, 0.0)
	if is_instance_valid(_car):
		remove_collision_exception_with(_car)
		_car.animate_driver_door(_side, false)
	_car = null
