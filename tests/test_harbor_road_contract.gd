extends SceneTree

const LAYOUT_SCRIPT := preload("res://world/harbor/HarborRoadLayout.gd")
const NETWORK_SCRIPT := preload("res://world/harbor/HarborRoadNetwork.gd")
const ROUTER_SCRIPT := preload("res://geodata/roads/EmergencyLaneRouter.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := Node2D.new()
	fixture.name = "HarborContract"
	root.add_child(fixture)
	var layout := LAYOUT_SCRIPT.new()
	layout.name = "RoadLayout"
	fixture.add_child(layout)
	var network := NETWORK_SCRIPT.new()
	network.name = "RoadNetwork"
	network.provider_paths = [NodePath("../RoadLayout")]
	fixture.add_child(network)
	await process_frame
	var definitions: Array[Dictionary] = layout.get_road_graph_definitions()
	_check(definitions.size() == 22, "Expected fourteen harbor streets, three northern streets and three highway sections")
	for definition in definitions:
		_check(definition.points is PackedVector2Array, "Points must be packed Vector2 data")
		_check((definition.points as PackedVector2Array).size() >= 2, "Every street needs geometry")
		_check((not definition.open_start and not definition.open_end) or String(definition.id).begins_with("mountain_bridge_"), "Only the official region boundary has open ends")
		for point in definition.points:
			_check(point.y <= 2200.0, "Street intrudes into the independent southern rail corridor")
	var errors: Array[String] = network.get_validation_errors()
	_check(errors.is_empty(), "Validation: %s" % [errors])
	var graph: Dictionary = network.get_graph_data()
	var roads: Array = graph.get("roads", [])
	var lanes: Array = graph.get("lanes", [])
	var junctions: Array = graph.get("junctions", [])
	_check(roads.size() == 22, "Shared network must collect all twenty authored roads")
	_check(lanes.size() == 44, "Shared network must collect forty lanes, including directed highway carriageways")
	_check(junctions.size() == 38, "Northern streets and the temporary highway return must form 38 real junctions")
	var local_count := 0
	for road in roads:
		if is_equal_approx(float(road.width), 72.0):
			local_count += 1
			_check((road.lanes as Array).size() == 2, "Each narrow local road must retain opposing lanes")
	_check(local_count == 2, "Exactly two new local streets must have authored 72px widths")
	for junction in junctions:
		var position: Vector2 = junction.position
		_check(position.x <= 3200.0 or position.x >= 4380.0, "Bridge over water must not generate a fictitious junction")
		_check(not is_equal_approx(position.y, 892.0), "Elevated railway must not become a road lane junction")
	var adjacency := {}
	for lane in lanes:
		adjacency[String(lane.lane_id)] = []
		var path: Path2D = network.get_lane_path(String(lane.lane_id))
		_check(path != null and path.curve != null, "Lane must have a real traversable Path2D")
	for connection in graph.get("lane_connections", []):
		var from_id := String(connection.from_lane_id)
		var to_id := String(connection.to_lane_id)
		_check(adjacency.has(from_id) and adjacency.has(to_id), "Connection references unknown lane")
		if adjacency.has(from_id):
			adjacency[from_id].append(to_id)
	for start_id in adjacency:
		var visited := {start_id: true}
		var pending: Array = [start_id]
		while not pending.is_empty():
			var current: String = pending.pop_front()
			for destination in adjacency.get(current, []):
				if not visited.has(destination):
					visited[destination] = true
					pending.append(destination)
		for target_id in adjacency:
			if String(start_id).contains("mountain_bridge_outbound"): continue
			if String(target_id).contains("mountain_bridge_inbound"): continue
			_check(visited.has(target_id), "Lane %s cannot reach %s" % [start_id,target_id])
	# Also exercise the real progress-aware router, not only lane-level BFS:
	# an island-to-island route must leave its starting street and cross Foundry.
	var probe := CharacterBody2D.new()
	fixture.add_child(probe)
	for trip in [
		[Vector2(770, 2230), Vector2(5800, 2230)],
		[Vector2(5800, 2170), Vector2(770, 2170)],
	]:
		probe.position = trip[0]
		var router := ROUTER_SCRIPT.new()
		router.guidance(probe, trip[1])
		_check(router.legs.size() >= 3, "Inter-island route must transition between streets")
		var crosses_bridge := false
		for leg in router.legs:
			var path := leg.path as Path2D
			_check(float(leg.end) >= float(leg.start), "Inter-island route cannot drive backwards on a directed lane")
			if path != null and String(path.get_meta("traffic_road_id", "")).ends_with("/foundry_avenue"):
				var start_point := path.to_global(path.curve.sample_baked(float(leg.start)))
				var end_point := path.to_global(path.curve.sample_baked(float(leg.end)))
				if minf(start_point.x, end_point.x) <= 3200.0 and maxf(start_point.x, end_point.x) >= 4380.0:
					crosses_bridge = true
		_check(crosses_bridge, "Inter-island route must traverse the continuous bridge lane")
		router.reset()
	print("HARBOR_ROAD_CONTRACT: roads=%d lanes=%d junctions=%d errors=%d failures=%d" % [
		roads.size(), lanes.size(), junctions.size(), errors.size(), _failures.size()])
	for failure in _failures:
		push_error(failure)
	fixture.free()
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
