class_name EmergencyDepotMarker
extends Node2D

## One authored emergency-service base. Positions come from Marker2D children,
## keeping dispatch/return logic coupled to the fixed map instead of magic numbers.

@export_enum("police", "ambulance", "fire") var service_key := "police"
@export var depot_id := "central_police"
@export var parking_bay_count := 2

signal gate_open_requested(depot_id: String)
signal gate_close_requested(depot_id: String)

func get_spawn_position() -> Vector2:
	return _marker_position("SpawnPoint")

func get_exit_position() -> Vector2:
	return _marker_position("ExitPoint")

func get_return_position() -> Vector2:
	return _marker_position("ReturnPoint")

func get_departure_rotation() -> float:
	var marker := get_node_or_null("ExitPoint") as Marker2D
	return marker.global_rotation if marker else global_rotation

func request_gate_open() -> void:
	gate_open_requested.emit(depot_id)

func request_gate_close() -> void:
	gate_close_requested.emit(depot_id)

func _marker_position(marker_name: String) -> Vector2:
	var marker := get_node_or_null(marker_name) as Marker2D
	return marker.global_position if marker else global_position
