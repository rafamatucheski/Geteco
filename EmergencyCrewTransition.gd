class_name EmergencyCrewTransition
extends RefCounted

## Shared geometry and presentation rules for responders entering/exiting an
## emergency unit.  Keeping this here prevents every service from inventing a
## slightly different "teleport at the truck" behaviour.

const EXIT_LATERAL_DISTANCE := 31.0
const DOOR_LATERAL_DISTANCE := 18.0

static func get_door_point(vehicle: Node2D, side: float, longitudinal: float = -8.0) -> Vector2:
	return vehicle.global_position + vehicle.transform.x * longitudinal + vehicle.transform.y * side * DOOR_LATERAL_DISTANCE


static func get_exit_point(vehicle: Node2D, side: float, longitudinal: float = -8.0) -> Vector2:
	return vehicle.global_position + vehicle.transform.x * longitudinal + vehicle.transform.y * side * EXIT_LATERAL_DISTANCE


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
