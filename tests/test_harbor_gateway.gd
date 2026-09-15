extends SceneTree

const PREVIEW := preload("res://world/harbor/HarborPreview.tscn")
const FACTORY := preload("res://emergency/ModernTrafficFactory.gd")
var failures: Array[String] = []
var excluded: Array[RID] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(4181)
	var scene := PREVIEW.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in 4:
		await physics_frame
	var network := scene.get_node("RoadNetwork") as Node2D
	var gateway := scene.get_node_or_null("Gateway") as Node2D
	_check(gateway != null and gateway.has_method("get_map2_connection_contract"), "Actual scene requires the explicit Map 2 gateway contract")
	if gateway == null:
		_finish(scene)
		return
	var contract: Dictionary = gateway.get_map2_connection_contract()
	_check(contract.connected == true and String(contract.transition_scene).ends_with("MountainPass.tscn"), "Official northern gateway advertises Mountain Pass")
	_check(contract.inbound.position == Vector2(5880, -4200) and contract.inbound.direction == Vector2.DOWN, "Inbound gateway position/direction mismatch")
	_check(contract.outbound.position == Vector2(6120, -4200) and contract.outbound.direction == Vector2.UP, "Outbound gateway position/direction mismatch")
	for port in [contract.inbound, contract.outbound]:
		_check(port.width == 96.0 and port.lane_count == 2, "Each carriageway must expose two same-direction lanes")
		_check(gateway.get_node_or_null(port.marker) is Marker2D, "Gateway must have actual authored marker nodes")
	_check(network.get_validation_errors().is_empty(), "Expanded graph must have zero validation warnings")
	var graph: Dictionary = network.get_graph_data()
	for bounds: Rect2 in scene.get_node("RoadLayout").get_reserved_road_rects():
		_check(bounds.size.x > 0.0 and bounds.size.y > 0.0, "North/westbound road reservations must have normalized positive bounds")
	# Additional providers (Ashbend) legitimately extend the production scene.
	# Keep all original roads and verify every configured provider's authored IDs
	# rather than accepting any graph merely because it has more roads.
	var expected_ids: Dictionary = {}
	for provider_path in network.provider_paths:
		var provider: Node = network.get_node(provider_path)
		for definition in provider.get_road_graph_definitions():
			expected_ids[str(provider.name) + "/" + str(definition.id)] = true
	var base_roads := 0
	var base_lanes := 0
	var actual_ids: Dictionary = {}
	for road in graph.roads:
		_check(expected_ids.has(String(road.id)), "Graph road must come from a configured provider: " + String(road.id))
		_check(not actual_ids.has(String(road.id)), "Graph road IDs must remain unique")
		actual_ids[String(road.id)] = true
		if String(road.id).begins_with("RoadLayout/"):
			base_roads += 1
			base_lanes += road.lanes.size()
	_check(graph.roads.size() == expected_ids.size() and base_roads == 22 and base_lanes == 44,
		"Expanded graph must preserve 20 original roads and include every configured provider road exactly once")
	_check(graph.lanes.size() >= 40 and graph.junctions.size() >= 38,
		"Expanded graph must preserve the original lane/junction capacity")
	var highway_roads := {}
	for road in graph.roads:
		if String(road.id) in [String(contract.inbound.road_id), String(contract.outbound.road_id), String(contract.temporary_return_road_id)]:
			highway_roads[String(road.id)] = road
			_check(road.lanes.size() == 2 and not road.open_start and not road.open_end, "Highway/return must have two lanes and no excused loose ends")
			for lane in road.lanes:
				_check(int(lane.direction) == 1 and is_equal_approx(absf(float(lane.offset)), 22.0), "Highway lanes must both follow their carriageway's direction")
	_check(highway_roads.size() == 3, "Both carriageways and the temporary return must be real graph roads")
	_quiet_ambient(scene)
	var space := network.get_world_2d().direct_space_state
	var probe_shape := CircleShape2D.new()
	probe_shape.radius = 9.0
	for road in highway_roads.values():
		for lane in road.lanes:
			var path: Path2D = network.get_lane_path(String(lane.lane_id))
			var length := path.curve.get_baked_length()
			for offset in range(0, int(length), 45):
				var point := path.to_global(path.curve.sample_baked(float(offset)))
				_check(_hits(space, probe_shape, Transform2D(0, point)).is_empty(), "Static obstruction on highway lane %s at %s" % [lane.lane_id, point])
	var car := scene.get_node("PlayerCar") as CharacterBody2D
	var player := scene.get_node("Player") as CharacterBody2D
	car.call("enter_vehicle", player)
	car.set_physics_process(true)
	car.collision_layer = 1
	car.collision_mask = 1
	car.set("max_speed", 240.0)
	await _drive_player(car, Vector2(6142, -2300), Vector2(6142, -3900), -PI * 0.5)
	await _drive_player(car, Vector2(5858, -3900), Vector2(5858, -2300), PI * 0.5)
	car.velocity = Vector2.ZERO
	car.set_physics_process(false)
	car.collision_layer = 0
	car.global_position = Vector2(5720, -2300)
	Engine.time_scale = 6.0
	var completed := 0
	if highway_roads.size() == 3:
		for lane in highway_roads[String(contract.outbound.road_id)].lanes:
			if await _drive_return_ai(network, graph, lane, contract):
				completed += 1
	Engine.time_scale = 1.0
	_check(completed == 2, "Both outbound lanes must navigate the real return and rejoin the inbound carriageway")
	print("HARBOR_GATEWAY_RESULT failures=%d real_return_routes=%d connected_map2=%s" % [failures.size(), completed, contract.connected])
	_finish(scene)


