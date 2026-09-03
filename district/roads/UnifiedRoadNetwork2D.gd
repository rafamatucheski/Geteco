@tool
class_name UnifiedRoadNetwork2D
extends Node2D

## One renderer and one logical graph for every at-grade street in a district.
## Providers expose control points; this node owns snapping, spline baking,
## junction discovery, lane markings and validation.

const ROAD_COLOR := Color("#202932")
const ROAD_EDGE_COLOR := Color("#151c23")
const SIDEWALK_COLOR := Color("#aaa9a1")
const CURB_COLOR := Color("#70767a")
const LANE_COLOR := Color("#dfc84d")
const SIDEWALK_MARGIN := 42.0
const DASH_LENGTH := 28.0
const DASH_GAP := 26.0
const MIN_POINT_DISTANCE := 2.0
const GENERATED_LANES_NODE := "GeneratedLanePaths"
const GENERATED_CONNECTIONS_NODE := "GeneratedLaneConnections"
const TRAFFIC_DIRECTION_FORWARD := 1
const TRAFFIC_DIRECTION_REVERSE := -1

@export var provider_paths: Array[NodePath] = [
	NodePath("../Bairro1Expansion"),
	NodePath("../Bairro1RoadNetwork"),
]
@export_range(1.0, 160.0, 1.0) var snap_distance: float = 112.0:
	set(value):
		snap_distance = value
		_rebuild_graph()
@export_range(4, 32, 1) var curve_subdivisions: int = 12:
	set(value):
		curve_subdivisions = value
		_rebuild_graph()
@export var show_junction_debug: bool = false:
	set(value):
		show_junction_debug = value
		queue_redraw()

var _roads: Array[Dictionary] = []
var _junctions: Array[Dictionary] = []
var _lane_connections: Array[Dictionary] = []
var _validation_errors: Array[String] = []
var _source_signature := ""


func _ready() -> void:
	z_index = 2
	_rebuild_graph()
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	var signature := _make_source_signature()
	if signature != _source_signature:
		_rebuild_graph()


func _make_source_signature() -> String:
	var values: Array = [snap_distance, curve_subdivisions]
	for provider in _get_provider_nodes():
		values.append([provider.get_path(), provider.call("get_road_graph_definitions")])
	return str(values)


func _rebuild_graph() -> void:
	if not is_inside_tree():
		return
	_roads.clear()
	_junctions.clear()
	_lane_connections.clear()
	_validation_errors.clear()
	_collect_roads()
	_snap_endpoints_to_network()
	_bake_all_curves()
	_build_lane_paths()
	_discover_all_junctions()
	_build_junction_connections()
	_build_lane_connections()
	_validate_graph()
	_source_signature = _make_source_signature()
	queue_redraw()


func _collect_roads() -> void:
	for provider in _get_provider_nodes():
		var definitions: Array = provider.call("get_road_graph_definitions")
		for source in definitions:
			var definition := source as Dictionary
			var local_points := PackedVector2Array()
			for source_point in definition.get("points", PackedVector2Array()):
				local_points.append(to_local(provider.to_global(source_point)))
			var width := float(definition.get("width", 120.0))
			var source_lanes: Variant = definition.get("lanes", [])
			var has_explicit_lanes := source_lanes is Array and not (source_lanes as Array).is_empty()
			var lane_definitions := _copy_lane_definitions(source_lanes, width)
			_roads.append({
				"road_index": _roads.size(),
				"id": "%s/%s" % [provider.name, String(definition.get("id", "road"))],
				"control": local_points,
				"points": PackedVector2Array(),
				"width": width,
				"lane_definitions": lane_definitions,
				"lane_source": "provider" if has_explicit_lanes else "two_way_default",
				"lanes": [],
				"lane_count_by_direction": {},
				"junctions": [],
				"render": bool(definition.get("render", true)),
				"open_start": bool(definition.get("open_start", false)),
				"open_end": bool(definition.get("open_end", false)),
				"snap_start": String(definition.get("snap_start", "")),
				"snap_end": String(definition.get("snap_end", "")),
				"snap_start_mode": String(definition.get("snap_start_mode", "auto")),
				"snap_end_mode": String(definition.get("snap_end_mode", "auto")),
			})


func _copy_lane_definitions(source_lanes: Variant, road_width: float) -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	if source_lanes is Array:
		for source_lane in source_lanes:
			if source_lane is Dictionary:
				copied.append((source_lane as Dictionary).duplicate(true))
	# Editor-created legacy segments predate the lane contract. Giving them a
	# deterministic two-way layout keeps a newly drawn street usable, while the
	# canonical Bairro 1 providers publish this same data explicitly.
	if copied.is_empty():
		var offset := road_width * 0.25
		copied = [
			{"lane_id": "forward_01", "offset": offset, "direction": TRAFFIC_DIRECTION_FORWARD, "direction_name": "forward"},
			{"lane_id": "reverse_01", "offset": -offset, "direction": TRAFFIC_DIRECTION_REVERSE, "direction_name": "reverse"},
		]
	return copied


