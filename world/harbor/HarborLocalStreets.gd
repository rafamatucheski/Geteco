extends RefCounted
## Shared geometry for the two local roads and their service approaches.
const GARAGE_POSITION := Vector2(790, 1495)
const POLICE_POSITION := Vector2(1080, 1950)
const PATROL_Y := 1718.0
const MEDICAL_Y := 1960.0
const MEDICAL_AISLE_X := 2083.0
const ROADS := [
	{"id": "westgate_service_lane", "start": Vector2(400, PATROL_Y), "end": Vector2(1300, PATROL_Y), "width": 72.0},
	{"id": "medical_garden_lane", "start": Vector2(1300, MEDICAL_Y), "end": Vector2(2200, MEDICAL_Y), "width": 84.0},
]

static func reserves(point: Vector2, radius := 0.0) -> bool:
	for road in ROADS:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, road.start, road.end)) < float(road.width) * .5 + 42.0 + radius:
			return true
	return Rect2(2041, 1725, 84, MEDICAL_Y - 1725).grow(radius).has_point(point)

static func medical_departure(origin: Vector2) -> PackedVector2Array:
	# Two 70px radius bends fit the existing ambulance hull and the south aisle.
	var points := PackedVector2Array([origin])
	var radius := 70.0
	var first := Vector2(MEDICAL_AISLE_X - radius, origin.y + radius)
	for i in 13:
		points.append(first + Vector2.from_angle(lerpf(-PI * .5, 0, i / 12.0)) * radius)
	var second := Vector2(MEDICAL_AISLE_X - radius, MEDICAL_Y - 21 - radius)
	for i in 13:
		points.append(second + Vector2.from_angle(lerpf(0, PI * .5, i / 12.0)) * radius)
	points.append(Vector2(1940, MEDICAL_Y - 21))
	return points

static func police_departure(origin: Vector2, target: Vector2) -> PackedVector2Array:
	var west := target.x < origin.x
	var lane_y := PATROL_Y + (-18 if west else 18)
	var center := Vector2(origin.x + (-45 if west else 45), lane_y + 45)
	var points := PackedVector2Array([origin])
	for i in 13:
		var angle := lerpf(0, -PI * .5, i / 12.0) if west else lerpf(PI, PI * 1.5, i / 12.0)
		points.append(center + Vector2.from_angle(angle) * 45)
	points.append(Vector2(center.x + (-70 if west else 70), lane_y))
	return points