func _quiet_ambient(node: Node) -> void:
	# Removing ambient followers is necessary: production lane spacing still
	# observes frozen siblings even if their collision layer has been disabled.
	if node is PathFollow2D and node.get_child_count() > 0 and node.get_child(0) is DemoTrafficVehicle:
		node.queue_free()
		return
	if node is PhysicsBody2D and not node is StaticBody2D:
		var body := node as PhysicsBody2D
		excluded.append(body.get_rid())
		body.set_physics_process(false)
		body.collision_layer = 0
	for child in node.get_children():
		_quiet_ambient(child)


func _drive_player(car: CharacterBody2D, start: Vector2, destination: Vector2, heading: float) -> void:
	Input.action_release("ui_up")
	car.global_position = start
	car.velocity = Vector2.ZERO
	car.rotation = heading
	await physics_frame
	Input.action_press("ui_up")
	var collision := false
	for _frame in 720:
		await physics_frame
		collision = collision or car.get_slide_collision_count() > 0
		if car.global_position.distance_to(destination) < 16.0:
			break
	Input.action_release("ui_up")
	_check(not collision and car.global_position.distance_to(destination) < 20.0, "Actual PlayerCar failed carriageway traversal: %s -> %s final=%s collision=%s" % [start, destination, car.global_position, collision])
	print("HARBOR_HIGHWAY_PLAYER start=%s end=%s collision=%s" % [start, car.global_position, collision])
	car.velocity = Vector2.ZERO


func _drive_return_ai(network: Node2D, graph: Dictionary, source_lane: Dictionary, contract: Dictionary) -> bool:
	var lane_suffix := String(source_lane.lane_id).get_file()
	var entry := _connection(graph, String(source_lane.lane_id), String(contract.temporary_return_road_id), lane_suffix)
	_check(not entry.is_empty(), "Outbound lane needs a legal connector to the temporary return")
	if entry.is_empty():
		return false
	var exit_connection := _connection(graph, String(entry.to_lane_id), String(contract.inbound.road_id), lane_suffix)
	_check(not exit_connection.is_empty(), "Temporary return needs a legal connector back south")
	if exit_connection.is_empty():
		return false
	_check(String(exit_connection.to_lane_id).get_file() == lane_suffix, "Each outbound probe must cover its corresponding distinct inbound lane")
	var source: Path2D = network.get_lane_path(String(source_lane.lane_id))
	var probe := FACTORY.spawn_moving_vehicle(source, "HighwayReturnProbe", "sedan_classic", 0.18, 155.0, 0)
	var follow := probe.get_parent() as PathFollow2D
	follow.set_meta("traffic_planned_connection_id", String(entry.connection_id))
	follow.set_meta("traffic_planned_junction_index", int(entry.junction_index))
	var entered_return := false
	var returned_south := false
	var travel := 0.0
	var previous := probe.global_position
	var blocked := false
	var collision_shape := probe.get_node("Collision") as CollisionShape2D
	for _sample in 700:
		await create_timer(0.1).timeout
		travel += previous.distance_to(probe.global_position)
		previous = probe.global_position
		var path := follow.get_parent() as Path2D
		if path == network.get_lane_path(String(entry.to_lane_id)) and not entered_return:
			entered_return = true
			follow.set_meta("traffic_planned_connection_id", String(exit_connection.connection_id))
			follow.set_meta("traffic_planned_junction_index", int(exit_connection.junction_index))
		var hits := _hits(network.get_world_2d().direct_space_state, collision_shape.shape, collision_shape.global_transform, probe.get_rid())
		blocked = blocked or not hits.is_empty()
		if entered_return and path == network.get_lane_path(String(exit_connection.to_lane_id)) and probe.global_position.y > -2450.0:
			returned_south = true
			break
	_check(entered_return and returned_south and travel > 3400.0 and not blocked, "Real highway AI failed north/return/south trip lane=%s position=%s travel=%.1f entered=%s returned=%s blocked=%s" % [source_lane.lane_id, probe.global_position, travel, entered_return, returned_south, blocked])
	print("HARBOR_HIGHWAY_AI lane=%s travel=%.1f entered_return=%s returned_south=%s blocked=%s" % [source_lane.lane_id, travel, entered_return, returned_south, blocked])
	follow.queue_free()
	await process_frame
	return entered_return and returned_south and travel > 3400.0 and not blocked


func _connection(graph: Dictionary, from_lane: String, to_road: String, lane_suffix: String) -> Dictionary:
	for connection in graph.lane_connections:
		if String(connection.from_lane_id) == from_lane and String(connection.to_road_id) == to_road and String(connection.to_lane_id).get_file() == lane_suffix and bool(connection.requires_connector):
			return connection
	return {}


func _hits(space: PhysicsDirectSpaceState2D, shape: Shape2D, transform: Transform2D, self_rid: RID = RID()) -> Array[Dictionary]:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = transform
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = excluded.duplicate()
	if self_rid.is_valid():
		query.exclude.append(self_rid)
	return space.intersect_shape(query, 16)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(scene: Node) -> void:
	Input.action_release("ui_up")
	Engine.time_scale = 1.0
	for failure in failures:
		push_error("HARBOR_GATEWAY: " + failure)
	scene.queue_free()
	quit(0 if failures.is_empty() else 1)
