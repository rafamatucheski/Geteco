class_name Bairro1CivicServices
extends Node2D

## Functional civic anchors for the first borough.  Their buildings are drawn
## by Bairro1Expansion; this companion owns only spawns, gates and dispatch.

const DEPOT_MARKER := preload("res://world/shared/emergency/EmergencyDepotMarker.gd")
const DEPOT_GATE := preload("res://world/shared/emergency/DepotGate.gd")

func _ready() -> void:
	add_to_group("bairro1_civic_services")
	_create_hospital_spawn()
	_create_police_depot("MirantePolicePrecinct", "mirante_precinct", Vector2(1690, 1740), Vector2(1770, 1740), Vector2(1690, 1810))
	_create_police_depot("PortoPoliceSubstation", "porto_substation", Vector2(2130, 2870), Vector2(2050, 2870), Vector2(2130, 2940))
	call_deferred("_register_police_depots")


func _create_hospital_spawn() -> void:
	var spawn := Marker2D.new()
	spawn.name = "MiranteHospitalRespawn"
	spawn.position = Vector2(1620, 2140)
	spawn.add_to_group("hospital_spawn")
	spawn.set_meta("service", "hospital")
	add_child(spawn)


func _create_police_depot(node_name: String, depot_id: String, spawn_at: Vector2, exit_at: Vector2, return_at: Vector2) -> void:
	var depot := DEPOT_MARKER.new() as EmergencyDepotMarker
	depot.name = node_name
	depot.service_key = "police"
	depot.depot_id = depot_id
	depot.parking_bay_count = 2
	add_child(depot)
	_add_marker(depot, "SpawnPoint", spawn_at, exit_at.angle_to_point(spawn_at))
	_add_marker(depot, "ExitPoint", exit_at, spawn_at.angle_to_point(exit_at))
	_add_marker(depot, "ReturnPoint", return_at, 0.0)
	_add_gate(depot, exit_at)


func _add_marker(parent: Node2D, marker_name: String, at: Vector2, facing: float) -> void:
	var marker := Marker2D.new()
	marker.name = marker_name
	marker.position = at
	marker.rotation = facing
	parent.add_child(marker)


func _add_gate(depot: EmergencyDepotMarker, at: Vector2) -> void:
	var gate := DEPOT_GATE.new() as DepotGate
	gate.name = "Gate"
	gate.position = at
	gate.opening_distance = 24.0
	for side in [-1.0, 1.0]:
		var door := Polygon2D.new()
		door.name = "LeftDoor" if side < 0.0 else "RightDoor"
		door.polygon = PackedVector2Array([Vector2(side * 34.0, -5), Vector2(side * 3.0, -5), Vector2(side * 3.0, 5), Vector2(side * 34.0, 5)])
		door.color = Color("#18334a")
		gate.add_child(door)
	# The gate reads its two doors in _ready, so attach it only after both exist.
	depot.add_child(gate)


func _register_police_depots() -> void:
	var director := get_tree().get_first_node_in_group("emergency_depot_director")
	if director == null or not director.has_method("register_depot"):
		push_warning("Emergency depot director unavailable for Bairro 1 police stations")
		return
	for child in get_children():
		if child is EmergencyDepotMarker:
			director.register_depot(child as EmergencyDepotMarker)
	print("BAIRRO1_CIVIC_READY|hospital=1|police_precincts=2|firehouse=1")
