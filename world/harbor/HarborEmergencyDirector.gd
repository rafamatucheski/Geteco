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

func _exit_tree() -> void:
	var pool := get_node_or_null("/root/EmergencyPool")
	var assigned: Array[Node] = []
	for bucket in _requests.values():
		for candidate in (bucket as Array):
			# Child depots and targets may already be freed during scene teardown.
			# Ownership is recorded on the pooled unit and survives that teardown.
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
		if service == "police": departure += Vector2(45, 0)
		if service == "fire": departure += Vector2(0, -10)
		var exit := _nearest_lane_point(departure)
		for marker_name in ["SpawnPoint", "ReturnPoint", "ExitPoint"]:
			var marker := Marker2D.new()
			marker.name = marker_name
			depot.add_child(marker)
			marker.global_position = exit if marker_name == "ExitPoint" else departure
			marker.global_rotation = departure.direction_to(exit).angle()
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

func request_dispatch(service_key: String, target: Node2D, _prefer_standby := true) -> Node:
	if not is_instance_valid(target) or not is_instance_valid(_world) or not can_process():
		return null
	var key := service_key + ":" + str(target.get_instance_id())
	var bucket: Array = _requests.get(key, [])
	# One active unit per (service, target) is correct for fire/ambulance/
	# coroner -- a burning car does not need a second engine. It is wrong for
	# police: WantedManager escalates to up to POOL_SIZE_POLICE simultaneous
	# cruisers as stars climb (max_active_cruisers = min(stars, 4)), calling
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
			if _owns_unit(existing) and existing.visible and not existing.get("is_broken") and existing.get("target") == target:
				return existing
	var depot := _choose_depot(service_key, target.global_position)
	if service_key == "police" and depot != null and depot.get_spawn_position().distance_to(target.global_position) > 3600.0:
		return null
	if depot == null or not _spawn_clear(depot):
		return null
	# Legacy standby groups can refer to another district; only our registered
	# exterior apron is a legitimate Harbor departure point.
	var vehicle := super.request_dispatch(service_key, target, false)
	if is_instance_valid(vehicle):
		vehicle.set_meta("harbor_director_id", get_instance_id())
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
	var key := str(assignment.get("service", "")) + ":" + str(current_target.get_instance_id())
	return (_requests.get(key, []) as Array).has(vehicle)

func _take_pooled_vehicle(service_key: String) -> Node:
	var pool := get_node_or_null("/root/EmergencyPool")
	# No unlimited instantiate fallback if all authored service units are busy.
	return pool.call("get_vehicle", service_key) if pool != null else null

func complete_vehicle_return(vehicle: Node) -> void:
	super.complete_vehicle_return(vehicle)
	for key in _requests.keys():
		var bucket: Array = _requests[key]
		if bucket.has(vehicle):
			bucket.erase(vehicle)
			if bucket.is_empty():
				_requests.erase(key)
			else:
				_requests[key] = bucket

func _spawn_clear(depot: EmergencyDepotMarker) -> bool:
	if not is_inside_tree():
		return false
	var shape := RectangleShape2D.new()
	# A conservative envelope around the production emergency body.
	shape.size = Vector2(100, 46)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(depot.get_departure_rotation(), depot.get_spawn_position())
	query.collision_mask = 7
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func get_harbor_depot_audit() -> Dictionary:
	var result := {}
	for service in _depots:
		var depot := _choose_depot(service, Vector2.ZERO)
		result[service] = {"spawn": depot.get_spawn_position(), "exit": depot.get_exit_position(),
			"return": depot.get_return_position(), "spawn_clear": _spawn_clear(depot)}
	return result
