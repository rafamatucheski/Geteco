extends SceneTree

## Runtime proof for the real road/rail crossing. This test only instantiates
## Main.tscn and observes the actors created by the game itself: it never adds,
## teleports, accelerates or otherwise drives a train or road vehicle.

const MAIN_SCENE: PackedScene = preload("res://legacy/Main.tscn")
const MAX_OBSERVATION_FRAMES := 4800
const STARTUP_FRAMES := 30
const FIXED_FPS := 60.0
const TRACK_CONFLICT_HALF_WIDTH := 22.0
const APPROACH_OBSERVATION_DISTANCE := 420.0


func _initialize() -> void:
	call_deferred("_run_runtime_audit")


func _run_runtime_audit() -> void:
	var world := MAIN_SCENE.instantiate()
	if world == null:
		_fail("could not instantiate res://legacy/Main.tscn")
		return
	root.add_child(world)
	current_scene = world
	for _frame in STARTUP_FRAMES:
		await physics_frame

	var crossing := await _wait_for_single_level_crossing()
	if crossing == null:
		_fail("expected exactly one generated rail_level_crossing")
		return
	var rail_line := world.get_node_or_null("DistrictOneComplete/DistrictRailLine")
	var train := rail_line.get_node_or_null("AmbientTrain") as Node2D if rail_line != null else null
	if rail_line == null or train == null or not rail_line.has_method("get_train_state"):
		_fail("Main.tscn did not expose the natural DistrictRailLine/AmbientTrain")
		return

	var initial_data: Dictionary = crossing.call("get_crossing_data")
	var crossing_id := String(initial_data.get("id", initial_data.get("crossing_id", "")))
	var crossing_road_id := String(initial_data.get("road_id", ""))
	if crossing_id.is_empty() or crossing_road_id.is_empty():
		_fail("level crossing is missing its canonical id/road_id")
		return

	var closure_started_frame := -1
	var fully_closed_frame := -1
	var train_entered_frame := -1
	var train_cleared_frame := -1
	var fully_reopened_frame := -1
	var train_occupancy_frames := 0
	var max_conflicting_vehicles := 0
	var minimum_vehicle_clearance := INF
	var observed_approach_vehicles := {}
	var conflicting_vehicle_names: Array[String] = []
	var gate_open_seen := not bool(initial_data.get("stop_required", false)) and float(initial_data.get("gate_ratio", 0.0)) <= 0.01
	var train_was_occupying := false
	var previous_stop_required := bool(initial_data.get("stop_required", false))

	for frame in MAX_OBSERVATION_FRAMES:
		await physics_frame
		var data: Dictionary = crossing.call("get_crossing_data")
		var stop_required := bool(data.get("stop_required", false))
		var gate_ratio := float(data.get("gate_ratio", 0.0))
		if not previous_stop_required and stop_required and closure_started_frame < 0:
			closure_started_frame = frame
		if stop_required and gate_ratio >= 0.99 and fully_closed_frame < 0:
			fully_closed_frame = frame

		var conflict_polygons := _build_conflict_polygons(data)
		var train_occupying := _train_overlaps_conflict(train, conflict_polygons)
		if train_occupying:
			train_occupancy_frames += 1
			if train_entered_frame < 0:
				train_entered_frame = frame
			var conflicts := _vehicles_overlapping_conflict(conflict_polygons)
			max_conflicting_vehicles = maxi(max_conflicting_vehicles, conflicts.size())
			for vehicle in conflicts:
				var vehicle_name := String((vehicle as Node).name)
				if not conflicting_vehicle_names.has(vehicle_name):
					conflicting_vehicle_names.append(vehicle_name)
					print(_describe_vehicle_conflict(vehicle as Node2D, crossing, data, frame))
			minimum_vehicle_clearance = minf(
				minimum_vehicle_clearance,
				_minimum_vehicle_clearance_to_track(data, crossing_road_id)
			)
		elif train_was_occupying and train_cleared_frame < 0:
			train_cleared_frame = frame

		_collect_approach_vehicles(data, crossing_road_id, observed_approach_vehicles)
		if train_cleared_frame >= 0 and not stop_required and gate_ratio <= 0.01:
			fully_reopened_frame = frame
			break
		gate_open_seen = gate_open_seen or (not stop_required and gate_ratio <= 0.01)
		train_was_occupying = train_occupying
		previous_stop_required = stop_required

	var failures: Array[String] = []
	if not gate_open_seen:
		failures.append("gate was never naturally observed open")
	if closure_started_frame < 0:
		failures.append("no natural gate-closing cycle was observed")
	if fully_closed_frame < 0:
		failures.append("gate never reached fully closed state")
	if train_entered_frame < 0 or train_occupancy_frames == 0:
		failures.append("the natural train never occupied the crossing conflict zone")
	if fully_closed_frame >= 0 and train_entered_frame >= 0 and fully_closed_frame > train_entered_frame:
		failures.append("train entered before the gate was fully closed")
	if train_cleared_frame < 0:
		failures.append("the natural train passage did not clear the conflict zone")
	if fully_reopened_frame < 0:
		failures.append("gate did not naturally reopen after the train cleared")
	if max_conflicting_vehicles > 0:
		failures.append("road vehicles occupied the conflict zone with the train: %s" % ", ".join(conflicting_vehicle_names))
	if observed_approach_vehicles.is_empty():
		failures.append("no natural vehicle on %s reached the observed crossing approach" % crossing_road_id)

	var close_lead_seconds := -1.0
	if fully_closed_frame >= 0 and train_entered_frame >= 0:
		close_lead_seconds = float(train_entered_frame - fully_closed_frame) / FIXED_FPS
	var occupied_seconds := float(train_occupancy_frames) / FIXED_FPS
	var cycle_seconds := -1.0
	if closure_started_frame >= 0 and fully_reopened_frame >= 0:
		cycle_seconds = float(fully_reopened_frame - closure_started_frame) / FIXED_FPS
	var clearance_text := "n/a" if minimum_vehicle_clearance == INF else "%.2f" % minimum_vehicle_clearance
	print(
		(
			"RAIL_LEVEL_CROSSING_RUNTIME: crossing=%s road=%s approach_vehicles=%d " +
			"closed_lead=%.3fs train_occupied=%.3fs cycle=%.3fs " +
			"max_vehicle_conflicts=%d min_vehicle_track_clearance_px=%s"
		)
		% [
			crossing_id,
			crossing_road_id,
			observed_approach_vehicles.size(),
			close_lead_seconds,
			occupied_seconds,
			cycle_seconds,
			max_conflicting_vehicles,
			clearance_text,
		]
	)
	if not failures.is_empty():
		for failure in failures:
			push_error("RAIL_LEVEL_CROSSING_RUNTIME: %s" % failure)
		_cleanup_and_quit(world, 1)
		return
	print("RAIL_LEVEL_CROSSING_RUNTIME: PASS natural_cycle=1 train_passage=1 conflict_free=1")
	_cleanup_and_quit(world, 0)


