extends RefCounted

## Per-vehicle cursor over directed lane/connector legs. Adjacency is owned by
## the network metadata and rebuilt only when its generated paths change.
const CACHE_KEY := &"emergency_routing_cache"
var legs: Array[Dictionary] = []
var leg_index := 0
var destination := Vector2.INF
var next_plan_ms := 0
var network: Node2D
var revision := -1
var plans := 0
var avoidance_target := Vector2.INF
var linked_lane: Path2D
var _linked_entry_pending := false
var at_roadside_goal := false


func reset() -> void:
	at_roadside_goal = false
	linked_lane = null
	_linked_entry_pending = false
	legs.clear()
	leg_index = 0
	destination = Vector2.INF
	next_plan_ms = 0
	network = null
	revision = -1
	avoidance_target = Vector2.INF


func guidance(vehicle: Node2D, target: Vector2) -> Vector2:
	at_roadside_goal = false
	if destination.distance_to(target) > 120.0:
		reset()
	if is_instance_valid(linked_lane):
		return _guide_linked_lane(vehicle, target)
	var now := Time.get_ticks_msec()
	var invalid := is_instance_valid(network) and revision != int(network.call("get_routing_revision"))
	var moved := destination.distance_to(target) > 120.0
	if invalid or (now >= next_plan_ms and (moved or legs.is_empty())):
		_plan(vehicle, target)
		next_plan_ms = now + 1500
	if is_instance_valid(linked_lane):
		return _guide_linked_lane(vehicle, target)
	if legs.is_empty():
		# An unavailable route must not create a diagonal shortcut through walls.
		return vehicle.global_position
	while leg_index < legs.size():
		var leg := legs[leg_index]
		var path := leg.path as Path2D
		if not is_instance_valid(path) or not path.can_process() or path.curve == null or path.curve.point_count < 2:
			legs.clear()
			next_plan_ms = 0
			return vehicle.global_position
		var curve := path.curve
		var end := float(leg.end)
		var end_point := path.to_global(curve.sample_baked(end, true))
		var offset := clampf(curve.get_closest_offset(path.to_local(vehicle.global_position)), float(leg.start), end)
		if vehicle.global_position.distance_to(end_point) < 28.0:
			leg_index += 1
			continue
		var on_path := path.to_global(curve.sample_baked(offset, true))
		if vehicle.global_position.distance_to(on_path) > 54.0:
			return _steer_clear(vehicle, on_path)
		return _steer_clear(vehicle, path.to_global(curve.sample_baked(minf(end, offset + 70.0), true)))
	# Finish at the road shoulder when the suspect is beyond drivable pavement.
	# A building entrance or a pedestrian on a bridge must not drag a cruiser
	# diagonally off its lane into the water or through the shop front.
	if not legs.is_empty():
		var last: Dictionary = legs.back()
		var path := last.path as Path2D
		if not is_instance_valid(path) or path.curve == null or path.curve.point_count < 2:
			legs.clear()
			return vehicle.global_position
		# A stopped suspect can be on a crossing. Carry the approach along the
		# same lane instead of parking there or waiting forever at the slot.
		if vehicle.get("type") == 0 and float(vehicle.get("_target_stopped_time")) >= 1.5 and not permits_police_stop(vehicle):
			var extended_end := minf(path.curve.get_baked_length(), float(last.end) + 100.0)
			if extended_end > float(last.end) + 1.0:
				last.end = extended_end
				legs[legs.size() - 1] = last
				leg_index = legs.size() - 1
				return _steer_clear(vehicle, path.to_global(path.curve.sample_baked(extended_end, true)))
		var endpoint := path.to_global(path.curve.sample_baked(float(last.end), true))
		if endpoint.distance_to(target) > 42.0:
			if float(last.end) >= path.curve.get_baked_length() - 30.0 and vehicle.global_position.distance_to(endpoint) < 32.0:
				if _link_adjacent_lane(vehicle, path):
					return _guide_linked_lane(vehicle, target)
			# O trecho terminou: devolver o ponto atrás do para-choque fazia
			# o veículo circular em torno dele sem autorizar a equipe a sair.
			if vehicle.global_position.distance_to(endpoint) < 32.0:
				at_roadside_goal = true
				return vehicle.global_position
			return endpoint
	return target


