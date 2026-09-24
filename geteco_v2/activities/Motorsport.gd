extends RefCounted
## Real trajectory and velocity scorer. Native adapters supply measured motion.
var mode := ""
var id := ""
var elapsed := 0.0
var countdown := 0.0
var gate := 0
var points := PackedVector3Array()
var start := Vector3.ZERO
var previous := Vector3.ZERO
var score := 0.0
var combo := 1.0
var outside := 0.0
var no_drift := 0.0
var radius := 0.0
var finished := false
var cancelled := false

func begin_race(race_id: String, origin: Vector3, checkpoints: PackedVector3Array, current: Vector3) -> bool:
	if mode != "" or checkpoints.is_empty() or current.distance_to(origin) >= 60.0/16.0: return false
	_reset()
	mode = "race"
	id = race_id
	start = origin
	points = checkpoints.duplicate()
	points.append(origin)
	previous = current
	countdown = 3.0
	return true

func begin_drift(zone_id: String, center: Vector3, zone_radius: float, current: Vector3) -> bool:
	if mode != "" or zone_radius <= 0.0 or current.distance_to(center) > zone_radius: return false
	_reset()
	mode = "drift"
	id = zone_id
	start = center
	radius = zone_radius
	previous = current
	return true

func _reset() -> void:
	elapsed = 0.0
	countdown = 0.0
	gate = 0
	score = 0.0
	combo = 1.0
	outside = 0.0
	no_drift = 0.0
	finished = false
	cancelled = false

func cancel() -> void:
	cancelled = true
	mode = ""

func update(delta: float, position: Vector3, velocity: Vector3, forward: Vector3, valid_driver: bool) -> void:
	if mode == "": return
	if not valid_driver or delta <= 0 or delta > .5 or not position.is_finite() or not velocity.is_finite() or not forward.is_finite():
		cancel()
		return
	# Prevent loading/teleporting across a gate from counting as driving.
	if position.distance_to(previous) > maxf(4.0, 100.0*delta):
		cancel()
		return
	if mode == "race":
		if countdown > 0:
			if position.distance_to(start) > 65.0/16.0:
				cancel()
				return
			countdown = maxf(0,countdown-delta)
			previous = position
			return
		elapsed += delta
		if elapsed > 600.0:
			cancel()
			return
		var closest := Geometry3D.get_closest_point_to_segment(points[gate],previous,position)
		if closest.distance_to(points[gate]) < 58.0/16.0:
			gate += 1
			if gate == points.size():
				finished = true
				mode = ""
	else:
		elapsed += delta
		var inside := position.distance_to(start) <= radius
		outside = 0.0 if inside else outside + delta
		# Actual displacement prevents scoring by accelerating against a wall.
		var measured := (position-previous)/delta
		var speed_vector := Vector3(measured.x,0,measured.z)
		var heading := Vector3(forward.x,0,forward.z).normalized()
		var lateral := absf(speed_vector.dot(heading.cross(Vector3.UP)))
		var angle := absf(heading.signed_angle_to(speed_vector.normalized(),Vector3.UP)) if speed_vector.length() > .001 else 0.0
		# Keep original speed/lateral thresholds and point scale; reject reverse spins.
		if inside and lateral > 35.0/16.0 and speed_vector.length() > 60.0/16.0 and angle > deg_to_rad(8) and angle < deg_to_rad(80):
			no_drift = 0.0
			combo = minf(5,combo+delta*.18)
			score += lateral*16.0*combo*delta*.55
		else:
			no_drift += delta
			if no_drift > 1.0: combo = 1.0
		if elapsed >= 25.0 or outside >= 3.0:
			finished = true
			mode = ""
	previous = position

func target_position() -> Vector3:
	if mode == "race": return start if countdown > 0 else points[gate]
	return start