func _get_provider_nodes() -> Array[Node2D]:
	var providers: Array[Node2D] = []
	var known := {}
	for path in provider_paths:
		var provider := get_node_or_null(path) as Node2D
		if provider == null:
			continue
		if provider.has_method("get_road_graph_definitions"):
			providers.append(provider)
			known[provider.get_instance_id()] = true
	var composition_root := get_parent()
	if composition_root != null:
		var candidates := [composition_root]
		candidates.append_array(composition_root.find_children("*", "Node2D", true, false))
		for candidate in candidates:
			if candidate is Node2D and candidate.has_method("get_road_graph_definitions") and not known.has(candidate.get_instance_id()):
				providers.append(candidate as Node2D)
				known[candidate.get_instance_id()] = true
	return providers


func _snap_endpoints_to_network() -> void:
	# Endpoint-to-endpoint snapping is deterministic: the earlier provider is
	# the anchor, so a manually edited main street does not drift toward a spur.
	for first_index in range(_roads.size()):
		var first_control: PackedVector2Array = _roads[first_index].control
		if first_control.size() < 2:
			continue
		for second_index in range(first_index + 1, _roads.size()):
			var second_control: PackedVector2Array = _roads[second_index].control
			if second_control.size() < 2:
				continue
			for first_endpoint in [0, first_control.size() - 1]:
				for second_endpoint in [0, second_control.size() - 1]:
					if first_control[first_endpoint].distance_to(second_control[second_endpoint]) <= snap_distance:
						second_control[second_endpoint] = first_control[first_endpoint]
			_roads[first_index].control = first_control
			_roads[second_index].control = second_control

	# A side street may legitimately terminate on the middle of another spline.
	# Snap that endpoint to the exact closest point, creating a mathematical T.
	for road_index in range(_roads.size()):
		var control: PackedVector2Array = _roads[road_index].control
		if control.size() < 2:
			continue
		for endpoint_index in [0, control.size() - 1]:
			var endpoint := control[endpoint_index]
			var best_point := endpoint
			var best_distance := snap_distance + 0.001
			for other_index in range(_roads.size()):
				if other_index == road_index:
					continue
				var other_control: PackedVector2Array = _roads[other_index].control
				var sampled := _catmull_rom(other_control, curve_subdivisions)
				for segment_index in range(sampled.size() - 1):
					var closest := Geometry2D.get_closest_point_to_segment(endpoint, sampled[segment_index], sampled[segment_index + 1])
					var distance := endpoint.distance_to(closest)
					if distance < best_distance:
						best_distance = distance
						best_point = closest
			if best_distance <= snap_distance:
				control[endpoint_index] = best_point
		_roads[road_index].control = control

	# Named connections make authored entrances deterministic. Proximity remains
	# the default for new streets, while important links declare their owner.
	for road_index in range(_roads.size()):
		var control: PackedVector2Array = _roads[road_index].control
		if control.size() < 2:
			continue
		for endpoint_data in [
			{"index": 0, "target": String(_roads[road_index].snap_start), "mode": String(_roads[road_index].snap_start_mode)},
			{"index": control.size() - 1, "target": String(_roads[road_index].snap_end), "mode": String(_roads[road_index].snap_end_mode)},
		]:
			var target_id := String(endpoint_data.target)
			if target_id.is_empty():
				continue
			var target_index := _find_road_index(target_id)
			if target_index < 0:
				_validation_errors.append("Unknown snap target %s for %s" % [target_id, _roads[road_index].id])
				continue
			var target_curve := _catmull_rom(_roads[target_index].control, curve_subdivisions)
			var endpoint_index := int(endpoint_data.index)
			var target_info := _closest_point_and_tangent(control[endpoint_index], target_curve)
			control[endpoint_index] = target_info.position
			_align_endpoint_approach(control, endpoint_index, target_info.tangent, String(endpoint_data.mode))
		_roads[road_index].control = control


func _bake_all_curves() -> void:
	for road_index in range(_roads.size()):
		var control: PackedVector2Array = _roads[road_index].control
		_roads[road_index].points = _catmull_rom(control, curve_subdivisions)


func _build_lane_paths() -> void:
	var container := get_node_or_null(GENERATED_LANES_NODE) as Node2D
	if container == null:
		container = Node2D.new()
		container.name = GENERATED_LANES_NODE
		add_child(container)
	for child in container.get_children():
		container.remove_child(child)
		child.free()

	for road_index in range(_roads.size()):
		var road: Dictionary = _roads[road_index]
		var road_id := String(road.id)
		var generated_lanes: Array[Dictionary] = []
		var counts := {"forward": 0, "reverse": 0}
		var lane_definitions: Array = road.lane_definitions
		for lane_index in range(lane_definitions.size()):
			var definition := lane_definitions[lane_index] as Dictionary
			var direction := _normalise_lane_direction(definition.get("direction", TRAFFIC_DIRECTION_FORWARD))
			var direction_name := "forward" if direction == TRAFFIC_DIRECTION_FORWARD else "reverse"
			var local_lane_id := String(definition.get("lane_id", "%s_%02d" % [direction_name, lane_index + 1]))
			var lane_id := "%s/%s" % [road_id, local_lane_id]
			var offset := float(definition.get("offset", 0.0))
			var lane_points := _offset_lane_centerline(road.points, offset)
			if direction == TRAFFIC_DIRECTION_REVERSE:
				lane_points.reverse()

			var curve := Curve2D.new()
			curve.bake_interval = 8.0
			for point in lane_points:
				curve.add_point(point)
			var path := Path2D.new()
			path.name = _lane_node_name(road_id, local_lane_id)
			path.curve = curve
			path.set_meta("traffic_road_index", road_index)
			path.set_meta("traffic_road_id", road_id)
			path.set_meta("traffic_lane_id", lane_id)
			path.set_meta("traffic_direction", direction)
			path.set_meta("traffic_direction_name", direction_name)
			path.set_meta("traffic_lane_offset", offset)
			var is_loop := lane_points.size() > 2 and lane_points[0].distance_to(lane_points[-1]) <= MIN_POINT_DISTANCE
			path.set_meta("traffic_lane_loop", is_loop)
			container.add_child(path)
			path.add_to_group("unified_traffic_lane")

			generated_lanes.append({
				"road_index": road_index,
				"road_id": road_id,
				"lane_index": lane_index,
				"lane_id": lane_id,
				"offset": offset,
				"direction": direction,
				"direction_name": direction_name,
				"points": lane_points,
				"curve": curve,
				"path": path,
				"path_node_path": get_path_to(path),
				"loop": is_loop,
			})
			counts[direction_name] = int(counts[direction_name]) + 1
		_roads[road_index].lanes = generated_lanes
		_roads[road_index].lane_count_by_direction = counts
		_roads[road_index].traffic_directions = _traffic_directions_from_counts(counts)


