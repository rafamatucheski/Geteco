@tool
class_name DistrictRoadSafetySystem2D
extends Node2D

## Derives every safety device from the canonical road and rail graphs.
## Authored inputs are semantic references ({road_id, t}), never coordinates.

signal safety_graph_rebuilt(summary: Dictionary)
signal crossing_pedestrian_request(crossing_id: StringName, junction_id: StringName)

const CROSSWALK_SCRIPT := preload("res://district/roads/safety/RoadCrossingArea2D.gd")
const RAIL_CROSSING_SCRIPT := preload("res://district/roads/safety/RailLevelCrossing2D.gd")
const MERGE_INTERSECTION_DISTANCE := 12.0
const DEFAULT_SIDEWALK_REACH := 42.0

@export var road_graph_path := NodePath("../UnifiedRoadNetwork")
@export var rail_line_path := NodePath("../DistrictRailLine")
@export var elevated_highway_path := NodePath("../District1HighwayExit")
@export_range(24.0, 320.0, 1.0) var signal_link_distance := 180.0
@export_range(40.0, 800.0, 1.0) var train_closing_lookahead := 380.0
@export_range(0.25, 2.0, 0.05) var editor_refresh_seconds := 0.5

var _pedestrian_reference_override: Array[Dictionary] = []
var _crosswalk_nodes: Array[RoadCrossingArea2D] = []
var _rail_crossing_nodes: Array[RailLevelCrossing2D] = []
var _rail_intersections: Array[Dictionary] = []
var _grade_separated_intersections: Array[Dictionary] = []
var _validation_errors: Array[String] = []
var _validation_warnings: Array[String] = []
var _source_signature := ""
var _editor_refresh_clock := 0.0


func _ready() -> void:
	add_to_group("district_road_safety_system")
	add_to_group("crossing_safety_system")
	add_to_group("traffic_crossing_safety")
	call_deferred("rebuild_from_sources")
	set_process(Engine.is_editor_hint())
	set_physics_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	_editor_refresh_clock += delta
	if _editor_refresh_clock < editor_refresh_seconds:
		return
	_editor_refresh_clock = 0.0
	var signature := _make_source_signature()
	if signature != _source_signature:
		rebuild_from_sources()


func _physics_process(_delta: float) -> void:
	_update_level_crossings_from_train()


func set_pedestrian_crossing_definitions(definitions: Array[Dictionary]) -> void:
	# Useful for an authoring tool or graph provider. Definitions must contain
	# road_id+t and may contain junction_id/junction_index; world positions are
	# deliberately ignored.
	_pedestrian_reference_override = definitions.duplicate(true)
	if is_inside_tree():
		rebuild_from_sources()


func rebuild_from_sources() -> void:
	_validation_errors.clear()
	_validation_warnings.clear()
	_crosswalk_nodes.clear()
	_rail_crossing_nodes.clear()
	_rail_intersections.clear()
	_grade_separated_intersections.clear()
	_clear_generated_root("GeneratedCrosswalks")
	_clear_generated_root("GeneratedRailCrossings")

	var road_graph := _road_graph()
	var rail_line := _rail_line()
	if road_graph == null or not road_graph.has_method("get_graph_data"):
		_validation_errors.append("Road safety requires UnifiedRoadNetwork2D.get_graph_data()")
		_finish_rebuild()
		return
	var graph_data: Dictionary = road_graph.call("get_graph_data")
	var roads: Array = graph_data.get("roads", [])
	var junctions: Array = graph_data.get("junctions", [])
	if roads.is_empty():
		_validation_errors.append("Canonical road graph contains no roads")

	_build_pedestrian_crossings(road_graph, graph_data, roads, junctions)
	if rail_line == null or not rail_line.has_method("get_rail_graph_data"):
		_validation_errors.append("Rail safety requires DistrictRailLine.get_rail_graph_data()")
	else:
		_detect_and_build_rail_crossings(road_graph, roads, rail_line)
	_run_elevated_span_audit(road_graph, junctions)
	_run_z_order_audit(road_graph, rail_line)
	_validate_rail_handoff(rail_line)
	_finish_rebuild()


