@tool
extends Node2D
## Self-contained east waterfront for the isolated Harbor district preview.
## The quay begins beyond the road/sidewalk reservation. The channel is impassable
## except for HarborBridge and the fixed gangway leading onto Northstar's deck.

const SHORE_X := 3200.0
const QUAY_X := 3130.0
const SHIP_BOUNDS := Rect2(3350.0, 650.0, 440.0, 1500.0)
const WATER_BOUNDS := Rect2(3200.0, -5000.0, 10000.0, 15000.0)
# Mountain terrain starts at local X=4650 and ends at local Y=5000,
# translated by ContinuousWorld.MOUNTAIN_OFFSET (4300, -4960).
const MOUNTAIN_COAST_X := 8950.0
const MOUNTAIN_SOUTH_Y := 40.0
const EAST_SHORE_X := 4380.0
const BRIDGE_OPENING := Rect2(3200.0, 298.0, 1180.0, 204.0)
const GANGWAY_BOUNDS := Rect2(3130.0, 1742.0, 288.0, 40.0)
const GANGWAY_RAILS: Array[Rect2] = [Rect2(3130, 1738, 242, 4), Rect2(3130, 1782, 242, 4)]
## Spreader positions stay over cargo bays, never the aft accommodation block.
const CRANE_Y: Array[float] = [990.0, 1460.0, 1700.0]
const CONTAINER_COLORS: Array[Color] = [
	Color("ba624c"), Color("3e8292"), Color("c2a468"),
	Color("526d7e"), Color("8b534b"), Color("6e8a78"),
]

@export var animate_water: bool = true


func _ready() -> void:
	_build_water_surfaces()
	_build_collisions()
	_build_ship_markers()
	if not Engine.is_editor_hint():
		var crew := preload("res://world/harbor/HarborDockCrew.gd").new()
		crew.name = "DockCrew"
		add_child(crew)
	set_process(false)
	queue_redraw()


func _build_water_surfaces() -> void:
	var water = preload("res://world/shared/nature/WaterPresentation.gd")
	# Filhos atrás do desenho estático mantêm navio, cais e terra sobre a água.
	water.rectangle(self, Rect2(WATER_BOUNDS.position, Vector2(MOUNTAIN_COAST_X - WATER_BOUNDS.position.x, WATER_BOUNDS.size.y)), Color("204754"), animate_water)
	water.rectangle(self, Rect2(Vector2(MOUNTAIN_COAST_X, MOUNTAIN_SOUTH_Y), WATER_BOUNDS.end - Vector2(MOUNTAIN_COAST_X, MOUNTAIN_SOUTH_Y)), Color("204754"), animate_water)
	water.rectangle(self, Rect2(3200, -5000, 32, 15000), Color("326a72"), animate_water)
	water.rectangle(self, Rect2(3232, -5000, 65, 15000), Color("2b5965"), animate_water)
	water.rectangle(self, Rect2(3297, -5000, 110, 15000), Color("264e5d"), animate_water)


func _build_collisions() -> void:
	if has_node("WaterfrontObstacles"):
		return
	var body := StaticBody2D.new()
	body.name = "WaterfrontObstacles"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var water_rects := get_water_collision_rects()
	for i in range(water_rects.size()):
		_add_box(body, water_rects[i], "ChannelBoundary%d" % i)
	for polygon in get_water_collision_polygons():
		var collision := CollisionPolygon2D.new()
		collision.polygon = polygon
		body.add_child(collision)
	# Metal impact groups belong to structures, never the water boundary.
	var structures := _new_solid_body("ShipStructures", true)
	for i in range(CRANE_Y.size()):
		_add_box(structures, Rect2(3140.0, CRANE_Y[i] - 36.0, 51.0, 72.0), "CraneBase%d" % i)
	var obstacles := _get_ship_obstacles()
	for i in range(obstacles.size()):
		_add_box(structures, obstacles[i], "ShipObstacle%d" % i)
	var rails := _new_solid_body("ShipGuardRails", true)
	for i in range(GANGWAY_RAILS.size()):
		_add_box(rails, GANGWAY_RAILS[i], "GangwayRail%d" % i)
	for segment in _deck_edge_segments():
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(segment[0].distance_to(segment[1]), 4)
		collision.shape = shape
		collision.position = (segment[0] + segment[1]) * 0.5
		collision.rotation = (segment[1] - segment[0]).angle()
		rails.add_child(collision)


func _new_solid_body(label: String, metal: bool) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	if metal:
		body.add_to_group("metal_prop")
	add_child(body)
	return body


