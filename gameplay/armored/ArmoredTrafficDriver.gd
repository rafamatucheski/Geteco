extends "res://gameplay/dispatch/DispatchDriver.gd"
## O comboio civil agendado usa o mesmo controlador de rua com colisão do
## trânsito normal. O serviço é dono da rota/formação; Vehicle é dono do movimento do corpo.
const CONTACT_PATIENCE := 5.0
const CONTACT_ATTEMPTS := 3
var contact_attempts := 0
var _contact_wait := 0.0
var _contact_anchor := -INF
var _contact_reverse := false

func tick(delta: float) -> void:
	if not is_instance_valid(vehicle) or vehicle.health <= 0: return
	if route == null:
		vehicle.traffic = false
		vehicle.set_external_driver(true)
		vehicle.throttle_input = 0.0
		vehicle.brake_input = true
		return
	offset = route.get_closest_offset(vehicle.global_position)
	remaining = route.get_baked_length()-offset
	blocked_ahead = vehicle.blocked
	stalled = vehicle.stall_time
	vehicle.route = route
	vehicle.route_distance = offset
	var contact_hold := _recover_contact(delta)
	vehicle.traffic = not holding and not contact_hold
	vehicle.set_external_driver(holding or contact_hold)
	if not holding and not contact_hold: vehicle.brake_input = false
	if holding or contact_hold:
		vehicle.throttle_input = 0.0
		vehicle.steer_input = 0.0
		vehicle.brake_input = true

func pending_recovery() -> bool:
	return is_instance_valid(vehicle) and (vehicle.backoff_time > 0.0 or vehicle.bypass_side != 0.0 or vehicle.bypass_blend > .05 or vehicle._merging_back)

func _recover_contact(delta: float) -> bool:
	# O desvio nativo suprime o bloqueador parado na faixa de origem antes que o casco inteiro
	# tenha necessariamente passado por ele. Um para-choque oblíquo ainda pode ficar preso fisicamente.
	if not is_finite(_contact_anchor) or offset-_contact_anchor >= 8.0:
		_contact_anchor = offset
		contact_attempts = 0
	if _contact_reverse:
		if holding or not _rear_clear():
			vehicle.backoff_time = 0.0
			_contact_reverse = false
			_contact_wait = 0.0
			return true
		if vehicle.backoff_time > 0.0: return false
		_contact_reverse = false
	if holding or vehicle.junction_wait or absf(vehicle.speed) > .2:
		_contact_wait = 0.0
		return false
	var frontal_contact := false
	for index in vehicle.get_slide_collision_count():
		var normal: Vector3 = vehicle.get_slide_collision(index).get_normal()
		if absf(normal.y) < .25 and normal.dot(-vehicle.global_basis.z) < -.2:
			frontal_contact = true
			break
	if not frontal_contact:
		_contact_wait = 0.0
		return false
	_contact_wait += delta
	if _contact_wait < CONTACT_PATIENCE or contact_attempts >= CONTACT_ATTEMPTS: return false
	_contact_wait = 0.0
	if not _rear_clear(): return false
	contact_attempts += 1
	_contact_reverse = true
	vehicle.backoff_time = .8
	return false

func settled() -> bool:
	if not is_stopped() or pending_recovery() or route == null: return false
	return route.get_closest_point(vehicle.global_position).distance_to(vehicle.global_position) < .8
