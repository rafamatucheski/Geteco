@tool
class_name DistrictRailLine
extends Node2D

## Ferrovia ambiental fixa do Bairro 1.
## Coordenadas são locais e foram pensadas para a cena ser instanciada em (0, 0).
## A rota começa e termina fora do mapa para o loop do trem não ficar visível.

const ROUTE_POINTS: Array[Vector2] = [
	# West approach stays north of Midtown Avenue instead of sharing its lanes.
	# DistrictOneComplete offsets this scene by (0, 520), so these become the
	# world-space corridor y=1620..1660 until the intentional viaduct crossing.
	Vector2(-260.0, 1100.0),
	Vector2(80.0, 1120.0),
	Vector2(390.0, 1125.0),
	Vector2(690.0, 1140.0),
	Vector2(910.0, 1218.0),
	Vector2(1190.0, 1248.0),
	Vector2(1490.0, 1220.0),
	Vector2(1760.0, 1142.0),
	Vector2(2020.0, 1098.0),
	Vector2(2300.0, 1132.0),
	Vector2(2630.0, 1238.0),
	Vector2(2920.0, 1280.0),
]

const TRACK_GAUGE := 22.0
const BALLAST_WIDTH := 54.0
const SAFETY_FENCE_OFFSET := 39.0
const SAFETY_FENCE_THICKNESS := 5.0
const CROSSING_GAP_RADIUS := 104.0
const SLEEPER_SPACING := 18.0
const SLEEPER_LENGTH := 42.0
const SIGNAL_POSITIONS: Array[Vector2] = [
	Vector2(560.0, 1260.0),
	Vector2(1380.0, 1240.0),
	Vector2(2170.0, 1108.0),
]

@export_range(0.0, 160.0, 1.0) var train_speed := 72.0
@export_range(1, 6, 1) var freight_car_count := 4
@export var train_enabled := true

var _route := Curve2D.new()
var _baked_points := PackedVector2Array()
var _detected_road_crossings: Array[Dictionary] = []


func _ready() -> void:
	# The highway deck is drawn above this root at the grade-separated crossing.
	z_index = 3
	build_route()
	_ensure_connection_marker()
	if Engine.is_editor_hint():
		queue_redraw()
		return
	_create_track_safety_boundaries()
	queue_redraw()
	var train := get_node_or_null("AmbientTrain") as AmbientTrain
	if train:
		train.configure(self, train_speed, freight_car_count)
		train.visible = train_enabled


func build_route() -> void:
	_route = Curve2D.new()
	_route.bake_interval = 8.0
	for point in ROUTE_POINTS:
		_route.add_point(point)
	_baked_points = _route.get_baked_points()


func get_route_curve() -> Curve2D:
	return _route


func get_route_length() -> float:
	return _route.get_baked_length()


func get_level_crossings() -> PackedVector2Array:
	var result := PackedVector2Array()
	for crossing in _detected_road_crossings:
		if String(crossing.get("classification", "")) == "at_grade":
			result.append(to_local(crossing.get("position", global_position)))
	return result


func get_rail_graph_data() -> Dictionary:
	if _baked_points.size() < 2:
		build_route()
	var global_points := PackedVector2Array()
	for point in _baked_points:
		global_points.append(to_global(point))
	var control_points := PackedVector2Array()
	for point in ROUTE_POINTS:
		control_points.append(point)
	return {
		"id": "district_1_rail_corridor",
		"control_points_local": control_points,
		"points_local": _baked_points.duplicate(),
		"global_points": global_points,
		"route_length": get_route_length(),
		"track_gauge": TRACK_GAUGE,
		"ballast_width": BALLAST_WIDTH,
		"handoffs": get_rail_handoffs(),
	}


func get_rail_handoffs() -> Array[Dictionary]:
	if _baked_points.size() < 2:
		build_route()
	var tangent := _baked_points[-2].direction_to(_baked_points[-1])
	return [{
		"id": "District2RailConnection",
		"position": to_global(_baked_points[-1]),
		"forward": global_transform.basis_xform(tangent).normalized(),
		"from_district": 1,
		"to_district": 2,
		"connection_type": "rail",
		"transport_mode": "rail",
	}]


func set_detected_road_crossings(crossings: Array) -> void:
	_detected_road_crossings.clear()
	for source in crossings:
		if source is Dictionary:
			_detected_road_crossings.append((source as Dictionary).duplicate(true))
	queue_redraw()
	if is_inside_tree() and not Engine.is_editor_hint():
		var existing := get_node_or_null("RailSafetyBoundaries")
		if existing != null:
			remove_child(existing)
			existing.free()
		_create_track_safety_boundaries()


func get_train_state() -> Dictionary:
	var train := get_node_or_null("AmbientTrain")
	if train == null or not train.has_method("get_rail_state"):
		return {
			"active": false,
			"progress": 0.0,
			"speed": train_speed,
			"consist_length": 0.0,
			"route_length": get_route_length(),
		}
	var state: Dictionary = train.call("get_rail_state")
	state["active"] = train_enabled and bool(state.get("active", false))
	return state


