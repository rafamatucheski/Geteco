extends RefCounted
## Local threat memory and collision-checked escape choices, updated at 2 Hz.
const HEARING_RADIUS := 240.0
const FIRING_LANE_RADIUS := 42.0
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
	var hearing_radius := clampf(float(projectile.get_meta("gunfire_hearing_radius",HEARING_RADIUS)),0.0,HEARING_RADIUS)
	# A trajetÃ³ria percebida termina na primeira parede/carro; tiros nÃ£o
	# ameaÃ§am uma rua inteira do outro lado de uma quadra fechada.
	var excluded: Array[RID] = []
	if shooter is CollisionObject2D: excluded.append(shooter.get_rid())
	var obstruction := preload("res://guns/combat/ShotQuery.gd").cast(projectile, origin, end, 3, excluded)
	if not obstruction.is_empty(): end = obstruction.position
	var listeners := projectile.get_tree().get_nodes_in_group("pedestrian")
	listeners.append_array(projectile.get_tree().get_nodes_in_group("restaurant_terrace"))
	listeners.append_array(projectile.get_tree().get_nodes_in_group("paramedic"))
	for person in listeners:
		if person == shooter or not is_instance_valid(person) or not person.is_visible_in_tree() or person.modulate.a < 0.1: continue
		if not person.has_method("hear_gunfire") or person.get_world_2d() != projectile.get_world_2d(): continue
		var near_line := Geometry2D.get_closest_point_to_segment(person.global_position, origin, end)
		var distance: float = person.global_position.distance_to(origin)
		if distance >= hearing_radius and person.global_position.distance_to(near_line) >= FIRING_LANE_RADIUS:
			continue
		# Mesmo perto do disparo, paredes separam as reaÃ§Ãµes. A faixa da bala
		# tambÃ©m respeita cobertura lateral, sem espalhar pÃ¢nico para outra rua.
		var cover := preload("res://guns/combat/ShotQuery.gd").cast(projectile, origin, person.global_position, 3, excluded)
		if not cover.is_empty() and cover.collider != person and not person.is_ancestor_of(cover.collider):
			continue
		person.set_meta("combat_attacker", shooter)
		if person.has_method("react_to_gunfire"):
			person.react_to_gunfire(origin, end, shooter)
		else:
			person.hear_gunfire(origin, end)

func remember(origin: Vector2, end: Vector2) -> void:
	for threat in threats:
		if threat.origin.distance_to(origin) < 80.0:
			threat.origin = origin
			threat.end = end
			threat.life = 12.0
			replan = 0.0
			sheltered = false
			return
	threats.append({"origin": origin, "end": end, "life": 12.0})
	if threats.size() > 4: threats.pop_front()
	replan = 0.0

func _ray(person: CharacterBody2D, start: Vector2, end: Vector2) -> Dictionary:
	return preload("res://guns/combat/ShotQuery.gd").cast(person, start, end, 3, [person.get_rid()])

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
		# A full 150px ray rejected every exit in short alleys and against
		# facades. Short safe steps and tangents let citizens turn the corner.
		for length in [150.0, 72.0, 36.0]:
			for angle in [0.0, -0.45, 0.45, -0.9, 0.9, -PI * 0.5, PI * 0.5, -2.1, 2.1]:
				var dir := away.rotated(angle)
				var candidate: Vector2 = person.global_position + dir * length
				var clear := true
				for offset in [-12.0, 0.0, 12.0]:
					var side: Vector2 = dir.orthogonal() * offset
					if not _ray(person, person.global_position + side, candidate + side).is_empty(): clear = false; break
				if not clear: continue
				var score: float = length * 0.08
				for threat in threats:
					var crossing = Geometry2D.segment_intersects_segment(person.global_position, candidate, threat.origin, threat.end)
					if crossing != null and person.global_position.distance_to(crossing) > 16.0:
						clear = false; break
					score += candidate.distance_to(threat.origin) - person.global_position.distance_to(threat.origin)
					if not _ray(person, threat.origin, candidate).is_empty(): score += 160.0
				# Preserve a useful escape direction across replans instead of
				# oscillating between equally good openings in a crowd.
				score += dir.dot(person.velocity.normalized()) * 8.0
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
