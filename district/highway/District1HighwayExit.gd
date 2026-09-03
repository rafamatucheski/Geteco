@tool
class_name District1HighwayExit
extends Node2D

## Authored southern exit for Bairro 1.  Coordinates are world-space when this
## scene is instantiated at Vector2.ZERO.  It starts at the Central District's
## south avenue (x ~= 870, y = 1280), bends east, crosses the future railway and
## ends at the hand-off marker for Bairro 2.

@export var district2_unlocked := false
@export var draw_standalone_verge := false

const ROAD_HALF_WIDTH := 82.0
const MEDIAN_HALF_WIDTH := 7.0
const RAIL_THICKNESS := 7.0
const ELEVATED_FROM := 8
const ELEVATED_TO := 29
const RAILWAY_MIN_Y := 1700.0
const RAILWAY_MAX_Y := 1850.0

const ROAD_COLOR := Color("#242d37")
const ROAD_EDGE := Color("#58626a")
const ASPHALT_WEAR := Color(0.42, 0.46, 0.48, 0.18)
const LANE_COLOR := Color("#d9c553")
const MEDIAN_COLOR := Color("#d8d5bd")
const GUARD_DARK := Color("#303940")
const GUARD_LIGHT := Color("#aab2b5")
const SHADOW_COLOR := Color(0.04, 0.055, 0.065, 0.48)

var _centerline := PackedVector2Array()
var _left_edge := PackedVector2Array()
var _right_edge := PackedVector2Array()
var _control_points := PackedVector2Array()


func _ready() -> void:
	add_to_group("district_one_vehicle_route_provider")
	_centerline = _build_centerline()
	_left_edge = _offset_polyline(_centerline, -ROAD_HALF_WIDTH)
	_right_edge = _offset_polyline(_centerline, ROAD_HALF_WIDTH)
	if Engine.is_editor_hint():
		queue_redraw()
		return
	_create_lane_paths()
	_create_side_barriers()
	_create_elevated_overlay()
	_create_temporary_limit()
	_create_connection_marker()
	queue_redraw()
	_validate_geometry()


func get_vehicle_routes() -> Dictionary:
	# The viaduct's old capsule route had a hidden turnaround before the Bairro 2
	# safety barrier.  It spawned cars that visibly made a U-turn at the closed
	# end.  Ambient traffic now uses Bairro1Expansion's connected circuits, which
	# traverse this deck through real junctions.  This provider stays empty until
	# Bairro 2 supplies a genuine continuation for the four highway lanes.
	return {}


func get_elevated_corridor_data() -> Dictionary:
	# Public safety/geodata API. Consumers receive the exact elevated slice of
	# this authoritative centerline instead of copying ELEVATED_FROM/TO or
	# approximating the bridge footprint.
	if _centerline.size() < ELEVATED_TO + 1:
		_centerline = _build_centerline()
	var local_points := _slice_points(_centerline, ELEVATED_FROM, ELEVATED_TO)
	var global_points := PackedVector2Array()
	for point in local_points:
		global_points.append(to_global(point))
	return {
		"global_points": global_points,
		"local_points": local_points,
		"half_width": ROAD_HALF_WIDTH,
		"safety_margin": 24.0,
		"deck_z_index": 6,
		"vehicle_z_index": 7,
		"source_road_id": "Bairro1Expansion/gateway_spine",
	}


func _build_centerline() -> PackedVector2Array:
	# The viaduct is an elevation upgrade of Bairro1Expansion's gateway_spine,
	# not a second road. It used to keep its own hand-typed copy of that curve,
	# which quietly drifted out of alignment with the ground-level street every
	# time either copy was edited (that mismatch was the crooked-merge bug).
	# Reading the control points from the source of truth makes drift impossible.
	_control_points = _source_control_points()
	return _catmull_rom(_control_points, 8)


func _source_control_points() -> PackedVector2Array:
	var expansion := get_node_or_null("../Bairro1Expansion")
	if expansion != null:
		var points = expansion.get("gateway_spine_points")
		if points is PackedVector2Array and points.size() >= 2:
			return points
	# Standalone editor fallback still reads the provider's one declaration.
	# Never repeat the gateway coordinates in this consumer.
	return Bairro1Expansion.GATEWAY_SPINE.duplicate()


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
		var normal := Vector2(-tangent.y, tangent.x)
		result.append(source[index] + normal * offset)
	return result