func _normalise_lane_direction(value: Variant) -> int:
	if value is String or value is StringName:
		var label := String(value).to_lower()
		if label in ["reverse", "backward", "inbound", "-1"]:
			return TRAFFIC_DIRECTION_REVERSE
		return TRAFFIC_DIRECTION_FORWARD
	return TRAFFIC_DIRECTION_REVERSE if int(value) < 0 else TRAFFIC_DIRECTION_FORWARD


func _traffic_directions_from_counts(counts: Dictionary) -> Array[int]:
	var directions: Array[int] = []
	if int(counts.get("forward", 0)) > 0:
		directions.append(TRAFFIC_DIRECTION_FORWARD)
	if int(counts.get("reverse", 0)) > 0:
		directions.append(TRAFFIC_DIRECTION_REVERSE)
	return directions


func _lane_node_name(road_id: String, local_lane_id: String) -> String:
	return ("%s__%s" % [road_id, local_lane_id]).replace("/", "__").replace(" ", "_")


func _offset_lane_centerline(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var shifted := PackedVector2Array()
	for index in range(points.size()):
		var before := points[maxi(0, index - 1)]
		var after := points[mini(points.size() - 1, index + 1)]
		var tangent := before.direction_to(after)
		if tangent.is_zero_approx():
			tangent = Vector2.RIGHT
		shifted.append(points[index] + tangent.orthogonal() * amount)
	return shifted


func _discover_all_junctions() -> void:
	# Discover exact endpoint connections and every at-grade spline crossing.
	for first_index in range(_roads.size()):
		var first_points: PackedVector2Array = _roads[first_index].points
		for second_index in range(first_index + 1, _roads.size()):
			var second_points: PackedVector2Array = _roads[second_index].points
			for first_segment in range(first_points.size() - 1):
				for second_segment in range(second_points.size() - 1):
					var hit = Geometry2D.segment_intersects_segment(
						first_points[first_segment], first_points[first_segment + 1],
						second_points[second_segment], second_points[second_segment + 1]
					)
					if hit != null:
						_add_junction(hit as Vector2, first_index, second_index)
	# Collinear/T connections can touch without producing a stable crossing hit.
	for road_index in range(_roads.size()):
		var points: PackedVector2Array = _roads[road_index].points
		for endpoint in [points[0], points[-1]]:
			for other_index in range(_roads.size()):
				if other_index == road_index:
					continue
				if _distance_to_polyline(endpoint, _roads[other_index].points) <= 0.75:
					_add_junction(endpoint, road_index, other_index)


func _add_junction(position: Vector2, first_road: int, second_road: int) -> void:
	for junction in _junctions:
		if (junction.position as Vector2).distance_to(position) <= 10.0:
			var roads: Array = junction.roads
			if not roads.has(first_road):
				roads.append(first_road)
			if not roads.has(second_road):
				roads.append(second_road)
			junction.roads = roads
			junction.radius = _junction_clearance(roads)
			return
	var connected_roads: Array[int] = [first_road, second_road]
	_junctions.append({"position": position, "roads": connected_roads, "radius": _junction_clearance(connected_roads)})


func _junction_clearance(road_indices: Array) -> float:
	var widest := 0.0
	for road_index in road_indices:
		widest = maxf(widest, float(_roads[int(road_index)].width))
	return widest * 0.68 + 14.0


func _build_junction_connections() -> void:
	for road_index in range(_roads.size()):
		_roads[road_index].junctions = []
	for junction_index in range(_junctions.size()):
		var junction: Dictionary = _junctions[junction_index]
		var road_ids: Array[String] = []
		var connections: Array[Dictionary] = []
		var approaches: Array[Dictionary] = []
		for road_index_value in junction.roads:
			var road_index := int(road_index_value)
			var road: Dictionary = _roads[road_index]
			var location := _closest_location_on_polyline(junction.position, road.points)
			var road_id := String(road.id)
			var road_approaches: Array[Dictionary] = []
			var entry_angles: Array[float] = []
			for direction in _entry_directions_at(location):
				var lane_ids: Array[String] = []
				for lane_value in road.lanes:
					var lane := lane_value as Dictionary
					if int(lane.direction) == direction:
						lane_ids.append(String(lane.lane_id))
				if lane_ids.is_empty():
					continue
				var entry_tangent: Vector2 = (location.tangent as Vector2) * float(direction)
				var entry_angle := entry_tangent.angle()
				var approach := {
					"approach_id": "%d:%s:%s" % [junction_index, road_id, "forward" if direction > 0 else "reverse"],
					"junction_index": junction_index,
					"road_index": road_index,
					"road_id": road_id,
					"direction": direction,
					"direction_name": "forward" if direction > 0 else "reverse",
					"lane_ids": lane_ids,
					"road_progress": float(location.progress),
					"entry_tangent": entry_tangent,
					"tangent": entry_tangent,
					"entry_angle": entry_angle,
					"angle": entry_angle,
					"angle_degrees": rad_to_deg(entry_angle),
				}
				road_approaches.append(approach)
				approaches.append(approach)
				entry_angles.append(entry_angle)
			road_ids.append(road_id)
			connections.append({
				"road_index": road_index,
				"road_id": road_id,
				"road_progress": float(location.progress),
				"distance_along": float(location.distance_along),
				"total_length": float(location.total_length),
				"position_on_road": location.position,
				"forward_tangent": location.tangent,
				"forward_angle": (location.tangent as Vector2).angle(),
				"entry_angles": entry_angles,
				"approaches": road_approaches,
			})
			var road_junctions: Array = _roads[road_index].junctions
			road_junctions.append({
				"junction_index": junction_index,
				"road_progress": float(location.progress),
				"position": junction.position,
			})
			_roads[road_index].junctions = road_junctions
		junction.index = junction_index
		junction.id = "junction_%03d_%d_%d" % [junction_index, roundi((junction.position as Vector2).x), roundi((junction.position as Vector2).y)]
		junction.road_ids = road_ids
		junction.connections = connections
		junction.approaches = approaches
		_junctions[junction_index] = junction

	for road_index in range(_roads.size()):
		var road_junctions: Array = _roads[road_index].junctions
		road_junctions.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			return float(first.road_progress) < float(second.road_progress)
		)
		_roads[road_index].junctions = road_junctions
		var junction_indices: Array[int] = []
		for junction_ref in road_junctions:
			junction_indices.append(int((junction_ref as Dictionary).junction_index))
		for lane_value in _roads[road_index].lanes:
			var lane := lane_value as Dictionary
			var path := lane.path as Path2D
			path.set_meta("traffic_junction_indices", junction_indices)


