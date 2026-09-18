extends Node2D
## One persistent coach physically links Harbor's terminal and a mountain village.
const COACH := preload("res://geodata/transit/HarborMountainCoach.gd")
const PLANNER := preload("res://geodata/transit/RegionalCoachLanePlanner.gd")
const HARBOR_BERTH := Vector2(1930, 1220)
const MOUNTAIN_BERTH := Vector2(7500, -1760)
const STATION_DWELL := 12.0
var world: Node2D
var stream: Node
var network: Node2D
var coach: Node2D
var harbor_lane: Path2D
var mountain_lane: Path2D
var access_lane: Path2D
var outbound_lane: Path2D
var inbound_lane: Path2D
var harbor_offset := 0.0
var mountain_entry_offset := 0.0
var mountain_exit_offset := 0.0
var mountain_berth_offset := 0.0
var state := "preparing"
var city_legs: Array[Dictionary] = []
var mountain_arrivals := 0
var harbor_arrivals := 0
var departures := 0
var completed_round_trips := 0
var max_handoff_displacement := 0.0
var berth_owner: Node2D
var exchange_started := false
var dwell_elapsed := 0.0
var _configured := false
var _initializing := false
var _clock := 0.0
var _last_lane: Path2D
var _connection_by_path: Dictionary = {}
var _return_merge_committed := false

func configure(harbor_world: Node2D, continuous_stream: Node) -> void:
	world = harbor_world
	stream = continuous_stream
	network = world.get_node("RoadNetwork")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("regional_coach_service")
	add_to_group("traffic_spawn_exclusion")
	set_meta("traffic_spawn_exclusion_rect", Rect2(HARBOR_BERTH - Vector2(82, 60), Vector2(164, 120)))
	_configured = true
	call_deferred("_initialize_service")