func _create_lane_paths() -> void:
	var lanes := Node2D.new()
	lanes.name = "HighwayLanePaths"
	add_child(lanes)
	var offsets := [-59.0, -20.0, 20.0, 59.0]
	for lane_index in offsets.size():
		var lane := Path2D.new()
		lane.name = "District1HighwayLane_%02d" % (lane_index + 1)
		lane.add_to_group("district_highway_lane")
		lane.set_meta("lane_index", lane_index)
		lane.set_meta("direction", "outbound" if lane_index < 2 else "inbound")
		lane.set_meta("district_connection", "District2Connection")
		var lane_points := _offset_polyline(_centerline, offsets[lane_index])
		if lane_index >= 2:
			lane_points.reverse()
		var curve := Curve2D.new()
		for point in lane_points:
			curve.add_point(point)
		lane.curve = curve
		lanes.add_child(lane)


func _create_side_barriers() -> void:
	var blockers := Node2D.new()
	blockers.name = "HighwayGuardRailCollisions"
	add_child(blockers)
	# Physical rails exist only on the elevated deck. Outside it, intersections
	# and driveways remain open to the authored Bairro 1 street network.
	for edge_info in [[_left_edge, "West"], [_right_edge, "East"]]:
		var edge: PackedVector2Array = edge_info[0]
		for index in range(ELEVATED_FROM, ELEVATED_TO):
			_add_segment_blocker(
				blockers,
				edge[index],
				edge[index + 1],
				RAIL_THICKNESS,
				"%sRail_%02d" % [edge_info[1], index]
			)


func _create_elevated_overlay() -> void:
	# Railway is rendered above ordinary ground. This dedicated overlay paints
	# only the deck above the tracks, while an Area raises cars/pedestrians above
	# the deck for the duration of their crossing.
	var deck := Node2D.new()
	deck.name = "ElevatedDeckOverlay"
	deck.z_index = 6
	add_child(deck)
	var left_slice := _slice_points(_left_edge, ELEVATED_FROM, ELEVATED_TO)
	var right_slice := _slice_points(_right_edge, ELEVATED_FROM, ELEVATED_TO)
	var deck_polygon := _ribbon_polygon(left_slice, right_slice)
	var asphalt := Polygon2D.new()
	asphalt.name = "ElevatedAsphalt"
	asphalt.polygon = deck_polygon
	asphalt.color = ROAD_COLOR
	deck.add_child(asphalt)
	_make_line(deck, "LeftDeckEdge", left_slice, ROAD_EDGE, 8.0)
	_make_line(deck, "RightDeckEdge", right_slice, ROAD_EDGE, 8.0)
	_make_line(deck, "LeftGuardRail", left_slice, GUARD_LIGHT, 4.0)
	_make_line(deck, "RightGuardRail", right_slice, GUARD_LIGHT, 4.0)
	for offset in [-MEDIAN_HALF_WIDTH, MEDIAN_HALF_WIDTH]:
		_make_line(deck, "Median_%s" % str(offset), _slice_points(_offset_polyline(_centerline, offset), ELEVATED_FROM, ELEVATED_TO), MEDIAN_COLOR, 3.0)
	for offset in [-41.0, 41.0]:
		var lane_points := _slice_points(_offset_polyline(_centerline, offset), ELEVATED_FROM, ELEVATED_TO)
		for index in range(0, lane_points.size() - 1, 2):
			_make_line(deck, "DeckDash_%s_%02d" % [str(offset), index], PackedVector2Array([lane_points[index], lane_points[index + 1]]), LANE_COLOR, 3.0)
	var detector := Area2D.new()
	detector.name = "ElevatedDeckBodyOrder"
	detector.collision_layer = 0
	detector.collision_mask = 1
	var detector_shape := CollisionPolygon2D.new()
	detector_shape.polygon = deck_polygon
	detector.add_child(detector_shape)
	detector.body_entered.connect(_on_bridge_body_entered)
	detector.body_exited.connect(_on_bridge_body_exited)
	add_child(detector)