func _build_lane_connections() -> void:
	var container := get_node_or_null(GENERATED_CONNECTIONS_NODE) as Node2D
	if container == null:
		container = Node2D.new()
		container.name = GENERATED_CONNECTIONS_NODE
		add_child(container)
	for child in container.get_children():
		container.remove_child(child)
		child.free()

	var lanes_by_id := {}
	for road_index in range(_roads.size()):
		for lane_value in _roads[road_index].lanes:
			var lane := lane_value as Dictionary
			lane.allowed_exits = []
			lanes_by_id[String(lane.lane_id)] = lane

	for junction_index in range(_junctions.size()):
		var junction: Dictionary = _junctions[junction_index]
		var junction_lane_connections: Array[Dictionary] = []
		for approach_value in junction.approaches:
			var approach := approach_value as Dictionary
			for from_lane_id_value in approach.lane_ids:
				var from_lane_id := String(from_lane_id_value)
				var from_lane := lanes_by_id.get(from_lane_id, {}) as Dictionary
				if from_lane.is_empty():
					continue
				for target_value in junction.connections:
					var target := target_value as Dictionary
					var to_road_index := int(target.road_index)
					for to_direction in _exit_directions_at(target):
						for to_lane_value in _roads[to_road_index].lanes:
							var to_lane := to_lane_value as Dictionary
							if int(to_lane.direction) != to_direction:
								continue
							var same_road := int(from_lane.road_index) == to_road_index
							var same_lane := from_lane_id == String(to_lane.lane_id)
							# A lane continues through an interior junction; changing to the
							# opposite lane of the same road would be an illegal U-turn.
							if same_road and not same_lane:
								continue
							var outgoing_tangent: Vector2 = (target.forward_tangent as Vector2) * float(to_direction)
							var turn_angle := wrapf(outgoing_tangent.angle() - float(approach.entry_angle), -PI, PI)
							if not same_lane and absf(turn_angle) > deg_to_rad(150.0):
								continue
							var movement := _movement_name(turn_angle, same_lane)
							var connection_id := "%d:%s>%s" % [junction_index, from_lane_id, String(to_lane.lane_id)]
							var connector_data := {
								"path": null,
								"curve": null,
								"path_node_path": NodePath(),
								"entry_curve_offset": -1.0,
								"exit_curve_offset": -1.0,
								"entry_lane_progress": float(approach.road_progress),
								"exit_lane_progress": float(target.road_progress),
							}
							if not same_lane:
								connector_data = _create_lane_connector_path(
									container, connection_id, junction, from_lane, to_lane, movement, turn_angle
								)
							var connection := {
								"connection_id": connection_id,
								"junction_index": junction_index,
								"from_road_index": int(from_lane.road_index),
								"from_road_id": String(from_lane.road_id),
								"from_lane_id": from_lane_id,
								"from_direction": int(from_lane.direction),
								"from_road_progress": float(approach.road_progress),
								"to_road_index": to_road_index,
								"to_road_id": String(to_lane.road_id),
								"to_lane_id": String(to_lane.lane_id),
								"to_direction": int(to_lane.direction),
								"to_road_progress": float(target.road_progress),
								"movement": movement,
								"turn_angle": turn_angle,
								"requires_connector": not same_lane,
								"path": connector_data.path,
								"curve": connector_data.curve,
								"path_node_path": connector_data.path_node_path,
								"entry_curve_offset": float(connector_data.entry_curve_offset),
								"exit_curve_offset": float(connector_data.exit_curve_offset),
								"entry_lane_progress": float(connector_data.entry_lane_progress),
								"exit_lane_progress": float(connector_data.exit_lane_progress),
							}
							_lane_connections.append(connection)
							junction_lane_connections.append(connection)
							var allowed_exits: Array = from_lane.allowed_exits
							allowed_exits.append({
								"connection_id": connection_id,
								"junction_index": junction_index,
								"to_road_index": to_road_index,
								"to_road_id": String(to_lane.road_id),
								"to_lane_id": String(to_lane.lane_id),
								"movement": movement,
								"turn_angle": turn_angle,
								"requires_connector": not same_lane,
								"connector_path": connector_data.path_node_path,
							})
							from_lane.allowed_exits = allowed_exits
		junction.lane_connections = junction_lane_connections
		_junctions[junction_index] = junction

	for road in _roads:
		for lane_value in road.lanes:
			var lane := lane_value as Dictionary
			var connection_ids: Array[String] = []
			for exit_value in lane.allowed_exits:
				connection_ids.append(String((exit_value as Dictionary).connection_id))
			var path := lane.path as Path2D
			path.set_meta("traffic_lane_connection_ids", connection_ids)