func permits_police_stop(vehicle: Node2D) -> bool:
	# Do not turn a connector or a sideways lane entry into a parking spot.
	var path: Path2D = linked_lane
	if not is_instance_valid(path) and leg_index < legs.size():
		path = legs[leg_index].path as Path2D
	if not is_instance_valid(path) and not legs.is_empty():
		path = legs.back().path as Path2D
	if not is_instance_valid(path) or not path.is_in_group("unified_traffic_lane") or path.curve == null:
		return false
	var curve := path.curve
	var length := curve.get_baked_length()
	if length < 1.0: return false
	var offset := curve.get_closest_offset(path.to_local(vehicle.global_position))
	var point := path.to_global(curve.sample_baked(offset, true))
	var tangent := path.to_global(curve.sample_baked(minf(length, offset + 12.0), true)) - path.to_global(curve.sample_baked(maxf(0.0, offset - 12.0), true))
	if vehicle.global_position.distance_to(point) > 24.0 or tangent.normalized().dot(vehicle.global_transform.x) < 0.92:
		return false
	if is_instance_valid(network):
		var cache := _cache(network)
		for junction_offset in cache.get("junction_offsets", {}).get(path.get_instance_id(), []):
			if absf(offset - float(junction_offset)) < 85.0:
				return false
	return true


func _cache(graph: Node2D) -> Dictionary:
	var version := int(graph.call("get_routing_revision"))
	var cached: Dictionary = graph.get_meta(CACHE_KEY, {})
	if int(cached.get("revision", -1)) == version:
		return cached
	var data := graph.call("get_graph_data") as Dictionary
	var lanes := {}
	var outgoing := {}
	var junction_offsets := {}
	for lane in data.lanes:
		lanes[String(lane.lane_id)] = lane.path
		outgoing[String(lane.lane_id)] = []
	for connection in data.lane_connections:
		if connection.from_lane_id != connection.to_lane_id:
			outgoing[String(connection.from_lane_id)].append(connection)
			for endpoint in [[connection.from_lane_id, connection.entry_lane_progress], [connection.to_lane_id, connection.exit_lane_progress]]:
				var lane_path := lanes[String(endpoint[0])] as Path2D
				if not is_instance_valid(lane_path) or lane_path.curve == null: continue
				var id := lane_path.get_instance_id()
				if not junction_offsets.has(id): junction_offsets[id] = []
				junction_offsets[id].append(float(endpoint[1]) * lane_path.curve.get_baked_length())
	cached = {"revision": version, "lanes": lanes, "outgoing": outgoing, "junction_offsets": junction_offsets}
	graph.set_meta(CACHE_KEY, cached)
	return cached


