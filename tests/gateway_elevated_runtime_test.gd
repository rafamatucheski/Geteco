extends SceneTree

## Natural runtime contract for the four-lane gateway/viaduct composition.
## The test loads the real Main scene and only observes actors spawned by the
## game. It never creates, repositions or advances a vehicle/train manually.

const MAIN_SCENE := preload("res://legacy/Main.tscn")
const GATEWAY_ROAD_ID := "Bairro1Expansion/gateway_spine"
const SAMPLE_PHYSICS_FRAMES := 180
const MIN_CENTERLINE_CLEARANCE := 1.0

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var world := MAIN_SCENE.instantiate()
	var district := world.get_node("DistrictOneComplete")
	var graph := district.get_node("UnifiedRoadNetwork") as Node2D
	var controller := district.get_node_or_null("JunctionTrafficController")
	if controller != null:
		# Match normal runtime discovery while removing ready-order ambiguity.
		controller.set("graph_source", graph)
	root.add_child(world)
	current_scene = world
	for _warmup in 16:
		await process_frame

	var highway := district.get_node_or_null("District1HighwayExit") as Node2D
	var rail_line := district.get_node_or_null("DistrictRailLine") as Node2D
	var train := rail_line.get_node_or_null("AmbientTrain") as Node2D if rail_line != null else null
	var deck := highway.get_node_or_null("ElevatedDeckOverlay") as Node2D if highway != null else null
	var detector := highway.get_node_or_null("ElevatedDeckBodyOrder") as Area2D if highway != null else null
	_check(highway != null and highway.has_method("get_elevated_corridor_data"), "highway must publish elevated geodata")
	_check(graph != null and graph.has_method("get_graph_data"), "UnifiedRoadNetwork graph API is unavailable")
	_check(rail_line != null, "DistrictRailLine is unavailable")
	_check(train != null, "natural AmbientTrain is unavailable")
	_check(deck != null, "ElevatedDeckOverlay is unavailable")
	_check(detector != null, "ElevatedDeckBodyOrder is unavailable")
	if highway == null or graph == null:
		_finish(world)
		return

	var elevated_data: Dictionary = highway.call("get_elevated_corridor_data")
	var graph_data: Dictionary = graph.call("get_graph_data")
	var published_lanes: Array = elevated_data.get("lane_definitions", [])
	var published_offsets: Array = elevated_data.get("lane_offsets", [])
	var separators: Array = elevated_data.get("lane_separator_offsets", [])
	var gateway_lanes := _gateway_lanes(graph_data.get("lanes", []))
	_check(published_lanes.size() == 4, "elevated geometry must publish four lane definitions")
	_check(published_offsets.size() == 4, "elevated geometry must publish four lane offsets")
	_check(separators.size() == 2, "elevated geometry must publish its two lane separators")
	_check(gateway_lanes.size() == 4, "canonical gateway must generate four directed lanes")
	_check(_float_arrays_match(published_offsets, [-59.0, -20.0, 20.0, 59.0]), "gateway lane centres must remain -59/-20/+20/+59")
	_check(_float_arrays_match(separators, [-41.0, 41.0]), "gateway separators must remain -41/+41")
	_check(_published_direction_at(published_lanes, -59.0) == -1 and _published_direction_at(published_lanes, -20.0) == -1, "negative gateway carriageway must travel north/reverse")
	_check(_published_direction_at(published_lanes, 20.0) == 1 and _published_direction_at(published_lanes, 59.0) == 1, "positive gateway carriageway must travel south/forward")
	_validate_lane_contract(gateway_lanes, published_lanes, separators)
	_validate_highway_paths(highway, published_lanes)

	var observed_gateway_vehicles := {}
	var sample_gateway_vehicle: CharacterBody2D = null
	var observed_detector_vehicle := false
	for _frame_index in SAMPLE_PHYSICS_FRAMES:
		await physics_frame
		for candidate in get_nodes_in_group("district_one_traffic"):
			if not candidate is CharacterBody2D:
				continue
			var vehicle := candidate as CharacterBody2D
			var follow := vehicle.get_parent() as PathFollow2D
			var lane := follow.get_parent() as Path2D if follow != null else null
			if lane == null or not lane.is_in_group("unified_traffic_lane"):
				continue
			if String(lane.get_meta("traffic_road_id", "")) != GATEWAY_ROAD_ID:
				continue
			observed_gateway_vehicles[vehicle.get_instance_id()] = true
			if sample_gateway_vehicle == null:
				sample_gateway_vehicle = vehicle
			_validate_vehicle_separator_clearance(vehicle, lane, separators)
		if detector != null:
			for overlapping_body in detector.get_overlapping_bodies():
				if overlapping_body is CharacterBody2D and overlapping_body.is_in_group("district_one_traffic"):
					observed_detector_vehicle = true
				sample_gateway_vehicle = overlapping_body as CharacterBody2D

	_check(not observed_gateway_vehicles.is_empty(), "natural district population must exercise gateway lanes")
	_check(observed_detector_vehicle, "ElevatedDeckBodyOrder must naturally detect canonical traffic during the sample")
	_validate_render_order(rail_line, train, deck, sample_gateway_vehicle)
	_validate_detector_mask(detector, sample_gateway_vehicle, elevated_data)
	_finish(world, observed_gateway_vehicles.size())