func synchronize_crossing_signal(
	junction: Variant,
	vehicle_permitted: bool,
	pedestrian_permitted: bool
) -> void:
	for crossing in _crosswalk_nodes:
		if not is_instance_valid(crossing):
			continue
		var matches := false
		if junction is int:
			matches = int(crossing.get_meta("junction_index", -1)) == int(junction)
		else:
			matches = crossing.junction_id == StringName(String(junction))
		if matches:
			crossing.set_signal_state(vehicle_permitted, pedestrian_permitted)


func bind_junction_signal_controller(junction: Variant, controller: Node) -> void:
	for crossing in _crosswalk_nodes:
		if not is_instance_valid(crossing):
			continue
		var matches := int(crossing.get_meta("junction_index", -1)) == int(junction) if junction is int else crossing.junction_id == StringName(String(junction))
		if matches:
			crossing.set_signal_controller(controller)


func should_stop_vehicle_at(world_position: Vector2, vehicle: Node = null) -> bool:
	for crossing in _crosswalk_nodes:
		if is_instance_valid(crossing) and crossing.contains_world_point(world_position) and crossing.should_stop_vehicle(vehicle):
			return true
	for crossing in _rail_crossing_nodes:
		if is_instance_valid(crossing) and crossing.should_stop_vehicle_at(world_position, vehicle):
			return true
	return false


func get_safety_data() -> Dictionary:
	var crosswalks: Array[Dictionary] = []
	for crossing in _crosswalk_nodes:
		if is_instance_valid(crossing):
			crosswalks.append(crossing.get_crossing_data())
	var rail_crossings: Array[Dictionary] = []
	for crossing in _rail_crossing_nodes:
		if is_instance_valid(crossing):
			rail_crossings.append(crossing.get_crossing_data())
	return {
		"pedestrian_crossings": crosswalks,
		"rail_level_crossings": rail_crossings,
		"grade_separated_rail_crossings": _grade_separated_intersections.duplicate(true),
		"validation_errors": _validation_errors.duplicate(),
		"validation_warnings": _validation_warnings.duplicate(),
	}


func get_validation_summary() -> String:
	return "crosswalks=%d rail_level=%d rail_grade_separated=%d errors=%d warnings=%d" % [
		_crosswalk_nodes.size(),
		_rail_crossing_nodes.size(),
		_grade_separated_intersections.size(),
		_validation_errors.size(),
		_validation_warnings.size(),
	]


func _build_pedestrian_crossings(road_graph: Node2D, graph_data: Dictionary, roads: Array, junctions: Array) -> void:
	var references := _collect_pedestrian_references(graph_data)
	if references.is_empty():
		_validation_warnings.append("No pedestrian crossing {road_id, t} references were published by the road graph/providers")
		return
	var generated := _generated_root("GeneratedCrosswalks")
	var seen := {}
	for source in references:
		var reference := source as Dictionary
		var requested_id := String(reference.get("road_id", reference.get("road", "")))
		var road_info := _find_road(roads, requested_id)
		if road_info.is_empty():
			_validation_errors.append("Pedestrian crossing references unknown or ambiguous road: %s" % requested_id)
			continue
		var road: Dictionary = road_info.road
		var road_id := String(road.id)
		var road_t := clampf(float(reference.get("t", 0.0)), 0.0, 1.0)
		var key := "%s@%0.5f" % [road_id, road_t]
		if seen.has(key):
			_validation_errors.append("Duplicate pedestrian crossing reference: %s" % key)
			continue
		seen[key] = true
		var sampled := _sample_polyline_at_fraction(road.points, road_t)
		if sampled.is_empty():
			_validation_errors.append("Pedestrian crossing road has insufficient geometry: %s" % road_id)
			continue
		var world_position := road_graph.to_global(sampled.position)
		var world_tangent := road_graph.global_transform.basis_xform(sampled.tangent).normalized()
		var crossing_half_depth := float(reference.get("crossing_depth", 30.0)) * 0.5
		if _is_on_elevated_source(road_id, road_t) or _is_under_elevated_span(world_position, crossing_half_depth):
			_validation_errors.append("Pedestrian crossing %s is forbidden under the elevated span" % key)
			continue
		var junction_link := _resolve_junction_reference(road_graph, junctions, reference, world_position)
		var crossing_name := String(reference.get("id", "crosswalk_%s_%04d" % [_safe_name(road_id), roundi(road_t * 10000.0)]))
		var crossing := CROSSWALK_SCRIPT.new() as RoadCrossingArea2D
		crossing.name = crossing_name
		crossing.z_index = 3
		generated.add_child(crossing)
		crossing.configure({
			"id": crossing_name,
			"junction_id": junction_link.id,
			"road_id": road_id,
			"road_index": int(road_info.index),
			"t": road_t,
			"position": generated.to_local(world_position),
			"road_tangent": global_transform.basis_xform_inv(world_tangent).normalized(),
			"road_width": float(road.width),
			"sidewalk_reach": float(reference.get("sidewalk_reach", DEFAULT_SIDEWALK_REACH)),
			"crossing_depth": float(reference.get("crossing_depth", 30.0)),
			"approach_depth": float(reference.get("approach_depth", 150.0)),
			"crossing_axis": reference.get("crossing_axis", "AUTO"),
		})
		crossing.set_meta("junction_index", int(junction_link.index))
		crossing.pedestrian_request.connect(_on_crossing_pedestrian_request)
		_crosswalk_nodes.append(crossing)
		_bind_discovered_signal_controller(crossing)