func _exit_directions_at(location: Dictionary) -> Array[int]:
	var distance_along := float(location.distance_along)
	var total_length := float(location.total_length)
	var endpoint_tolerance := minf(12.0, maxf(MIN_POINT_DISTANCE, total_length * 0.002))
	if distance_along <= endpoint_tolerance:
		return [TRAFFIC_DIRECTION_FORWARD]
	if total_length - distance_along <= endpoint_tolerance:
		return [TRAFFIC_DIRECTION_REVERSE]
	return [TRAFFIC_DIRECTION_FORWARD, TRAFFIC_DIRECTION_REVERSE]


func _movement_name(turn_angle: float, same_lane: bool) -> String:
	if same_lane or absf(turn_angle) < deg_to_rad(20.0):
		return "straight"
	# Positive rotation is clockwise in Godot's screen coordinate system.
	return "right" if turn_angle > 0.0 else "left"


func _create_lane_connector_path(
	container: Node2D,
	connection_id: String,
	junction: Dictionary,
	from_lane: Dictionary,
	to_lane: Dictionary,
	movement: String,
	turn_angle: float
) -> Dictionary:
	var from_curve := from_lane.curve as Curve2D
	var to_curve := to_lane.curve as Curve2D
	var junction_position := junction.position as Vector2
	var from_closest := from_curve.get_closest_offset(junction_position)
	var to_closest := to_curve.get_closest_offset(junction_position)
	var trim_distance := maxf(18.0, float(junction.radius) * 0.72)
	var entry_offset := maxf(0.0, from_closest - trim_distance)
	var exit_offset := minf(to_curve.get_baked_length(), to_closest + trim_distance)
	var entry_point := from_curve.sample_baked(entry_offset, true)
	var exit_point := to_curve.sample_baked(exit_offset, true)
	var entry_tangent := _curve_tangent_at(from_curve, entry_offset)
	var exit_tangent := _curve_tangent_at(to_curve, exit_offset)
	var handle_length := clampf(entry_point.distance_to(exit_point) * 0.36, 12.0, trim_distance)

	var connector_curve := Curve2D.new()
	connector_curve.bake_interval = 6.0
	connector_curve.add_point(entry_point, Vector2.ZERO, entry_tangent * handle_length)
	connector_curve.add_point(exit_point, -exit_tangent * handle_length, Vector2.ZERO)
	var connector := Path2D.new()
	connector.name = _lane_node_name("connector", connection_id)
	connector.curve = connector_curve
	connector.set_meta("traffic_connection_id", connection_id)
	connector.set_meta("traffic_junction_index", int(junction.index))
	connector.set_meta("traffic_from_road_index", int(from_lane.road_index))
	connector.set_meta("traffic_from_road_id", String(from_lane.road_id))
	connector.set_meta("traffic_from_lane_id", String(from_lane.lane_id))
	connector.set_meta("traffic_to_road_index", int(to_lane.road_index))
	connector.set_meta("traffic_to_road_id", String(to_lane.road_id))
	connector.set_meta("traffic_to_lane_id", String(to_lane.lane_id))
	connector.set_meta("traffic_movement", movement)
	connector.set_meta("traffic_turn_angle", turn_angle)
	connector.set_meta("traffic_lane_loop", false)
	container.add_child(connector)
	connector.add_to_group("unified_lane_connector")
	return {
		"path": connector,
		"curve": connector_curve,
		"path_node_path": get_path_to(connector),
		"entry_curve_offset": entry_offset,
		"exit_curve_offset": exit_offset,
		"entry_lane_progress": entry_offset / from_curve.get_baked_length() if from_curve.get_baked_length() > 0.0 else 0.0,
		"exit_lane_progress": exit_offset / to_curve.get_baked_length() if to_curve.get_baked_length() > 0.0 else 0.0,
	}


