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


func reset() -> void:
	legs.clear()
	leg_index = 0
	destination = Vector2.INF
	next_plan_ms = 0
	network = null
	revision = -1
	avoidance_target = Vector2.INF


func guidance(vehicle: Node2D, target: Vector2) -> Vector2:
	var now := Time.get_ticks_msec()
	var invalid := is_instance_valid(network) and revision != int(network.call("get_routing_revision"))
	var moved := destination.distance_to(target) > 120.0
	if invalid or (now >= next_plan_ms and (moved or legs.is_empty())):
		_plan(vehicle, target)
		next_plan_ms = now + 1500
	if legs.is_empty():
		# An unavailable route must not create a diagonal shortcut through walls.
		return vehicle.global_position
	while leg_index < legs.size():
		var leg := legs[leg_index]
		var path := leg.path as Path2D
		if not is_instance_valid(path):
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
	# Final short approach from the destination lane to a depot/incident apron.
	return target


func _cache(graph: Node2D) -> Dictionary:
	var version := int(graph.call("get_routing_revision"))
	var cached: Dictionary = graph.get_meta(CACHE_KEY, {})
	if int(cached.get("revision", -1)) == version:
		return cached
	var data := graph.call("get_graph_data") as Dictionary
	var lanes := {}
	var outgoing := {}
	for lane in data.lanes:
		lanes[String(lane.lane_id)] = lane.path
		outgoing[String(lane.lane_id)] = []
	for connection in data.lane_connections:
		if connection.from_lane_id != connection.to_lane_id:
			outgoing[String(connection.from_lane_id)].append(connection)
	cached = {"revision": version, "lanes": lanes, "outgoing": outgoing}
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
		var parent := lane.get_parent()
		var graph := parent.get_parent() if parent != null else null
		if graph is Node2D and graph.has_method("get_routing_revision") and not graphs.has(graph):
			graphs.append(graph)
	var nearest := INF
	for graph in graphs:
		var cache := _cache(graph)
		for path_value in cache.lanes.values():
			var path := path_value as Path2D
			var point := path.to_global(path.curve.get_closest_point(path.to_local(vehicle.global_position)))
			var distance := point.distance_to(vehicle.global_position)
			if distance < nearest:
				nearest = distance
				network = graph
	if not is_instance_valid(network):
		return
	var cache := _cache(network)
	revision = int(cache.revision)
	var starts := _nearest_lanes(cache.lanes, vehicle.global_position)
	var goals := _nearest_lanes(cache.lanes, target)
	var frontier: Array[Dictionary] = []
	var costs := {}
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
			cost += _obstacle_cost(vehicle, path, float(state.offset), entry, obstacle_costs)
			if is_instance_valid(connector):
				cost += _obstacle_cost(vehicle, connector, 0.0, length, obstacle_costs)
			var key := String(connection.connection_id)
			if cost >= float(costs.get(key, INF)):
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
		var offset := path.curve.get_closest_offset(path.to_local(position))
		var distance := position.distance_to(path.to_global(path.curve.sample_baked(offset, true)))
		nearest = minf(nearest, distance)
		candidates.append({"id": id, "offset": offset, "distance": distance})
	# Include the opposite direction of the nearest road so an apron can merge
	# into a reachable lane. Never pick a distant road merely to shorten a route.
	return candidates.filter(func(item: Dictionary) -> bool: return float(item.distance) <= nearest + 85.0)


func _steer_clear(vehicle: Node2D, waypoint: Vector2) -> Vector2:
	if avoidance_target.is_finite():
		if vehicle.global_position.distance_to(avoidance_target) > 20.0:
			return avoidance_target
		avoidance_target = Vector2.INF
	var forward := vehicle.global_position.direction_to(waypoint)
	var normal := Vector2(-forward.y, forward.x)
	if _clear_motion(vehicle, waypoint):
		return waypoint
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
	var shape := CircleShape2D.new()
	shape.radius = 22.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [vehicle.get_rid()]
	query.transform = Transform2D(0.0, vehicle.global_position)
	query.motion = point - vehicle.global_position
	var fractions := vehicle.get_world_2d().direct_space_state.cast_motion(query)
	return fractions[0] >= 0.99