func _initialize_service() -> void:
	if _initializing or not _configured:
		return
	_initializing = true
	# This graph's long turns see sidewalk residents outside their actual path.
	# Scope corridor-aware pedestrian yielding to Harbor's authored connectors.
	for connection in network.get_graph_data().lane_connections:
		var connector: Path2D = connection.get("path")
		if is_instance_valid(connector) and connector.is_in_group("unified_lane_connector"):
			connector.set_meta("curved_pedestrian_corridor", true)
	# Long-coach corner sweeps need more setback than the ordinary car lanes.
	# Move physical masts and 3D presentation together onto the wider sidewalks.
	for signal_view in get_tree().get_nodes_in_group("junction_signal_visual"):
		for corner in [Vector2(5880, -2000), Vector2(4650, -1100), Vector2(5550, -2000), Vector2(5550, -1100), Vector2(4650, 400)]:
			if signal_view.global_position.distance_to(corner) < 5.0:
				signal_view.extra_sidewalk_clearance = maxf(signal_view.extra_sidewalk_clearance, 26.0)
				signal_view._rebuild_posts()
				break
	for lane in get_tree().get_nodes_in_group("unified_traffic_lane"):
		var id := String(lane.get_meta("traffic_road_id", "")).get_file()
		if id == "market_street" and int(lane.get_meta("traffic_direction", 0)) == 1:
			harbor_lane = lane
		elif id == "mountain_bridge_outbound":
			outbound_lane = lane
		elif id == "mountain_bridge_inbound":
			inbound_lane = lane
		elif id == "map2_temporary_return":
			# The 240px link is shorter than two junction envelopes plus a coach.
			# Retain both reservations during its connecting maneuver.
			lane.set_meta("compound_junction_reservations", true)
	if harbor_lane == null or outbound_lane == null or inbound_lane == null:
		push_error("Regional coach requires the Harbor market and mountain bridge lanes")
		state = "missing_road_connection"
		return
	harbor_offset = harbor_lane.curve.get_closest_offset(harbor_lane.to_local(HARBOR_BERTH))
	# Pre-warm the regional coach model so meshes and materials compile during world init, not during gameplay
	var prewarm_model = preload("res://geodata/transit/RegionalIntercityCoachModel.gd").new()
	prewarm_model.free()
	# Terminal operations and the local service are also created deferred during
	# HarborGame startup. Let their collision bodies reach the physics server
	# before testing this shared street berth; otherwise both long coaches can
	# be spawned on the same frame at virtually the same position and neither
	# can recover from the overlap.
	await get_tree().physics_frame

	# Pre-instantiate the regional coach early during world startup so its nodes, SubViewport,
	# and collision structures do not cause a frame drop when the berth later clears.
	var follow := PathFollow2D.new()
	follow.name = "RegionalCoachFollow"
	follow.loop = false
	harbor_lane.add_child(follow)
	follow.progress = harbor_offset
	coach = preload("res://cars/traffic/TrafficVehicle.tscn").instantiate()
	coach.set_script(COACH)
	coach.station = self
	coach.stop_lane = harbor_lane
	coach.stop_offset = harbor_offset
	coach.visible = false
	coach.process_mode = Node.PROCESS_MODE_DISABLED
	var original_col_layer: int = coach.collision_layer
	var original_col_mask: int = coach.collision_mask
	coach.collision_layer = 0
	coach.collision_mask = 0
	follow.add_child(coach)
	if coach.collision != null:
		coach.collision.disabled = true
	var ped_col = coach.pedestrian_hitbox.get_node_or_null("Collision") as CollisionShape2D if coach.pedestrian_hitbox else null
	if ped_col != null:
		ped_col.disabled = true

	while is_inside_tree() and not _harbor_berth_clear():
		await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return

	# Berth is now clear: activate the coach seamlessly without construction hitch
	coach.visible = true
	coach.process_mode = Node.PROCESS_MODE_PAUSABLE
	coach.collision_layer = original_col_layer
	coach.collision_mask = original_col_mask
	if coach.collision != null:
		coach.collision.disabled = false
	if ped_col != null:
		ped_col.disabled = false
	state = "harbor_dwell"
	dwell_elapsed = 0.0
	# The city leg does not require a resident mountain scene. Prepare it ahead
	# of this scheduled service or the player, not while parked at the terminal.
	while is_inside_tree() and is_instance_valid(coach) and not coach._detached_from_lane and not stream.ready_for_crossing and not stream.building and coach.global_position.y >= -1000.0:
		await get_tree().create_timer(0.2).timeout
	if not is_inside_tree() or not is_instance_valid(coach) or coach._detached_from_lane:
		_initializing = false
		return
	stream.ensure_mountain()
	while is_inside_tree() and not stream.ready_for_crossing:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	mountain_lane = stream.mountain.get_node("MountainTraffic").lane
	_build_access()
	if state in ["outbound", "border_wait"]:
		coach.stop_lane = access_lane
		coach.stop_offset = mountain_berth_offset
		if state == "border_wait": coach.depart()
		state = "outbound"
	_initializing = false

func _harbor_berth_clear() -> bool:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(145, 45)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = harbor_lane.global_transform * harbor_lane.curve.sample_baked_with_rotation(harbor_offset, true)
	query.collision_mask = 2
	# The opening pauses gameplay before the first physics sync. A physics_frame
	# signal still fires then, but newly added coaches may be absent from space
	# queries. Check their authored live hulls as well, without waiting for the
	# broadphase to admit them (or spawning a second coach inside the first).
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if not vehicle is CollisionObject2D or vehicle.get_world_2d() != get_world_2d(): continue
		if (vehicle.collision_layer & 2) == 0: continue
		var hull := vehicle.get_node_or_null("Collision") as CollisionShape2D
		if hull == null or hull.disabled or hull.shape == null: continue
		if shape.collide(query.transform, hull.shape, hull.global_transform): return false
	return get_world_2d().direct_space_state.intersect_shape(query).is_empty()