func _make_line(parent: Node, line_name: String, points: PackedVector2Array, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.name = line_name
	line.points = points
	line.default_color = color
	line.width = width
	line.antialiased = true
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	parent.add_child(line)


func _slice_points(points: PackedVector2Array, first: int, last: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(first, last + 1):
		result.append(points[index])
	return result


func _on_bridge_body_entered(body: Node2D) -> void:
	if not body.has_meta("district1_pre_bridge_z"):
		body.set_meta("district1_pre_bridge_z", body.z_index)
	body.z_index = maxi(body.z_index, 7)


func _on_bridge_body_exited(body: Node2D) -> void:
	if body.has_meta("district1_pre_bridge_z"):
		body.z_index = int(body.get_meta("district1_pre_bridge_z"))
		body.remove_meta("district1_pre_bridge_z")


func _create_temporary_limit() -> void:
	if district2_unlocked:
		return
	var final_tangent := (_centerline[-1] - _centerline[-2]).normalized()
	var normal := Vector2(-final_tangent.y, final_tangent.x)
	var center := _centerline[-1] - final_tangent * 26.0
	_add_segment_blocker(
		self,
		center - normal * (ROAD_HALF_WIDTH - 5.0),
		center + normal * (ROAD_HALF_WIDTH - 5.0),
		18.0,
		"District2TemporarySafetyBarrier"
	)


func _create_connection_marker() -> void:
	var marker := Marker2D.new()
	marker.name = "District2Connection"
	marker.position = _centerline[-1]
	marker.add_to_group("District2Connection")
	marker.add_to_group("district_connection")
	marker.set_meta("from_district", 1)
	marker.set_meta("to_district", 2)
	marker.set_meta("connection_type", "four_lane_highway")
	marker.set_meta("temporary_blocked", not district2_unlocked)
	add_child(marker)


func _add_segment_blocker(parent: Node, from: Vector2, to: Vector2, thickness: float, blocker_name: String) -> void:
	var segment := to - from
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


func _validate_geometry() -> void:
	var expected_size := (_control_points.size() - 1) * 8 + 1
	assert(_centerline.size() == expected_size, "Highway curve sampling changed unexpectedly")
	assert(_centerline[0].distance_to(_control_points[0]) < 1.0, "Highway centerline did not sample its own first control point")
	assert(_control_points[0].distance_to(Vector2(870, 1260)) < 1.0, "Highway no longer starts where gateway_spine meets Bairro 1")
	var crosses_railway := false
	for point in _centerline:
		if point.y >= RAILWAY_MIN_Y and point.y <= RAILWAY_MAX_Y:
			crosses_railway = true
			break
	assert(crosses_railway, "Viaduct must cross the planned railway band")
	assert(get_node_or_null("District2Connection") != null, "Bairro 2 hand-off marker is required")
	print("DISTRICT1_HIGHWAY_READY: curved 4-lane viaduct, railway crossing and District2Connection")


func _draw() -> void:
	if _centerline.is_empty():
		return
	if draw_standalone_verge:
		_draw_approach_ground()
	_draw_elevated_shadow()
	_draw_viaduct_supports()
	_draw_road_ribbon()
	_draw_lane_markings()
	_draw_viaduct_structure()
	_draw_lighting_and_signage()
	if not district2_unlocked:
		_draw_temporary_barrier()


func _draw_approach_ground() -> void:
	# Dark verge makes the road read as a deliberate district edge, not empty void.
	var verge := _ribbon_polygon(
		_offset_polyline(_centerline, -(ROAD_HALF_WIDTH + 34.0)),
		_offset_polyline(_centerline, ROAD_HALF_WIDTH + 34.0)
	)
	draw_colored_polygon(verge, Color("#424a46"))


func _draw_elevated_shadow() -> void:
	var left_slice := PackedVector2Array()
	var right_slice := PackedVector2Array()
	for index in range(ELEVATED_FROM, ELEVATED_TO + 1):
		left_slice.append(_left_edge[index] + Vector2(24, 28))
		right_slice.append(_right_edge[index] + Vector2(24, 28))
	draw_colored_polygon(_ribbon_polygon(left_slice, right_slice), SHADOW_COLOR)


func _draw_road_ribbon() -> void:
	draw_colored_polygon(_ribbon_polygon(_left_edge, _right_edge), ROAD_COLOR)
	draw_polyline(_left_edge, ROAD_EDGE, 8.0, true)
	draw_polyline(_right_edge, ROAD_EDGE, 8.0, true)
	# Subtle seams and patched asphalt keep the large surface from looking flat.
	for index in range(4, _centerline.size() - 2, 5):
		var tangent := (_centerline[index + 1] - _centerline[index - 1]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		draw_line(
			_centerline[index] - normal * 88.0,
			_centerline[index] + normal * 88.0,
			ASPHALT_WEAR,
			2.0
		)


func _draw_lane_markings() -> void:
	# Solid double centre line divides opposing carriageways.
	for offset in [-MEDIAN_HALF_WIDTH, MEDIAN_HALF_WIDTH]:
		draw_polyline(_offset_polyline(_centerline, offset), MEDIAN_COLOR, 3.0, true)
	# Dashed separators create two lanes in each direction.
	_draw_dashed_curve(_offset_polyline(_centerline, -41.0), LANE_COLOR, 3.0)
	_draw_dashed_curve(_offset_polyline(_centerline, 41.0), LANE_COLOR, 3.0)


func _draw_dashed_curve(points: PackedVector2Array, color: Color, width: float) -> void:
	for index in range(0, points.size() - 1, 2):
		draw_line(points[index], points[index + 1], color, width, true)


func _draw_viaduct_structure() -> void:
	# Rails are drawn only over the elevated span; lower approach uses kerbs.
	for edge in [_left_edge, _right_edge]:
		var elevated := PackedVector2Array()
		for index in range(ELEVATED_FROM, ELEVATED_TO + 1):
			elevated.append(edge[index])
		draw_polyline(elevated, GUARD_DARK, 12.0, true)
		draw_polyline(elevated, GUARD_LIGHT, 4.0, true)
		for index in range(ELEVATED_FROM, ELEVATED_TO + 1, 2):
			draw_circle(edge[index], 5.0, GUARD_DARK)
			draw_circle(edge[index], 2.2, Color("#d3d7d5"))


func _draw_viaduct_supports() -> void:
	# Piers are painted before the deck so the road correctly occludes their
	# inner halves. Their outer caps remain visible from the top-down camera.
	for index in [13, 19, 26]:
		var tangent := (_centerline[index + 1] - _centerline[index - 1]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		for side in [-1.0, 1.0]:
			var center: Vector2 = _centerline[index] + normal * (ROAD_HALF_WIDTH + 20.0) * float(side)
			draw_ellipse_shadow(center + Vector2(13, 18), Vector2(37, 16))
			draw_set_transform(center, tangent.angle(), Vector2.ONE)
			draw_rect(Rect2(Vector2(-28, -13), Vector2(56, 26)), Color("#6f7778"))
			draw_rect(Rect2(Vector2(-22, -9), Vector2(44, 18)), Color("#a5a6a0"))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_ellipse_shadow(center: Vector2, radius: Vector2) -> void:
	var points := PackedVector2Array()
	for step in range(18):
		var angle := TAU * float(step) / 18.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, Color(0.04, 0.05, 0.05, 0.4))


func _draw_lighting_and_signage() -> void:
	# Paired road lights keep the long exit alive at night without cluttering it.
	for index in range(6, _centerline.size() - 4, 6):
		var tangent := (_centerline[index + 1] - _centerline[index - 1]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		for side in [-1.0, 1.0]:
			var base: Vector2 = _centerline[index] + normal * (ROAD_HALF_WIDTH + 14.0) * float(side)
			draw_circle(base + Vector2(7, 9), 6.5, Color(0.03, 0.04, 0.05, 0.42))
			draw_circle(base, 5.0, Color("#3b4449"))
			draw_circle(base, 2.4, Color("#f2c86a"))
	# A physical gantry near the future hand-off, not a floating HUD label.
	var gantry_y := 3366.0
	draw_rect(Rect2(1360, gantry_y, 10, 78), GUARD_DARK)
	draw_rect(Rect2(1570, gantry_y, 10, 78), GUARD_DARK)
	draw_rect(Rect2(1360, gantry_y, 220, 9), GUARD_LIGHT)
	draw_rect(Rect2(1402, gantry_y - 35, 136, 37), Color("#214d42"))
	draw_rect(Rect2(1402, gantry_y - 35, 136, 37), Color("#d8ddd1"), false, 3.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(1413, gantry_y - 11), "ACESSO DISTRITO 2", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#f0f1dc"))


func _draw_temporary_barrier() -> void:
	var center := _centerline[-1] - Vector2(0, 26)
	draw_rect(Rect2(center - Vector2(96, 9), Vector2(192, 18)), Color("#d5d1c1"))
	for x in range(int(center.x - 90), int(center.x + 82), 24):
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, center.y - 8), Vector2(x + 12, center.y - 8),
			Vector2(x + 25, center.y + 8), Vector2(x + 13, center.y + 8)
		]), Color("#d45b34"))
	for x in [center.x - 76.0, center.x + 76.0]:
		draw_rect(Rect2(x - 5, center.y + 8, 10, 18), GUARD_DARK)


func _ribbon_polygon(left: PackedVector2Array, right: PackedVector2Array) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point in left:
		polygon.append(point)
	for index in range(right.size() - 1, -1, -1):
		polygon.append(right[index])
	return polygon