func _wait_for_single_level_crossing() -> Node:
	for _frame in 180:
		var crossings := get_nodes_in_group("rail_level_crossing")
		if crossings.size() == 1 and crossings[0].has_method("get_crossing_data"):
			return crossings[0]
		await physics_frame
	return null


func _build_conflict_polygons(data: Dictionary) -> Array:
	var center: Vector2 = data.get("position", Vector2.ZERO)
	var road_tangent: Vector2 = data.get("road_tangent", Vector2.RIGHT)
	var rail_tangent: Vector2 = data.get("rail_tangent", Vector2.DOWN)
	if road_tangent.is_zero_approx():
		road_tangent = Vector2.RIGHT
	if rail_tangent.is_zero_approx():
		rail_tangent = road_tangent.orthogonal()
	road_tangent = road_tangent.normalized()
	rail_tangent = rail_tangent.normalized()
	var road_width := maxf(32.0, float(data.get("road_width", 96.0)))
	var crossing_sine := maxf(0.12, absf(rail_tangent.dot(road_tangent.orthogonal())))
	var rail_span := road_width / crossing_sine + TRACK_CONFLICT_HALF_WIDTH * 4.0
	var road_polygon := _oriented_rectangle(center, road_tangent, 300.0, road_width)
	var rail_polygon := _oriented_rectangle(center, rail_tangent, rail_span, TRACK_CONFLICT_HALF_WIDTH * 2.0)
	return Geometry2D.intersect_polygons(road_polygon, rail_polygon)