func _build_access() -> void:
	var region: Node2D = stream.mountain
	var half := mountain_lane.curve.get_baked_length() * 0.5
	mountain_entry_offset = _closest_in_range(Vector2(6901, -1566), 0.0, half)
	mountain_exit_offset = _closest_in_range(Vector2(6694, -1600), half, mountain_lane.curve.get_baked_length())
	var entry_pose := mountain_lane.curve.sample_baked_with_rotation(mountain_entry_offset, true)
	var exit_pose := mountain_lane.curve.sample_baked_with_rotation(mountain_exit_offset, true)
	access_lane = Path2D.new()
	access_lane.name = "MountainVillageCoachAccess"
	access_lane.curve = Curve2D.new()
	access_lane.curve.bake_interval = 4.0
	access_lane.curve.add_point(entry_pose.origin, Vector2.ZERO, entry_pose.x * 90.0)
	_add_access_point(Vector2(6840, -1740), Vector2(0, 95), Vector2(0, -95))
	_add_access_point(Vector2(7010, -1870), Vector2(-110, 0), Vector2(110, 0))
	_add_access_point(Vector2(7240, -1760), Vector2(-110, 0), Vector2(110, 0))
	_add_access_point(MOUNTAIN_BERTH, Vector2(-95, 0), Vector2(95, 0))
	_add_access_point(Vector2(7700, -1760), Vector2(-65, 0), Vector2(49.706, 0))
	_add_access_point(Vector2(7790, -1850), Vector2(0, 49.706), Vector2(0, -49.706))
	_add_access_point(Vector2(7700, -1940), Vector2(49.706, 0), Vector2(-110, 0))
	_add_access_point(Vector2(7010, -1940), Vector2(110, 0), Vector2(-80, 0))
	_add_access_point(Vector2(6880, -1890), Vector2(45, -50), Vector2(-45, 50))
	_add_access_point(Vector2(6750, -1810), Vector2(60, -45), Vector2(-60, 45))
	_add_access_point(Vector2(6630, -1680), Vector2(-20, -60), Vector2(20, 60))
	access_lane.curve.add_point(exit_pose.origin, -exit_pose.x * 65.0, Vector2.ZERO)
	region.add_child(access_lane)
	access_lane.add_to_group("unified_traffic_lane")
	access_lane.set_meta("traffic_lane_id", "mountain_village_coach_access")
	access_lane.set_meta("traffic_road_id", "mountain_village_coach_access")
	access_lane.set_meta("traffic_lane_loop", false)
	access_lane.set_meta("mountain_traffic", true)
	mountain_berth_offset = access_lane.curve.get_closest_offset(MOUNTAIN_BERTH)
	# Pavement follows exactly the same curve as the moving coach.
	var paved := Line2D.new()
	paved.name = "VillageCoachPavement"
	paved.points = access_lane.curve.get_baked_points()
	paved.width = 88.0
	paved.default_color = preload("res://geodata/roads/BridgeSurfaceStyle.gd").ASPHALT
	paved.joint_mode = Line2D.LINE_JOINT_ROUND
	paved.begin_cap_mode = Line2D.LINE_CAP_ROUND
	paved.end_cap_mode = Line2D.LINE_CAP_ROUND
	# The highway owns the junction surface and its continuous lane markings.
	# Keep the branch's rounded endpoints underneath that black asphalt.
	paved.z_index = 1
	region.add_child(paved)
	preload("res://world/mountain_pass/MountainGroundMaterials.gd").grain(paved)
	var center_line := Line2D.new()
	center_line.points = paved.points
	center_line.width = 2.0
	center_line.default_color = Color("c9c7a4")
	center_line.z_index = 1
	region.add_child(center_line)
	region.road.register_coach_access(access_lane.curve)

func _add_access_point(point: Vector2, incoming: Vector2, outgoing: Vector2) -> void:
	access_lane.curve.add_point(point, incoming, outgoing)

func _closest_in_range(point: Vector2, begin: float, end: float) -> float:
	var result := begin
	var distance := INF
	var offset := begin
	while offset <= end:
		var candidate := mountain_lane.curve.sample_baked(offset, true)
		var separation := candidate.distance_squared_to(point)
		if separation < distance:
			distance = separation
			result = offset
		offset += 2.0
	return result