func _plan(vehicle: Node2D, target: Vector2) -> void:
	plans += 1
	destination = target
	legs.clear()
	leg_index = 0
	avoidance_target = Vector2.INF
	network = null
	var graphs: Array[Node2D] = []
	for lane in vehicle.get_tree().get_nodes_in_group("unified_traffic_lane"):
		if not lane.can_process(): continue
		var parent := lane.get_parent()
		var graph := parent.get_parent() if parent != null else null
		if graph is Node2D and graph.has_method("get_routing_revision") and not graphs.has(graph):
			graphs.append(graph)
	var nearest := INF
	for graph in graphs:
		var cache := _cache(graph)
		for path_value in cache.lanes.values():
			var path := path_value as Path2D
			if not is_instance_valid(path) or path.curve == null or path.curve.point_count < 2: continue
			var point := path.to_global(path.curve.get_closest_point(path.to_local(vehicle.global_position)))
			var distance := point.distance_to(vehicle.global_position)
			if distance < nearest:
				nearest = distance
				network = graph
	if nearest > 180.0:
		network = null
	if not is_instance_valid(network):
		var nearest_path_distance := 180.0
		for node in vehicle.get_tree().get_nodes_in_group("unified_traffic_lane"):
			var path := node as Path2D
			if path == null or not path.can_process() or path.curve == null or path.curve.point_count < 2: continue
			var point := path.to_global(path.curve.get_closest_point(path.to_local(vehicle.global_position)))
			if point.distance_to(vehicle.global_position) < nearest_path_distance:
				nearest_path_distance = point.distance_to(vehicle.global_position)
				linked_lane = path
		return
	var cache := _cache(network)
	revision = int(cache.revision)
	var starts := _nearest_lanes(cache.lanes, vehicle.global_position)
	var goals := _nearest_lanes(cache.lanes, target)
	var frontier: Array[Dictionary] = []
	var costs := {}
	# Join in the current direction; use road junctions to turn back.
	var forward_starts: Array[Dictionary] = []
	if vehicle.get("type") in [0,1,3]:
		for start in starts:
			var path := cache.lanes[start.id] as Path2D
			var offset := float(start.offset)
			var tangent := path.to_global(path.curve.sample_baked(minf(path.curve.get_baked_length(), offset + 10.0))) - path.to_global(path.curve.sample_baked(maxf(0.0, offset - 10.0)))
			if tangent.normalized().dot(vehicle.global_transform.x) > .3:
				forward_starts.append(start)
		if not forward_starts.is_empty(): starts = forward_starts
	for start in starts:
		frontier.append({"lane": start.id, "offset": start.offset, "cost": start.distance * 4.0, "legs": []})
	var best := INF
	var obstacle_costs := {}
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.cost) > float(b.cost))
		var state := frontier.pop_back() as Dictionary
		if float(state.cost) >= best:
			continue
		var path := cache.lanes[state.lane] as Path2D
		for goal in goals:
			if goal.id == state.lane and float(goal.offset) >= float(state.offset) - 1.0:
				var cost := float(state.cost) + maxf(0.0, float(goal.offset) - float(state.offset)) + float(goal.distance) * 4.0
				cost += _obstacle_cost(vehicle, path, float(state.offset), float(goal.offset), obstacle_costs)
				if cost < best:
					best = cost
					legs.assign(state.legs)
					legs.append({"path": path, "start": state.offset, "end": maxf(float(state.offset), float(goal.offset))})
		for connection in cache.outgoing[state.lane]:
			var entry := float(connection.entry_lane_progress) * path.curve.get_baked_length()
			if entry < float(state.offset) - 1.0:
				continue
			var next_path := cache.lanes[connection.to_lane_id] as Path2D
			var exit_offset := float(connection.exit_lane_progress) * next_path.curve.get_baked_length()
			var connector := connection.path as Path2D
			if bool(connection.requires_connector) and not is_instance_valid(connector):
				continue
			var length := connector.curve.get_baked_length() if is_instance_valid(connector) else 0.0
			var cost := float(state.cost) + maxf(0.0, entry - float(state.offset)) + length
			var key := String(connection.connection_id)
			# Obstacle penalties are nonnegative. Reject already dominated
			# routes before sweeping their full length through the physics world.
			if cost >= best or cost >= float(costs.get(key, INF)):
				continue
			cost += _obstacle_cost(vehicle, path, float(state.offset), entry, obstacle_costs)
			if is_instance_valid(connector):
				cost += _obstacle_cost(vehicle, connector, 0.0, length, obstacle_costs)
			if cost >= best or cost >= float(costs.get(key, INF)):
				continue
			costs[key] = cost
			var route: Array = (state.legs as Array).duplicate()
			route.append({"path": path, "start": state.offset, "end": entry})
			if is_instance_valid(connector):
				route.append({"path": connector, "start": 0.0, "end": length})
			frontier.append({"lane": String(connection.to_lane_id), "offset": exit_offset, "cost": cost, "legs": route})