func _oriented_rectangle(center: Vector2, forward: Vector2, length: float, width: float) -> PackedVector2Array:
	var axis := forward.normalized()
	var normal := axis.orthogonal().normalized()
	var half_forward := axis * length * 0.5
	var half_normal := normal * width * 0.5
	return PackedVector2Array([
		center - half_forward - half_normal,
		center + half_forward - half_normal,
		center + half_forward + half_normal,
		center - half_forward + half_normal,
	])


func _train_overlaps_conflict(train: Node2D, conflict_polygons: Array) -> bool:
	if _polygon_overlaps_any(_node_rectangle(train, Vector2(92.0, 40.0)), conflict_polygons):
		return true
	for child in train.get_children():
		if child is Node2D and String(child.name).begins_with("FreightWagon_"):
			if _polygon_overlaps_any(_node_rectangle(child as Node2D, Vector2(64.0, 36.0)), conflict_polygons):
				return true
	return false


func _vehicles_overlapping_conflict(conflict_polygons: Array) -> Array[Node]:
	var conflicts: Array[Node] = []
	for candidate in get_nodes_in_group("vehicle"):
		if not candidate is Node2D or not is_instance_valid(candidate):
			continue
		var polygon := _vehicle_polygon(candidate as Node2D)
		if not polygon.is_empty() and _polygon_overlaps_any(polygon, conflict_polygons):
			conflicts.append(candidate)
	return conflicts


func _describe_vehicle_conflict(vehicle: Node2D, crossing: Node, data: Dictionary, frame: int) -> String:
	var follow := vehicle.get_parent() as PathFollow2D
	var path := follow.get_parent() as Path2D if follow != null else null
	var local_position := (crossing as Node2D).to_local(vehicle.global_position)
	return (
		"RAIL_LEVEL_CROSSING_RUNTIME: conflict_detail frame=%d vehicle=%s road=%s " +
		"path=%s unified_lane=%s connector=%s progress=%.2f local=(%.2f, %.2f) " +
		"lane_speed=%.2f gate_ratio=%.3f stop_at_position=%s motion_contract=%s " +
		"spacing=%s obstruction=%s safety_zones=%s ray_colliders=%s"
	) % [
		frame,
		vehicle.name,
		String(vehicle.get_meta("traffic_road_id", "")),
		String(path.name) if path != null else "<none>",
		str(path != null and path.is_in_group("unified_traffic_lane")),
		str(path != null and path.is_in_group("unified_lane_connector")),
		follow.progress if follow != null else -1.0,
		local_position.x,
		local_position.y,
		float(vehicle.get("_lane_motion_speed")),
		float(data.get("gate_ratio", 0.0)),
		str(crossing.call("should_stop_vehicle_at", vehicle.global_position, vehicle)),
		str(vehicle.get("_last_lane_motion_contract")),
		str(vehicle.call("_lane_spacing_motion", follow)) if follow != null else "{}",
		str(vehicle.call("_get_lane_obstruction", follow)) if follow != null else "{}",
		str(vehicle.call("_traffic_control_zone_motion", path, follow)) if path != null and follow != null else "{}",
		_describe_ray_colliders(vehicle),
	]