func _process(delta: float) -> void:
	if coach == null or coach.is_broken or coach._detached_from_lane:
		return
	_clock += delta
	dwell_elapsed += delta
	if _clock < 0.1:
		return
	_clock = 0.0
	var follow := coach.get_parent() as PathFollow2D
	if follow == null:
		return
	var lane := follow.get_parent() as Path2D
	if lane != _last_lane:
		_last_lane = lane
		if lane == mountain_lane and state == "outbound":
			state = "mountain_approach"
		if lane == inbound_lane and state == "returning":
			_plan_city(harbor_lane, harbor_offset)
	if state == "harbor_dwell" and dwell_elapsed > STATION_DWELL:
		if _plan_city(outbound_lane, outbound_lane.curve.get_baked_length()):
			coach.stop_lane = access_lane if access_lane != null else outbound_lane
			coach.stop_offset = mountain_berth_offset if access_lane != null else outbound_lane.curve.get_baked_length() - 2.0
			coach.depart()
			state = "outbound"
			departures += 1
	elif state == "mountain_approach" and lane == mountain_lane and absf(follow.progress - mountain_entry_offset) < 0.75:
		if _transfer(follow, access_lane, 0.0):
			state = "village_approach"
	elif state == "outbound" and mountain_lane != null and lane == outbound_lane and follow.progress >= outbound_lane.curve.get_baked_length() - 0.75:
		if _transfer(follow, mountain_lane, 0.0):
			state = "mountain_approach"
	elif state == "mountain_dwell" and coach.doors > 0.95:
		var passengers := _passenger_exchange()
		if not exchange_started:
			exchange_started = passengers == null or passengers.receive_coach(coach)
		if exchange_started and dwell_elapsed > STATION_DWELL and (passengers == null or passengers.is_exchange_complete()):
			if passengers != null:
				passengers.release_coach(coach)
			berth_owner = null
			coach.stop_lane = harbor_lane
			coach.stop_offset = harbor_offset
			coach.depart()
			state = "returning"
			_return_merge_committed = false
			departures += 1
	elif state == "returning" and lane == access_lane and follow.progress >= access_lane.curve.get_baked_length() - 0.75:
		_transfer(follow, mountain_lane, mountain_exit_offset)
	elif state == "returning" and lane == mountain_lane and follow.progress >= mountain_lane.curve.get_baked_length() - 0.75:
		if _transfer(follow, inbound_lane, 0.0):
			_plan_city(harbor_lane, harbor_offset)

func _plan_city(destination_lane: Path2D, offset: float) -> bool:
	var follow := coach.get_parent() as PathFollow2D
	var planner := PLANNER.new()
	planner.start_lane = follow.get_parent()
	planner.goal_lane = destination_lane
	city_legs = planner.plan(coach, destination_lane.to_global(destination_lane.curve.sample_baked(offset, true)))
	_connection_by_path.clear()
	for connection in network.get_graph_data().lane_connections:
		if is_instance_valid(connection.path):
			_connection_by_path[connection.path] = String(connection.connection_id)
	if city_legs.is_empty():
		push_warning("Regional coach waiting for a directed city route")
		return false
	return true

func planned_connection(lane: Path2D, progress: float) -> String:
	if lane == null or bool(lane.get_meta("is_lane_connector", false)):
		return ""
	for index in range(city_legs.size() - 1):
		var leg := city_legs[index]
		if leg.path == lane and progress <= float(leg.end) + 1.0:
			return String(_connection_by_path.get(city_legs[index + 1].path, ""))
	return ""

func lane_stop_limit(lane: Path2D, progress: float) -> float:
	if state == "mountain_approach" and lane == mountain_lane:
		return mountain_entry_offset
	if lane == access_lane and state == "village_approach" and progress < mountain_berth_offset:
		if berth_owner != coach and not request_berth(coach):
			return maxf(0.0, mountain_berth_offset - 175.0)
	if lane == access_lane and state == "returning" and not _return_merge_committed:
		var hold := access_lane.curve.get_baked_length() - 250.0
		if progress > hold - 80.0:
			if progress >= hold - 0.75 and _return_merge_is_clear():
				_return_merge_committed = true
			else:
				return hold
	return INF