func _add_box(body: StaticBody2D, bounds: Rect2, label: String) -> void:
	var collision := CollisionShape2D.new()
	collision.name = label
	var shape := RectangleShape2D.new()
	shape.size = bounds.size
	collision.shape = shape
	collision.position = bounds.get_center()
	body.add_child(collision)


func get_waterfront_audit_data() -> Dictionary:
	var bases: Array[Rect2] = []
	for y in CRANE_Y:
		bases.append(Rect2(3140.0, y - 36.0, 51.0, 72.0))
	return {
		"shore_x": SHORE_X,
		"quay_bounds": Rect2(QUAY_X, 0.0, SHORE_X - QUAY_X, 2700.0),
		"ship_bounds": SHIP_BOUNDS,
		"east_shore_x": EAST_SHORE_X,
		# This is only the envelope; audit the actual rectangles AND clipped polygons.
		"water_collision_bounds": Rect2(SHORE_X, -5000.0, EAST_SHORE_X - SHORE_X, 15000.0),
		"water_collision_rects": get_water_collision_rects(),
		"water_collision_polygons": get_water_collision_polygons(),
		"bridge_opening": BRIDGE_OPENING,
		"crane_obstacles": bases,
		"ship_access": get_ship_access_data(),
	}


func get_water_collision_rects() -> Array[Rect2]:
	return [
		Rect2(SHORE_X, -5000.0, EAST_SHORE_X - SHORE_X, BRIDGE_OPENING.position.y + 5000.0),
		Rect2(SHORE_X, 2140.0, EAST_SHORE_X - SHORE_X, 7860.0),
	]


func get_water_collision_polygons() -> Array[PackedVector2Array]:
	# Joining the hull to the shore BEFORE subtraction avoids a polygonal hole
	# being interpreted as another filled collision polygon. The stern touches
	# this band's bottom; all results are simple water polygons, never deck boxes.
	var water_band := _rect_polygon(Rect2(SHORE_X, BRIDGE_OPENING.end.y, EAST_SHORE_X - SHORE_X, 2140.0 - BRIDGE_OPENING.end.y))
	var connected_land := Geometry2D.merge_polygons(_hull_polygon(), _rect_polygon(GANGWAY_BOUNDS))
	assert(connected_land.size() == 1, "Ship gangway must physically overlap its hull")
	return Geometry2D.clip_polygons(water_band, connected_land[0])


func _rect_polygon(bounds: Rect2) -> PackedVector2Array:
	return PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])


func _hull_polygon() -> PackedVector2Array:
	return PackedVector2Array([Vector2(3570, 650), Vector2(3663, 728), Vector2(3745, 848), Vector2(3790, 984), Vector2(3790, 2070), Vector2(3756, 2140), Vector2(3384, 2140), Vector2(3350, 2070), Vector2(3350, 984), Vector2(3395, 848), Vector2(3477, 728)])


func _deck_polygon() -> PackedVector2Array:
	return PackedVector2Array([Vector2(3570, 680), Vector2(3645, 748), Vector2(3722, 862), Vector2(3768, 990), Vector2(3768, 2070), Vector2(3740, 2115), Vector2(3400, 2115), Vector2(3372, 2070), Vector2(3372, 990), Vector2(3418, 862), Vector2(3495, 748)])


func _cargo_bounds() -> Array[Rect2]:
	var cargo: Array[Rect2] = []
	for row in range(6):
		for x in [3430.0, 3540.0, 3650.0]:
			cargo.append(Rect2(x, 1000 + row * 112, 60, 104))
	return cargo


func _get_ship_obstacles() -> Array[Rect2]:
	var obstacles := _cargo_bounds()
	obstacles.append_array([
		Rect2(3504, 855, 28, 34), Rect2(3608, 855, 28, 34),
		Rect2(3532, 903, 76, 23),
		Rect2(3440, 1795, 260, 232), Rect2(3424, 1811, 292, 54),
		Rect2(3430, 1890, 23, 84), Rect2(3690, 1890, 23, 84),
	])
	return obstacles


func _deck_edge_segments() -> Array[PackedVector2Array]:
	var segments: Array[PackedVector2Array] = []
	var deck := _deck_polygon()
	for i in range(deck.size()):
		var first := deck[i]
		var last := deck[(i + 1) % deck.size()]
		if first.x == 3372.0 and last.x == 3372.0:
			segments.append(PackedVector2Array([first, Vector2(3372, GANGWAY_BOUNDS.end.y)]))
			segments.append(PackedVector2Array([Vector2(3372, GANGWAY_BOUNDS.position.y), last]))
		else:
			segments.append(PackedVector2Array([first, last]))
	return segments


