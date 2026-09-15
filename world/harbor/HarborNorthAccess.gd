@tool
extends RefCounted
## Closed construction access: deliberately excluded from through-traffic routing.
## Its lower crossing must never create junctions with the mountain bridge.
const WIDTH := 96.0
const AXES := [5860.0, 6020.0]
const GATE_Y := -5510.0
const TUNNEL := Rect2(5772, -5140, 336, 190)
const PATCH := Rect2(6400, -4780, 600, 470)
const BOUNDS := Rect2(5300, -5920, 1750, 2110)

## Only these at-grade mouths join the avenue. The rest remains on the lower
## layer, including the crossing beneath the mountain bridge.
static func mouths() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for route in curves():
		var points := PackedVector2Array()
		for point in route.get_baked_points():
			if point.y >= -4260: points.append(point)
		result.append(points)
	return result

static func avenue_opening(inbound: bool) -> Dictionary:
	var side_x := 5790.0 if inbound else 6210.0
	var nearest := Vector2.INF
	for point in mouths()[0 if inbound else 1]:
		if absf(point.x-side_x) < absf(nearest.x-side_x): nearest = point
	return {"position":Vector2(side_x,nearest.y),"radius":140.0}

static func curves() -> Array[Curve2D]:
	var left := Curve2D.new()
	left.bake_interval = 8
	left.add_point(Vector2(5880,-3970), Vector2.ZERO, Vector2(0,-160))
	left.add_point(Vector2(5480,-4420), Vector2(0,190), Vector2(0,-240))
	left.add_point(Vector2(5860,-4940), Vector2(0,270), Vector2(0,-130))
	left.add_point(Vector2(5860,GATE_Y), Vector2(0,140), Vector2.ZERO)
	var right := Curve2D.new()
	right.bake_interval = 8
	right.add_point(Vector2(6020,GATE_Y), Vector2.ZERO, Vector2(0,140))
	right.add_point(Vector2(6020,-4940), Vector2(0,-140), Vector2(0,130))
	right.add_point(Vector2(6800,-4550), Vector2(0,-280), Vector2(0,210))
	right.add_point(Vector2(6530,-4090), Vector2(230,0), Vector2(-220,0))
	right.add_point(Vector2(6120,-3880), Vector2(0,-140), Vector2.ZERO)
	return [left,right]

static func distance_to_route(point: Vector2, route: Curve2D) -> float:
	return point.distance_to(route.sample_baked(route.get_closest_offset(point)))

static func contains(point: Vector2, margin: float = 0.0) -> bool:
	for route in curves():
		if distance_to_route(point,route) <= WIDTH * 0.5 + margin: return true
	return false

static func water_cutouts() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for route in curves():
		result.append_array(Geometry2D.offset_polyline(route.get_baked_points(),74,Geometry2D.JOIN_ROUND,Geometry2D.END_SQUARE))
	for x in AXES:
		var r := Rect2(x-74,-5880,148,400)
		result.append(PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]))
	return result
