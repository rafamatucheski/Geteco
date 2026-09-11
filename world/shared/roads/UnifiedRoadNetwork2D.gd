@tool
class_name UnifiedRoadNetwork2D
extends Node2D

## One renderer and one logical graph for every at-grade street in a district.
## Providers expose control points; this node owns snapping, spline baking,
## junction discovery, lane markings and validation.

const ROAD_COLOR := Color("#202932")
const BRIDGE_SURFACE = preload("res://world/shared/roads/BridgeSurfaceStyle.gd")
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
## Junction material is restricted to the already discovered conflict core.
## This small padding hides butt-cap precision seams without letting a shallow
## approach project asphalt hundreds of pixels into lots or sidewalks.
const JUNCTION_CORE_PADDING := 8.0
const JUNCTION_CORE_EDGE_CLEARANCE := 2.0
const JUNCTION_ARM_MERGE_COSINE := 0.99862953475 # cos(3 degrees)
const JUNCTION_SURFACE_EPSILON := 0.05
const GENERATED_GUARD_RAILS_NODE := "GeneratedGuardRails"
const GUARD_RAIL_THICKNESS := 10.0
## How close a rail segment may sit to a junction center before it is skipped,
## so intersections/merges never get sealed off by their own shoulder wall.
const GUARD_RAIL_JUNCTION_CLEARANCE := 26.0
## Same dark-GTA vocabulary as the rest of the district: a flat base tone plus
## small vector tufts, never a raster texture, so it can never render at the
## wrong scale the way a photo tile did.
const GROUND_COLOR := Color("#2c3a28")
const GRASS_TUFT_LIGHT := Color("#4c6a3f")
const GRASS_TUFT_DARK := Color("#37502f")
const GRASS_TUFT_SPACING := 46.0
const GRASS_BOUNDS_MARGIN := 260.0

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
## Optional explicit exceptions keyed by canonical junction id
## (`junction_003_1200_900`) or quantized position (`1200,900`). The default
## is systemic: only junctions with at least three incoming approaches receive
## traffic lights. Conflict reservations still exist for every junction.
@export var signalized_junction_overrides: Dictionary = {}:
	set(value):
		signalized_junction_overrides = value.duplicate(true)
		_rebuild_graph()
## Local exceptions for junctions whose approach geometry needs a wider gap
## between generated shoulder walls. Keys accept the same junction id/position
## forms as signalized_junction_overrides, plus a stable sorted road-id signature.
@export var guard_rail_junction_clearance_overrides: Dictionary = {}:
	set(value):
		guard_rail_junction_clearance_overrides = value.duplicate(true)
		_rebuild_graph()
@export var show_junction_debug: bool = false:
	set(value):
		show_junction_debug = value
		queue_redraw()
## Off by default until parking lots, garages and district connections have
## dedicated openings. These are
## generated StaticBody2D walls at the outer edge of each road's sidewalk
## (skipped near junctions and near any road end marked open_start/open_end),
## meant to stop vehicles from leaving the paved network into the surrounding
## grass. They CAN accidentally seal off an entrance this graph does not know
## about (e.g. a driveway that is not itself one of the authored roads) --
## Keep new entrances covered by runtime navigation tests; widen
## GUARD_RAIL_JUNCTION_CLEARANCE or
## mark the road open_start/open_end if something gets blocked.
@export var build_guard_rails: bool = false:
	set(value):
		build_guard_rails = value
		_rebuild_graph()

var _roads: Array[Dictionary] = []
var _routing_revision: int = 0
var _junctions: Array[Dictionary] = []
var _lane_connections: Array[Dictionary] = []
var _junction_exclusion_ranges: Array[Dictionary] = []
var _grade_separated_crossings: Array[Dictionary] = []
var _surface_topology_audit: Array[Dictionary] = []
var _validation_errors: Array[String] = []
var _source_signature := ""
var _grass_bounds := Rect2()


func _ready() -> void:
	z_index = 2
	_rebuild_graph()
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	var signature := _make_source_signature()
	if signature != _source_signature:
		_rebuild_graph()


func _make_source_signature() -> String:
	var values: Array = [snap_distance, curve_subdivisions, signalized_junction_overrides, guard_rail_junction_clearance_overrides]
	for provider in _get_provider_nodes():
		values.append([provider.get_path(), provider.call("get_road_graph_definitions")])
	for corridor_source in _get_elevated_corridor_sources():
		values.append([corridor_source.get_path(), corridor_source.call("get_elevated_corridor_data")])
	return str(values)


func _rebuild_graph() -> void:
	if not is_inside_tree():
		return
	_roads.clear()
	_junctions.clear()
	_lane_connections.clear()
	_junction_exclusion_ranges.clear()
	_grade_separated_crossings.clear()
	_surface_topology_audit.clear()
	_validation_errors.clear()
	_collect_roads()
	_snap_endpoints_to_network()
	_bake_all_curves()
	_update_grass_bounds()
	_build_junction_exclusion_ranges()
	_build_lane_paths()
	_discover_all_junctions()
	_build_junction_connections()
	_build_lane_connections()
	_build_guard_rails()
	_validate_graph()
	_routing_revision += 1
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
			var guard_rail_openings: Array[Dictionary] = []
			for opening_value in definition.get("guard_rail_openings", []):
				var source_opening := opening_value as Dictionary
				var source_position: Variant = source_opening.get("position", null)
				if not source_position is Vector2:
					continue
				guard_rail_openings.append({
					"position": to_local(provider.to_global(source_position as Vector2)),
					"radius": maxf(0.0, float(source_opening.get("radius", 0.0))),
				})
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
				"bridge_surface": bool(definition.get("bridge_surface", false)),
				"open_start": bool(definition.get("open_start", false)),
				"open_end": bool(definition.get("open_end", false)),
				"preserve_open_endpoints": bool(definition.get("preserve_open_endpoints", false)),
				"guard_rail_openings": guard_rail_openings,
				"snap_start": String(definition.get("snap_start", "")),
				"snap_end": String(definition.get("snap_end", "")),
				"snap_start_t": float(definition.get("snap_start_t", -1.0)),
				"snap_end_t": float(definition.get("snap_end_t", -1.0)),
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