func _curve_tangent_at(curve: Curve2D, offset: float) -> Vector2:
	var length := curve.get_baked_length()
	var before := curve.sample_baked(maxf(0.0, offset - 2.0), true)
	var after := curve.sample_baked(minf(length, offset + 2.0), true)
	var tangent := before.direction_to(after)
	return tangent if not tangent.is_zero_approx() else Vector2.RIGHT


func _entry_directions_at(location: Dictionary) -> Array[int]:
	var distance_along := float(location.distance_along)
	var total_length := float(location.total_length)
	var endpoint_tolerance := minf(12.0, maxf(MIN_POINT_DISTANCE, total_length * 0.002))
	if distance_along <= endpoint_tolerance:
		return [TRAFFIC_DIRECTION_REVERSE]
	if total_length - distance_along <= endpoint_tolerance:
		return [TRAFFIC_DIRECTION_FORWARD]
	return [TRAFFIC_DIRECTION_FORWARD, TRAFFIC_DIRECTION_REVERSE]


func _closest_location_on_polyline(point: Vector2, points: PackedVector2Array) -> Dictionary:
	var total_length := 0.0
	for index in range(points.size() - 1):
		total_length += points[index].distance_to(points[index + 1])
	var nearest := INF
	var travelled := 0.0
	var result_position := point
	var result_tangent := Vector2.RIGHT
	var result_distance_along := 0.0
	var result_segment := -1
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		var segment_length := a.distance_to(b)
		if segment_length < MIN_POINT_DISTANCE:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var distance := point.distance_to(closest)
		if distance < nearest:
			nearest = distance
			result_position = closest
			result_tangent = a.direction_to(b)
			result_distance_along = travelled + a.distance_to(closest)
			result_segment = index
		travelled += segment_length
	return {
		"position": result_position,
		"tangent": result_tangent,
		"distance": nearest,
		"distance_along": result_distance_along,
		"total_length": total_length,
		"progress": result_distance_along / total_length if total_length > 0.0 else 0.0,
		"segment_index": result_segment,
	}


func _draw() -> void:
	if _roads.is_empty():
		return
	# Material passes are global. Sidewalks can never be painted over finished
	# asphalt because all outer layers are completed before any inner layer.
	_draw_road_pass(SIDEWALK_COLOR, SIDEWALK_MARGIN * 2.0)
	_draw_road_pass(CURB_COLOR, 10.0)
	_draw_road_pass(ROAD_EDGE_COLOR, 4.0)
	_draw_road_pass(ROAD_COLOR, 0.0)
	for road in _roads:
		if bool(road.render):
			_draw_lane_markings(road.points)
	if show_junction_debug:
		for junction in _junctions:
			draw_circle(junction.position, 9.0, Color(0.15, 0.9, 0.55, 0.85))


func _draw_road_pass(color: Color, extra_width: float) -> void:
	for road in _roads:
		if bool(road.render):
			var surfaces := Geometry2D.offset_polyline(
				road.points,
				(float(road.width) + extra_width) * 0.5,
				Geometry2D.JOIN_ROUND,
				Geometry2D.END_BUTT
			)
			for surface in surfaces:
				var polygon := surface as PackedVector2Array
				if polygon.size() >= 3 and not Geometry2D.is_polygon_clockwise(polygon):
					draw_colored_polygon(polygon, color)


func _draw_lane_markings(points: PackedVector2Array) -> void:
	var travelled := 0.0
	var cycle_length := DASH_LENGTH + DASH_GAP
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		var segment_length := a.distance_to(b)
		if segment_length < MIN_POINT_DISTANCE:
			continue
		var direction := a.direction_to(b)
		var walked := 0.0
		while walked < segment_length - 0.01:
			var phase := fmod(travelled + walked, cycle_length)
			var drawing := phase < DASH_LENGTH
			var remaining := (DASH_LENGTH - phase) if drawing else (cycle_length - phase)
			var step := minf(remaining, segment_length - walked)
			if drawing and step > 0.5:
				var from := a + direction * walked
				var to := a + direction * (walked + step)
				if not _marking_hits_junction((from + to) * 0.5):
					draw_line(from, to, LANE_COLOR, 3.0, true)
			walked += maxf(step, 0.5)
		travelled += segment_length


func _marking_hits_junction(point: Vector2) -> bool:
	for junction in _junctions:
		if point.distance_to(junction.position) < float(junction.radius):
			return true
	return false