func _gateway_lanes(source: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for lane_value in source:
		var lane := lane_value as Dictionary
		if String(lane.get("road_id", "")) == GATEWAY_ROAD_ID:
			result.append(lane)
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return float(first.get("offset", 0.0)) < float(second.get("offset", 0.0))
	)
	return result


func _validate_lane_contract(graph_lanes: Array[Dictionary], published_lanes: Array, separators: Array) -> void:
	for published_value in published_lanes:
		var published := published_value as Dictionary
		var expected_offset := float(published.get("offset", INF))
		var graph_lane := _lane_at_offset(graph_lanes, expected_offset)
		_check(not graph_lane.is_empty(), "graph is missing published gateway offset %.1f" % expected_offset)
		if graph_lane.is_empty():
			continue
		_check(int(graph_lane.get("direction", 0)) == int(published.get("direction", 0)), "gateway direction differs from elevated provider at offset %.1f" % expected_offset)
		_check(String(graph_lane.get("lane_id", "")).ends_with(String(published.get("lane_id", ""))), "gateway lane id differs from elevated provider at offset %.1f" % expected_offset)
		for separator_value in separators:
			var distance := absf(expected_offset - float(separator_value))
			_check(distance > MIN_CENTERLINE_CLEARANCE, "gateway lane centre %.1f overlaps painted separator %.1f" % [expected_offset, float(separator_value)])


func _validate_highway_paths(highway: Node2D, published_lanes: Array) -> void:
	var container := highway.get_node_or_null("HighwayLanePaths")
	_check(container != null, "HighwayLanePaths is unavailable at runtime")
	if container == null:
		return
	var paths: Array[Path2D] = []
	for child in container.get_children():
		if child is Path2D:
			paths.append(child as Path2D)
	_check(paths.size() == published_lanes.size(), "highway helper paths must mirror the published gateway lane count")
	for published_value in published_lanes:
		var published := published_value as Dictionary
		var expected_offset := float(published.get("offset", INF))
		var matched: Path2D = null
		for path in paths:
			if is_equal_approx(float(path.get_meta("traffic_lane_offset", INF)), expected_offset):
				matched = path
				break
		_check(matched != null, "highway helper path is missing offset %.1f" % expected_offset)
		if matched != null:
			_check(int(matched.get_meta("traffic_direction", 0)) == int(published.get("direction", 0)), "highway helper direction differs at offset %.1f" % expected_offset)