func _get_elevated_corridor_sources() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var composition_root := get_parent()
	if composition_root == null:
		return result
	var candidates: Array[Node] = [composition_root]
	candidates.append_array(composition_root.find_children("*", "Node2D", true, false))
	for candidate in candidates:
		if candidate is Node2D and candidate.has_method("get_elevated_corridor_data"):
			result.append(candidate as Node2D)
	return result


func _fixed_open_endpoint(road: Dictionary, index: int) -> bool:
	if not bool(road.get("preserve_open_endpoints", false)): return false
	return bool(road.open_start) if index == 0 else bool(road.open_end)

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
				if _fixed_open_endpoint(_roads[first_index], first_endpoint): continue
				for second_endpoint in [0, second_control.size() - 1]:
					if _fixed_open_endpoint(_roads[second_index], second_endpoint): continue
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
			if _fixed_open_endpoint(_roads[road_index], endpoint_index): continue
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
			{"index": 0, "target": String(_roads[road_index].snap_start), "target_t": float(_roads[road_index].snap_start_t), "mode": String(_roads[road_index].snap_start_mode)},
			{"index": control.size() - 1, "target": String(_roads[road_index].snap_end), "target_t": float(_roads[road_index].snap_end_t), "mode": String(_roads[road_index].snap_end_mode)},
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
			var target_t := float(endpoint_data.target_t)
			var target_info := _point_and_tangent_at_progress(target_curve, target_t) \
				if target_t >= 0.0 and target_t <= 1.0 \
				else _closest_point_and_tangent(control[endpoint_index], target_curve)
			control[endpoint_index] = target_info.position
			_align_endpoint_approach(control, endpoint_index, target_info.tangent, String(endpoint_data.mode))
		_roads[road_index].control = control


func _bake_all_curves() -> void:
	for road_index in range(_roads.size()):
		var control: PackedVector2Array = _roads[road_index].control
		_roads[road_index].points = _catmull_rom(control, curve_subdivisions)


func _update_grass_bounds() -> void:
	# Bounding box of every road, padded out. Whatever the sidewalk and
	# asphalt polygons do not paint over -- roadside verges and the pockets
	# between separate loops of a curvy road -- reads as ground instead of an
	# empty void, without needing real polygon-subtraction of the gaps.
	var bounds := Rect2()
	var has_point := false
	for road in _roads:
		for point in (road.points as PackedVector2Array):
			if not has_point:
				bounds = Rect2(point, Vector2.ZERO)
				has_point = true
			else:
				bounds = bounds.expand(point)
	_grass_bounds = bounds.grow(GRASS_BOUNDS_MARGIN) if has_point else Rect2()


func _draw_grass_ground() -> void:
	if _grass_bounds.size.x <= 0.0 or _grass_bounds.size.y <= 0.0:
		return
	static_canvas.draw_rect(_grass_bounds, GROUND_COLOR)
	var spacing := GRASS_TUFT_SPACING
	var cols := int(_grass_bounds.size.x / spacing) + 1
	var rows := int(_grass_bounds.size.y / spacing) + 1
	for row in rows:
		for col in cols:
			var cell := Vector2i(col, row)
			if _tuft_hash(cell, 91.7) < 0.42:
				continue
			var jitter := Vector2(
				(_tuft_hash(cell, 12.9) - 0.5) * spacing * 0.8,
				(_tuft_hash(cell, 78.2) - 0.5) * spacing * 0.8
			)
			var base := _grass_bounds.position + Vector2(float(col), float(row)) * spacing + jitter
			var tone := GRASS_TUFT_LIGHT if _tuft_hash(cell, 33.3) > 0.5 else GRASS_TUFT_DARK
			var blade_count := 2 + int(_tuft_hash(cell, 55.1) * 2.0)
			for blade in blade_count:
				var angle := (_tuft_hash(cell, 4.0 + float(blade)) - 0.5) * 1.1
				var blade_length := 6.0 + _tuft_hash(cell, 61.0 + float(blade)) * 5.0
				var tip := base + Vector2(sin(angle), -cos(angle)) * blade_length
				static_canvas.draw_line(base, tip, tone, 1.6)


func _tuft_hash(cell: Vector2i, seed_offset: float) -> float:
	# Deterministic per-cell pseudo-random value: same cell always yields the
	# same tuft, so the field does not reshuffle itself on every queue_redraw.
	var n := float(cell.x) * 127.1 + float(cell.y) * 311.7 + seed_offset * 78.233
	return fposmod(sin(n) * 43758.5453, 1.0)


func _build_guard_rails() -> void:
	var container := get_node_or_null(GENERATED_GUARD_RAILS_NODE) as Node2D
	if container == null:
		container = Node2D.new()
		container.name = GENERATED_GUARD_RAILS_NODE
		add_child(container)
	for child in container.get_children():
		container.remove_child(child)
		child.free()
	if not build_guard_rails:
		return
	for road_index in range(_roads.size()):
		var road: Dictionary = _roads[road_index]
		if not bool(road.render):
			continue
		var half_width := float(road.width) * 0.5 + SIDEWALK_MARGIN
		for side in [-1.0, 1.0]:
			var edge := _offset_polyline_by_normal(road.points, half_width * side)
			_add_guard_rail_segments(container, edge, road_index, side)


