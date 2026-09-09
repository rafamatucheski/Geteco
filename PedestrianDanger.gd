extends RefCounted
## Local threat memory and collision-checked escape choices, updated at 2 Hz.
var threats: Array[Dictionary] = []
var destination := Vector2.ZERO
var replan := 0.0
var sheltered := false

static func report(projectile: Node2D, origin: Vector2, direction: Vector2, shooter: Node) -> void:
	# One notification per burst interval, not per pellet or physics frame.
	if is_instance_valid(shooter):
		var now := Time.get_ticks_msec()
		if now < int(shooter.get_meta("civilian_alert_after", 0)): return
		shooter.set_meta("civilian_alert_after", now + 200)
	var end := origin + direction.normalized() * 850.0
	for person in projectile.get_tree().get_nodes_in_group("pedestrian"):
		if person == shooter or not is_instance_valid(person) or not person.is_visible_in_tree(): continue
		if not person.has_method("hear_gunfire") or person.get_world_2d() != projectile.get_world_2d(): continue
		var near_line := Geometry2D.get_closest_point_to_segment(person.global_position, origin, end)
		if person.global_position.distance_to(origin) < 650.0 or person.global_position.distance_to(near_line) < 100.0:
			person.hear_gunfire(origin, end)

func remember(origin: Vector2, end: Vector2) -> void:
	for threat in threats:
		if threat.origin.distance_to(origin) < 80.0:
			threat.origin = origin
			threat.end = end
			threat.life = 12.0
			return
	threats.append({"origin": origin, "end": end, "life": 12.0})
	if threats.size() > 4: threats.pop_front()
	replan = 0.0

func _ray(person: CharacterBody2D, start: Vector2, end: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(start, end, 3, [person.get_rid()])
	return person.get_world_2d().direct_space_state.intersect_ray(query)

func movement(person: CharacterBody2D, delta: float, speed: float) -> Vector2:
	for threat in threats: threat.life -= delta
	threats = threats.filter(func(t): return t.life > 0.0)
	if threats.is_empty(): return Vector2.ZERO
	replan -= delta
	if replan <= 0.0:
		replan = 0.5 + float(person.get_instance_id() % 5) * 0.04
		var away := Vector2.ZERO
		for threat in threats:
			var near := Geometry2D.get_closest_point_to_segment(person.global_position, threat.origin, threat.end)
			away += near.direction_to(person.global_position) + threat.origin.direction_to(person.global_position)
		if away.length_squared() < 0.01: away = Vector2.UP.rotated(float(person.get_instance_id() % 6))
		away = away.normalized()
		destination = person.global_position
		var best := -INF
		sheltered = false
		for angle in [0.0, -0.45, 0.45, -0.9, 0.9, -1.5, 1.5]:
			var dir := away.rotated(angle)
			var candidate := person.global_position + dir * 150.0
			var clear := true
			for offset in [-10.0, 0.0, 10.0]:
				var side: Vector2 = dir.orthogonal() * offset
				if not _ray(person, person.global_position + side, candidate + side).is_empty(): clear = false; break
			if not clear: continue
			var score := 0.0
			for threat in threats:
				var crossing = Geometry2D.segment_intersects_segment(person.global_position, candidate, threat.origin, threat.end)
				if crossing != null and person.global_position.distance_to(crossing) > 16.0:
					clear = false; break
				score += candidate.distance_to(threat.origin) - person.global_position.distance_to(threat.origin)
				if not _ray(person, threat.origin, candidate).is_empty(): score += 160.0
			if clear and score > best:
				best = score
				destination = candidate
		# Once behind cover and well away from the shooters, stay there until quiet.
		var safe := true
		for threat in threats:
			if person.global_position.distance_to(threat.origin) < 300.0 or _ray(person, threat.origin, person.global_position).is_empty(): safe = false
		if safe:
			sheltered = true
			destination = person.global_position
	var direction := person.global_position.direction_to(destination)
	if person.global_position.distance_to(destination) < 12.0: return Vector2.ZERO
	# Recheck a short sweep as cars or other obstacles enter the escape path.
	for offset in [-10.0, 0.0, 10.0]:
		var side: Vector2 = direction.orthogonal() * offset
		if not _ray(person, person.global_position + side, person.global_position + side + direction * 22.0).is_empty():
			replan = 0.0
			return Vector2.ZERO
	return direction * speed
