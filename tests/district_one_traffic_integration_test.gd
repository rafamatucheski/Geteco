extends SceneTree

const SAMPLE_FRAMES := 180
const MAX_CONTINUOUS_FRAME_DISPLACEMENT := 16.0

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_integration")


func _run_integration() -> void:
	var main_scene := load("res://legacy/Main.tscn") as PackedScene
	var world := main_scene.instantiate()
	var district := world.get_node("DistrictOneComplete")
	var graph := district.get_node("UnifiedRoadNetwork") as Node2D
	var controller := district.get_node("JunctionTrafficController")
	# This is equivalent to the controller's runtime discovery, assigned before
	# _ready so the test has no ordering dependency on SceneTree.current_scene.
	controller.graph_source = graph
	root.add_child(world)
	current_scene = world
	for _warmup in 12:
		await process_frame

	var graph_data: Dictionary = graph.get_graph_data()
	_check((graph_data.get("validation_errors", []) as Array).is_empty(), "canonical graph validation must be clean")
	_check((graph_data.get("lanes", []) as Array).size() >= 2, "canonical graph must publish directed lanes")
	_check((graph_data.get("lane_connections", []) as Array).size() >= 1, "canonical graph must publish lane connectors")
	var signalized_count := 0
	var unsignalized_count := 0
	for junction_value in graph_data.get("junctions", []):
		var junction := junction_value as Dictionary
		_check(junction.has("signalized"), "every canonical junction must publish signalized")
		var signalized := bool(junction.get("signalized", false))
		var approach_count := (junction.get("approaches", []) as Array).size()
		if signalized:
			signalized_count += 1
		else:
			unsignalized_count += 1
		var source := String(junction.get("signalization_source", ""))
		if approach_count < 3 and source == "approach_count":
			_check(not signalized, "two-approach continuation %s must not be signalized" % String(junction.get("id", "")))
		if not signalized:
			var junction_index := int(junction.get("index", -1))
			for road_index_value in junction.get("roads", []):
				var road_index := int(road_index_value)
				_check(controller.get_vehicle_permission(junction_index, road_index), "unsignalized junction %s manufactured an invisible red" % String(junction.get("id", "")))
			_check(not controller.is_pedestrian_phase(junction_index), "unsignalized junction %s manufactured a pedestrian all-red phase" % String(junction.get("id", "")))
	_check(signalized_count > 0, "canonical district must retain real signalized intersections")
	_check(unsignalized_count > 0, "canonical district must classify simple continuations as unsignalized")
	var traffic: Array[Node] = get_nodes_in_group("district_one_traffic")
	_check(not traffic.is_empty(), "DistrictOnePopulation must spawn traffic on unified lanes")
	var previous_positions := {}
	var maximum_displacement := 0.0
	var maximum_displacement_details := ""
	for vehicle in traffic:
		if vehicle is Node2D:
			previous_positions[vehicle.get_instance_id()] = (vehicle as Node2D).global_position

	for frame_index in SAMPLE_FRAMES:
		await process_frame
		for vehicle in traffic:
			if not is_instance_valid(vehicle) or not vehicle is Node2D:
				continue
			var vehicle_2d := vehicle as Node2D
			var previous: Vector2 = previous_positions.get(vehicle.get_instance_id(), vehicle_2d.global_position)
			var displacement := previous.distance_to(vehicle_2d.global_position)
			if displacement > maximum_displacement:
				maximum_displacement = displacement
				var follow_debug := vehicle.get_parent() as PathFollow2D
				var path_debug := follow_debug.get_parent() as Path2D if follow_debug != null else null
				maximum_displacement_details = "frame=%d vehicle=%s from=%s to=%s path=%s progress=%.3f" % [
					frame_index,
					vehicle.name,
					previous,
					vehicle_2d.global_position,
					path_debug.name if path_debug != null else "none",
					follow_debug.progress if follow_debug != null else -1.0,
				]
			previous_positions[vehicle.get_instance_id()] = vehicle_2d.global_position

	var telemetry: Dictionary = controller.get_telemetry_snapshot()
	_check(int(telemetry.get("reservation_grants", 0)) > 0, "runtime traffic must request at least one junction reservation")
	_check(int(telemetry.get("deadlock_limit_exceeded", 0)) == 0, "no vehicle may exceed the declared deadlock limit")
	_check(int(telemetry.get("signalized_junction_count", -1)) == signalized_count, "controller signalized count must match canonical graph")
	_check(int(telemetry.get("unsignalized_junction_count", -1)) == unsignalized_count, "controller unsignalized count must match canonical graph")
	_check(int(telemetry.get("signal_visual_count", -1)) == signalized_count, "only signalized junctions may own visual signal sets")
	_check(maximum_displacement <= MAX_CONTINUOUS_FRAME_DISPLACEMENT, "lane handoff must not teleport a vehicle (max frame displacement %.3f; %s)" % [maximum_displacement, maximum_displacement_details])
	for vehicle in traffic:
		if not is_instance_valid(vehicle):
			continue
		var follow := vehicle.get_parent() as PathFollow2D
		_check(follow != null, "%s must remain attached to a PathFollow2D" % vehicle.name)
		if follow == null:
			continue
		var lane := follow.get_parent() as Path2D
		_check(lane != null and (lane.is_in_group("unified_traffic_lane") or lane.is_in_group("unified_lane_connector")), "%s left the unified lane graph" % vehicle.name)
		if lane != null and lane.is_in_group("unified_traffic_lane"):
			_check(follow.loop == bool(lane.get_meta("traffic_lane_loop", false)), "%s has an illegal PathFollow loop" % vehicle.name)

	if _failures.is_empty():
		print("DISTRICT_ONE_TRAFFIC_INTEGRATION: PASS vehicles=%d signalized=%d unsignalized=%d visuals=%d grants=%d connector_entries=%d connector_handoffs=%d max_frame_move=%.3f max_wait=%.3f" % [
			traffic.size(),
			signalized_count,
			unsignalized_count,
			int(telemetry.get("signal_visual_count", -1)),
			int(telemetry.get("reservation_grants", 0)),
			int(telemetry.get("connector_entries", 0)),
			int(telemetry.get("connector_handoffs", 0)),
			maximum_displacement,
			float(telemetry.get("maximum_wait_seconds", 0.0)),
		])
		await _cleanup_and_quit(world, 0)
	else:
		print("DISTRICT_ONE_TRAFFIC_TELEMETRY: %s" % telemetry)
		for failure in _failures:
			push_error("DISTRICT_ONE_TRAFFIC_INTEGRATION: %s" % failure)
		await _cleanup_and_quit(world, 1)


func _cleanup_and_quit(world: Node, exit_code: int) -> void:
	if is_instance_valid(world):
		world.process_mode = Node.PROCESS_MODE_DISABLED
		for audio in world.find_children("*", "AudioStreamPlayer", true, false):
			(audio as AudioStreamPlayer).stop()
		for audio in world.find_children("*", "AudioStreamPlayer2D", true, false):
			(audio as AudioStreamPlayer2D).stop()
	await process_frame
	await process_frame
	await process_frame
	quit(exit_code)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