func _offset_polyline_by_normal(source: PackedVector2Array, offset: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in source.size():
		var previous := source[maxi(0, index - 1)]
		var following := source[mini(source.size() - 1, index + 1)]
		var tangent := (following - previous).normalized()
		if tangent.is_zero_approx():
			tangent = Vector2.RIGHT
		var normal := Vector2(-tangent.y, tangent.x)
		result.append(source[index] + normal * offset)
	return result


func _add_guard_rail_segments(container: Node2D, edge: PackedVector2Array, road_index: int, side: float) -> void:
	if edge.size() < 2:
		return
	var open_start := bool(_roads[road_index].open_start)
	var open_end := bool(_roads[road_index].open_end)
	var last_index := edge.size() - 2
	for index in range(edge.size() - 1):
		if index == 0 and open_start:
			continue
		if index == last_index and open_end:
			continue
		var a := edge[index]
		var b := edge[index + 1]
		if _guard_rail_segment_hits_opening(a, b, road_index):
			continue
		if _near_junction((a + b) * 0.5):
			continue
		_add_segment_blocker(
			container,
			a,
			b,
			GUARD_RAIL_THICKNESS,
			"GuardRail_%02d_%s_%03d" % [road_index, ("R" if side > 0.0 else "L"), index]
		)


func _guard_rail_segment_hits_opening(a: Vector2, b: Vector2, road_index: int) -> bool:
	for opening_value in _roads[road_index].guard_rail_openings:
		var opening := opening_value as Dictionary
		var center := opening.position as Vector2
		var closest := Geometry2D.get_closest_point_to_segment(center, a, b)
		if closest.distance_to(center) <= float(opening.radius):
			return true
	return false


func _near_junction(point: Vector2) -> bool:
	for junction_value in _junctions:
		var junction := junction_value as Dictionary
		if point.distance_to(junction.position as Vector2) <= float(junction.radius) + _guard_rail_junction_clearance(junction):
			return true
	return false


func _guard_rail_junction_clearance(junction: Dictionary) -> float:
	var road_ids: Array[String] = []
	for road_id in junction.get("road_ids", []):
		road_ids.append(String(road_id))
	road_ids.sort()
	var position: Vector2 = junction.get("position", Vector2.ZERO)
	var keys: Array[String] = [
		String(junction.get("id", "")),
		"%d,%d" % [roundi(position.x), roundi(position.y)],
		str(int(junction.get("index", -1))),
		"|".join(road_ids),
	]
	for key in keys:
		if not key.is_empty() and guard_rail_junction_clearance_overrides.has(key):
			return maxf(0.0, float(guard_rail_junction_clearance_overrides[key]))
	return GUARD_RAIL_JUNCTION_CLEARANCE


func _add_segment_blocker(parent: Node, from: Vector2, to: Vector2, thickness: float, blocker_name: String) -> void:
	var segment := to - from
	if segment.length() < 0.5:
		return
	var body := StaticBody2D.new()
	body.name = blocker_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = (from + to) * 0.5
	body.rotation = segment.angle()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(segment.length() + 3.0, thickness)
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _build_junction_exclusion_ranges() -> void:
	for road_index in range(_roads.size()):
		_roads[road_index].junction_exclusion_ranges = []
	for corridor_source in _get_elevated_corridor_sources():
		var data := corridor_source.call("get_elevated_corridor_data") as Dictionary
		var road_id := String(data.get("source_road_id", ""))
		var road_index := _find_road_index(road_id)
		if road_index < 0:
			_validation_errors.append("Elevated corridor references unknown road: %s" % road_id)
			continue
		var local_points := PackedVector2Array()
		for global_point in data.get("global_points", PackedVector2Array()):
			local_points.append(to_local(global_point))
		if local_points.size() < 2:
			_validation_errors.append("Elevated corridor for %s has insufficient geometry" % road_id)
			continue
		var from_t := clampf(float(data.get("from_t", 0.0)), 0.0, 1.0)
		var to_t := clampf(float(data.get("to_t", 1.0)), 0.0, 1.0)
		if from_t > to_t:
			var swap := from_t
			from_t = to_t
			to_t = swap
		var exclusion := {
			"id": "elevated_%s_%s" % [String(corridor_source.name).to_snake_case(), road_id.replace("/", "_")],
			"road_index": road_index,
			"road_id": road_id,
			"from_t": from_t,
			"to_t": to_t,
			"points": local_points,
			"half_width": float(data.get("half_width", float(_roads[road_index].width) * 0.5)),
			"safety_margin": float(data.get("safety_margin", 0.0)),
			"classification": "grade_separated",
			"source_path": get_path_to(corridor_source),
		}
		_junction_exclusion_ranges.append(exclusion)
		var road_ranges: Array = _roads[road_index].junction_exclusion_ranges
		road_ranges.append(exclusion)
		_roads[road_index].junction_exclusion_ranges = road_ranges


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


func _junction_exclusion_at(position: Vector2, first_road: int, second_road: int) -> Dictionary:
	for exclusion_value in _junction_exclusion_ranges:
		var exclusion := exclusion_value as Dictionary
		var protected_road := int(exclusion.road_index)
		if protected_road != first_road and protected_road != second_road:
			continue
		var location := _closest_location_on_polyline(position, _roads[protected_road].points)
		var progress := float(location.progress)
		if progress < float(exclusion.from_t) - 0.005 or progress > float(exclusion.to_t) + 0.005:
			continue
		var footprint := float(exclusion.half_width) + float(exclusion.safety_margin)
		if _distance_to_polyline(position, exclusion.points) <= footprint:
			return exclusion
	return {}


func _record_grade_separated_crossing(position: Vector2, first_road: int, second_road: int, exclusion: Dictionary) -> void:
	var ordered_roads: Array[int] = [mini(first_road, second_road), maxi(first_road, second_road)]
	for crossing in _grade_separated_crossings:
		if crossing.roads == ordered_roads and (crossing.position as Vector2).distance_to(position) <= 10.0:
			return
	_grade_separated_crossings.append({
		"id": "grade_separated_%03d" % _grade_separated_crossings.size(),
		"position": position,
		"roads": ordered_roads,
		"road_ids": [String(_roads[ordered_roads[0]].id), String(_roads[ordered_roads[1]].id)],
		"exclusion_id": String(exclusion.id),
		"classification": "grade_separated",
	})


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
						var position := hit as Vector2
						var exclusion := _junction_exclusion_at(position, first_index, second_index)
						if exclusion.is_empty():
							_add_junction(position, first_index, second_index)
						else:
							_record_grade_separated_crossing(position, first_index, second_index, exclusion)
	# Collinear/T connections can touch without producing a stable crossing hit.
	for road_index in range(_roads.size()):
		var points: PackedVector2Array = _roads[road_index].points
		for endpoint in [points[0], points[-1]]:
			for other_index in range(_roads.size()):
				if other_index == road_index:
					continue
				if _distance_to_polyline(endpoint, _roads[other_index].points) <= 0.75:
					var exclusion := _junction_exclusion_at(endpoint, road_index, other_index)
					if exclusion.is_empty():
						_add_junction(endpoint, road_index, other_index)
					else:
						_record_grade_separated_crossing(endpoint, road_index, other_index, exclusion)


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
					"road_width": float(road.width),
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
		var signalization := _resolve_junction_signalization(junction)
		junction.signalized = bool(signalization.value)
		junction.signalization_source = String(signalization.source)
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


func _resolve_junction_signalization(junction: Dictionary) -> Dictionary:
	# A geometric continuation has one incoming approach from each joined road
	# (two total). It still needs exclusive conflict reservation for traffic AI,
	# but must not manufacture an invisible red phase or roadside signal heads.
	var default_value := (junction.get("approaches", []) as Array).size() >= 3
	if junction.has("signalized_override"):
		return {"value": bool(junction.signalized_override), "source": "junction_override"}
	var position: Vector2 = junction.get("position", Vector2.ZERO)
	var keys: Array[String] = [
		String(junction.get("id", "")),
		"%d,%d" % [roundi(position.x), roundi(position.y)],
		str(int(junction.get("index", -1))),
	]
	for key in keys:
		if not key.is_empty() and signalized_junction_overrides.has(key):
			return {"value": bool(signalized_junction_overrides[key]), "source": "explicit_override"}
	return {"value": default_value, "source": "approach_count"}


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

	# A connector's exit_curve_offset can land a vehicle past the SAME
	# destination lane's own outgoing entry_curve_offset at the same
	# junction -- a short lane whose relevant end IS the junction (a tight
	# quarter-arc road, not a long unbroken one). That vehicle would have no
	# room left to plan its own next move: JunctionTrafficController's
	# entry_curve_offset filters reject any candidate already behind
	# progress, and this junction never offers a "continue on the current
	# lane, no connector needed" fallback because there IS no more current
	# lane left. Reproduced live: junction_039_7400_1700's cobra_approach ->
	# cobra_court_southwest connector (Ashbend/Cobra roundabout) landed a
	# vehicle 51px past its own only two real exits, stranding it forever --
	# reservation granted, signal green, nowhere the game would ever let it
	# go. Compute, once here, exactly how much extra allowance each
	# INDIVIDUALLY AFFECTED connection needs (0.0 for the overwhelming
	# majority) so the controller can grant it only where structurally
	# required. A per-junction blanket relaxation was tried instead and
	# reverted: it also loosened ordinary drove-past-it-too-fast overshoot
	# for unrelated connections sharing the same junction radius, including
	# ones on Bairro1's rail level crossing approach, and caused a real
	# vehicle/train collision (rail_level_crossing_runtime_test). This
	# per-connection value cannot affect any connection it is not computed
	# for -- every other connection's allowance stays 0.0.
	# Group every connector-requiring connection by the lane it ARRIVES ON,
	# so each OUTGOING connection (the one that actually gets filtered by
	# entry_curve_offset in JunctionTrafficController) can look up whatever
	# might have landed a vehicle on its own from_lane_id past its own
	# entry point.
	var incoming_by_lane: Dictionary = {}
	for connection in _lane_connections:
		if not bool(connection.requires_connector):
			continue
		var to_lane_id := String(connection.to_lane_id)
		var bucket: Array = incoming_by_lane.get(to_lane_id, [])
		bucket.append(connection)
		incoming_by_lane[to_lane_id] = bucket
	for connection in _lane_connections:
		if not bool(connection.requires_connector):
			continue
		var from_lane_id := String(connection.from_lane_id)
		var entry_offset := float(connection.entry_curve_offset)
		var junction_index := int(connection.junction_index)
		var worst_needed := 0.0
		for incoming_value in (incoming_by_lane.get(from_lane_id, []) as Array):
			var incoming := incoming_value as Dictionary
			# Both ends of the same short lane can register against the same
			# junction (the Cobra roundabout pattern this exists for); a long,
			# unbroken lane threading through several DIFFERENT junctions
			# must not have an arrival at one distant junction treated as
			# overshooting THIS junction's unrelated exit -- only an
			# incoming connector landing at the SAME junction this outgoing
			# connection departs from is structurally the same "nowhere left
			# to plan" case. Missing this scoped to junction_index inflated
			# allowances up to 1115px on Bairro1Expansion/midtown_cross and
			# east_arc (long roads spanning several junctions including the
			# rail crossing) and reintroduced the vehicle/train collision.
			if int(incoming.get("junction_index", -1)) != junction_index:
				continue
			var incoming_exit := float(incoming.get("exit_curve_offset", -1.0))
			if incoming_exit < 0.0:
				continue
			worst_needed = maxf(worst_needed, incoming_exit - entry_offset)
		if worst_needed > 0.0:
			# +1.0 covers get_closest_offset's sampling resolution: the
			# entry/exit trims are meant to mirror each other exactly but
			# can miss by a few thousandths of a pixel, which would
			# otherwise reject the very overshoot this exists to cover.
			connection.landing_overshoot_allowance = worst_needed + 1.0

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


var static_canvas := preload("res://world/shared/roads/StaticCanvasGeometry.gd").new(self)

func _draw() -> void:
	static_canvas.begin()
	if _roads.is_empty():
		return
	# Ground layer first: flat color plus small vector tufts fill the whole
	# network's bounding box, then every paved layer below is painted on top
	# in the same order as before. Anything the paved passes do not cover
	# keeps reading as grass -- at the correct, resolution-independent scale.
	_draw_grass_ground()
	# Material passes are global. Sidewalks can never be painted over finished
	# asphalt because all outer layers are completed before any inner layer.
	_draw_road_pass(SIDEWALK_COLOR, SIDEWALK_MARGIN * 2.0)
	_draw_road_pass(CURB_COLOR, 10.0)
	_draw_road_pass(ROAD_EDGE_COLOR, 4.0)
	_draw_road_pass(ROAD_COLOR, 0.0)
	for road in _roads:
		if bool(road.render):
			if bool(road.get("bridge_surface", false)):
				_draw_bridge_lane(road)
			else:
				_draw_lane_markings(road.points)
	if show_junction_debug:
		for junction in _junctions:
			static_canvas.draw_circle(junction.position, 9.0, Color(0.15, 0.9, 0.55, 0.85))


func _draw_road_pass(color: Color, extra_width: float) -> void:
	for road in _roads:
		if bool(road.render):
			var surface_color := color
			if bool(road.get("bridge_surface", false)):
				surface_color = BRIDGE_SURFACE.ASPHALT if extra_width == 0 else (BRIDGE_SURFACE.SHOULDER if extra_width > 10 else BRIDGE_SURFACE.CURB)
			var surfaces := Geometry2D.offset_polyline(
				road.points,
				(float(road.width) + extra_width) * 0.5,
				Geometry2D.JOIN_ROUND,
				Geometry2D.END_BUTT
			)
			for surface in surfaces:
				var polygon := surface as PackedVector2Array
				if polygon.size() >= 3 and not Geometry2D.is_polygon_clockwise(polygon):
					static_canvas.draw_colored_polygon(polygon, surface_color)
	# Every material layer receives the same topological junction envelope.
	# Drawing this after all independent ribbons removes their butt-cap seams;
	# the progressively narrower passes then cover the inner sidewalk/curb
	# wedges without changing the authored centerlines or traffic graph.
	for junction in _junctions:
		var geometry := _build_junction_surface_geometry(junction, extra_width)
		var patch := geometry.polygon as PackedVector2Array
		if patch.size() >= 3 and not Geometry2D.triangulate_polygon(patch).is_empty():
			static_canvas.draw_colored_polygon(patch, color)


func _draw_bridge_lane(road: Dictionary) -> void:
	# Each separated carriageway has exactly one lane: no central divider.
	var points: PackedVector2Array = road.points
	static_canvas.draw_polyline(points, BRIDGE_SURFACE.WEAR, 18.0, true)
	for side in [-1.0, 1.0]:
		var edge := PackedVector2Array()
		for i in points.size():
			var tangent := (points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]).normalized()
			edge.append(points[i]+Vector2(-tangent.y,tangent.x)*(float(road.width)*0.5-8)*side)
		if edge.size() > 1:
			static_canvas.draw_polyline(edge, BRIDGE_SURFACE.EDGE, 3.0, true)