func get_ship_access_data() -> Dictionary:
	return {
		"gangway_bounds": GANGWAY_BOUNDS,
		"hull_polygon": _hull_polygon(),
		"deck_polygon": _deck_polygon(),
		"obstacles": _get_ship_obstacles(),
		"cargo_obstacles": _cargo_bounds(),
		"guard_rails": GANGWAY_RAILS.duplicate(),
		"deck_edge_segments": _deck_edge_segments(),
		"walk_route": PackedVector2Array([Vector2(3130, 1762), Vector2(3402, 1762), Vector2(3402, 1050), Vector2(3402, 965), Vector2(3465, 965), Vector2(3515, 965), Vector2(3515, 1450), Vector2(3515, 965), Vector2(3465, 965), Vector2(3465, 830), Vector2(3570, 830), Vector2(3570, 755), Vector2(3570, 830), Vector2(3675, 830), Vector2(3675, 965), Vector2(3738, 965), Vector2(3738, 2070), Vector2(3402, 2070), Vector2(3402, 1762), Vector2(3130, 1762)]),
		"future_markers": {"GangwayEntry": Vector2(3130, 1762), "ShipLanding": Vector2(3402, 1762), "CargoInspection": Vector2(3515, 1450), "BowLookout": Vector2(3570, 755), "AftAssembly": Vector2(3570, 2070)},
		"combat_probe": {"position": Vector2(3402, 1762), "target": Vector2(3460, 1610)},
		"water_negative_samples": PackedVector2Array([Vector2(3300, 750), Vector2(4000, 1000), Vector2(3300, 1710), Vector2(3300, 1820), Vector2(3400, 720), Vector2(3570, 2180)]),
		"mission_integrated": false,
		"ship_pilotable": false,
	}


func _build_ship_markers() -> void:
	if has_node("ShipWaypoints"):
		return
	var waypoints := Node2D.new()
	waypoints.name = "ShipWaypoints"
	add_child(waypoints)
	for label in get_ship_access_data().future_markers:
		var marker := Marker2D.new()
		marker.name = label
		marker.position = get_ship_access_data().future_markers[label]
		waypoints.add_child(marker)


func _draw() -> void:
	_draw_water()
	_draw_quay()
	_draw_ship()
	_draw_gangway_and_rails()
	for i in range(CRANE_Y.size()):
		_draw_crane(CRANE_Y[i], i)


func _draw_water() -> void:
	# Harbor navigation buoys occupy the shipping channel, never a road.
	for y in [650.0, 2250.0, 2530.0]:
		var buoy := Vector2(4050.0, y)
		draw_circle(buoy + Vector2(4, 5), 13.0, Color(0.04, 0.12, 0.15, 0.35))
		draw_circle(buoy, 8.0, Color("c26650"))
		draw_circle(buoy, 3.5, Color("e7cba1"))


func _draw_quay() -> void:
	draw_rect(Rect2(3130, 0, 70, 2700), Color("989488"))
	draw_rect(Rect2(3130, 0, 8, 2700), Color("b2ad9a"))
	draw_rect(Rect2(3190, 0, 10, 2700), Color("c3bba6"))
	draw_rect(Rect2(3200, 0, 7, 2700), Color("132c35"))
	for y in range(0, 2700, 95):
		draw_line(Vector2(3138, y), Vector2(3190, y), Color("797b73"), 1.0)
	for y in range(25, 2690, 42):
		draw_line(Vector2(3188, y), Vector2(3197, y + 15), Color("d9b75a"), 5.0)
	for y in range(180, 2600, 160):
		# Bollards are outside the usable road corridor; rubber fenders face water.
		draw_rect(Rect2(3197, y - 18, 13, 36), Color("192e33"))
		draw_circle(Vector2(3179, y), 7.0, Color("444b48"))
		draw_line(Vector2(3173, y), Vector2(3185, y), Color("d0b273"), 5.0)
	for y in [700.0, 2110.0]:
		# Bow lines reach the narrowing hull rather than ending in open water.
		var first_hull_point := Vector2(3442, 785) if y < 1000 else Vector2(3371, 2065)
		var second_hull_point := Vector2(3414, 825) if y < 1000 else Vector2(3368, 2015)
		draw_line(Vector2(3179, y), first_hull_point, Color("bcb49a"), 2.5, true)
		draw_line(Vector2(3179, y + 40), second_hull_point, Color("8f977f"), 2.0, true)
	_draw_label(Vector2(3152, 410), "BERTH 04", 12, Color("e9e1c9"), -PI / 2.0)
	_draw_label(Vector2(3152, 2520), "RESTRICTED QUAYSIDE", 10, Color("e9e1c9"), -PI / 2.0)


