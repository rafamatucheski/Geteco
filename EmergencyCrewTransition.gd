class_name EmergencyCrewTransition
extends RefCounted

## Shared geometry and presentation rules for responders entering/exiting an
## emergency unit.  Keeping this here prevents every service from inventing a
## slightly different "teleport at the truck" behaviour.

const EXIT_LATERAL_DISTANCE := 31.0
const DOOR_LATERAL_DISTANCE := 18.0

static func finish_exit(actor: CharacterBody2D, vehicle: Node2D, side: float, delta: float) -> bool:
	# Stay at the doorway until the panel has shut, then resume the route.
	var elapsed := float(actor.get_meta("crew_close_elapsed", 0.0))
	if elapsed == 0.0:
		vehicle.close_crew_cover_door(side)
	actor.velocity = Vector2.ZERO
	elapsed += delta
	if elapsed < 0.45:
		actor.set_meta("crew_close_elapsed", elapsed)
		return false
	actor.remove_meta("crew_close_elapsed")
	return true

static func get_door_point(vehicle: Node2D, side: float, longitudinal: float = -8.0) -> Vector2:
	return vehicle.global_position + vehicle.transform.x * longitudinal + vehicle.transform.y * side * DOOR_LATERAL_DISTANCE


static func get_exit_point(vehicle: Node2D, side: float, longitudinal: float = -8.0) -> Vector2:
	# A frota 3D tem larguras diferentes. A equipe precisa sair inteiramente da
	# carroceria antes de restaurar colisão com o veículo.
	var lateral := EXIT_LATERAL_DISTANCE
	var collision := vehicle.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision and collision.shape is RectangleShape2D:
		lateral = maxf(lateral, collision.shape.size.y * 0.5 + 16.0)
	return vehicle.global_position + vehicle.transform.x * longitudinal + vehicle.transform.y * side * lateral


static func get_spawn_point(vehicle: Node2D, side: float, longitudinal: float = -8.0) -> Vector2:
	# This is just inside the silhouette, so the worker visibly walks through
	# the open doorway before heading for the incident.
	return vehicle.global_position + vehicle.transform.x * longitudinal + vehicle.transform.y * side * 7.0


static func paint_for_service(service_type: int) -> Color:
	match service_type:
		0: return Color("#213d72") # police blue
		1: return Color("#e8ecef") # ambulance white
		2: return Color("#b9232f") # fire red
		3: return Color("#2a2c33") # coroner charcoal
		_: return Color("#526476")
