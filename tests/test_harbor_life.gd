extends SceneTree

const LAYOUT := preload("res://world/harbor/HarborRoadLayout.gd")
const NETWORK := preload("res://world/harbor/HarborRoadNetwork.gd")
const LIFE := preload("res://world/harbor/HarborLife.gd")
const RAIL := preload("res://world/harbor/HarborRailLine.gd")
const DISTRICT := preload("res://world/harbor/HarborDistrict.gd")
const SAFETY := preload("res://world/harbor/HarborSafety.gd")
const EAST := preload("res://world/harbor/HarborEastDistrict.gd")
const NORTH := preload("res://world/harbor/HarborNorthDistrict.gd")
const FACTORY := preload("res://world/shared/emergency/ModernTrafficFactory.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(4817)
	var fixture := Node2D.new()
	fixture.name = "HarborLifeContract"
	root.add_child(fixture)
	current_scene = fixture
	var layout := LAYOUT.new()
	layout.name = "RoadLayout"
	fixture.add_child(layout)
	var network := NETWORK.new()
	network.name = "RoadNetwork"
	network.provider_paths = [NodePath("../RoadLayout")]
	fixture.add_child(network)
	_test_queue_reservation(network)
	if OS.get_cmdline_user_args().has("--queue-only"):
		fixture.free()
		quit(0 if failures.is_empty() else 1)
		return
	var district := DISTRICT.new()
	district.name = "District"
	fixture.add_child(district)
	var east := EAST.new()
	east.name = "EastDistrict"
	fixture.add_child(east)
	var north := NORTH.new()
	north.name = "NorthDistrict"
	fixture.add_child(north)
	var rail := RAIL.new()
	rail.name = "FreightRail"
	fixture.add_child(rail)
	var safety := SAFETY.new()
	safety.name = "RoadSafety"
	fixture.add_child(safety)
	var life := LIFE.new()
	life.name = "Life"
	fixture.add_child(life)
	life.setup(network)
	await process_frame
	_check(network.get_validation_errors().is_empty(), "Canonical road graph must be valid")
	_check(life.vehicles.size() >= 38, "Expanded streets need traffic distributed across at least 38 lanes")
	_check(life.walkers.size() == 66, "All three districts need 66 distributed pedestrians")
	_check(life.rail_line == rail and life.get_node_or_null("FreightRail") == null, "Life must reuse the scene railway without duplication")
	var before: Dictionary = life.get_population_snapshot()
	_check(bool(before.train.get("active", false)), "Real freight train must be active")
	var positions: Array[Vector2] = []
	for car in life.vehicles:
		positions.append(car.global_position)
	var pedestrian_before: Vector2 = life.walkers[0].global_position
	var railway: PackedVector2Array = life.rail_line.get_rail_graph_data().points_local
	for rail_point in railway:
		var vertical: Dictionary = rail.get_elevated_crossing_data(rail_point)
		if bool(vertical.above_ground):
			for site in district.sites:
				_check(not (site.bounds as Rect2).grow(18.0 + rail.DECK_WIDTH * 0.5 - 0.5).has_point(rail_point), "Rail deck overlaps building/roof %s" % site.id)
	for rect in rail.get_pillar_bounds():
		for site in district.sites:
			_check(not (site.bounds as Rect2).grow(6.0).intersects(rect), "Rail pillar occupies building %s" % site.id)
		for access in district.accesses:
			_check(not (access.bounds as Rect2).intersects(rect), "Rail pillar blocks access %s" % access.id)
	_check(safety.get_safety_data().validation_errors.is_empty(), "Rail and road safety geometry must validate")
	# Run the actual physics loop, not hand-authored changes to actor positions.
	Engine.time_scale = 6.0
	for sample in 35:
		await create_timer(1.0).timeout
		for walker in life.walkers:
			for site in district.sites + east.sites + north.sites:
				_check(not (site.bounds as Rect2).grow(6.0).has_point(walker.global_position), "Pedestrian entered building %s" % site.id)
			for tree in get_nodes_in_group("procedural_tree"):
				_check(walker.global_position.distance_to(tree.global_position + Vector2(0, 5) * tree.crown_scale) > 18.0, "Pedestrian entered a tree trunk")
			for definition in layout.get_road_graph_definitions():
				var points: PackedVector2Array = definition.points
				for segment in range(points.size() - 1):
					var closest := Geometry2D.get_closest_point_to_segment(walker.global_position, points[segment], points[segment + 1])
					_check(closest.distance_to(walker.global_position) >= float(definition.width) * 0.5 + 4.0, "Pedestrian entered a traffic lane: %s on %s" % [walker.name, definition.id])
	Engine.time_scale = 1.0
	var moved := 0
	for index in life.vehicles.size():
		if is_instance_valid(life.vehicles[index]) and life.vehicles[index].global_position.distance_to(positions[index]) > 100.0:
			moved += 1
	var after: Dictionary = life.get_population_snapshot()
	_check(int(after.get("outdoor_destination_pauses", 0)) >= 4, "Outdoor strollers must reach verified destinations and pause")
	_check(moved >= 17, "At least seventeen of twenty-eight vehicles must make real spatial progress; moved=%d" % moved)
	_check(int(after.traffic.get("connector_handoffs", 0)) > 0, "Traffic must transfer between graph lanes")
	_check(int(after.traffic.get("invalid_lane_contracts", 0)) == 0, "No invalid lane contracts")
	_check(float(after.train.progress) > float(before.train.progress) + 1000.0, "Freight train must travel its route")
	_check(life.walkers[0].global_position.distance_to(pedestrian_before) > 20.0, "Pedestrians must walk")
	await _test_local_street_driving(network, life)
	await _test_complete_tunnel_cycle(rail)
	print("HARBOR_LIFE_RESULT failures=%d moved=%d population=%s" % [failures.size(), moved, after])
	fixture.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(0 if failures.is_empty() else 1)


func _test_queue_reservation(network: Node2D) -> void:
	# Deterministic arbitration contract: processing the rear vehicle first must
	# not reserve the intersection behind the head of the same physical queue.
	var controller := LIFE.HarborController.new()
	controller.graph_source = network
	network.get_parent().add_child(controller)
	var graph: Dictionary = network.get_graph_data()
	for junction in graph.junctions:
		for lane in graph.lanes:
			var path: Path2D = network.get_lane_path(String(lane.lane_id))
			var road_index := int(path.get_meta("traffic_road_index", -1))
			if not (junction.roads as Array).has(road_index):
				continue
			if not controller.get_vehicle_permission(StringName(junction.id), road_index):
				continue
			var offset := path.curve.get_closest_offset(path.to_local(network.to_global(junction.position)))
			if offset < 350.0 or offset > path.curve.get_baked_length() - 200.0:
				continue
			var head := FACTORY.spawn_moving_vehicle(path, "QueueHead", "sedan_classic", 0.4, 90.0, 0)
			var rear := FACTORY.spawn_moving_vehicle(path, "QueueRear", "sedan_classic", 0.6, 90.0, 0)
			var head_follow := head.get_parent() as PathFollow2D
			var rear_follow := rear.get_parent() as PathFollow2D
			head_follow.progress = offset - 140.0
			rear_follow.progress = offset - 240.0
			var rear_granted := controller.try_reserve_junction(StringName(junction.id), rear.get_instance_id(), road_index, StringName(lane.lane_id), rear)
			var head_granted := controller.try_reserve_junction(StringName(junction.id), head.get_instance_id(), road_index, StringName(lane.lane_id), head)
			print("HARBOR_QUEUE_RESERVATION rear_first=%s head_second=%s gap=%.1f" % [rear_granted, head_granted, head_follow.progress - rear_follow.progress])
			_check(not rear_granted and head_granted, "Rear vehicle must not own a reservation ahead of the queue head")
			rear_follow.progress = head_follow.progress + 50.0
			_check(controller.try_reserve_junction(StringName(junction.id), head.get_instance_id(), road_index, StringName(lane.lane_id), head), "Existing reservation renewal must never be revoked by queue admission")
			rear_follow.progress = offset - 240.0
			head_follow.progress = offset + 100.0
			controller.release_junction(StringName(junction.id), head.get_instance_id())
			_check(controller.try_reserve_junction(StringName(junction.id), rear.get_instance_id(), road_index, StringName(lane.lane_id), rear), "Once the head passes the junction the rear must receive its reservation")
			head_follow.free()
			rear_follow.free()
			controller.free()
			return
	controller.free()
	_check(false, "Queue arbitration fixture needs a sufficiently long lane approach")


func _test_local_street_driving(network: Node2D, life: Node2D) -> void:
	var graph: Dictionary = network.get_graph_data()
	var local_roads: Array[Dictionary] = []
	for road in graph.roads:
		if is_equal_approx(float(road.width), 72.0):
			local_roads.append(road)
	_check(local_roads.size() == 2, "Two narrow local streets must exist")
	var completed := 0
	Engine.time_scale = 6.0
	for road in local_roads:
		for lane in road.lanes:
			var lane_id := String(lane.lane_id)
			var target_path: Path2D = network.get_lane_path(lane_id)
			var entry: Dictionary = {}
			var exit_connection: Dictionary = {}
			var entry_clearance := -1.0
			for connection in graph.lane_connections:
				if not bool(connection.requires_connector):
					continue
				if String(connection.to_lane_id) == lane_id and String(connection.from_road_id) != String(road.id) and float(connection.exit_curve_offset) < target_path.curve.get_baked_length() * 0.5:
					var clearance := _approach_spawn_clearance(connection, graph, network)
					if clearance > entry_clearance:
						entry = connection
						entry_clearance = clearance
				if String(connection.from_lane_id) == lane_id and String(connection.to_road_id) != String(road.id) and float(connection.entry_curve_offset) > target_path.curve.get_baked_length() * 0.5:
					if exit_connection.is_empty() or String(connection.movement) == "right":
						exit_connection = connection
			_check(not entry.is_empty() and not exit_connection.is_empty(), "Local lane needs real incoming and outgoing connectors: %s" % lane_id)
			if entry.is_empty() or exit_connection.is_empty():
				continue
			var source: Path2D = network.get_lane_path(String(entry.from_lane_id))
			var spawn_offset := -1.0
			for attempt in 100:
				# A position can be physically free but ahead of a car that already
				# owns the junction. Inserting there would artificially strand its
				# reservation behind the newly spawned probe (not an authored trip).
				var state: Dictionary = life.traffic_controller.get_junction_snapshot(int(entry.junction_index))
				if int(state.get("reservation_owner", 0)) != 0:
					await create_timer(0.2).timeout
					continue
				for setback in range(160, int(entry_clearance - 150.0), 20):
					var offset := float(entry.entry_curve_offset) - float(setback)
					var candidate := source.to_global(source.curve.sample_baked(offset, true))
					if FACTORY._position_is_clear(self, candidate) and FACTORY._junction_spawn_is_clear(source, offset / source.curve.get_baked_length(), source.curve.get_baked_length()):
						spawn_offset = offset
						break
				if spawn_offset >= 0.0:
					break
				await create_timer(0.2).timeout
			_check(spawn_offset >= 0.0, "A safe upstream spawn must exist for local route %s" % lane_id)
			if spawn_offset < 0.0:
				continue
			var probe := FACTORY.spawn_moving_vehicle(source, "LocalStreetProbe_%d" % completed, "sedan_classic", spawn_offset / source.curve.get_baked_length(), 90.0, 0)
			var follow := probe.get_parent() as PathFollow2D
			_check(follow.progress < float(entry.entry_curve_offset), "Probe must start before its entrance connector: %s source=%s requested=%.1f actual=%.1f entry=%.1f" % [lane_id, source.name, spawn_offset, follow.progress, float(entry.entry_curve_offset)])
			follow.set_meta("traffic_planned_connection_id", String(entry.connection_id))
			follow.set_meta("traffic_planned_junction_index", int(entry.junction_index))
			var entered := false
			var exited := false
			var travelled := 0.0
			var previous := probe.global_position
			var obstacle_names: Array[String] = []
			for sample in 600:
				await create_timer(0.1).timeout
				if not is_instance_valid(probe):
					break
				travelled += previous.distance_to(probe.global_position)
				previous = probe.global_position
				var current_path := follow.get_parent() as Path2D
				if current_path == target_path and not entered:
					entered = true
					# Prescribe a legal destination, not position/velocity: all turns,
					# signal waits and PathFollow handoffs execute in production AI.
					follow.set_meta("traffic_planned_connection_id", String(exit_connection.connection_id))
					follow.set_meta("traffic_planned_junction_index", int(exit_connection.junction_index))
				if entered and current_path == network.get_lane_path(String(exit_connection.to_lane_id)):
					exited = true
				var vehicle_collision := probe.get_node("Collision") as CollisionShape2D
				var query := PhysicsShapeQueryParameters2D.new()
				query.shape = vehicle_collision.shape
				query.transform = vehicle_collision.global_transform
				query.collision_mask = 1
				query.collide_with_areas = false
				query.exclude = [probe.get_rid()]
				for hit in network.get_world_2d().direct_space_state.intersect_shape(query):
					var obstacle: Node = hit.collider
					if not obstacle_names.has(String(obstacle.get_path())):
						obstacle_names.append(String(obstacle.get_path()))
				if exited and probe.global_position.distance_to((graph.junctions[int(exit_connection.junction_index)] as Dictionary).position) > 210.0:
					break
			if not entered or not exited:
				print("LOCAL_ROUTE_DIAGNOSTIC entry=%s exit=%s follow=%s controller=%s" % [entry.connection_id, exit_connection.connection_id, follow.get_meta_list(), life.traffic_controller.get_junction_snapshot(int(entry.junction_index))])
				var owner_id := int(life.traffic_controller.get_junction_snapshot(int(entry.junction_index)).get("reservation_owner", 0))
				print("LOCAL_RESERVATION_OWNER ", instance_from_id(owner_id) if owner_id != 0 else null)
				print("LOCAL_EXIT_STATE ", life.traffic_controller.get_junction_snapshot(int(exit_connection.junction_index)))
				var exit_owner_id := int(life.traffic_controller.get_junction_snapshot(int(exit_connection.junction_index)).get("reservation_owner", 0))
				print("LOCAL_EXIT_OWNER ", instance_from_id(exit_owner_id) if exit_owner_id != 0 else null)
				for ambient in life.vehicles:
					if ambient.global_position.distance_to(probe.global_position) < 450.0:
						print("LOCAL_NEIGHBOR %s at=%s path=%s planned=%s" % [ambient.name, ambient.global_position, ambient.get_parent().get_parent().name, ambient.get_parent().get_meta("traffic_planned_connection_id", "")])
						print("LOCAL_NEIGHBOR_CONTRACT ", ambient.get("_last_lane_motion_contract"), " zone=", ambient.call("_traffic_control_zone_motion", ambient.get_parent().get_parent(), ambient.get_parent()), " spacing=", ambient.call("_lane_spacing_motion", ambient.get_parent()))
			_check(entered and exited, "Real vehicle must enter and leave local lane %s (position=%s)" % [lane_id, probe.global_position])
			_check(travelled > target_path.curve.get_baked_length() * 0.7, "Local trip must traverse the street, not only touch its entrance: %s" % lane_id)
			_check(obstacle_names.is_empty(), "Local driving envelope intersects obstacles on %s: %s" % [lane_id, obstacle_names])
			if entered and exited:
				completed += 1
			print("HARBOR_LOCAL_DRIVE lane=%s entered=%s exited=%s traveled=%.1f obstacles=%s" % [lane_id, entered, exited, travelled, obstacle_names])
			follow.queue_free()
			await process_frame
	_check(completed == 4, "Both local streets must support entry and exit in both directions")
	_check(int(life.traffic_controller.get_telemetry_snapshot().invalid_lane_contracts) == 0, "Local street driving must retain valid lane contracts")
	Engine.time_scale = 1.0


func _approach_spawn_clearance(connection: Dictionary, graph: Dictionary, network: Node2D) -> float:
	var path: Path2D = network.get_lane_path(String(connection.from_lane_id))
	var previous_junction_offset := 0.0
	for road in graph.roads:
		if String(road.id) != String(connection.from_road_id):
			continue
		for junction in road.junctions:
			var progress := float(junction.road_progress)
			if int(path.get_meta("traffic_direction", 1)) < 0:
				progress = 1.0 - progress
			var offset := progress * path.curve.get_baked_length()
			if offset < float(connection.entry_curve_offset):
				previous_junction_offset = maxf(previous_junction_offset, offset)
	return float(connection.entry_curve_offset) - previous_junction_offset


func _test_complete_tunnel_cycle(rail: Node2D) -> void:
	var train: Node2D = rail.get_node("AmbientTrain")
	var route_length := float(rail.get_route_length())
	var previous := float(train.get_rail_state().progress)
	var travelled := 0.0
	var saw_partial := false
	var saw_hidden := false
	var saw_emergence := false
	Engine.time_scale = 8.0
	var elapsed := 0.0
	while travelled < route_length + 100.0 and elapsed < 180.0:
		await create_timer(0.25).timeout
		elapsed += 0.25
		var state: Dictionary = train.get_rail_state()
		travelled += fposmod(float(state.progress) - previous, route_length)
		previous = float(state.progress)
		var opaque := 0
		for piece in state.pieces:
			if float(piece.opacity) > 0.5:
				opaque += 1
		var visuals: Array = train.get("_freight_visuals")
		for index in visuals.size():
			_check(is_equal_approx(visuals[index].self_modulate.a, float(state.pieces[index + 1].opacity)), "Actual wagon visibility must follow its own tunnel offset")
		saw_partial = saw_partial or (opaque > 0 and opaque < 7)
		saw_emergence = saw_emergence or (saw_hidden and opaque == 7)
		saw_hidden = saw_hidden or opaque == 0
	_check(travelled >= route_length, "Real train must complete an entire visible/underground loop")
	_check(saw_partial and saw_hidden and saw_emergence, "Consist must enter tunnel one piece at a time, disappear underground, then emerge")
	Engine.time_scale = 1.0
	print("HARBOR_TRAIN_CYCLE distance=%.1f partial=%s hidden=%s emerged=%s pillars=%d" % [travelled, saw_partial, saw_hidden, saw_emergence, rail.get_pillar_bounds().size()])


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)
