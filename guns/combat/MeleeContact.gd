extends RefCounted

static func first_body(attacker: CollisionObject2D, direction: Vector2, reach: float, minimum_dot: float, candidates: Array) -> Node2D:
	direction = direction.normalized()
	var ordered := candidates.filter(func(candidate): return candidate is Node2D and candidate != attacker)
	ordered.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return attacker.global_position.distance_squared_to(a.global_position) < attacker.global_position.distance_squared_to(b.global_position)
	)
	for body in ordered:
		if not preload("res://guns/combat/CombatWorld.gd").shares_world(attacker, body): continue
		if "health" in body and float(body.health) <= 0.0: continue
		var offset: Vector2 = body.global_position - attacker.global_position
		var distance := offset.length()
		if distance <= 0.01 or distance > reach or direction.dot(offset / distance) < minimum_dot: continue
		var ray := PhysicsRayQueryParameters2D.create(attacker.global_position, body.global_position, 1 | 2 | 4, [attacker.get_rid()])
		var obstruction := attacker.get_world_2d().direct_space_state.intersect_ray(ray)
		if obstruction.is_empty() or obstruction.collider == body:
			return body
	return null