func _build_junction_surface_geometry(junction: Dictionary, extra_width: float) -> Dictionary:
	var arms := _junction_surface_arms(junction, extra_width)
	if arms.size() < 2:
		return {
			"polygon": PackedVector2Array(),
			"arms": arms,
			"extent_limit": 0.0,
			"beveled_sector_count": 0,
			"component_count": 0,
			"construction": "suppressed",
		}

	var center := junction.position as Vector2
	var largest_outer_half := 0.0
	for arm_value in arms:
		largest_outer_half = maxf(largest_outer_half, float((arm_value as Dictionary).outer_half_width))
	var junction_core_limit := maxf(
		float(junction.radius) + JUNCTION_CORE_PADDING,
		largest_outer_half + JUNCTION_CORE_EDGE_CLEARANCE
	)
	var extent_limit := 0.0
	for arm_index in range(arms.size()):
		var arm := arms[arm_index] as Dictionary
		var is_hidden_arm: bool = (arm.rendered_road_indices as Array).is_empty()
		var half_width := minf(float(arm.half_width), junction_core_limit)
		var radial_cutback_limit := sqrt(maxf(
			0.0,
			junction_core_limit * junction_core_limit - half_width * half_width
		))
		# Both cap corners lie exactly on (or inside) the bounded core envelope.
		# The per-layer half-width also caps longitudinal reach, keeping asphalt
		# naturally smaller than the sidewalk while the ribbons cover each arm.
		arm.cutback = 0.0 if is_hidden_arm else minf(half_width + JUNCTION_CORE_PADDING, radial_cutback_limit)
		extent_limit = maxf(
			extent_limit,
			sqrt(float(arm.cutback) * float(arm.cutback) + half_width * half_width)
		)
		arms[arm_index] = arm

	# The hull uses only the two nearby cut corners of each physical arm plus
	# the node itself. It is the smallest deterministic one-piece bevel for the
	# core and, unlike the previous offset-line intersection, cannot escape the
	# junction envelope at shallow angles.
	var polygon := _junction_cap_convex_hull(arms, center)
	return {
		"polygon": polygon,
		"arms": arms,
		"extent_limit": extent_limit,
		"junction_core_limit": junction_core_limit,
		"beveled_sector_count": arms.size(),
		"component_count": 1 if polygon.size() >= 3 else 0,
		"construction": "local_cap_hull",
	}


