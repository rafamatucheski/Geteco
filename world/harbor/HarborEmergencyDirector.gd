extends "res://world/shared/emergency/EmergencyDepotDirector.gd"

## Harbor adapter for the existing finite emergency pool. Interior fire trucks
## remain independently playable; dispatch never creates or borrows those trucks.
const DEPOTS := {
	"fire": {"path": "NorthDistrict/FireStationApron", "id": "harbor_north_fire"},
	"police": {"path": "District/PatrolAccess", "id": "harbor_patrol"},
	"ambulance": {"path": "District/ClinicVehicleAccess", "id": "harbor_clinic"},
	# No standalone IML/morgue building is placed in the district yet (its
	# interior exists as an unused template — see HarborMorgueInterior.gd).
	# The coroner shares the clinic apron, the district's medical hub, so
	# dispatch is real instead of silently failing (no depot was ever
	# registered for "coroner" before, so request_dispatch("coroner", ...)
	# always returned null -- the IML never actually responded to a death).
	# Distinct id from "ambulance" (same path) so the two depot markers don't
	# collide on node name (EmergencyDepotMarker.name = str(id)).
	"coroner": {"path": "District/CoronerVehicleAccess", "id": "harbor_clinic_iml"},
}
var _world: Node2D
var _requests: Dictionary = {}
var _medical_slots: Dictionary = {}
var _medical_arrivals: Array[int] = []
var _medical_admission_owner := 0

func _exit_tree() -> void:
	var pool := get_node_or_null("/root/EmergencyPool")
	var assigned: Array[Node] = []
	for bucket in _requests.values():
		for candidate in (bucket as Array):
			# Child depots and targets may already be freed during scene teardown.
			# Ownership is recorded on the pooled unit and survives that teardown.
			if is_instance_valid(candidate) and int(candidate.get_meta("harbor_director_id", 0)) == get_instance_id() and not assigned.has(candidate):
				assigned.append(candidate)
	# Completed hospital units remain visible in their bay after their request
	# bucket is cleared. They still belong to this region during teardown.
	for candidate in get_tree().get_nodes_in_group("emergency_vehicle"):
		if is_instance_valid(candidate) and int(candidate.get_meta("harbor_director_id", 0)) == get_instance_id() and not assigned.has(candidate):
			assigned.append(candidate)
	# Pooled units are root children, therefore their deployed crews are too.
	# Remove only this scene's crews, never another director's responders.
	var crew_links := {"firefighter": "fire_truck", "paramedic": "ambulance",
		"police_officer": "service_vehicle", "mortician": "hearse"}
	for group in crew_links:
		for actor in get_tree().get_nodes_in_group(group):
			if assigned.has(actor.get(crew_links[group])):
				actor.queue_free()
	if pool:
		for vehicle in assigned:
			if is_instance_valid(vehicle):
				pool.call("return_vehicle", vehicle)
	_requests.clear()
	_vehicle_assignments.clear()
	_medical_slots.clear()
	_medical_arrivals.clear()
	_medical_admission_owner = 0

func configure(world: Node2D) -> void:
	_world = world
	if not _depots.is_empty():
		return
	var medical_parking := preload("res://world/harbor/HarborMedicalParking.gd").new()
	medical_parking.name = "MedicalParking"
	world.get_node("District").add_child(medical_parking)
	for service in DEPOTS:
		var access := world.get_node_or_null(DEPOTS[service].path) as Marker2D
		if access == null:
			push_warning("Harbor service access missing: " + str(DEPOTS[service].path))
			continue
		if service == "police":
			var parking := preload("res://world/harbor/HarborPatrolParking.gd").new()
			parking.name = "PatrolParking"
			world.add_child(parking)
			parking.global_position = access.global_position
		var depot := EmergencyDepotMarker.new()
		depot.name = str(DEPOTS[service].id)
		depot.depot_id = str(DEPOTS[service].id)
		depot.service_key = service
		depot.parking_bay_count = 2
		add_child(depot)
		# Keep the full engine envelope inside its painted bay: the original
		# marker allowed a wide passing bus to overlap its front by a few pixels.
		var departure := access.global_position
		if service == "fire": departure += Vector2(0, -10)
		# The full pumper is longer than the strip between facade and traffic.
		# Park parallel to the facade and merge along the apron, instead of
		# spawning its rear inside the building with its nose in passing cars.
		var exit := _nearest_lane_point(departure + Vector2(-140, 0) if service == "fire" else departure)
		if service == "police":
			exit = _nearest_lane_point(Vector2(departure.x, preload("res://world/harbor/HarborLocalStreets.gd").PATROL_Y))
		if service in ["ambulance", "coroner"]:
			# The recessed yard exits east through Warehouse Way. Searching from
			# its inner bays can pick Market Street and steer through the building.
			exit = _nearest_lane_point(Vector2(2145, departure.y))
		var departure_rotation := PI if service == "fire" else departure.direction_to(exit).angle()
		for marker_name in ["SpawnPoint", "ReturnPoint", "ExitPoint"]:
			var marker := Marker2D.new()
			marker.name = marker_name
			depot.add_child(marker)
			marker.global_position = exit if marker_name == "ExitPoint" else departure
			marker.global_rotation = departure_rotation
		register_depot(depot)

