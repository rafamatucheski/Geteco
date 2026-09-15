extends RefCounted
## Hearing is an event, not a scan of the city's population every frame.
const RADIUS := 240.0

static func report(vehicle: CharacterBody2D) -> void:
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, vehicle.global_position)
	query.collision_mask = 5
	query.exclude = [vehicle.get_rid()]
	for result in vehicle.get_world_2d().direct_space_state.intersect_shape(query, 64):
		var person = result.collider
		if not person.has_method("hear_traffic_horn"): continue
		var cover := PhysicsRayQueryParameters2D.create(vehicle.global_position, person.global_position, 1, [vehicle.get_rid()])
		var wall := vehicle.get_world_2d().direct_space_state.intersect_ray(cover)
		if not wall.is_empty() and wall.collider != person: continue
		person.hear_traffic_horn(vehicle)
