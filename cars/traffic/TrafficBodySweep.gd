extends RefCounted
## Validate the same proposed poses that will be committed, for the whole convoy.
## Rotation is subdivided by corner travel, not merely by movement of the centre.
const FLOW := preload("res://cars/traffic/TrafficFlowModel.gd")
const MAX_CORNER_STEP := 2.0

static func rectangle(body: Node2D, pose: Transform2D, margin := 0.0) -> PackedVector2Array:
	var collision := body.get_node_or_null("Collision") as CollisionShape2D
	if collision == null or not collision.shape is RectangleShape2D: return PackedVector2Array()
	var half: Vector2 = collision.shape.size * 0.5 + Vector2.ONE * margin
	var transform := pose * collision.transform
	var points := PackedVector2Array()
	for corner in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]:
		points.append(transform * corner)
	return points

static func clear(actor: Node2D, proposed: Array[Dictionary]) -> bool:
	var own := FLOW.bodies(actor)
	var exclude: Array[RID] = []
	for body in own:
		if body is CollisionObject2D: exclude.append(body.get_rid())
		if body is PhysicsBody2D:
			for exception in body.get_collision_exceptions():
				if is_instance_valid(exception): exclude.append(exception.get_rid())
	var space := actor.get_world_2d().direct_space_state
	var traffic := FLOW.traffic_actors(actor)
	var swept_region := Rect2()
	var has_region := false
	for item in proposed:
		var body: Node2D = item.body
		var hull := body.get_node_or_null("Collision") as CollisionShape2D
		if hull == null or hull.disabled or not hull.shape is RectangleShape2D: continue
		var target: Transform2D = item.pose
		var local_radius := 0.0
		for corner in rectangle(body, Transform2D.IDENTITY, MAX_CORNER_STEP):
			local_radius = maxf(local_radius, corner.length())
		# Bounds every interpolated rotation, scale and skew, including corners
		# outside both endpoint AABBs. Broad phase only; exact sweeps stay below.
		var basis_bound := maxf(body.global_transform.x.length(), target.x.length()) + maxf(body.global_transform.y.length(), target.y.length())
		var region := Rect2(body.global_position, Vector2.ZERO).expand(target.origin).grow(local_radius * basis_bound)
		swept_region = swept_region.merge(region) if has_region else region
		has_region = true
	if not has_region: return true
	# This call never yields or moves actors. Reuse the same live obstacle
	# geometry across substeps, but rebuild it on the next call (even in the
	# same frame): lane actors can move before the physics server catches up.
	var obstacles: Array[Dictionary] = []
	for other in traffic:
		if not is_instance_valid(other) or own.has(other) or not other is Node2D: continue
		var other_hull := other.get_node_or_null("Collision") as CollisionShape2D
		if other_hull == null or other_hull.disabled or not other_hull.shape is RectangleShape2D: continue
		var radius: float = other_hull.shape.size.length() * maxf(other_hull.global_transform.x.length(), other_hull.global_transform.y.length()) * 0.5
		if not swept_region.grow(radius).has_point(other_hull.global_position): continue
		obstacles.append({"body": other, "center": other_hull.global_position, "radius": radius, "polygon": PackedVector2Array()})
	var steps := 1
	var corner_step := 0.5 if own.size() > 1 else MAX_CORNER_STEP
	for item in proposed:
		var body: Node2D = item.body
		var hull := body.get_node_or_null("Collision") as CollisionShape2D
		if hull == null or hull.disabled or not hull.shape is RectangleShape2D: continue
		var radius: float = hull.shape.size.length() * maxf(body.global_scale.x, body.global_scale.y) * 0.5 + hull.position.length()
		var target: Transform2D = item.pose
		var travel := body.global_position.distance_to(target.origin) + radius * absf(angle_difference(body.global_rotation, target.get_rotation()))
		steps = maxi(steps, ceili(travel / corner_step))
	for step in range(1, steps + 1):
		var polygons: Array[PackedVector2Array] = []
		for item in proposed:
			var body: Node2D = item.body
			var hull := body.get_node_or_null("Collision") as CollisionShape2D
			if hull == null or hull.disabled or not hull.shape is RectangleShape2D: continue
			var pose := body.global_transform.interpolate_with(item.pose, float(step) / steps)
			var polygon := rectangle(body, pose, MAX_CORNER_STEP)
			var own_polygon := rectangle(body, pose)
			# Adjacent sections may share joints, but never overlapping body hulls.
			for other_polygon in polygons:
				if not Geometry2D.intersect_polygons(own_polygon, other_polygon).is_empty(): return false
			polygons.append(own_polygon)
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = hull.shape
			query.transform = pose * hull.transform
			query.margin = MAX_CORNER_STEP
			query.collision_mask = int(body.collision_mask) if body is CollisionObject2D else 7
			query.exclude = exclude
			if not space.intersect_shape(query, 1).is_empty(): return false
			# Lane actors move in idle; the physics server can still have their
			# previous pose. Also compare current scene poses, without a stale cache.
			var region := Rect2(polygon[0], Vector2.ZERO)
			for point in polygon: region = region.expand(point)
			for obstacle in obstacles:
				if not region.grow(obstacle.radius).has_point(obstacle.center): continue
				if obstacle.polygon.is_empty():
					obstacle.polygon = rectangle(obstacle.body, obstacle.body.global_transform)
				if not Geometry2D.intersect_polygons(polygon, obstacle.polygon).is_empty(): return false
	return true