func _validate_vehicle_separator_clearance(vehicle: CharacterBody2D, lane: Path2D, separators: Array) -> void:
	var lane_offset := float(lane.get_meta("traffic_lane_offset", INF))
	var collision := vehicle.get_node_or_null("Collision") as CollisionShape2D
	var half_vehicle_width := 0.0
	if collision != null and collision.shape is RectangleShape2D:
		half_vehicle_width = (collision.shape as RectangleShape2D).size.y * 0.5
	for separator_value in separators:
		var separator := float(separator_value)
		var clearance := absf(lane_offset - separator) - half_vehicle_width
		_check(clearance >= MIN_CENTERLINE_CLEARANCE, "%s footprint overlaps gateway separator %.1f (lane=%.1f clearance=%.2f)" % [vehicle.name, separator, lane_offset, clearance])


func _validate_render_order(rail_line: Node2D, train: Node2D, deck: Node2D, gateway_vehicle: CharacterBody2D) -> void:
	if rail_line == null or train == null or deck == null:
		return
	var rail_z := _effective_z(rail_line)
	var train_z := _effective_z(train)
	var deck_z := _effective_z(deck)
	_check(rail_z < train_z, "rail bed must render below locomotive (%d !< %d)" % [rail_z, train_z])
	_check(train_z < deck_z, "locomotive must render below elevated deck (%d !< %d)" % [train_z, deck_z])
	var wagon_count := 0
	for child in train.get_children():
		if child is CanvasItem and String(child.name).begins_with("FreightWagon_"):
			wagon_count += 1
			var wagon_z := _effective_z(child as CanvasItem)
			_check(rail_z < wagon_z and wagon_z < deck_z, "%s must render between rail and deck (%d < %d < %d)" % [child.name, rail_z, wagon_z, deck_z])
	_check(wagon_count > 0, "natural train must contain freight wagon visuals")
	if gateway_vehicle != null:
		var vehicle_z := _effective_z(gateway_vehicle)
		_check(deck_z < vehicle_z, "gateway traffic must render above deck (%d !< %d)" % [deck_z, vehicle_z])


func _validate_detector_mask(detector: Area2D, gateway_vehicle: CharacterBody2D, elevated_data: Dictionary) -> void:
	if detector == null or gateway_vehicle == null:
		return
	var vehicle_layer := gateway_vehicle.collision_layer
	_check(vehicle_layer != 0, "gateway TrafficVehicle must expose a collision layer")
	_check((detector.collision_mask & vehicle_layer) != 0, "ElevatedDeckBodyOrder mask does not cover TrafficVehicle layer %d" % vehicle_layer)
	_check(detector.collision_mask == int(elevated_data.get("body_collision_mask", -1)), "detector mask differs from published elevated geodata")


func _lane_at_offset(lanes: Array[Dictionary], expected_offset: float) -> Dictionary:
	for lane in lanes:
		if is_equal_approx(float(lane.get("offset", INF)), expected_offset):
			return lane
	return {}


func _published_direction_at(lanes: Array, expected_offset: float) -> int:
	for lane_value in lanes:
		var lane := lane_value as Dictionary
		if is_equal_approx(float(lane.get("offset", INF)), expected_offset):
			return int(lane.get("direction", 0))
	return 0


func _float_arrays_match(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index in actual.size():
		if not is_equal_approx(float(actual[index]), float(expected[index])):
			return false
	return true


func _effective_z(item: CanvasItem) -> int:
	var result := item.z_index
	if not item.z_as_relative:
		return result
	var ancestor := item.get_parent()
	while ancestor != null:
		if ancestor is CanvasItem:
			var canvas_ancestor := ancestor as CanvasItem
			result += canvas_ancestor.z_index
			if not canvas_ancestor.z_as_relative:
				break
		ancestor = ancestor.get_parent()
	return result


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)


func _finish(world: Node, observed_vehicle_count: int = 0) -> void:
	if current_scene == world:
		current_scene = null
	if is_instance_valid(world):
		if world.get_parent() != null:
			world.get_parent().remove_child(world)
		world.free()
	if _failures.is_empty():
		print("GATEWAY_ELEVATED_RUNTIME: PASS natural_gateway_vehicles=%d" % observed_vehicle_count)
		quit(0)
	else:
		for failure in _failures:
			push_error("GATEWAY_ELEVATED_RUNTIME: %s" % failure)
		quit(1)