func _junction_surface_arms(junction: Dictionary, extra_width: float) -> Array[Dictionary]:
	var arms: Array[Dictionary] = []
	var rendered_connection_count := 0
	for connection_value in junction.connections:
		var road_index := int((connection_value as Dictionary).road_index)
		if road_index >= 0 and road_index < _roads.size() and bool(_roads[road_index].render):
			rendered_connection_count += 1
	if rendered_connection_count < 1 or (junction.connections as Array).size() < 2:
		return arms
	for connection_value in junction.connections:
		var connection := connection_value as Dictionary
		var road_index := int(connection.road_index)
		if road_index < 0 or road_index >= _roads.size():
			continue
		var road := _roads[road_index] as Dictionary
		var road_is_rendered := bool(road.render)
		var tangent := (connection.forward_tangent as Vector2).normalized()
		if tangent.is_zero_approx():
			continue
		var distance_along := float(connection.distance_along)
		var total_length := float(connection.total_length)
		var endpoint_tolerance := minf(12.0, maxf(MIN_POINT_DISTANCE, total_length * 0.002))
		var directions: Array[Vector2] = []
		if distance_along <= endpoint_tolerance:
			directions.append(tangent)
		elif total_length - distance_along <= endpoint_tolerance:
			directions.append(-tangent)
		else:
			directions.append(tangent)
			directions.append(-tangent)
		for direction in directions:
			var arm_extra: float = extra_width if road_is_rendered else 0.0
			var half_width := (float(road.width) + arm_extra) * 0.5
			var outer_half_width := float(road.width) * 0.5 + (SIDEWALK_MARGIN if road_is_rendered else 0.0)
			var merged_index := -1
			for existing_index in range(arms.size()):
				if (arms[existing_index].direction as Vector2).dot(direction) >= JUNCTION_ARM_MERGE_COSINE:
					merged_index = existing_index
					break
			if merged_index < 0:
				arms.append({
					"direction": direction,
					"angle": direction.angle(),
					"half_width": half_width,
					"outer_half_width": outer_half_width,
					"road_indices": [road_index],
					"rendered_road_indices": [road_index] if road_is_rendered else [],
					"hidden_road_indices": [] if road_is_rendered else [road_index],
					"cutback": 0.0,
				})
				continue
			var merged := arms[merged_index] as Dictionary
			var combined_direction := (merged.direction as Vector2) + direction
			if not combined_direction.is_zero_approx():
				merged.direction = combined_direction.normalized()
				merged.angle = (merged.direction as Vector2).angle()
			merged.half_width = maxf(float(merged.half_width), half_width)
			merged.outer_half_width = maxf(float(merged.outer_half_width), outer_half_width)
			var road_indices := merged.road_indices as Array
			if not road_indices.has(road_index):
				road_indices.append(road_index)
			merged.road_indices = road_indices
			var visibility_key := "rendered_road_indices" if road_is_rendered else "hidden_road_indices"
			var visibility_indices := merged[visibility_key] as Array
			if not visibility_indices.has(road_index):
				visibility_indices.append(road_index)
			merged[visibility_key] = visibility_indices
			arms[merged_index] = merged
	arms.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return float(first.angle) < float(second.angle)
	)
	return arms


