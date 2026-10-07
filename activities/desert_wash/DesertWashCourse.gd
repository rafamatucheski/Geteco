extends RefCounted
## The authored wash centreline; no new terrain, road graph or collision.
const LANDFORMS := preload("res://world/desert/expansion/DesertLandforms.gd")
const START_T := .08
const END_T := .92
const GATES := 13
const HALF_WIDTH := 4.0
const TIME_LIMIT := 65.0
const PRIZE_TIME := 45.0

static func point(t: float) -> Vector3:
	var p := LANDFORMS.wash_point(t)
	return Vector3(p.x, 0.08, p.y)

static func gate(index: int) -> Vector3:
	return point(lerpf(START_T, END_T, float(index)/float(GATES-1)))

static func direction(index: int) -> Vector3:
	var t := lerpf(START_T, END_T, float(index)/float(GATES-1))
	return (point(t+.001)-point(t-.001)).normalized()

static func crossing(before: Vector3, after: Vector3, index: int) -> float:
	var center := gate(index)
	var forward := direction(index)
	var a := (before-center).dot(forward)
	var b := (after-center).dot(forward)
	if a > 0.0 or b <= 0.0 or b <= a: return -1.0
	var weight := -a/(b-a)
	var intersection := before.lerp(after, weight)-center
	if absf(intersection.dot(forward.cross(Vector3.UP)))>HALF_WIDTH: return -1.0
	if absf(intersection.y)>3.0: return -1.0
	return weight

static func distance_to_course(point_value: Vector3) -> float:
	var p := Vector2(point_value.x,point_value.z)
	var best := INF
	for i in GATES-1:
		var a := gate(i)
		var b := gate(i+1)
		best=minf(best,p.distance_to(Geometry2D.get_closest_point_to_segment(p,Vector2(a.x,a.z),Vector2(b.x,b.z))))
	return best