func _draw_ship() -> void:
	# Bow north, squared stern south. Hull, deck and rows share one orientation.
	var hull := _hull_polygon()
	var shadow := PackedVector2Array()
	for point in hull:
		shadow.append(point + Vector2(24, 28))
	draw_colored_polygon(shadow, Color(0.025, 0.10, 0.13, 0.42))
	draw_colored_polygon(hull, Color("182f3b"))
	var closed := hull.duplicate()
	closed.append(hull[0])
	draw_polyline(closed, Color("d6c9a8"), 5.0, true)
	var deck := _deck_polygon()
	draw_colored_polygon(deck, Color("596a68"))
	# Raised foredeck, mooring gear and hatch before the first container bay.
	draw_colored_polygon(PackedVector2Array([
		Vector2(3570, 704), Vector2(3650, 790), Vector2(3705, 939),
		Vector2(3435, 939), Vector2(3490, 790),
	]), Color("8b9587"))
	for x in [3518.0, 3622.0]:
		draw_rect(Rect2(x - 14, 865, 28, 24), Color("384b4b"))
		draw_circle(Vector2(x, 865), 10.0, Color("b4b6a1"))
		draw_line(Vector2(x, 855), Vector2(3570, 726), Color("536a69"), 2.0)
	draw_rect(Rect2(3532, 903, 76, 23), Color("b6b49c"))
	# Cargo leaves >=50px longitudinal work aisles and a real fore/aft circuit.
	# These are traversable spaces, not the old 11px gaps between painted boxes.
	var cargo := _cargo_bounds()
	for i in range(cargo.size()):
		_draw_container(cargo[i], CONTAINER_COLORS[(i + int(i / 3)) % CONTAINER_COLORS.size()])
	for x in [3402.0, 3515.0, 3625.0, 3738.0]:
		draw_line(Vector2(x, 980), Vector2(x, 1740), Color(0.83, 0.80, 0.64, 0.30), 22.0)
		draw_line(Vector2(x - 17, 992), Vector2(x - 17, 1715), Color("d3c596"), 1.0)
		draw_line(Vector2(x + 17, 992), Vector2(x + 17, 1715), Color("d3c596"), 1.0)
	draw_line(Vector2(3392, 1762), Vector2(3748, 1762), Color(0.83, 0.80, 0.64, 0.20), 30.0)
	# Aft accommodation block / wheelhouse reads differently from cargo.
	draw_rect(Rect2(3448, 1807, 260, 232), Color(0.05, 0.13, 0.15, 0.35))
	draw_rect(Rect2(3440, 1795, 260, 232), Color("e0dbbd"))
	draw_rect(Rect2(3451, 1804, 238, 211), Color("aab5a9"))
	draw_rect(Rect2(3424, 1811, 292, 54), Color("ece6ca"))
	for column in range(10):
		draw_rect(Rect2(3432 + column * 28, 1818, 23, 24), Color("335667"))
		draw_line(Vector2(3434 + column * 28, 1820), Vector2(3450 + column * 28, 1820), Color("79a1a6"), 2.0)
	draw_rect(Rect2(3473, 1880, 183, 112), Color("d5d5bc"))
	draw_rect(Rect2(3521, 1891, 77, 88), Color("a94f3f"))
	draw_rect(Rect2(3529, 1900, 61, 59), Color("293b40"))
	draw_rect(Rect2(3537, 1906, 17, 40), Color("132c36"))
	draw_rect(Rect2(3567, 1906, 17, 40), Color("132c36"))
	# Lifeboats at the stern-side davits, safely distinct from container colors.
	for x in [3430.0, 3690.0]:
		draw_style_box(_rounded_box(Color("db7f47"), 10), Rect2(x, 1890, 23, 84))
		draw_rect(Rect2(x + 6, 1904, 11, 46), Color("f0cf94"))
		draw_line(Vector2(x - 4, 1895), Vector2(x + 27, 1895), Color("c8c9ad"), 3.0)
		draw_line(Vector2(x - 4, 1970), Vector2(x + 27, 1970), Color("c8c9ad"), 3.0)
	# Mast is on the accommodation roof, not across the gangway landing.
	draw_line(Vector2(3569, 1830), Vector2(3569, 1907), Color("e5d8b8"), 4.0)
	draw_line(Vector2(3537, 1841), Vector2(3601, 1841), Color("e5d8b8"), 3.0)
	draw_circle(Vector2(3569, 1829), 6.0, Color("ead7a0"))
	_draw_label(Vector2(3422, 2087), "NORTHSTAR  /  PACIFIC FREIGHT", 15, Color("e4dfc7"))


