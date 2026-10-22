extends CharacterBody3D
## Like motocross: swept movement, gravity, real ramp launch, landing and bail.
signal bailed(damage: float)
signal trick_landed(points: int, title: String)
const MODEL := preload("res://activities/skate/SkateModel.gd")
var visual: Node3D
var deck: Node3D
var speed := 0.0
var riding := false
var rider: CharacterBody3D
var pushing := false
var push_phase := 0.0
var lean := 0.0
var airborne := false
var trick := ""
var trick_time := 0.0
var trick_total := 0
var trick_title := ""
var air_time := 0.0
var _throttle := 0.0
var _steer := 0.0
var _brake := false
var _grace := .4
var _previous_up := 0.0
var _previous_normal := Vector3.UP
var _takeoff_direction := Vector3.FORWARD
var color := Color("d36c3e")
var former_rider: WeakRef
var push_direction := 1.0
var push_contact := false
var push_support := false
var push_foot := Vector3.ZERO
var push_normal := Vector3.UP
var landing_compression := 0.0
var terrain_flex := 0.0
var _planted_foot := Vector3.ZERO
var _return_foot := Vector3.ZERO

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	floor_snap_length = .32
	floor_max_angle = deg_to_rad(65)
	floor_stop_on_slope = false
	var hull := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .22
	shape.height = 1.45
	hull.shape = shape
	hull.position.y = .725
	add_child(hull)
	visual = Node3D.new()
	add_child(visual)
	deck = MODEL.new()
	deck.color = color
	visual.add_child(deck)
	add_to_group("skate_boards")
	add_to_group("v2_damageable")
	set_meta("impact_material", "wood")
	set_meta("gameplay_role", "skate")

func drive(throttle: float, steer: float, braking: bool) -> void:
	_throttle = clampf(throttle, -1, 1) if is_finite(throttle) else 0.0
	_steer = clampf(steer, -1, 1) if is_finite(steer) else 0.0
	_brake = braking

func ollie() -> bool:
	if not riding or not is_on_floor() or not trick.is_empty(): return false
	velocity.y = 6.2
	airborne = true
	air_time = 0
	_takeoff_direction = -global_basis.z
	return true

func start_trick(kind: String) -> bool:
	if not riding or not airborne or not trick.is_empty() or kind not in ["flip", "shove"]: return false
	trick = kind
	trick_time = 0
	trick_title = "Kickflip" if kind == "flip" else "Shove-it"
	return true

func receive_damage(amount: float, source: Node = null) -> void:
	if not riding or not is_finite(amount) or amount <= 0: return
	# Preserve Actor's combat reporting and civilian injury/emergency contract.
	if is_instance_valid(rider) and not rider.is_player: rider.receive_damage(amount, source)
	bail(0.0 if is_instance_valid(rider) and not rider.is_player else amount)

func bail(damage: float) -> void:
	if not riding: return
	riding = false
	collision_layer = 0
	collision_mask = 1
	pushing = false
	trick = ""
	deck.rotation = Vector3.ZERO
	bailed.emit(damage)