func _nearest_lanes(lanes: Dictionary, position: Vector2) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var nearest := INF
	for id in lanes:
		var path := lanes[id] as Path2D
		if not is_instance_valid(path) or path.curve == null or path.curve.point_count < 2: continue
		var offset := path.curve.get_closest_offset(path.to_local(position))
		var distance := position.distance_to(path.to_global(path.curve.sample_baked(offset, true)))
		nearest = minf(nearest, distance)
		candidates.append({"id": id, "offset": offset, "distance": distance})
	# Include the opposite direction of the nearest road so an apron can merge
	# into a reachable lane. Never pick a distant road merely to shorten a route.
	return candidates.filter(func(item: Dictionary) -> bool: return float(item.distance) <= nearest + 85.0)


func _steer_clear(vehicle: Node2D, waypoint: Vector2) -> Vector2:
	# Rejoin as soon as the lane ahead is clear; retaining a detour already
	# passed by the bumper would turn the responder back into the blockage.
	if _clear_motion(vehicle, waypoint):
		avoidance_target = Vector2.INF
		return waypoint
	if avoidance_target.is_finite():
		if vehicle.global_position.distance_to(avoidance_target) > 20.0 and _clear_motion(vehicle, avoidance_target):
			return avoidance_target
		avoidance_target = Vector2.INF
	var forward := vehicle.global_position.direction_to(waypoint)
	var normal := Vector2(-forward.y, forward.x)
	for lateral in [40.0, -40.0, 64.0, -64.0]:
		var candidate: Vector2 = waypoint + normal * float(lateral)
		if _clear_motion(vehicle, candidate):
			avoidance_target = candidate
			return candidate
	# When rejoining beside a broad static obstacle, clear its flank before
	# turning toward the lane again. Each step remains collision-checked.
	for lateral in [64.0, -64.0]:
		var candidate: Vector2 = vehicle.global_position + normal * float(lateral)
		if _clear_motion(vehicle, candidate):
			avoidance_target = candidate
			return candidate
	return waypoint


## Prefer an unobstructed lane when authored props encroach on one direction.
## This is sampled only while planning; moving traffic does not alter topology.
func _obstacle_cost(vehicle: Node2D, path: Path2D, start: float, end: float, costs: Dictionary) -> float:
	var key := "%d:%.1f:%.1f" % [path.get_instance_id(), start, end]
	if costs.has(key):
		return float(costs[key])
	var shape := CircleShape2D.new()
	shape.radius = 24.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [vehicle.get_rid()]
	var total := 0.0
	var samples := maxi(1, ceili((end - start) / 40.0))
	for index in range(samples + 1):
		var point := path.to_global(path.curve.sample_baked(lerpf(start, end, float(index) / samples), true))
		if point.distance_to(destination) < 140.0:
			continue
		query.transform = Transform2D(0.0, point)
		for hit in vehicle.get_world_2d().direct_space_state.intersect_shape(query, 8):
			if hit.collider is StaticBody2D:
				total += 160.0
	costs[key] = total
	return total


func _clear_motion(vehicle: Node2D, point: Vector2) -> bool:
	var hull := vehicle.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	if hull != null:
		query.shape = hull.shape
		query.transform = hull.global_transform
	else:
		var shape := CircleShape2D.new()
		shape.radius = 22.0
		query.shape = shape
		query.transform = Transform2D(0.0, vehicle.global_position)
	query.collision_mask = 1 | 2 | 4 | 8
	query.margin = 3.0
	query.exclude = [vehicle.get_rid()]
	query.motion = point - vehicle.global_position
	var space := vehicle.get_world_2d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return false
	var fractions := space.cast_motion(query)
	return fractions[0] >= 0.99


