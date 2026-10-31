extends RefCounted
## Expectativa física independente para a passagem sul estreita junto ao carro estacionado.
static func footprint(vehicle: CharacterBody3D) -> AABB:
	var box := AABB(vehicle.global_position,Vector3.ZERO)
	for x: float in [-float(vehicle.get("half_width")),float(vehicle.get("half_width"))]:
		for z: float in [-float(vehicle.get("half_length")),float(vehicle.get("half_length"))]:
			box = box.expand(vehicle.to_global(Vector3(x,0,z)))
	return box

static func path(world, car: CharacterBody3D, actor: CharacterBody3D) -> PackedVector3Array:
	var bounds: AABB = footprint(car)
	var passage_x: float = world.player.global_position.x
	var south: float = bounds.end.z+.6
	var right: float = INF
	for other in world.get_children():
		if other == car or not other is CharacterBody3D or not other.has_method("driver_seat_anchor"): continue
		if other.global_position.distance_to(car.global_position) > 12: continue
		var box: AABB = footprint(other)
		if box.position.x <= bounds.end.x or box.position.z > bounds.end.z or box.end.z < bounds.position.z: continue
		right = minf(right,box.position.x)
		south = maxf(south,box.end.z+.6)
	if is_finite(right): passage_x = (bounds.end.x+right)*.5
	var away: Vector3 = actor.global_position-car.global_position
	away.y = 0
	var goal: Vector3 = actor.global_position+away.normalized()*1.4
	var height: float = world.player.global_position.y
	goal.y = height
	var result := PackedVector3Array([Vector3(passage_x,height,south),Vector3(goal.x,height,south),goal])
	var previous: Vector3 = world.player.global_position
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 7
	query.exclude = [world.player.get_rid(),actor.get_rid()]
	for point: Vector3 in result:
		query.transform = Transform3D(Basis.IDENTITY,previous+Vector3.UP*.86)
		query.motion = point-previous
		var safe: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
		if safe[0] < 1.0: return PackedVector3Array()
		previous = point
	return result
