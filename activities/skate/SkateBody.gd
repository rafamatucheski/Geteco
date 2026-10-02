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
var _push_clock := .65
var _grace := .4
var _previous_up := 0.0
var _previous_normal := Vector3.UP
var _takeoff_direction := Vector3.FORWARD
var color := Color("d36c3e")

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
	_throttle = clampf(throttle, 0, 1) if is_finite(throttle) else 0.0
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
	bail(0 if is_instance_valid(rider) and not rider.is_player else amount)

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
	var grounded := is_on_floor() and velocity.y <= 0
	var forward := -global_basis.z
	pushing = grounded and _throttle > .1 and not _brake
	if pushing:
		_push_clock += delta * lerpf(.6, 1, _throttle)
		push_phase = fposmod(_push_clock / .72, 1.0)
		if _push_clock >= .72:
			_push_clock -= .72
			speed = minf(8.5, speed + 1.6 * _throttle)
	else: push_phase = move_toward(push_phase, 0, delta * 4)
	if grounded:
		var normal := get_floor_normal()
		var slope := -(forward.x * normal.x + forward.z * normal.z) / maxf(.3, normal.y)
		speed = clampf(speed - slope * 13 * delta, 0, 13)
		_previous_normal = normal
	speed = move_toward(speed, 0, delta * (7.5 if _brake else .3))
	rotation.y += _steer * delta * (1.7 if grounded else 2.4) * clampf(speed / 2, .3, 1)
	lean = lerpf(lean, _steer * clampf(speed / 12, 0, .35), minf(1, delta * 8))
	forward = -global_basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	if grounded: velocity.y = -.5
	else: velocity.y -= 20 * delta
	var impact_speed := speed
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
			deck.rotation = Vector3(0, TAU * progress if trick == "shove" else 0, TAU * progress if trick == "flip" else 0)
			if progress >= 1:
				trick_total += 100 if trick == "flip" else 75
				trick = ""
				deck.rotation = Vector3.ZERO
	elif airborne:
		airborne = false
		var wrong_heading := absf(_takeoff_direction.signed_angle_to(forward, Vector3.UP))
		if not trick.is_empty() or (air_time > .25 and wrong_heading > 1.15):
			bail(clampf(6 + impact_speed, 6, 20))
		elif trick_total > 0:
			trick_landed.emit(trick_total, trick_title)
		trick_total = 0
		air_time = 0
	_previous_up = maxf(0, velocity.y)
	if now_grounded:
		var n := get_floor_normal()
		var pitch := atan2(forward.x * n.x + forward.z * n.z, n.y)
		visual.rotation.x = lerpf(visual.rotation.x, -pitch, minf(1, delta * 12))
	else: visual.rotation.x = lerpf(visual.rotation.x, 0, minf(1, delta * 4))
	visual.rotation.z = lean
	for wheel in deck.wheels: wheel.rotate_x(-speed * delta / MODEL.WHEEL_RADIUS)

func trick_duration() -> float: return .42 if trick == "flip" else .36