func _junction_cap_convex_hull(arms: Array[Dictionary], center: Vector2) -> PackedVector2Array:
	var cap_points := PackedVector2Array([center])
	for arm_value in arms:
		var arm := arm_value as Dictionary
		var direction := arm.direction as Vector2
		var normal := Vector2(-direction.y, direction.x)
		var cap_center := center + direction * float(arm.cutback)
		cap_points.append(cap_center - normal * float(arm.half_width))
		cap_points.append(cap_center + normal * float(arm.half_width))
	var hull := Geometry2D.convex_hull(cap_points)
	if hull.size() > 1 and hull[0].distance_to(hull[-1]) <= JUNCTION_SURFACE_EPSILON:
		hull.resize(hull.size() - 1)
	return _counter_clockwise_polygon(hull)


func _counter_clockwise_polygon(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3 or not Geometry2D.is_polygon_clockwise(points):
		return points
	var reversed := PackedVector2Array()
	for index in range(points.size() - 1, -1, -1):
		reversed.append(points[index])
	return reversed


func _draw_lane_markings(points: PackedVector2Array) -> void:
	var dash_segments := PackedVector2Array()
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
					dash_segments.append(from)
					dash_segments.append(to)
			walked += maxf(step, 0.5)
		travelled += segment_length
	if not dash_segments.is_empty():
		static_canvas.draw_multiline(dash_segments, LANE_COLOR, 3.0, true)


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
	var exclusion_ids := {}
	for exclusion_value in _junction_exclusion_ranges:
		var exclusion := exclusion_value as Dictionary
		var exclusion_id := String(exclusion.get("id", ""))
		if exclusion_id.is_empty() or exclusion_ids.has(exclusion_id):
			_validation_errors.append("Missing or duplicate junction exclusion id: %s" % exclusion_id)
		exclusion_ids[exclusion_id] = true
		var protected_road := int(exclusion.get("road_index", -1))
		if protected_road < 0 or protected_road >= _roads.size():
			_validation_errors.append("Junction exclusion %s references an unknown road" % exclusion_id)
			continue
		if String(exclusion.get("road_id", "")) != String(_roads[protected_road].id):
			_validation_errors.append("Junction exclusion %s has inconsistent road ownership" % exclusion_id)
		var from_t := float(exclusion.get("from_t", -1.0))
		var to_t := float(exclusion.get("to_t", -1.0))
		if from_t < 0.0 or to_t > 1.0 or from_t >= to_t:
			_validation_errors.append("Junction exclusion %s has an invalid road-relative range" % exclusion_id)
		if (exclusion.get("points", PackedVector2Array()) as PackedVector2Array).size() < 2:
			_validation_errors.append("Junction exclusion %s has no corridor geometry" % exclusion_id)
	for junction_index in range(_junctions.size()):
		var junction: Dictionary = _junctions[junction_index]
		if (junction.roads as Array).size() < 2:
			_validation_errors.append("Junction %d has fewer than two connected roads" % junction_index)
		if (junction.connections as Array).size() != (junction.roads as Array).size():
			_validation_errors.append("Junction %d has incomplete road connection metadata" % junction_index)
		if (junction.approaches as Array).is_empty():
			_validation_errors.append("Junction %d has no directed approaches" % junction_index)
		if not junction.has("signalized"):
			_validation_errors.append("Junction %d does not publish signalized classification" % junction_index)
		for approach_value in junction.approaches:
			var approach := approach_value as Dictionary
			if float(approach.get("road_width", 0.0)) <= 0.0:
				_validation_errors.append("Junction %d approach %s has no road_width" % [junction_index, String(approach.get("approach_id", ""))])
		if (junction.lane_connections as Array).is_empty():
			_validation_errors.append("Junction %d has no navigable lane connections" % junction_index)
		for road_index in junction.roads:
			if _distance_to_polyline(junction.position, _roads[int(road_index)].points) > 0.75:
				_validation_errors.append("Junction %d is not on road %s" % [junction_index, _roads[int(road_index)].id])
		var junction_roads := junction.roads as Array
		for first_road_offset in range(junction_roads.size()):
			for second_road_offset in range(first_road_offset + 1, junction_roads.size()):
				var exclusion := _junction_exclusion_at(
					junction.position,
					int(junction_roads[first_road_offset]),
					int(junction_roads[second_road_offset])
				)
				if not exclusion.is_empty():
					_validation_errors.append("Junction %d exists inside grade-separated corridor %s" % [junction_index, String(exclusion.id)])
		_audit_junction_surface(junction)
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


func _audit_junction_surface(junction: Dictionary) -> void:
	var rendered_road_ids: Array[String] = []
	var hidden_road_ids: Array[String] = []
	for road_index_value in junction.roads:
		var road_index := int(road_index_value)
		if road_index < 0 or road_index >= _roads.size():
			continue
		var road_id := String(_roads[road_index].id)
		if bool(_roads[road_index].render):
			rendered_road_ids.append(road_id)
		else:
			hidden_road_ids.append(road_id)

	var layers := [
		{"id": "sidewalk", "extra_width": SIDEWALK_MARGIN * 2.0},
		{"id": "curb", "extra_width": 10.0},
		{"id": "road_edge", "extra_width": 4.0},
		{"id": "asphalt", "extra_width": 0.0},
	]
	var layer_audit := {}
	var reference_geometry := _build_junction_surface_geometry(junction, 0.0)
	var physical_arm_count := (reference_geometry.arms as Array).size()
	var patch_required := physical_arm_count >= 2
	for layer_value in layers:
		var layer := layer_value as Dictionary
		var geometry := _build_junction_surface_geometry(junction, float(layer.extra_width))
		var polygon := geometry.polygon as PackedVector2Array
		var layer_id := String(layer.id)
		var layer_errors: Array[String] = []
		if patch_required and polygon.size() < 3:
			layer_errors.append("missing polygon")
		elif not patch_required and not polygon.is_empty():
			layer_errors.append("orphan polygon")
		if patch_required and int(geometry.component_count) != 1:
			layer_errors.append("surface has %d components" % int(geometry.component_count))
		if polygon.size() >= 3:
			if Geometry2D.is_polygon_clockwise(polygon):
				layer_errors.append("clockwise winding")
			if not _surface_polygon_is_simple(polygon):
				layer_errors.append("self intersection")
			if Geometry2D.triangulate_polygon(polygon).is_empty():
				layer_errors.append("not triangulable")
			if absf(_surface_polygon_area(polygon)) <= 1.0:
				layer_errors.append("zero area")
			var maximum_extent := 0.0
			for point in polygon:
				maximum_extent = maxf(maximum_extent, (point as Vector2).distance_to(junction.position))
			if maximum_extent > float(geometry.extent_limit) + 0.5:
				layer_errors.append("miter envelope exceeded")

		var overlap_road_ids: Array[String] = []
		if polygon.size() >= 3 and layer_errors.is_empty():
			for road_index_value in junction.roads:
				var road_index := int(road_index_value)
				if road_index < 0 or road_index >= _roads.size() or not bool(_roads[road_index].render):
					continue
				if _junction_patch_overlap_area(polygon, _roads[road_index], float(layer.extra_width)) > 1.0:
					overlap_road_ids.append(String(_roads[road_index].id))
				else:
					layer_errors.append("does not overlap %s" % String(_roads[road_index].id))
		for layer_error in layer_errors:
			_validation_errors.append(
				"Junction surface %s/%s: %s" % [String(junction.id), layer_id, layer_error]
			)
		layer_audit[layer_id] = {
			"point_count": polygon.size(),
			"area": absf(_surface_polygon_area(polygon)),
			"triangle_count": Geometry2D.triangulate_polygon(polygon).size() / 3 if polygon.size() >= 3 else 0,
			"component_count": int(geometry.component_count),
			"beveled_sector_count": int(geometry.beveled_sector_count),
			"construction": String(geometry.construction),
			"maximum_extent": _surface_polygon_maximum_extent(polygon, junction.position),
			"extent_limit": float(geometry.extent_limit),
			"overlap_road_ids": overlap_road_ids,
			"errors": layer_errors,
		}

	_surface_topology_audit.append({
		"junction_id": String(junction.id),
		"position": junction.position,
		"road_ids": (junction.road_ids as Array).duplicate(),
		"rendered_road_ids": rendered_road_ids,
		"hidden_road_ids": hidden_road_ids,
		"physical_arm_count": physical_arm_count,
		"patch_required": patch_required,
		"layers": layer_audit,
	})


func _junction_patch_overlap_area(patch: PackedVector2Array, road: Dictionary, extra_width: float) -> float:
	var overlap_area := 0.0
	var surfaces := Geometry2D.offset_polyline(
		road.points,
		(float(road.width) + extra_width) * 0.5,
		Geometry2D.JOIN_ROUND,
		Geometry2D.END_BUTT
	)
	for surface_value in surfaces:
		var surface := _counter_clockwise_polygon(surface_value as PackedVector2Array)
		for overlap_value in Geometry2D.intersect_polygons(patch, surface):
			overlap_area += absf(_surface_polygon_area(overlap_value as PackedVector2Array))
	return overlap_area


func _surface_polygon_area(polygon: PackedVector2Array) -> float:
	var twice_area := 0.0
	for index in range(polygon.size()):
		var point := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		twice_area += point.cross(next)
	return twice_area * 0.5


func _surface_polygon_maximum_extent(polygon: PackedVector2Array, center: Vector2) -> float:
	var maximum_extent := 0.0
	for point in polygon:
		maximum_extent = maxf(maximum_extent, (point as Vector2).distance_to(center))
	return maximum_extent


func _surface_polygon_is_simple(polygon: PackedVector2Array) -> bool:
	var edge_count := polygon.size()
	for first_index in range(edge_count):
		var first_next := (first_index + 1) % edge_count
		for second_index in range(first_index + 1, edge_count):
			var second_next := (second_index + 1) % edge_count
			if (
				first_index == second_index
				or first_next == second_index
				or second_next == first_index
			):
				continue
			var intersection = Geometry2D.segment_intersects_segment(
				polygon[first_index], polygon[first_next],
				polygon[second_index], polygon[second_next]
			)
			if intersection != null:
				var hit := intersection as Vector2
				if (
					hit.distance_to(polygon[first_index]) <= JUNCTION_SURFACE_EPSILON
					or hit.distance_to(polygon[first_next]) <= JUNCTION_SURFACE_EPSILON
					or hit.distance_to(polygon[second_index]) <= JUNCTION_SURFACE_EPSILON
					or hit.distance_to(polygon[second_next]) <= JUNCTION_SURFACE_EPSILON
				):
					continue
				return false
	return true


func _validate_endpoint(road_index: int, endpoint_index: int, explicitly_open: bool) -> void:
	if explicitly_open:
		return
	var control: PackedVector2Array = _roads[road_index].control
	var endpoint := control[endpoint_index]
	for other_index in range(_roads.size()):
		if other_index == road_index or _distance_to_polyline(endpoint, _roads[other_index].points) > 0.75:
			continue
		if _junction_exclusion_at(endpoint, road_index, other_index).is_empty():
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


func _point_and_tangent_at_progress(points: PackedVector2Array, progress: float) -> Dictionary:
	if points.size() < 2:
		return {"position": points[0] if not points.is_empty() else Vector2.ZERO, "tangent": Vector2.RIGHT}
	var total_length := 0.0
	for index in range(points.size() - 1):
		total_length += points[index].distance_to(points[index + 1])
	var target_distance := clampf(progress, 0.0, 1.0) * total_length
	var travelled := 0.0
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		var segment_length := a.distance_to(b)
		if segment_length < MIN_POINT_DISTANCE:
			continue
		if travelled + segment_length >= target_distance:
			var local_t := clampf((target_distance - travelled) / segment_length, 0.0, 1.0)
			return {"position": a.lerp(b, local_t), "tangent": a.direction_to(b)}
		travelled += segment_length
	return {"position": points[-1], "tangent": points[-2].direction_to(points[-1])}


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


## Consumers can invalidate adjacency/path caches without copying graph data.
func get_routing_revision() -> int:
	return _routing_revision


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
		"junction_exclusion_ranges": _junction_exclusion_ranges.duplicate(true),
		"grade_separated_crossings": _grade_separated_crossings.duplicate(true),
		"surface_topology_audit": _surface_topology_audit.duplicate(true),
		"validation_errors": _validation_errors.duplicate(),
	}


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func get_surface_topology_audit() -> Dictionary:
	var surface_errors: Array[String] = []
	for validation_error in _validation_errors:
		if validation_error.begins_with("Junction surface "):
			surface_errors.append(validation_error)
	return {
		"junctions": _surface_topology_audit.duplicate(true),
		"errors": surface_errors,
		"render_policy": {
			"hidden_roads_contribute": "only_at_mixed_visibility_junctions",
			"all_hidden_junctions_suppressed": true,
			"minimum_physical_arms": 2,
			"end_cap": "butt",
			"junction_join": "local_cap_bevel",
			"core_padding": JUNCTION_CORE_PADDING,
		},
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
	return "roads=%d lanes=%d junctions=%d lane_connections=%d grade_separated=%d errors=%d" % [
		_roads.size(), lane_count, _junctions.size(), _lane_connections.size(),
		_grade_separated_crossings.size(), _validation_errors.size()
	]
