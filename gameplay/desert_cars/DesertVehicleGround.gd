extends RefCounted
## Predict upright vehicle support on the authored canyon and quarry faces.
## NAN means ordinary gravity/floor handling must remain in charge. This helper
## never moves a body, changes horizontal velocity, or suppresses a collision.
const FIELD := preload("res://world/desert/DesertTerrainRelief.gd")
const MINING_LAYOUT := preload("res://world/mining/MiningLayout.gd")

static func vertical_velocity(car: CharacterBody3D, horizontal: Vector3, delta: float) -> float:
	if not is_instance_valid(car) or delta <= 0.0 or not is_finite(delta):
		return NAN
	var height_at := terrain_height_provider(car)
	if not height_at.is_valid():
		return NAN
	var planar := Vector3(horizontal.x, 0.0, horizontal.z)
	if not planar.is_finite():
		return NAN
	var half_width := float(car.get("half_width"))
	var half_length := float(car.get("half_length"))
	if half_width <= 0.0 or half_length <= 0.0:
		return NAN
	# Steering has already updated the vehicle basis. Both position and footprint
	# therefore describe the upcoming sweep, including the new supporting corner.
	var right := car.global_basis.x
	var along := car.global_basis.z
	right.y = 0.0
	along.y = 0.0
	right = right.normalized()
	along = along.normalized()
	var next_center := car.global_position + planar * delta
	var highest := -INF
	for width_index in 3:
		var across := float(width_index - 1) * half_width
		for length_index in 5:
			var longitudinal := float(length_index - 2) * half_length * 0.5
			var point := next_center + right * across + along * longitudinal
			var height := float(height_at.call(Vector2(point.x, point.z)))
			if not is_finite(height):
				return NAN
			highest = maxf(highest, height)
	# Vehicle.gd's upright BoxShape bottom is its origin. The fixed clearance
	# avoids a cumulative upward bias: it is added to terrain, not to body height.
	var clearance := maxf(car.safe_margin, 0.002)
	var rise := highest + clearance - car.global_position.y
	var horizontal_step := planar.length() * delta
	var maximum_rise := horizontal_step * tan(car.floor_max_angle) + clearance * 2.0
	if rise > maximum_rise or rise < -maxf(car.floor_snap_length, maximum_rise):
		return NAN
	return rise / delta

static func terrain_height_provider(car: CharacterBody3D) -> Callable:
	if not is_instance_valid(car) or not car.is_on_floor():
		return Callable()
	# Ordinary city cars never issue the fallback ray. Bounds alone do not grant
	# support: the actual contact/ray must still identify the tagged terrain body.
	var point := Vector2(car.global_position.x, car.global_position.z)
	if not FIELD.BOUNDS.has_point(point) and not (MINING_LAYOUT.enabled() and MINING_LAYOUT.BOUNDS.has_point(point)):
		return Callable()
	var floor_limit := cos(car.floor_max_angle)
	for slide_index in car.get_slide_collision_count():
		var contact := car.get_slide_collision(slide_index)
		for collision_index in contact.get_collision_count():
			if contact.get_normal(collision_index).y < floor_limit:
				continue
			var collider := contact.get_collider(collision_index)
			var provider := _provider_from_body(collider)
			if provider.is_valid():
				return provider
	# apply_floor_snap can establish is_on_floor without retaining slide contacts.
	# Reconfirm that floor physically instead of assuming an empty contact list
	# means an unsupported car or remembering a collider which may have streamed out.
	var query := PhysicsRayQueryParameters3D.create(
		car.global_position + Vector3.UP * 0.05,
		car.global_position + Vector3.DOWN * 0.6, 1, [car.get_rid()])
	query.collide_with_areas = false
	var hit := car.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Callable()
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if normal.y < floor_limit:
		return Callable()
	return _provider_from_body(hit.get("collider"))

static func _provider_from_body(body: Object) -> Callable:
	if not is_instance_valid(body) or not body is Node:
		return Callable()
	if not bool(body.get_meta("desert_continuous_ground", false)) or not body.has_meta("desert_ground_height"):
		return Callable()
	var provider: Variant = body.get_meta("desert_ground_height")
	if provider is Callable and provider.is_valid():
		return provider
	return Callable()
