extends RefCounted
## Reserve the next step against live actor positions before the physics slide.
## Moving kinematic bodies can otherwise penetrate by one frame of travel.
const NEIGHBORHOOD := preload("res://characters/pedestrians/PedestrianNeighborhood.gd")
const CLEARANCE := 24.0

static func move_actor(actor: CharacterBody2D) -> void:
	# PopulationActivity can deactivate/free an actor during a streaming handoff
	# while one physics callback is still queued. Avoid test_move/move_and_slide
	# against a body that no longer owns a live PhysicsServer2D space.
	if not _has_live_space(actor):
		return
	var delta := actor.get_physics_process_delta_time()
	var motion := actor.velocity * delta
	var length := motion.length()
	if length < 0.0001: return
	var direction := motion / length
	var neighbors: Array[Vector2] = []
	for other in NEIGHBORHOOD.neighbors(actor, CLEARANCE + length):
		if other == actor or not is_instance_valid(other) or not other is CharacterBody2D: continue
		if not other.is_visible_in_tree() or (other.collision_layer & actor.collision_mask & 4) == 0: continue
		if other.get_world_2d() != actor.get_world_2d(): continue
		neighbors.append(other.global_position - actor.global_position)
	var allowed := _free_distance(direction, length, neighbors)
	if not _has_live_space(actor):
		return
	if allowed < length * 0.25 and actor.has_method("_person_detour_direction"):
		# The route owner keeps the side selected for this encounter. At contact
		# it may step sideways/backwards, but cannot invent a conflicting route.
		var side: Vector2 = actor._person_detour_direction(direction)
		for detour in [side, (side - direction * 0.25).normalized()]:
			if not actor._navigation_point_allowed(actor.global_position + detour * length): continue
			var available := _free_distance(detour, length, neighbors)
			if available <= length * 0.5 or not _has_live_space(actor) or actor.test_move(actor.global_transform, detour * available): continue
			direction = detour
			allowed = available
			break
	if allowed < length * 0.25 and not actor.has_method("_navigation_point_allowed"):
		# Both approaching walkers prefer their own right side. They can pass
		# without a shared destination deadlocking the whole line behind them.
		for angle in [0.55, -0.55, 1.1, -1.1, 1.57, -1.57]:
			var detour := direction.rotated(angle)
			var available := _free_distance(detour, length, neighbors)
			if available <= length * 0.5 or not _has_live_space(actor): continue
			if actor.test_move(actor.global_transform, detour * available): continue
			direction = detour
			allowed = available
			break
	actor.velocity = direction * allowed / delta
	if allowed > 0.0001 and _has_live_space(actor): actor.move_and_slide()

static func _has_live_space(actor: CharacterBody2D) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return false
	var world := actor.get_world_2d()
	if world == null or not world.space.is_valid():
		return false
	# A sleeping CollisionObject2D can remain in the scene tree for one queued
	# callback after DISABLE_MODE_REMOVE has detached its body from the space.
	# Check the server-owned body RID, not only the World2D RID.
	var body_space := PhysicsServer2D.body_get_space(actor.get_rid())
	return body_space.is_valid()

static func _free_distance(direction: Vector2, length: float, neighbors: Array[Vector2]) -> float:
	var allowed := length
	for relative in neighbors:
		var along := relative.dot(direction)
		if along <= 0.0: continue
		var lateral_squared := maxf(0.0, relative.length_squared() - along * along)
		if lateral_squared >= CLEARANCE * CLEARANCE: continue
		var entry := along - sqrt(CLEARANCE * CLEARANCE - lateral_squared)
		allowed = minf(allowed, maxf(0.0, entry))
	return allowed
