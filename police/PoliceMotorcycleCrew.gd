extends RefCounted

static func exit_seat(vehicle: CharacterBody2D) -> Vector2:
	var query := PhysicsShapeQueryParameters2D.new()
	var footprint := CircleShape2D.new()
	footprint.radius = 8.5
	query.shape = footprint
	query.collision_mask = 1 | 2 | 4
	query.exclude = [vehicle.get_rid()]
	var space := vehicle.get_world_2d().direct_space_state
	for longitudinal in [-8.0, 8.0]:
		for side in [-1.0, 1.0]:
			var start: Vector2 = vehicle.get_crew_spawn_point(side, longitudinal)
			var finish: Vector2 = vehicle.get_crew_exit_point(side, longitudinal)
			query.transform = Transform2D(0, start)
			query.motion = Vector2.ZERO
			if not space.intersect_shape(query, 1).is_empty(): continue
			query.motion = finish - start
			if space.cast_motion(query)[0] >= .999: return Vector2(longitudinal, side)
	return Vector2.INF
