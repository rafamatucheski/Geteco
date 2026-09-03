@tool
class_name Bairro1ProgressionConnections
extends Node2D

## The first borough has two—and only two—authored progression exits.  District
## 2 owns the southern viaduct marker; this node completes the eastbound
## District 3 egress without fabricating either future borough.

@export var district3_unlocked := false

const ROAD_HALF_WIDTH := 82.0
const ROAD_COLOR := Color("#202932")
const ROAD_EDGE_COLOR := Color("#58626a")
const LANE_COLOR := Color("#dfc84d")
const SIGN_GREEN := Color("#214d42")
const BARRIER_LIGHT := Color("#d5d1c1")
const BARRIER_ORANGE := Color("#d45b34")

# Continues the existing EastArc at x=2430.  Its end is deliberately outside
# Bairro 1's authored lots, so future District 3 can attach road-for-road.
static var DISTRICT3_APPROACH := PackedVector2Array([
	Vector2(2428, 2140), Vector2(2580, 2145), Vector2(2750, 2090),
	Vector2(2920, 2035), Vector2(3080, 2030),
])

var _centerline := PackedVector2Array()


func _ready() -> void:
	name = "Bairro1ProgressionConnections"
	_centerline = _catmull_rom(DISTRICT3_APPROACH, 8)
	if Engine.is_editor_hint():
		queue_redraw()
		return
	_create_district3_anchor()
	_create_temporary_district3_limit()
	queue_redraw()
	call_deferred("_validate_connections")


## Stable integration data for a future streaming/scene-transition manager.
func get_transition_data(destination_district: int) -> Dictionary:
	if destination_district == 2:
		var district2_anchor := get_tree().get_first_node_in_group("District2Connection") as Marker2D
		return {
			"from_district": 1,
			"to_district": 2,
			"anchor": district2_anchor,
			"approach": "southern_viaduct",
			"vehicle_spawn_forward": Vector2(0.16, 0.99).normalized(),
		}
	if destination_district == 3:
		var district3_anchor := get_node_or_null("District3Connection") as Marker2D
		return {
			"from_district": 1,
			"to_district": 3,
			"anchor": district3_anchor,
			"approach": "east_coastal_road",
			"vehicle_spawn_forward": Vector2(0.95, -0.10).normalized(),
		}
	return {}


func _create_district3_anchor() -> void:
	var anchor := Marker2D.new()
	anchor.name = "District3Connection"
	anchor.position = _centerline[-1]
	anchor.add_to_group("District3Connection")
	anchor.add_to_group("district_connection")
	anchor.set_meta("from_district", 1)
	anchor.set_meta("to_district", 3)
	anchor.set_meta("connection_type", "two_lane_coastal_arterial")
	anchor.set_meta("temporary_blocked", not district3_unlocked)
	anchor.set_meta("handoff_spawn_forward", Vector2(0.95, -0.10).normalized())
	anchor.set_meta("preserve_vehicle", true)
	add_child(anchor)


func _create_temporary_district3_limit() -> void:
	if district3_unlocked:
		return
	var tangent := (_centerline[-1] - _centerline[-2]).normalized()
	var normal := tangent.orthogonal()
	var center := _centerline[-1] - tangent * 24.0
	_add_segment_blocker(center - normal * (ROAD_HALF_WIDTH - 5.0), center + normal * (ROAD_HALF_WIDTH - 5.0), 18.0)


func _add_segment_blocker(from: Vector2, to: Vector2, thickness: float) -> void:
	var segment := to - from
	var blocker := StaticBody2D.new()
	blocker.name = "District3TemporarySafetyBarrier"
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	blocker.position = (from + to) * 0.5
	blocker.rotation = segment.angle()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(segment.length() + 2.0, thickness)
	collision.shape = shape
	blocker.add_child(collision)
	add_child(blocker)


func _validate_connections() -> void:
	var exits: Array[Marker2D] = []
	for node in get_tree().get_nodes_in_group("district_connection"):
		if node is Marker2D and int(node.get_meta("from_district", -1)) == 1:
			exits.append(node as Marker2D)
	assert(exits.size() == 2, "Bairro 1 must expose exactly two future district exits")
	var destinations := []
	for exit_anchor in exits:
		destinations.append(int(exit_anchor.get_meta("to_district", -1)))
	assert(destinations.has(2) and destinations.has(3), "Bairro 1 exits must lead to Districts 2 and 3")
	assert(_centerline[0].distance_to(Vector2(2428, 2140)) < 1.0, "District 3 road must meet EastArc")
	print("BAIRRO1_CONNECTIONS_READY: District2 viaduct + District3 coastal arterial")


func _draw() -> void:
	if _centerline.is_empty():
		return
	var left := _offset_polyline(_centerline, -ROAD_HALF_WIDTH)
	var right := _offset_polyline(_centerline, ROAD_HALF_WIDTH)
	draw_colored_polygon(_ribbon_polygon(left, right), ROAD_COLOR)
	draw_polyline(left, ROAD_EDGE_COLOR, 8.0, true)
	draw_polyline(right, ROAD_EDGE_COLOR, 8.0, true)
	_draw_dashes(_centerline)
	_draw_roadside_sign()
	if not district3_unlocked:
		_draw_temporary_barrier()


func _draw_dashes(points: PackedVector2Array) -> void:
	for index in range(0, points.size() - 2, 4):
		draw_line(points[index], points[index + 2], LANE_COLOR, 3.0, true)


func _draw_roadside_sign() -> void:
	var sign_position := Vector2(2760, 1964)
	draw_rect(Rect2(sign_position + Vector2(8, 34), Vector2(8, 46)), Color("#303940"))
	draw_rect(Rect2(sign_position, Vector2(172, 40)), SIGN_GREEN)
	draw_rect(Rect2(sign_position, Vector2(172, 40)), Color("#d8ddd1"), false, 3.0)
	var font := ThemeDB.fallback_font
	draw_string(font, sign_position + Vector2(13, 17), "DISTRITO 3", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#f0f1dc"))
	draw_string(font, sign_position + Vector2(13, 32), "ESTRADA COSTEIRA", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#d8ddd1"))


func _draw_temporary_barrier() -> void:
	var tangent := (_centerline[-1] - _centerline[-2]).normalized()
	var normal := tangent.orthogonal()
	var center := _centerline[-1] - tangent * 24.0
	var start := center - normal * 88.0
	draw_set_transform(center, tangent.angle(), Vector2.ONE)
	draw_rect(Rect2(Vector2(-88, -9), Vector2(176, 18)), BARRIER_LIGHT)
	for x in range(-84, 76, 24):
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, -8), Vector2(x + 12, -8), Vector2(x + 25, 8), Vector2(x + 13, 8),
		]), BARRIER_ORANGE)
	for x in [-70.0, 70.0]:
		draw_rect(Rect2(x - 5, 8, 10, 18), Color("#303940"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _catmull_rom(control: PackedVector2Array, subdivisions: int) -> PackedVector2Array:
	var sampled := PackedVector2Array()
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


func _offset_polyline(source: PackedVector2Array, offset: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in source.size():
		var previous := source[maxi(0, index - 1)]
		var following := source[mini(source.size() - 1, index + 1)]
		var tangent := (following - previous).normalized()
		result.append(source[index] + tangent.orthogonal() * offset)
	return result


func _ribbon_polygon(left: PackedVector2Array, right: PackedVector2Array) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point in left:
		polygon.append(point)
	for index in range(right.size() - 1, -1, -1):
		polygon.append(right[index])
	return polygon