func _nearest_lane_point(point: Vector2) -> Vector2:
	var network := _world.get_node_or_null("RoadNetwork") as Node2D
	var best := point
	var distance := INF
	if network == null:
		return best
	for path in network.find_children("*", "Path2D", true, false):
		if not path.is_in_group("unified_traffic_lane") or path.curve == null:
			continue
		var sample: Vector2 = path.to_global(path.curve.get_closest_point(path.to_local(point)))
		if sample.distance_squared_to(point) < distance:
			distance = sample.distance_squared_to(point)
			best = sample
	return best

func _dispatch_unbatched(service_key: String, target: Node2D, _prefer_standby := true) -> Node:
	if not is_instance_valid(target) or not is_instance_valid(_world) or not can_process():
		return null
	var key := service_key + ":" + str(target.get_instance_id())
	var bucket: Array = _requests.get(key, [])
	# One active unit per (service, target) is correct for fire/ambulance/
	# coroner -- a burning car does not need a second engine. It is wrong for
	# police: WantedManager escalates to up to five simultaneous cruisers as
	# stars climb, calling
	# request_dispatch again each time it wants one more. Collapsing every
	# call for the same fleeing player onto whichever cruiser answered first
	# silently capped real response at exactly one unit no matter how high
	# wanted went. Reproduced live at 6 stars: only 1 cruiser was ever
	# simultaneously active for ~12s (rest of _dispatch_police's own attempts
	# every ~3s all returned that same instance) while the player's car took
	# repeated ramming damage from it alone; WantedManager's own
	# active_police_count/max_active_cruisers cap (checked before this is
	# ever called) already prevents unbounded spawning, so this dedup was
	# never needed to protect police in the first place.
	if service_key != "police":
		for existing in bucket:
			if service_key == "ambulance" and is_instance_valid(existing) and existing.has_meta("medical_abort_reason"): continue
			if _owns_unit(existing) and existing.visible and not existing.get("is_broken") and existing.get("target") == target:
				return existing
	var depot := _choose_depot(service_key, target.global_position)
	if service_key == "police" and depot != null and depot.get_spawn_position().distance_to(target.global_position) > 3600.0:
		return null
	if depot == null or not _spawn_clear(depot):
		return null
	# Legacy standby groups can refer to another district; only our registered
	# exterior apron is a legitimate Harbor departure point.
	var vehicle := super._dispatch_unbatched(service_key, target, false)
	if is_instance_valid(vehicle):
		vehicle.set_meta("harbor_director_id", get_instance_id())
		if service_key == "police":
			vehicle.set_meta("depot_departure_waypoints", preload("res://world/harbor/HarborLocalStreets.gd").police_departure(vehicle.global_position, target.global_position))
		if service_key in ["ambulance", "coroner"] and target.global_position.x < 2145.0:
			# Depart through the south aisle for incidents west of the medical yard.
			# Keep the original road gate for the existing hospital return routine.
			vehicle.set_meta("depot_departure_waypoints", preload("res://world/harbor/HarborLocalStreets.gd").medical_departure(vehicle.global_position))
		if service_key == "ambulance":
			get_medical_return_position(vehicle)
			preload("res://audio/police_dispatch/EmergencyServiceRadio.gd").play_at(vehicle, &"medical_dispatch")
		bucket.append(vehicle)
		_requests[key] = bucket
	return vehicle

func _owns_unit(vehicle: Variant) -> bool:
	if not is_instance_valid(vehicle) or int(vehicle.get_meta("harbor_director_id", 0)) != get_instance_id():
		return false
	var assignment: Dictionary = _vehicle_assignments.get(vehicle.get_instance_id(), {})
	var depot: Variant = assignment.get("depot")
	if not is_instance_valid(depot) or vehicle.get("home_depot_id") != depot.depot_id:
		return false
	var current_target: Variant = vehicle.get("target")
	if not is_instance_valid(current_target):
		return not vehicle.visible or bool(vehicle.get("is_returning_to_base"))
	for bucket in _requests.values():
		if (bucket as Array).has(vehicle): return true
	return false

func _take_pooled_vehicle(service_key: String) -> Node:
	var pool := get_node_or_null("/root/EmergencyPool")
	# No unlimited instantiate fallback if all authored service units are busy.
	return pool.call("get_vehicle", service_key) if pool != null else null

func complete_vehicle_return(vehicle: Node) -> void:
	release_medical_admission(vehicle)
	super.complete_vehicle_return(vehicle)
	for key in _requests.keys():
		var bucket: Array = _requests[key]
		if bucket.has(vehicle):
			bucket.erase(vehicle)
			if bucket.is_empty():
				_requests.erase(key)
			else:
				_requests[key] = bucket

