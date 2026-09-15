extends RefCounted
## Order separate vehicle renders at bus contact. Physics remains responsible
## for blocking hulls; this only resolves the elevated roof's visual overlap.
static func update(body: Node2D, visual: Sprite2D) -> void:
	if not is_instance_valid(visual): return
	var shadow := body.get_node_or_null("ContactShadow") as CanvasItem
	if is_instance_valid(shadow) and not shadow.has_meta("transit_depth_home"):
		shadow.set_meta("transit_depth_home", [shadow.z_index, shadow.z_as_relative])
	if body.is_in_group("urban_bus") or body.is_in_group("urban_bus_section"):
		if is_instance_valid(shadow):
			shadow.z_as_relative = false
			shadow.z_index = body.z_index - 3
		return
	if not visual.has_meta("transit_depth_home"):
		visual.set_meta("transit_depth_home", [visual.z_index, visual.z_as_relative])
	var closest: Node2D
	var distance := INF
	for bus in body.get_tree().get_nodes_in_group("urban_bus"):
		for section in [bus] + bus.sections:
			if not is_instance_valid(section) or not section.visible: continue
			var shape: CollisionShape2D = section.collision
			var half: Vector2 = shape.shape.size * .5
			var local := shape.to_local(body.global_position)
			var edge := shape.to_global(local.clamp(-half,half))
			var separation := body.global_position.distance_squared_to(edge)
			if separation < distance and separation < 10000:
				distance = separation
				closest = section
	if closest == null:
		var home: Array = visual.get_meta("transit_depth_home")
		visual.z_index = home[0]
		visual.z_as_relative = home[1]
		if is_instance_valid(shadow):
			var shadow_home: Array = shadow.get_meta("transit_depth_home")
			shadow.z_index = shadow_home[0]
			shadow.z_as_relative = shadow_home[1]
		return
	# A tall roof projects toward the north. A northern car is behind it;
	# a southern car stays in front. Keep road shadows at their original depth.
	visual.z_as_relative = false
	visual.z_index = closest.z_index + (-1 if body.global_position.y < closest.global_position.y else 1)
	if is_instance_valid(shadow):
		shadow.z_as_relative = false
		shadow.z_index = closest.z_index - 3
