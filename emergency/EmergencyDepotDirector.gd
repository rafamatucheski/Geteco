class_name EmergencyDepotDirector
extends Node2D

## Coordinates operational emergency buildings, their gates, pooled vehicles
## and authored alley standby units. Add one instance to Main.tscn.

signal vehicle_dispatched(vehicle: Node, service_key: String, depot_id: String)
signal vehicle_returned(vehicle: Node, service_key: String, depot_id: String)

var _depots: Dictionary = {}
var _vehicle_assignments: Dictionary = {}
var _service_incidents: Node

func _ready() -> void:
	add_to_group("emergency_depot_director")
	for child in get_children():
		if child is EmergencyDepotMarker:
			register_depot(child)

func register_depot(depot: EmergencyDepotMarker) -> void:
	var service_key := depot.service_key
	if not _depots.has(service_key):
		_depots[service_key] = []
	var service_depots := _depots[service_key] as Array
	if not service_depots.has(depot):
		service_depots.append(depot)

func request_dispatch(service_key: String, target: Node2D, prefer_standby := true) -> Node:
	if not is_instance_valid(target) or not is_inside_tree() or not can_process(): return null
	# Coroner/IML was removed: fatalities are handled by the bounded corpse
	# presentation budget and never allocate an emergency vehicle or incident.
	if service_key == "coroner": return null
	if service_key == "fire":
		if not is_instance_valid(_service_incidents):
			_service_incidents = preload("res://emergency/ServiceIncidents.gd").new()
			_service_incidents.director = self
			add_child(_service_incidents)
		return _service_incidents.request(service_key, target)
	return _dispatch_unbatched(service_key, target, prefer_standby)

func _dispatch_unbatched(service_key: String, target: Node2D, prefer_standby := true) -> Node:
	if not is_instance_valid(target):
		return null
	var depot := _choose_depot(service_key, target.global_position)
	if depot == null:
		push_warning("No authored depot registered for service '%s'" % service_key)
		return null
	if service_key == "coroner":
		# A new crew waits while the physical departure bay is occupied.
		# Reusing the pool must not stack a second van over a collecting unit.
		for occupied in get_tree().get_nodes_in_group("emergency_vehicle"):
			if occupied.visible and occupied.global_position.distance_to(depot.get_spawn_position()) < 110:
				return null

	var vehicle := _take_pooled_vehicle(service_key)
	if vehicle == null: return null
	# Claim only a matching parked body: a departing SUV cannot replace a sedan
	# (nor can a motorcycle replace a parked four-wheel cruiser).
	var body_filter := ""
	if service_key == "police":
		body_filter = "motorcycle" if vehicle.police_variant == "motorcycle" else vehicle.police_archetype
	var standby := _claim_standby(service_key, body_filter) if prefer_standby else null

	var departure_position := standby.global_position if standby else depot.get_spawn_position()
	var departure_rotation := standby.global_rotation if standby else depot.get_departure_rotation()
	if vehicle.has_meta("hospital_departure_position"):
		departure_position = vehicle.get_meta("hospital_departure_position")
		departure_rotation = vehicle.get_meta("hospital_departure_rotation")
		vehicle.remove_meta("hospital_departure_position")
		vehicle.remove_meta("hospital_departure_rotation")
		if standby:
			standby.available = true
			standby.visible = true
			standby = null
	if vehicle.has_method("configure_depot_assignment"):
		vehicle.configure_depot_assignment(
			depot.depot_id,
			depot.get_return_position(),
			depot.get_spawn_position(),
			standby.standby_id if standby else ""
		)
	vehicle.set("type", _service_type(service_key))
	vehicle.set("target", target)
	vehicle.global_position = departure_position
	vehicle.global_rotation = departure_rotation
	vehicle.set_meta("depot_road_gate", depot.get_exit_position())
	vehicle.set_meta("depot_departure_pending", standby == null)
	# EmergencyPool.get_vehicle() already resets and activates pooled instances.
	# Calling EmergencyVehicle.activate() here would duplicate that work and would
	# also rely on its legacy dynamically-created collision node name.
	_vehicle_assignments[vehicle.get_instance_id()] = {"depot": depot, "standby": standby, "service": service_key}
	depot.request_gate_open()
	_close_gate_later(depot)
	vehicle_dispatched.emit(vehicle, service_key, depot.depot_id)
	return vehicle

func begin_vehicle_return(vehicle: Node) -> void:
	var assignment: Dictionary = _vehicle_assignments.get(vehicle.get_instance_id(), {})
	var depot = assignment.get("depot")
	if is_instance_valid(depot) and depot is EmergencyDepotMarker:
		depot.request_gate_open()

func complete_vehicle_return(vehicle: Node) -> void:
	var assignment: Dictionary = _vehicle_assignments.get(vehicle.get_instance_id(), {})
	var depot = assignment.get("depot")
	var standby = assignment.get("standby")
	var service_key := String(assignment.get("service", ""))
	if is_instance_valid(depot) and depot is EmergencyDepotMarker:
		depot.request_gate_close()
		vehicle_returned.emit(vehicle, service_key, depot.depot_id)
	if standby:
		standby.restore_after_return()
	_vehicle_assignments.erase(vehicle.get_instance_id())

func get_return_position(service_key: String) -> Vector2:
	var depot := _choose_depot(service_key, Vector2.ZERO)
	return depot.get_return_position() if depot else Vector2.ZERO


func _choose_depot(service_key: String, near_position: Vector2) -> EmergencyDepotMarker:
	var service_depots := _depots.get(service_key, []) as Array
	var chosen: EmergencyDepotMarker = null
	var best_distance := INF
	for candidate in service_depots:
		var depot := candidate as EmergencyDepotMarker
		if not is_instance_valid(depot):
			continue
		var distance := depot.get_exit_position().distance_squared_to(near_position)
		if chosen == null or distance < best_distance:
			chosen = depot
			best_distance = distance
	return chosen

func _claim_standby(service_key: String, body_filter := "") -> EmergencyStandbyPoint:
	for node in get_tree().get_nodes_in_group("emergency_standby_point"):
		var point := node as EmergencyStandbyPoint
		if point and not body_filter.is_empty():
			if not is_instance_valid(point.parked_car) or point.parked_car.active_archetype_id != body_filter: continue
		if point and point.service_key == service_key and point.claim():
			return point
	return null

func _take_pooled_vehicle(service_key: String) -> Node:
	var pool := get_node_or_null("/root/EmergencyPool")
	if pool and pool.has_method("get_vehicle"):
		return pool.get_vehicle(service_key)
	return null

func _close_gate_later(depot: EmergencyDepotMarker) -> void:
	await get_tree().create_timer(1.25).timeout
	if is_instance_valid(depot):
		depot.request_gate_close()

func _service_type(service_key: String) -> int:
	match service_key:
		"ambulance": return 1
		"fire": return 2
		"coroner": return 3
		_: return 0