func _describe_ray_colliders(vehicle: Node2D) -> String:
	var result: Array[String] = []
	for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
		var ray := vehicle.get_node_or_null(ray_name) as RayCast2D
		if ray == null or not ray.is_colliding():
			continue
		var collider := ray.get_collider() as Node
		if collider == null:
			continue
		var groups: Array[String] = []
		for group in collider.get_groups():
			groups.append(String(group))
		result.append("%s:%s[%s]" % [ray_name, collider.name, ",".join(groups)])
	return ";".join(result)


func _vehicle_polygon(vehicle: Node2D) -> PackedVector2Array:
	var collision := vehicle.get_node_or_null("Collision") as CollisionShape2D
	if collision != null and collision.shape is RectangleShape2D:
		return _node_rectangle(collision, (collision.shape as RectangleShape2D).size)
	var vehicle_length := float(vehicle.get("target_length")) if vehicle.get("target_length") != null else 76.0
	return _node_rectangle(vehicle, Vector2(maxf(28.0, vehicle_length * 0.78), 36.0))


func _node_rectangle(node: Node2D, size: Vector2) -> PackedVector2Array:
	var half_size := size * 0.5
	return PackedVector2Array([
		node.to_global(Vector2(-half_size.x, -half_size.y)),
		node.to_global(Vector2(half_size.x, -half_size.y)),
		node.to_global(Vector2(half_size.x, half_size.y)),
		node.to_global(Vector2(-half_size.x, half_size.y)),
	])


func _polygon_overlaps_any(polygon: PackedVector2Array, targets: Array) -> bool:
	for target in targets:
		if target is PackedVector2Array and not Geometry2D.intersect_polygons(polygon, target).is_empty():
			return true
	return false


func _collect_approach_vehicles(data: Dictionary, road_id: String, result: Dictionary) -> void:
	var center: Vector2 = data.get("position", Vector2.ZERO)
	var road_tangent: Vector2 = data.get("road_tangent", Vector2.RIGHT)
	if road_tangent.is_zero_approx():
		road_tangent = Vector2.RIGHT
	road_tangent = road_tangent.normalized()
	var road_normal := road_tangent.orthogonal()
	var road_width := maxf(32.0, float(data.get("road_width", 96.0)))
	for candidate in get_nodes_in_group("vehicle"):
		if not candidate is Node2D or String(candidate.get_meta("traffic_road_id", "")) != road_id:
			continue
		var relative := (candidate as Node2D).global_position - center
		if absf(relative.dot(road_tangent)) <= APPROACH_OBSERVATION_DISTANCE and absf(relative.dot(road_normal)) <= road_width:
			result[candidate.get_instance_id()] = true


func _minimum_vehicle_clearance_to_track(data: Dictionary, road_id: String) -> float:
	var center: Vector2 = data.get("position", Vector2.ZERO)
	var rail_tangent: Vector2 = data.get("rail_tangent", Vector2.DOWN)
	if rail_tangent.is_zero_approx():
		rail_tangent = Vector2.DOWN
	var rail_normal := rail_tangent.normalized().orthogonal()
	var minimum_clearance := INF
	for candidate in get_nodes_in_group("vehicle"):
		if not candidate is Node2D or String(candidate.get_meta("traffic_road_id", "")) != road_id:
			continue
		var polygon := _vehicle_polygon(candidate as Node2D)
		var minimum_projection := INF
		var maximum_projection := -INF
		for point in polygon:
			var projection := (point - center).dot(rail_normal)
			minimum_projection = minf(minimum_projection, projection)
			maximum_projection = maxf(maximum_projection, projection)
		var centerline_distance := 0.0 if minimum_projection <= 0.0 and maximum_projection >= 0.0 else minf(absf(minimum_projection), absf(maximum_projection))
		minimum_clearance = minf(minimum_clearance, centerline_distance - TRACK_CONFLICT_HALF_WIDTH)
	return minimum_clearance


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


func _fail(message: String) -> void:
	push_error("RAIL_LEVEL_CROSSING_RUNTIME: %s" % message)
	quit(1)