func _draw_gangway_and_rails() -> void:
	# A fixed docked access bridge: floor and bullet/player ordering remain z=0.
	draw_rect(Rect2(GANGWAY_BOUNDS.position + Vector2(0, 7), GANGWAY_BOUNDS.size), Color(0.035, 0.1, 0.12, 0.4))
	draw_rect(GANGWAY_BOUNDS, Color("#a4ada4"))
	draw_rect(GANGWAY_BOUNDS.grow(-3), Color("#737f7b"))
	for x in range(int(GANGWAY_BOUNDS.position.x) + 7, int(GANGWAY_BOUNDS.end.x) - 3, 9):
		draw_line(Vector2(x, 1745), Vector2(x, 1779), Color("#b1b9a8"), 1.0)
	for rail in GANGWAY_RAILS:
		draw_rect(rail, Color("#d7cda7"))
		for x in range(int(rail.position.x), int(rail.end.x), 28):
			draw_circle(Vector2(x, rail.get_center().y), 3.0, Color("#e8dbb3"))
	for segment in _deck_edge_segments():
		draw_line(segment[0], segment[1], Color("#d4c9a4"), 4.0, true)
		var length := segment[0].distance_to(segment[1])
		for offset in range(12, int(length), 45):
			draw_circle(segment[0].lerp(segment[1], float(offset) / length), 2.5, Color("#eadcb4"))
	_draw_label(Vector2(3220, 1770), "NORTHSTAR", 11, Color("#f0e6c6"))


func _draw_container(bounds: Rect2, color: Color) -> void:
	draw_rect(Rect2(bounds.position + Vector2(4, 5), bounds.size), Color(0.035, 0.095, 0.12, 0.36))
	draw_rect(bounds, color.darkened(0.16))
	draw_rect(Rect2(bounds.position + Vector2(3, 3), bounds.size - Vector2(6, 6)), color)
	for rib in range(5, int(bounds.size.y) - 3, 7):
		var y := bounds.position.y + rib
		draw_line(Vector2(bounds.position.x + 4, y), Vector2(bounds.end.x - 4, y), color.lightened(0.16), 1.5)
	draw_rect(bounds, color.darkened(0.30), false, 1.5)
	draw_rect(Rect2(bounds.position + Vector2(8, 14), Vector2(17, 6)), Color(0.93, 0.91, 0.79, 0.55))


func _draw_crane(y: float, index: int) -> void:
	var base := Vector2(3165, y)
	var boom_end := Vector2(3715 - index * 26, y - 110)
	var gold := Color("c4a366")
	var shade := Color("7b754f")
	# A diagonal raised boom reaches across the vessel; its shadow sits on water.
	draw_line(base + Vector2(18, 19), boom_end + Vector2(18, 19), Color(0.05, 0.15, 0.18, 0.28), 17.0, true)
	draw_rect(Rect2(3140, y - 36, 51, 72), Color("5f6b65"))
	draw_rect(Rect2(3146, y - 30, 39, 60), gold)
	draw_circle(base, 16.0, shade)
	var perpendicular := (boom_end - base).normalized().orthogonal() * 11.0
	draw_line(base + perpendicular, boom_end + perpendicular, gold, 5.0, true)
	draw_line(base - perpendicular, boom_end - perpendicular, gold, 5.0, true)
	for part in range(14):
		var start := base.lerp(boom_end, float(part) / 14.0)
		var finish := base.lerp(boom_end, float(part + 1) / 14.0)
		draw_line(start + perpendicular, finish - perpendicular, shade, 2.5, true)
		draw_line(start - perpendicular, start + perpendicular, gold, 2.0, true)
	draw_rect(Rect2(base + Vector2(4, -22), Vector2(26, 26)), Color("dad1a9"))
	draw_rect(Rect2(base + Vector2(10, -18), Vector2(16, 13)), Color("355561"))
	var trolley := base.lerp(boom_end, 0.77)
	draw_circle(trolley, 6.0, Color("303f41"))
	draw_line(trolley, trolley + Vector2(0, 49), Color("d0ccac"), 1.5)
	draw_rect(Rect2(trolley + Vector2(-25, 44), Vector2(50, 11)), gold)


func _rounded_box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style


func _draw_label(at: Vector2, label: String, size: int, color: Color, angle: float = 0.0) -> void:
	draw_set_transform(at, angle)
	draw_string(ThemeDB.fallback_font, Vector2.ZERO, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	draw_set_transform(Vector2.ZERO)