func _physics_process(delta: float) -> void:
	_grace = maxf(0, _grace - delta)
	if not riding:
		speed = move_toward(speed, 0, delta * 3)
		velocity.x = -global_basis.z.x * speed
		velocity.z = -global_basis.z.z * speed
		velocity.y = -.5 if is_on_floor() else velocity.y - 20 * delta
		move_and_slide()
		return
	# Positive vertical velocity is normal while climbing. Only an actual
	# takeoff (ollie/airborne) suspends contact and pushing.
	var grounded := is_on_floor() and not airborne
	var forward := -global_basis.z
	# Small gravity rollback during the approach is not a reverse command.
	# Otherwise an uphill rider cancels every stroke before the sole lands.
	var opposing := _throttle * speed < -.1 and not (pushing and absf(speed) < .6 and signf(_throttle) == push_direction)
	# Finish the stroke even when the AI reaches cruising speed mid-remada.
	# Braking, takeoff and collisions still release contact immediately.
	var cruise_speed := 8.5 * absf(_throttle) if _throttle > 0 else 3.0 * absf(_throttle)
	var wants_push := grounded and absf(_throttle) > .1 and not _brake and not opposing and absf(speed) < cruise_speed * .92
	if not grounded or _brake or opposing:
		pushing = false
		push_contact = false
	elif not pushing and wants_push:
		pushing = true
		push_direction = signf(_throttle)
		push_phase = 0.0
		push_contact = false
	if pushing:
		# A planted shoe can only stay in reach for the length of the stroke.
		# Shorter contact at speed prevents sliding or stretching the leg.
		var rate := 1.0 / .72
		if push_phase >= .18 and push_phase < .65:
			rate = maxf(rate, absf(speed) * .47 / .56)
		push_phase += delta * rate
		if push_phase >= 1.0:
			pushing = false
			push_phase = 0.0
			push_contact = false
		# Apply the push over sole contact, not a single tiny impulse per cycle.
		if pushing and wants_push and push_phase >= .18 and push_phase <= .65:
			var target_speed := 8.5 * _throttle if _throttle > 0 else 3.0 * _throttle
			speed = move_toward(speed, target_speed, 20 * absf(_throttle) * delta)
	else: push_phase = 0.0
	if grounded:
		var normal := get_floor_normal()
		var tangent := forward.slide(normal).normalized()
		speed = clampf(speed - tangent.y * 9 * delta, -8.5, 13)
		_previous_normal = normal
	speed = move_toward(speed, 0, delta * (9.0 if _brake or opposing else .3))
	rotation.y += _steer * delta * (1.7 if grounded else 2.4) * clampf(absf(speed) / 2, .3, 1) * (-1 if speed < -.1 else 1)
	lean = lerpf(lean, _steer * clampf(speed / 12, -.35, .35), minf(1, delta * 8))
	forward = -global_basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	if grounded: velocity = forward.slide(get_floor_normal()).normalized() * speed - get_floor_normal() * .5
	else: velocity.y -= 20 * delta
	var impact_speed := absf(speed)
	move_and_slide()
	if is_on_wall() and impact_speed > 3.5 and _grace <= 0:
		bail(clampf(impact_speed * 2, 6, 24))
		return
	var now_grounded := is_on_floor()
	if not now_grounded:
		if not airborne:
			airborne = true
			air_time = 0
			_takeoff_direction = forward
			# Momentum up the transition carries through the lip, as in motocross.
			velocity.y = maxf(velocity.y, _previous_up)
		air_time += delta
		if not trick.is_empty():
			trick_time += delta
			var progress := minf(1, trick_time / trick_duration())
			deck.rotation = Vector3(0.0, TAU * progress if trick == "shove" else 0.0, TAU * progress if trick == "flip" else 0.0)
			if progress >= 1:
				trick_total += 100 if trick == "flip" else 75
				trick = ""
				deck.rotation = Vector3.ZERO
	elif airborne:
		airborne = false
		landing_compression = clampf(air_time * .22, .04, .18)
		var wrong_heading := absf(_takeoff_direction.signed_angle_to(forward, Vector3.UP))
		if not trick.is_empty() or (air_time > .25 and wrong_heading > 1.15):
			bail(clampf(6 + impact_speed, 6, 20))
		elif trick_total > 0:
			trick_landed.emit(trick_total, trick_title)
		trick_total = 0
		air_time = 0
	_previous_up = maxf(0, velocity.y)
	landing_compression = move_toward(landing_compression, 0, delta * .65)
	if now_grounded:
		var n := get_floor_normal()
		# Follow both longitudinal and lateral slope. Banking belongs to the
		# rider, not the deck: rolling the board lifted its wheels off the floor.
		var along := forward.slide(n).normalized()
		var ground_basis := Basis(along.cross(n).normalized(), n, -along)
		var target_basis := (global_basis.inverse() * ground_basis).orthonormalized()
		terrain_flex = lerpf(terrain_flex, clampf(visual.basis.y.angle_to(target_basis.y) * .25, 0, .10), minf(1, delta * 12))
		visual.basis = visual.basis.orthonormalized().slerp(target_basis, 1 - exp(-20 * delta)).orthonormalized()
	else:
		visual.basis = visual.basis.orthonormalized().slerp(Basis.IDENTITY, 1 - exp(-4 * delta)).orthonormalized()
		terrain_flex = move_toward(terrain_flex, 0, delta * .3)
	if not now_grounded:
		pushing = false
		push_contact = false
	_update_push_support()
	for wheel in deck.wheels: wheel.rotate_x(-speed * delta / MODEL.WHEEL_RADIUS)

func _update_push_support() -> void:
	push_support = false
	if not pushing or airborne: return
	var stroke := Vector3(-.28, 0, lerpf(-.20, .36, clampf((push_phase - .18) / .47, 0, 1)) * push_direction)
	var point := visual.to_global(stroke)
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .65, point - Vector3.UP * .65, 1)
	ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		push_contact = false
		return
	push_support = true
	push_normal = hit.normal
	var contact := push_phase >= .18 and push_phase < .65
	if contact and not push_contact: _planted_foot = hit.position
	if not contact and push_contact: _return_foot = visual.to_local(_planted_foot)
	push_contact = contact
	push_foot = _return_foot if push_phase >= .65 else visual.to_local(_planted_foot if contact else hit.position)

func trick_duration() -> float: return .42 if trick == "flip" else .36