func _collect_pedestrian_references(graph_data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen_sources := {}
	for key in ["pedestrian_crossings", "crosswalks"]:
		for source in graph_data.get(key, []):
			if source is Dictionary:
				result.append((source as Dictionary).duplicate(true))
	for source in _pedestrian_reference_override:
		result.append(source.duplicate(true))
	var composition_root := get_parent()
	if composition_root != null:
		var candidates: Array[Node] = [composition_root]
		# Providers are composition modules/direct siblings of this coordinator.
		# Do not rescan thousands of spawned cars and pedestrians every rebuild.
		candidates.append_array(composition_root.get_children())
		for candidate in candidates:
			if not candidate.has_method("get_pedestrian_crossing_definitions"):
				continue
			if seen_sources.has(candidate.get_instance_id()):
				continue
			seen_sources[candidate.get_instance_id()] = true
			for source in candidate.call("get_pedestrian_crossing_definitions"):
				if source is Dictionary:
					result.append((source as Dictionary).duplicate(true))
	return result


func _detect_and_build_rail_crossings(road_graph: Node2D, roads: Array, rail_line: Node2D) -> void:
	var rail_data: Dictionary = rail_line.call("get_rail_graph_data")
	var rail_points: PackedVector2Array = rail_data.get("global_points", PackedVector2Array())
	var rail_ballast_width := float(rail_data.get("ballast_width", 54.0))
	var track_gauge := float(rail_data.get("track_gauge", 22.0))
	if rail_points.size() < 2:
		_validation_errors.append("Canonical rail graph contains fewer than two baked points")
		return
	var all_intersections: Array[Dictionary] = []
	for road_index in range(roads.size()):
		var road: Dictionary = roads[road_index]
		var lane_controls: Array[Dictionary] = []
		for lane_value in road.get("lanes", []):
			if not lane_value is Dictionary:
				continue
			var lane := lane_value as Dictionary
			lane_controls.append({
				"lane_id": String(lane.get("lane_id", "")),
				"offset": float(lane.get("offset", 0.0)),
				"direction": int(lane.get("direction", 1)),
			})
		var road_points_global := PackedVector2Array()
		var road_points: PackedVector2Array = road.points
		for point in road_points:
			road_points_global.append(road_graph.to_global(point))
		var road_prefix := _polyline_prefix_lengths(road_points_global)
		var rail_prefix := _polyline_prefix_lengths(rail_points)
		for road_segment in range(road_points_global.size() - 1):
			for rail_segment in range(rail_points.size() - 1):
				var hit = Geometry2D.segment_intersects_segment(
					road_points_global[road_segment], road_points_global[road_segment + 1],
					rail_points[rail_segment], rail_points[rail_segment + 1]
				)
				if hit == null:
					continue
				var position := hit as Vector2
				var duplicate := false
				for existing in all_intersections:
					if String(existing.road_id) == String(road.id) and (existing.position as Vector2).distance_to(position) <= MERGE_INTERSECTION_DISTANCE:
						duplicate = true
						break
				if duplicate:
					continue
				var road_length: float = road_prefix[-1]
				var rail_length: float = rail_prefix[-1]
				var road_distance := float(road_prefix[road_segment]) + road_points_global[road_segment].distance_to(position)
				var rail_distance := float(rail_prefix[rail_segment]) + rail_points[rail_segment].distance_to(position)
				var intersection := {
					"id": "rail_%s_%04d" % [_safe_name(String(road.id)), roundi(road_distance / maxf(road_length, 1.0) * 10000.0)],
					"position": position,
					"road_id": String(road.id),
					"road_index": road_index,
					"road_t": road_distance / maxf(road_length, 1.0),
					"rail_t": rail_distance / maxf(rail_length, 1.0),
					"rail_offset": rail_distance,
					"road_width": float(road.width),
					"rail_ballast_width": rail_ballast_width,
					"track_gauge": track_gauge,
					"lane_controls": lane_controls.duplicate(true),
					"road_tangent": road_points_global[road_segment].direction_to(road_points_global[road_segment + 1]),
					"rail_tangent": rail_points[rail_segment].direction_to(rail_points[rail_segment + 1]),
				}
				if _is_on_elevated_source(String(road.id), float(intersection.road_t)) or _is_under_elevated_span(position):
					intersection["classification"] = "grade_separated"
					_grade_separated_intersections.append(intersection)
				else:
					intersection["classification"] = "at_grade"
					_rail_intersections.append(intersection)
				all_intersections.append(intersection)

	if all_intersections.is_empty():
		_validation_errors.append("Rail corridor does not intersect any canonical road")
	if _grade_separated_intersections.is_empty():
		_validation_warnings.append("No road/rail intersection was classified under the elevated deck")

	# Rail fences need a physical clearance at every road crossing, including the
	# bridge. Only at-grade intersections receive gates and stop logic.
	if rail_line.has_method("set_detected_road_crossings"):
		rail_line.call("set_detected_road_crossings", all_intersections)
	else:
		_validation_errors.append("DistrictRailLine must accept detected crossing clearances")

	var generated := _generated_root("GeneratedRailCrossings")
	for intersection in _rail_intersections:
		var crossing := RAIL_CROSSING_SCRIPT.new() as RailLevelCrossing2D
		crossing.name = String(intersection.id)
		crossing.z_index = 5
		generated.add_child(crossing)
		var local_data := intersection.duplicate(true)
		local_data.position = generated.to_local(intersection.position)
		local_data.road_tangent = global_transform.basis_xform_inv(intersection.road_tangent).normalized()
		local_data.rail_tangent = global_transform.basis_xform_inv(intersection.rail_tangent).normalized()
		crossing.configure(local_data)
		_rail_crossing_nodes.append(crossing)


func _resolve_junction_reference(
	road_graph: Node2D,
	junctions: Array,
	reference: Dictionary,
	world_position: Vector2
) -> Dictionary:
	if reference.has("junction_index"):
		var explicit_index := int(reference.junction_index)
		if explicit_index >= 0 and explicit_index < junctions.size():
			return {"index": explicit_index, "id": _junction_id(explicit_index, junctions[explicit_index])}
	if reference.has("junction_id") and not String(reference.junction_id).is_empty():
		var explicit_id := StringName(String(reference.junction_id))
		for index in range(junctions.size()):
			if _junction_id(index, junctions[index]) == explicit_id:
				return {"index": index, "id": explicit_id}
		_validation_errors.append("Pedestrian crossing references unknown junction_id: %s" % explicit_id)
		return {"index": -1, "id": explicit_id}
	var nearest_index := -1
	var nearest_distance := INF
	for index in range(junctions.size()):
		var junction: Dictionary = junctions[index]
		var junction_world := road_graph.to_global(junction.position)
		var distance := world_position.distance_to(junction_world)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	if nearest_index >= 0 and nearest_distance <= signal_link_distance:
		return {"index": nearest_index, "id": _junction_id(nearest_index, junctions[nearest_index])}
	return {"index": -1, "id": StringName()}


func _junction_id(index: int, junction: Dictionary) -> StringName:
	if junction.has("id") and not String(junction.id).is_empty():
		return StringName(String(junction.id))
	var position: Vector2 = junction.get("position", Vector2.ZERO)
	return StringName("junction_%03d_%d_%d" % [index, roundi(position.x), roundi(position.y)])


func _find_road(roads: Array, requested_id: String) -> Dictionary:
	var matches: Array[int] = []
	for index in range(roads.size()):
		var road: Dictionary = roads[index]
		var candidate := String(road.get("id", ""))
		if candidate == requested_id or candidate.ends_with("/" + requested_id):
			matches.append(index)
	if matches.size() != 1:
		return {}
	return {"index": matches[0], "road": roads[matches[0]]}


func _sample_polyline_at_fraction(points: PackedVector2Array, fraction: float) -> Dictionary:
	if points.size() < 2:
		return {}
	var prefix := _polyline_prefix_lengths(points)
	var total: float = prefix[-1]
	if total <= 0.001:
		return {"position": points[0], "tangent": Vector2.RIGHT, "distance": 0.0}
	var target := clampf(fraction, 0.0, 1.0) * total
	for index in range(points.size() - 1):
		var a_distance: float = prefix[index]
		var b_distance: float = prefix[index + 1]
		if target <= b_distance or index == points.size() - 2:
			var segment_length := maxf(b_distance - a_distance, 0.001)
			return {
				"position": points[index].lerp(points[index + 1], (target - a_distance) / segment_length),
				"tangent": points[index].direction_to(points[index + 1]),
				"distance": target,
			}
	return {}


func _polyline_prefix_lengths(points: PackedVector2Array) -> PackedFloat32Array:
	var result := PackedFloat32Array([0.0])
	var total := 0.0
	for index in range(points.size() - 1):
		total += points[index].distance_to(points[index + 1])
		result.append(total)
	return result


func _is_under_elevated_span(world_position: Vector2, extra_clearance: float = 0.0) -> bool:
	var highway := _elevated_highway()
	if highway == null or not highway.has_method("get_elevated_corridor_data"):
		return false
	var data: Dictionary = highway.call("get_elevated_corridor_data")
	var points: PackedVector2Array = data.get("global_points", PackedVector2Array())
	var clearance := float(data.get("half_width", 0.0)) + float(data.get("safety_margin", 18.0)) + extra_clearance
	return _distance_to_polyline(world_position, points) <= clearance


func _is_on_elevated_source(road_id: String, road_t: float) -> bool:
	var highway := _elevated_highway()
	if highway == null or not highway.has_method("get_elevated_corridor_data"):
		return false
	var data: Dictionary = highway.call("get_elevated_corridor_data")
	if String(data.get("source_road_id", "")) != road_id:
		return false
	var from_t := float(data.get("from_t", -1.0))
	var to_t := float(data.get("to_t", -1.0))
	return from_t >= 0.0 and road_t >= minf(from_t, to_t) and road_t <= maxf(from_t, to_t)


func _run_elevated_span_audit(road_graph: Node2D, junctions: Array) -> void:
	var highway := _elevated_highway()
	if highway == null:
		_validation_warnings.append("Elevated highway node is unavailable; span exclusion could not be audited")
		return
	if not highway.has_method("get_elevated_corridor_data"):
		_validation_errors.append("Elevated highway must expose get_elevated_corridor_data()")
		return
	for index in range(junctions.size()):
		var junction: Dictionary = junctions[index]
		var world_position := road_graph.to_global(junction.position)
		if _is_under_elevated_span(world_position):
			_validation_errors.append("Road junction %s (%s) is forbidden under the elevated span" % [
				_junction_id(index, junction),
				", ".join(junction.get("road_ids", [])),
			])


func _run_z_order_audit(road_graph: Node2D, rail_line: Node2D) -> void:
	if rail_line == null:
		return
	var highway := _elevated_highway()
	if highway == null or not highway.has_method("get_elevated_corridor_data"):
		return
	var elevated_data: Dictionary = highway.call("get_elevated_corridor_data")
	var deck_z := int(elevated_data.get("deck_z_index", 6))
	if road_graph.z_index >= rail_line.z_index:
		_validation_errors.append("Z-order invalid: ordinary road graph must be below the railway")
	if rail_line.z_index >= deck_z:
		_validation_errors.append("Z-order invalid: railway must be below the elevated deck")


func _validate_rail_handoff(rail_line: Node2D) -> void:
	if rail_line == null:
		return
	var handoff := rail_line.get_node_or_null("District2RailConnection")
	if handoff == null:
		_validation_errors.append("Rail corridor is missing District2RailConnection handoff marker")
		return
	if not handoff.is_in_group("district_connection") or String(handoff.get_meta("connection_type", "")) != "rail":
		_validation_errors.append("Rail handoff marker is missing district_connection/rail metadata")


func _update_level_crossings_from_train() -> void:
	var rail_line := _rail_line()
	if rail_line == null or not rail_line.has_method("get_train_state"):
		return
	var state: Dictionary = rail_line.call("get_train_state")
	var route_length := float(state.get("route_length", 0.0))
	var train_active := bool(state.get("active", false)) and route_length > 0.0
	var progress := float(state.get("progress", 0.0))
	var consist_length := float(state.get("consist_length", 0.0))
	var speed := absf(float(state.get("speed", 0.0)))
	for crossing in _rail_crossing_nodes:
		if not is_instance_valid(crossing):
			continue
		var crossing_offset := crossing.rail_t * route_length
		var ahead := fposmod(crossing_offset - progress, route_length) if route_length > 0.0 else INF
		var behind := fposmod(progress - crossing_offset, route_length) if route_length > 0.0 else INF
		# The warning distance is derived from the actual skew/ballast geometry.
		# It covers arm travel plus the worst-case clearance of a vehicle which
		# has just committed past the entry gate.
		var lookahead := maxf(train_closing_lookahead, crossing.required_warning_distance(speed))
		var occupied_tail := consist_length + 44.0
		crossing.set_train_approaching(train_active and (ahead <= lookahead or behind <= occupied_tail))


func _bind_discovered_signal_controller(crossing: RoadCrossingArea2D) -> void:
	for controller in get_tree().get_nodes_in_group("junction_traffic_controller"):
		# JunctionTrafficController is a district-wide dispatcher. It resolves the
		# crossing's own junction_id+road_index when synchronizing signal state.
		crossing.set_signal_controller(controller)
		return


func _on_crossing_pedestrian_request(crossing_id: StringName, junction_id: StringName) -> void:
	crossing_pedestrian_request.emit(crossing_id, junction_id)


func _road_graph() -> Node2D:
	return get_node_or_null(road_graph_path) as Node2D


func _rail_line() -> Node2D:
	return get_node_or_null(rail_line_path) as Node2D


func _elevated_highway() -> Node2D:
	return get_node_or_null(elevated_highway_path) as Node2D


func _generated_root(root_name: String) -> Node2D:
	var root := get_node_or_null(root_name) as Node2D
	if root == null:
		root = Node2D.new()
		root.name = root_name
		add_child(root)
	return root


func _clear_generated_root(root_name: String) -> void:
	var root := get_node_or_null(root_name)
	if root != null:
		remove_child(root)
		root.free()


func _distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	if points.size() < 2:
		return INF
	var nearest := INF
	for index in range(points.size() - 1):
		nearest = minf(nearest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1])))
	return nearest


func _safe_name(value: String) -> String:
	return value.replace("/", "_").replace(" ", "_").replace("-", "_")


func _make_source_signature() -> String:
	var road_graph := _road_graph()
	var rail_line := _rail_line()
	var highway := _elevated_highway()
	var values: Array = [_pedestrian_reference_override]
	if road_graph != null and road_graph.has_method("get_graph_data"):
		values.append(road_graph.call("get_graph_data"))
	if rail_line != null and rail_line.has_method("get_rail_graph_data"):
		values.append(rail_line.call("get_rail_graph_data"))
	if highway != null and highway.has_method("get_elevated_corridor_data"):
		values.append(highway.call("get_elevated_corridor_data"))
	return str(values)


func _finish_rebuild() -> void:
	_source_signature = _make_source_signature()
	var summary := get_safety_data()
	safety_graph_rebuilt.emit(summary)
	if not _validation_errors.is_empty():
		push_warning("District road safety validation:\n%s" % "\n".join(_validation_errors))
	print("DISTRICT_ROAD_SAFETY: %s" % get_validation_summary())