func _prune_medical_slots() -> void:
	for unit_id in _medical_slots.keys():
		var unit := instance_from_id(int(unit_id))
		if is_instance_valid(unit) and unit.visible and not unit.is_broken and int(unit.get_meta("harbor_director_id", 0)) == get_instance_id(): continue
		_medical_slots.erase(unit_id)
		_medical_arrivals.erase(int(unit_id))
		if _medical_admission_owner == int(unit_id): _medical_admission_owner = 0

func get_medical_return_position(unit: Node2D) -> Vector2:
	_prune_medical_slots()
	var unit_id := unit.get_instance_id()
	# Occupancy can change while the ambulance is away. Keep a latched arrival
	# fixed, but release an obstructed destination before asking for another bay.
	if _medical_slots.has(unit_id) and not bool(unit.get_meta("hospital_arrived",false)):
		var assigned: Vector2 = _medical_slots[unit_id]
		if not preload("res://world/shared/emergency/HospitalArrival.gd").clear_pose(unit,Transform2D(global_rotation,assigned)):
			_medical_slots.erase(unit_id)
	if not _medical_slots.has(unit_id):
		var assignment: Dictionary = _vehicle_assignments.get(unit_id, {})
		var depot: Variant = assignment.get("depot")
		var origin: Vector2 = depot.get_return_position() if is_instance_valid(depot) else unit.home_return_position
		# Park slightly north within the marked bay: its southern island leaves
		# room for the vehicle but obstructs a full passenger-door disembark.
		var reserve_offset: Vector2 = preload("res://world/harbor/HarborMedicalParking.gd").RESERVE_STOP + Vector2(16, -12) - preload("res://world/harbor/HarborMedicalParking.gd").AMBULANCE_STOP
		# Fixed bays remain reserved while their own unit is in service or
		# parked. Releasing admission never sends another car onto that body.
		for candidate in [origin, origin+reserve_offset]:
			if _medical_slots.values().has(candidate): continue
			if not preload("res://world/shared/emergency/HospitalArrival.gd").clear_pose(unit,Transform2D(global_rotation,candidate)): continue
			_medical_slots[unit_id] = candidate
			break
		if not _medical_slots.has(unit_id): return Vector2.INF
	return _medical_slots[unit_id]

func is_medical_bay_owner(unit: Node2D) -> bool:
	var stop := get_medical_return_position(unit)
	var unit_id := unit.get_instance_id()
	if not bool(unit.get_meta("hospital_arrived",false)) and unit.global_position.distance_to(stop) > 18.0: return false
	if not _medical_arrivals.has(unit_id): _medical_arrivals.append(unit_id)
	if _medical_admission_owner == 0 and not _medical_arrivals.is_empty():
		_medical_admission_owner = _medical_arrivals[0]
	return _medical_admission_owner == unit_id

func release_medical_admission(unit: Node) -> void:
	var unit_id := unit.get_instance_id()
	_medical_arrivals.erase(unit_id)
	if _medical_admission_owner == unit_id: _medical_admission_owner = 0

func _spawn_clear(depot: EmergencyDepotMarker) -> bool:
	if not is_inside_tree():
		return false
	var shape := RectangleShape2D.new()
	# A conservative envelope around the production emergency body.
	shape.size = Vector2(146, 46) if depot.service_key == "fire" else Vector2(100, 46)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(depot.get_departure_rotation(), depot.get_spawn_position())
	if depot.service_key == "ambulance":
		for candidate in get_tree().get_nodes_in_group("emergency_vehicle"):
			if candidate.home_depot_id == depot.depot_id and bool(candidate.get_meta("hospital_available", false)) and not candidate.is_broken:
				# This is a departure by the unit already standing here, so check
				# its actual bay and exclude its own collider from the occupancy.
				query.transform = candidate.global_transform
				query.exclude = [candidate.get_rid()]
				break
	query.collision_mask = 7
	query.collide_with_areas = false
	# A second dispatch can run in the same scan before the physics server has
	# registered the first activated body. Check live bodies too, so the pair
	# never materializes in the same departure bay.
	for candidate in get_tree().get_nodes_in_group("emergency_vehicle"):
		if not candidate.is_visible_in_tree() or query.exclude.has(candidate.get_rid()): continue
		var collider := candidate.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collider and collider.shape and shape.collide(query.transform, collider.shape, collider.global_transform): return false
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func get_harbor_depot_audit() -> Dictionary:
	var result := {}
	for service in _depots:
		var depot := _choose_depot(service, Vector2.ZERO)
		result[service] = {"spawn": depot.get_spawn_position(), "exit": depot.get_exit_position(),
			"return": depot.get_return_position(), "spawn_clear": _spawn_clear(depot)}
	return result