func _validate_graph() -> void:
	var ids := {}
	var lane_ids := {}
	var endpoint_pairs := {}
	for road_index in range(_roads.size()):
		var road: Dictionary = _roads[road_index]
		var road_id := String(road.id)
		if ids.has(road_id):
			_validation_errors.append("Duplicate road id: %s" % road_id)
		ids[road_id] = true
		var control: PackedVector2Array = road.control
		if control.size() < 2:
			_validation_errors.append("Road %s has fewer than two control points" % road_id)
			continue
		if float(road.width) < 16.0:
			_validation_errors.append("Road %s has invalid width" % road_id)
		var lanes: Array = road.lanes
		if lanes.is_empty():
			_validation_errors.append("Road %s has no traffic lanes" % road_id)
		var actual_counts := {"forward": 0, "reverse": 0}
		for lane_value in lanes:
			var lane := lane_value as Dictionary
			var lane_id := String(lane.get("lane_id", ""))
			if lane_id.is_empty():
				_validation_errors.append("Road %s has a lane without lane_id" % road_id)
			elif lane_ids.has(lane_id):
				_validation_errors.append("Duplicate lane id: %s" % lane_id)
			lane_ids[lane_id] = true
			if int(lane.get("road_index", -1)) != road_index or String(lane.get("road_id", "")) != road_id:
				_validation_errors.append("Lane %s has inconsistent road ownership" % lane_id)
			var direction := int(lane.get("direction", 0))
			if direction != TRAFFIC_DIRECTION_FORWARD and direction != TRAFFIC_DIRECTION_REVERSE:
				_validation_errors.append("Lane %s has invalid direction" % lane_id)
			var direction_name := "forward" if direction == TRAFFIC_DIRECTION_FORWARD else "reverse"
			actual_counts[direction_name] = int(actual_counts[direction_name]) + 1
			if absf(float(lane.get("offset", 0.0))) >= float(road.width) * 0.5:
				_validation_errors.append("Lane %s lies outside road %s" % [lane_id, road_id])
			var lane_points: PackedVector2Array = lane.get("points", PackedVector2Array())
			if lane_points.size() != (road.points as PackedVector2Array).size():
				_validation_errors.append("Lane %s does not follow the complete baked road" % lane_id)
			var path := lane.get("path") as Path2D
			if path == null or path.curve == null or path.curve.get_point_count() != lane_points.size():
				_validation_errors.append("Lane %s has no matching Path2D/Curve2D" % lane_id)
			elif not path.is_in_group("unified_traffic_lane"):
				_validation_errors.append("Lane %s is missing unified_traffic_lane group" % lane_id)
		if actual_counts != (road.lane_count_by_direction as Dictionary):
			_validation_errors.append("Road %s lane direction counts are inconsistent" % road_id)
		for index in range(control.size() - 1):
			if control[index].distance_to(control[index + 1]) < MIN_POINT_DISTANCE:
				_validation_errors.append("Road %s has a degenerate segment at %d" % [road_id, index])
		var road_surfaces := Geometry2D.offset_polyline(
			road.points,
			float(road.width) * 0.5,
			Geometry2D.JOIN_ROUND,
			Geometry2D.END_BUTT
		)
		if road_surfaces.is_empty():
			_validation_errors.append("Road %s did not produce a surface polygon" % road_id)
		for surface in road_surfaces:
			var polygon := surface as PackedVector2Array
			if polygon.size() < 3 or Geometry2D.triangulate_polygon(polygon).is_empty():
				_validation_errors.append("Road %s produced invalid triangulation" % road_id)
		var pair_key := _endpoint_pair_key(control[0], control[-1])
		if endpoint_pairs.has(pair_key):
			_validation_errors.append("Duplicate segment endpoints: %s and %s" % [endpoint_pairs[pair_key], road_id])
		endpoint_pairs[pair_key] = road_id
		_validate_endpoint(road_index, 0, bool(road.open_start))
		_validate_endpoint(road_index, control.size() - 1, bool(road.open_end))
	for junction_index in range(_junctions.size()):
		var junction: Dictionary = _junctions[junction_index]
		if (junction.roads as Array).size() < 2:
			_validation_errors.append("Junction %d has fewer than two connected roads" % junction_index)
		if (junction.connections as Array).size() != (junction.roads as Array).size():
			_validation_errors.append("Junction %d has incomplete road connection metadata" % junction_index)
		if (junction.approaches as Array).is_empty():
			_validation_errors.append("Junction %d has no directed approaches" % junction_index)
		if (junction.lane_connections as Array).is_empty():
			_validation_errors.append("Junction %d has no navigable lane connections" % junction_index)
		for road_index in junction.roads:
			if _distance_to_polyline(junction.position, _roads[int(road_index)].points) > 0.75:
				_validation_errors.append("Junction %d is not on road %s" % [junction_index, _roads[int(road_index)].id])
	if _lane_connections.is_empty():
		_validation_errors.append("Road graph has no navigable lane connections")
	var connection_ids := {}
	var lanes_with_exits := {}
	for connection_value in _lane_connections:
		var connection := connection_value as Dictionary
		var connection_id := String(connection.get("connection_id", ""))
		if connection_id.is_empty() or connection_ids.has(connection_id):
			_validation_errors.append("Missing or duplicate lane connection id: %s" % connection_id)
		connection_ids[connection_id] = true
		lanes_with_exits[String(connection.get("from_lane_id", ""))] = true
		if not lane_ids.has(String(connection.get("from_lane_id", ""))) or not lane_ids.has(String(connection.get("to_lane_id", ""))):
			_validation_errors.append("Lane connection %s references an unknown lane" % connection_id)
		if bool(connection.get("requires_connector", false)):
			var connector := connection.get("path") as Path2D
			if connector == null or connector.curve == null or connector.curve.get_point_count() < 2:
				_validation_errors.append("Lane connection %s has no connector curve" % connection_id)
			elif not connector.is_in_group("unified_lane_connector"):
				_validation_errors.append("Lane connection %s is missing unified_lane_connector group" % connection_id)
	for junction in _junctions:
		for approach_value in junction.approaches:
			for lane_id_value in (approach_value as Dictionary).lane_ids:
				if not lanes_with_exits.has(String(lane_id_value)):
					_validation_errors.append("Inbound lane %s has no allowed exit" % String(lane_id_value))
	if not _validation_errors.is_empty():
		push_warning("Unified road graph validation:\n%s" % "\n".join(_validation_errors))