func _link_adjacent_lane(vehicle: Node2D, from_path: Path2D) -> bool:
	var length := from_path.curve.get_baked_length()
	var end := from_path.to_global(from_path.curve.sample_baked(length, true))
	var outgoing := (end - from_path.to_global(from_path.curve.sample_baked(maxf(0, length - 12), true))).normalized()
	var best := 50.01
	var candidate: Path2D
	for node in vehicle.get_tree().get_nodes_in_group("unified_traffic_lane"):
		var path := node as Path2D
		if path == null or path == from_path or not path.can_process() or path.curve == null or path.curve.point_count < 2: continue
		var start := path.to_global(path.curve.sample_baked(0, true))
		var gap := start.distance_to(end)
		if gap > 50.0 or gap >= best: continue
		var incoming := (path.to_global(path.curve.sample_baked(12, true)) - start).normalized()
		if incoming.dot(outgoing) < 0.8: continue
		best = gap
		candidate = path
	if candidate == null: return false
	linked_lane = candidate
	_linked_entry_pending = true
	legs.clear()
	network = null
	return true


func _guide_linked_lane(vehicle: Node2D, target: Vector2) -> Vector2:
	if not is_instance_valid(linked_lane) or not linked_lane.can_process() or linked_lane.curve == null or linked_lane.curve.point_count < 2:
		linked_lane = null
		return vehicle.global_position
	# Move beyond the seam before replanning: nearby opposite lane endpoints
	# must not immediately hand the same stationary car back across the seam.
	if _linked_entry_pending:
		var entry_offset := linked_lane.curve.get_closest_offset(linked_lane.to_local(vehicle.global_position))
		if entry_offset < minf(45.0, linked_lane.curve.get_baked_length() * 0.5):
			return linked_lane.to_global(linked_lane.curve.sample_baked(60.0, true))
		_linked_entry_pending = false
	# Once back on a canonical city lane, resume its junction graph normally.
	var parent := linked_lane.get_parent()
	var graph := parent.get_parent() if parent != null else null
	if graph is Node2D and graph.has_method("get_routing_revision"):
		linked_lane = null
		next_plan_ms = 0
		_plan(vehicle, target)
		# Resume on the next physics tick. Re-entering guidance synchronously can
		# recurse forever if a streamed seam replans to the same linked lane.
		return vehicle.global_position
	var path := linked_lane
	var curve := path.curve
	var length := curve.get_baked_length()
	var offset := curve.get_closest_offset(path.to_local(vehicle.global_position))
	var point := path.to_global(curve.sample_baked(offset, true))
	if point.distance_to(vehicle.global_position) > 54.0:
		return _steer_clear(vehicle, path.to_global(curve.sample_baked(minf(length, offset + 65.0), true)))
	var goal := curve.get_closest_offset(path.to_local(target))
	var goal_point := path.to_global(curve.sample_baked(goal, true))
	if goal_point.distance_to(vehicle.global_position) < 28.0:
		# A suspect in a yard or interior can be farther than 160 from this
		# loop. Finish on its nearest pavement, as canonical graph routes do,
		# instead of making endless laps. Preserve cross-region handoffs.
		if goal >= length - 50.0 and goal_point.distance_to(target) > 160.0 and _link_adjacent_lane(vehicle, path):
			return _guide_linked_lane(vehicle, target)
		at_roadside_goal = goal_point.distance_to(target) > 32.0
		return vehicle.global_position if at_roadside_goal else target
	var end := path.to_global(curve.sample_baked(length, true))
	if offset >= length - 50.0 and end.distance_to(vehicle.global_position) < 28.0:
		if _link_adjacent_lane(vehicle, path): return _guide_linked_lane(vehicle, target)
		if bool(path.get_meta("traffic_lane_loop", false)) or end.distance_to(path.to_global(curve.sample_baked(0, true))) < 5.0:
			return path.to_global(curve.sample_baked(60.0, true))
		return vehicle.global_position
	var lookahead := minf(length, offset + 65.0)
	if goal >= offset and goal < length - 50.0:
		lookahead = minf(lookahead, goal)
	return _steer_clear(vehicle, path.to_global(curve.sample_baked(lookahead, true)))
