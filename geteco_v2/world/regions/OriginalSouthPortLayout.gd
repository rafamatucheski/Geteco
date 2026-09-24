extends RefCounted
## Shared ground contract for rendering, ocean subtraction, roads and navigation.
const LAND := Rect2(3200, 3200, 2900, 2800)
const WALKWAY := Rect2(3534, 2108, 72, 1132)
const WALK_ROUTE := [Vector2(3570, 2070), Vector2(3570, 3260), Vector2(3570, 3500), Vector2(3670, 3500)]
const ACCESS := [Vector2(3000, 2200), Vector2(3180, 2200), Vector2(3310, 2330), Vector2(3310, 3600), Vector2(3750, 3600)]
# The road renderer already reserves 92px from the centreline (50px asphalt +
# 42px sidewalk).  The shoreline needs a separate shoulder beyond that: using
# the same 92px envelope put the physical seawall directly against the bend.
const ACCESS_LAND_HALF_WIDTH := 142.0
const PIERS := [Rect2(6100, 3650, 230, 100), Rect2(6100, 4210, 230, 100)]
const SHIP := Rect2(3950, 2730, 1710, 390)
const SHIP_GANGWAY := Rect2(4218, 3090, 64, 160)
const SHIP_CARGO := Rect2(4310, 2780, 1065, 268)
const WHEELHOUSE := Rect2(3990, 2780, 210, 270)
const CRANES := [Vector2(4140, 3260), Vector2(4730, 3260), Vector2(5320, 3260)]
const WAREHOUSES := [Rect2(3980, 5050, 640, 330), Rect2(4860, 5050, 640, 330)]

static func roads() -> Array[Dictionary]:
	return [
		{"id":"south_port_access", "points":PackedVector2Array(ACCESS), "width":100.0, "open_start":false, "open_end":false},
		{"id":"south_port_north", "points":PackedVector2Array([Vector2(3750,3600),Vector2(5750,3600)]), "width":120.0, "open_start":false, "open_end":false},
		{"id":"south_port_east", "points":PackedVector2Array([Vector2(5750,3600),Vector2(5750,5650)]), "width":120.0, "open_start":false, "open_end":false},
		{"id":"south_port_south", "points":PackedVector2Array([Vector2(5750,5650),Vector2(3750,5650)]), "width":120.0, "open_start":false, "open_end":false},
		{"id":"south_port_west", "points":PackedVector2Array([Vector2(3750,5650),Vector2(3750,3600)]), "width":120.0, "open_start":false, "open_end":false},
		{"id":"south_port_dispatch", "points":PackedVector2Array([Vector2(3750,4770),Vector2(5750,4770)]), "width":110.0, "open_start":false, "open_end":false},
	]

static func containers() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for y in [3890, 4360]:
		for x in [3990, 4510, 5030]:
			for row in 3:
				result.append(Rect2(x, y + row * 86, 330, 65))
	return result

static func rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x,rect.position.y), rect.end, Vector2(rect.position.x,rect.end.y)])

static func ship_hull() -> PackedVector2Array:
	return PackedVector2Array([Vector2(3950,2730),Vector2(5460,2730),Vector2(5620,2820),Vector2(5700,2925),Vector2(5590,3050),Vector2(5460,3120),Vector2(3950,3120),Vector2(3895,3070),Vector2(3895,2790)])

static func ship_containers() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for col in 7:
		for row in 2:
			var center := SHIP_CARGO.position + Vector2(SHIP_CARGO.size.x/14.0+col*SHIP_CARGO.size.x/7.0,SHIP_CARGO.size.y*(.12 if row == 0 else .88))
			var size := Vector2(SHIP_CARGO.size.x/7.0*.90,SHIP_CARGO.size.y*.21)
			result.append(Rect2(center-size*.5,size))
	return result

static func surfaces() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = [rect_polygon(LAND), rect_polygon(WALKWAY)]
	result.append_array(Geometry2D.offset_polyline(PackedVector2Array(ACCESS), ACCESS_LAND_HALF_WIDTH, Geometry2D.JOIN_ROUND, Geometry2D.END_SQUARE))
	for pier in PIERS: result.append(rect_polygon(pier))
	# Join to the quay before clipping: an isolated hull would create a water hole.
	var boarding := Geometry2D.merge_polygons(rect_polygon(SHIP_GANGWAY),ship_hull())
	result.append_array(boarding)
	return result

static func subtract_surfaces(water: PackedVector2Array) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [water]
	for surface in surfaces():
		var next: Array[PackedVector2Array] = []
		for piece in pieces: next.append_array(Geometry2D.clip_polygons(piece,surface))
		pieces = next
	return pieces