func _validate_endpoint(road_index: int, endpoint_index: int, explicitly_open: bool) -> void:
	if explicitly_open:
		return
	var control: PackedVector2Array = _roads[road_index].control
	var endpoint := control[endpoint_index]
	for other_index in range(_roads.size()):
		if other_index != road_index and _distance_to_polyline(endpoint, _roads[other_index].points) <= 0.75:
			return
	_validation_errors.append("Disconnected endpoint: %s at %s" % [_roads[road_index].id, endpoint])


func _endpoint_pair_key(a: Vector2, b: Vector2) -> String:
	var first := "%d,%d" % [roundi(a.x * 10.0), roundi(a.y * 10.0)]
	var second := "%d,%d" % [roundi(b.x * 10.0), roundi(b.y * 10.0)]
	return "%s|%s" % [first, second] if first < second else "%s|%s" % [second, first]


func _distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	var nearest := INF
	for index in range(points.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1])
		nearest = minf(nearest, point.distance_to(closest))
	return nearest


func _closest_point_on_polyline(point: Vector2, points: PackedVector2Array) -> Vector2:
	var result := point
	var nearest := INF
	for index in range(points.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1])
		var distance := point.distance_to(closest)
		if distance < nearest:
			nearest = distance
			result = closest
	return result


func _closest_point_and_tangent(point: Vector2, points: PackedVector2Array) -> Dictionary:
	var result := point
	var tangent := Vector2.RIGHT
	var nearest := INF
	for index in range(points.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1])
		var distance := point.distance_to(closest)
		if distance < nearest:
			nearest = distance
			result = closest
			tangent = points[index].direction_to(points[index + 1])
	return {"position": result, "tangent": tangent}


func _align_endpoint_approach(control: PackedVector2Array, endpoint_index: int, target_tangent: Vector2, mode: String) -> void:
	if control.size() < 3 or target_tangent.is_zero_approx():
		return
	var adjacent_index := 1 if endpoint_index == 0 else control.size() - 2
	var endpoint := control[endpoint_index]
	var adjacent := control[adjacent_index]
	var incoming := adjacent.direction_to(endpoint)
	var tangent := target_tangent.normalized()
	var perpendicular := tangent.orthogonal()
	if perpendicular.dot(incoming) < 0.0:
		perpendicular = -perpendicular
	if tangent.dot(incoming) < 0.0:
		tangent = -tangent
	var chosen := tangent
	if mode == "perpendicular" or (mode == "auto" and absf(incoming.dot(target_tangent.normalized())) < 0.72):
		chosen = perpendicular
	var approach_length := clampf(adjacent.distance_to(endpoint), 90.0, 210.0)
	control[adjacent_index] = endpoint - chosen * approach_length


func _find_road_index(road_id: String) -> int:
	for index in range(_roads.size()):
		if String(_roads[index].id) == road_id:
			return index
	return -1


func _catmull_rom(control: PackedVector2Array, subdivisions: int) -> PackedVector2Array:
	var sampled := PackedVector2Array()
	if control.size() < 2:
		return control.duplicate()
	for index in range(control.size() - 1):
		var p0 := control[maxi(0, index - 1)]
		var p1 := control[index]
		var p2 := control[index + 1]
		var p3 := control[mini(control.size() - 1, index + 2)]
		for step in subdivisions:
			var t := float(step) / float(subdivisions)
			var t2 := t * t
			var t3 := t2 * t
			sampled.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	sampled.append(control[-1])
	return sampled


func get_graph_data() -> Dictionary:
	var lanes: Array[Dictionary] = []
	for road in _roads:
		for lane_value in road.lanes:
			lanes.append((lane_value as Dictionary).duplicate(true))
	return {
		"roads": _roads.duplicate(true),
		"lanes": lanes,
		"lane_connections": _lane_connections.duplicate(true),
		"junctions": _junctions.duplicate(true),
		"validation_errors": _validation_errors.duplicate(),
	}


func get_lane_path(lane_id: String) -> Path2D:
	for road in _roads:
		for lane_value in road.lanes:
			var lane := lane_value as Dictionary
			if String(lane.lane_id) == lane_id:
				return lane.path as Path2D
	return null


func get_validation_summary() -> String:
	var lane_count := 0
	for road in _roads:
		lane_count += (road.lanes as Array).size()
	return "roads=%d lanes=%d junctions=%d lane_connections=%d errors=%d" % [
		_roads.size(), lane_count, _junctions.size(), _lane_connections.size(), _validation_errors.size()
	]