func _ensure_connection_marker() -> void:
	if _baked_points.size() < 2:
		return
	var marker := get_node_or_null("District2RailConnection") as Marker2D
	if marker == null:
		marker = Marker2D.new()
		marker.name = "District2RailConnection"
		add_child(marker)
	marker.position = _baked_points[-1]
	marker.add_to_group("District2RailConnection")
	marker.add_to_group("district_connection")
	marker.add_to_group("rail_district_connection")
	marker.set_meta("from_district", 1)
	marker.set_meta("to_district", 2)
	marker.set_meta("connection_type", "rail")
	marker.set_meta("transport_mode", "rail")
	marker.set_meta("temporary_blocked", false)
	marker.set_meta("forward", _baked_points[-2].direction_to(_baked_points[-1]))


func _create_track_safety_boundaries() -> void:
	# Low collision rails keep road vehicles and pedestrians out of the ballast.
	# Deliberate road crossings remain open through generous, symmetric gaps.
	var body := StaticBody2D.new()
	body.name = "RailSafetyBoundaries"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("rail_safety_boundary")
	var route_length := get_route_length()
	var distance := 0.0
	while distance + 16.0 <= route_length:
		var next_distance := minf(distance + 16.0, route_length)
		var midpoint_distance := (distance + next_distance) * 0.5
		var midpoint := _route.sample_baked(midpoint_distance, true)
		if not _inside_crossing_gap(midpoint):
			var tangent := _route_tangent(midpoint_distance)
			var normal := tangent.orthogonal().normalized()
			for side in [-1.0, 1.0]:
				var a: Vector2 = _route.sample_baked(distance, true) + normal * SAFETY_FENCE_OFFSET * side
				var b: Vector2 = _route.sample_baked(next_distance, true) + normal * SAFETY_FENCE_OFFSET * side
				_add_boundary_segment(body, a, b)
		distance = next_distance
	add_child(body)


func _inside_crossing_gap(point: Vector2) -> bool:
	for crossing in _detected_road_crossings:
		var local_position := to_local(crossing.get("position", global_position))
		var on_route := _route.sample_baked(_nearest_route_offset(local_position), true)
		var gap_radius := maxf(CROSSING_GAP_RADIUS, float(crossing.get("road_width", 0.0)) * 0.72)
		if point.distance_to(on_route) <= gap_radius:
			return true
	return false


func _add_boundary_segment(body: StaticBody2D, from: Vector2, to: Vector2) -> void:
	var segment := to - from
	if segment.length_squared() < 1.0:
		return
	var collision := CollisionShape2D.new()
	collision.position = (from + to) * 0.5
	collision.rotation = segment.angle()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(segment.length() + 1.5, SAFETY_FENCE_THICKNESS)
	collision.shape = shape
	body.add_child(collision)


func _draw() -> void:
	if _baked_points.size() < 2:
		return

	# Lastro, dormentes e trilhos em desenho vetorial barato.
	draw_polyline(_baked_points, Color("#574e43"), BALLAST_WIDTH, true)
	draw_polyline(_baked_points, Color("#6c6255"), BALLAST_WIDTH - 10.0, true)
	_draw_sleepers()
	_draw_rail_pair()

	for signal_position in SIGNAL_POSITIONS:
		_draw_rail_signal(signal_position)


func _draw_sleepers() -> void:
	var route_length := get_route_length()
	var distance := 0.0
	while distance <= route_length:
		var point := _route.sample_baked(distance, true)
		var tangent := _route_tangent(distance)
		var normal := tangent.orthogonal()
		draw_line(point - normal * SLEEPER_LENGTH * 0.5, point + normal * SLEEPER_LENGTH * 0.5, Color("#352d27"), 6.0, true)
		distance += SLEEPER_SPACING


func _draw_rail_pair() -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var route_length := get_route_length()
	var distance := 0.0
	while distance <= route_length:
		var point := _route.sample_baked(distance, true)
		var normal := _route_tangent(distance).orthogonal()
		left.append(point + normal * TRACK_GAUGE * 0.5)
		right.append(point - normal * TRACK_GAUGE * 0.5)
		distance += 8.0
	if left.size() > 1:
		draw_polyline(left, Color("#c1c7c9"), 4.0, true)
		draw_polyline(right, Color("#c1c7c9"), 4.0, true)
		draw_polyline(left, Color("#51595d"), 1.0, true)
		draw_polyline(right, Color("#51595d"), 1.0, true)


func _draw_rail_signal(signal_position: Vector2) -> void:
	var route_offset := _nearest_route_offset(signal_position)
	var tangent := _route_tangent(route_offset)
	var normal := tangent.orthogonal()
	var anchor := _route.sample_baked(route_offset, true) + normal * 44.0
	draw_line(anchor, anchor - normal * 17.0, Color("#24292d"), 5.0, true)
	draw_circle(anchor - normal * 20.0, 8.0, Color("#171a1c"))
	draw_circle(anchor - normal * 23.0, 3.5, Color("#d22e2e"))
	draw_circle(anchor - normal * 17.0, 3.5, Color("#d49c25"))
	draw_line(anchor + tangent * 9.0, anchor - tangent * 9.0, Color("#89847a"), 4.0, true)


func _nearest_route_offset(target: Vector2) -> float:
	return _route.get_closest_offset(target)


func _route_tangent(distance: float) -> Vector2:
	var length := maxf(get_route_length(), 1.0)
	var before := _route.sample_baked(clampf(distance - 4.0, 0.0, length), true)
	var after := _route.sample_baked(clampf(distance + 4.0, 0.0, length), true)
	var tangent := before.direction_to(after)
	return tangent if tangent.length_squared() > 0.001 else Vector2.RIGHT