func _return_merge_is_clear() -> bool:
	# Wait on the private approach before the full coach sweeps into the road.
	# Checking only at the final lane handoff strands two touching vehicles.
	for follower in mountain_lane.get_children():
		if follower is PathFollow2D and follower.get_child_count() > 0:
			if follower.progress > mountain_exit_offset - 620.0 and follower.progress < mountain_exit_offset + 220.0:
				return false
	var query := PhysicsShapeQueryParameters2D.new()
	var gap := RectangleShape2D.new()
	gap.size = Vector2(620, 54)
	query.shape = gap
	query.transform = mountain_lane.global_transform * mountain_lane.curve.sample_baked_with_rotation(mountain_exit_offset, true)
	query.collision_mask = 2
	query.exclude = [coach.get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query).is_empty()

func request_berth(candidate: Node2D) -> bool:
	if berth_owner != null and berth_owner != candidate:
		return false
	if access_lane == null:
		return false
	var shape := RectangleShape2D.new()
	shape.size = Vector2(150, 52)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = access_lane.global_transform * access_lane.curve.sample_baked_with_rotation(mountain_berth_offset, true)
	query.collision_mask = 2
	if candidate is CollisionObject2D:
		query.exclude = [candidate.get_rid()]
	if not get_world_2d().direct_space_state.intersect_shape(query).is_empty():
		return false
	berth_owner = candidate
	return true

func _transfer(follow: PathFollow2D, target: Path2D, offset: float) -> bool:
	var destination := target.to_global(target.curve.sample_baked(offset, true))
	var displacement := follow.global_position.distance_to(destination)
	if displacement > 1.0:
		push_error("Regional coach refused a discontinuous lane handoff: %.3f px" % displacement)
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = coach.collision.shape
	query.transform = target.global_transform * target.curve.sample_baked_with_rotation(offset, true)
	query.collision_mask = 1 | 2 | 4
	query.exclude = [coach.get_rid()]
	if not get_world_2d().direct_space_state.intersect_shape(query).is_empty():
		return false
	follow.reparent(target, false)
	follow.loop = false
	follow.progress = offset
	coach.position = Vector2.ZERO
	coach.rotation = 0.0
	follow.reset_physics_interpolation()
	max_handoff_displacement = maxf(max_handoff_displacement, displacement)
	return true

func bus_arrived() -> void:
	dwell_elapsed = 0.0
	exchange_started = false
	if access_lane == null and coach.get_parent().get_parent() == outbound_lane:
		state = "border_wait"
		return
	if coach.get_parent().get_parent() == access_lane:
		state = "mountain_dwell"
		mountain_arrivals += 1
	else:
		state = "harbor_dwell"
		harbor_arrivals += 1
		completed_round_trips += 1

func at_mountain_berth() -> bool:
	# Keep the same door side while closing after departure from the platform.
	return coach != null and coach.get_parent().get_parent() == access_lane

func _passenger_exchange() -> Node:
	if not is_instance_valid(stream) or not is_instance_valid(stream.mountain):
		return null
	return stream.mountain.find_child("TransitPassengers", true, false)

func get_service_status() -> Dictionary:
	return {"state": state, "mountain_arrivals": mountain_arrivals, "harbor_arrivals": harbor_arrivals, "round_trips": completed_round_trips, "departures": departures, "distance": coach.distance_travelled if coach else 0.0, "capacity": 1, "berth_occupied": berth_owner != null, "handoff_displacement": max_handoff_displacement, "destination_loaded": access_lane != null, "coach_spawned": coach != null, "coach_position": coach.global_position if coach else HARBOR_BERTH, "lane_speed": coach._lane_motion_speed if coach else 0.0}

func _exit_tree() -> void:
	if is_instance_valid(coach) and coach.get_parent() is PathFollow2D:
		coach.get_parent().queue_free()

func bus_stolen() -> void:
	state = "stolen"
	berth_owner = null
	var passengers := _passenger_exchange()
	if passengers != null and passengers.active_bus == coach:
		passengers.cancel_exchange(coach)
