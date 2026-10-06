extends RefCounted
## One metre-space contract for the remote quarry, dirt access and activities.
## A 28 m excavation and a 14 m haul spiral share one sampled XYZ centreline.
const CENTER := Vector3(-180,0,-1760)
const BOUNDS := Rect2(-326,-1910,300,310)
const PIT_CENTER := Vector2(0,-18)
const PIT_DEPTH := 28.0
const HAUL_WIDTH := 14.0
const GATE := CENTER+Vector3(0,0,130)
const SECRET_EXTERIOR := CENTER+Vector3(-26,-28,-13)
const SECRET_ENTRY := SECRET_EXTERIOR+Vector3(0,0,3.7)
const SECRET_RETURN := SECRET_EXTERIOR+Vector3(0,0,6.5)
const SECRET_RESERVE := Rect2(-34,-20,16,22)
const MACHINE_BAYS := []
const ACCESS := [Vector2(-180,-1540),Vector2(-180,-1574),Vector2(-167,-1598),Vector2(-167,-1611),Vector2(-180,-1630)]
const ACCESS_WIDTH := 10.5
static var _haul_points := PackedVector3Array()
static var _haul_buckets: Dictionary={}
const ROAD_BUCKET := 24.0

static func enabled() -> bool:
	return not (OS.is_debug_build() and Engine.get_meta("mining_benchmark_disabled",false))

static func roads() -> Array[Dictionary]:
	if not enabled(): return []
	var points := PackedVector3Array()
	for p in ACCESS: points.append(Vector3(p.x,0,p.y))
	return [{"id":"mining_access","region":"desert","surface":"dirt","width":ACCESS_WIDTH,"traffic":false,"one_way":false,"points":points},
		{"id":"mining_haul_road","region":"desert","surface":"dirt","width":HAUL_WIDTH,"traffic":false,"one_way":false,"points":haul_points()}]

static func haul_points() -> PackedVector3Array:
	if not _haul_points.is_empty(): return _haul_points
	var approach := preload("res://world/desert/DesertLayout.gd")._rounded([Vector2(0,130),Vector2(-22,123),Vector2(-75,111),Vector2(-116,69),Vector2(-123,29),Vector2(-113,3),Vector2(-105,-18)],18.0)
	for point in approach:
		var next := CENTER+Vector3(point.x,0,point.y)
		# The generic corner smoother can emit centimetre-long spans where two
		# headings nearly agree. Such 14 m wide slivers are dropped by collision
		# meshing; keep a clean continuous centreline before producing the strip.
		if not _haul_points.is_empty() and _haul_points[-1].distance_to(next)<.35: continue
		_haul_points.append(next)
	for i in range(1,161):
		var t := float(i)/160.0
		var angle := PI+TAU*1.25*t
		var radius := lerpf(105,27,t)
		# Zero grade at both landings: a loaded 8 m truck must not straddle an
		# abrupt 12% ramp-to-flat kink at the excavation floor.
		var descent := t*t*(3.0-2.0*t)
		_haul_points.append(CENTER+Vector3(cos(angle)*radius,-PIT_DEPTH*descent,PIT_CENTER.y+sin(angle)*radius))
	_haul_points.append(CENTER+Vector3(8,-PIT_DEPTH,-44))
	return _haul_points

static func _prepare_haul_buckets() -> void:
	if not _haul_buckets.is_empty(): return
	var points := haul_points()
	for i in range(1,points.size()):
		var a: Vector3=points[i-1]-CENTER
		var b: Vector3=points[i]-CENTER
		var planar_a := Vector2(a.x,a.z)
		var planar_b := Vector2(b.x,b.z)
		var rect := Rect2(planar_a,Vector2.ZERO).expand(planar_b).grow(14.0)
		var record := {"a":planar_a,"b":planar_b,"ay":a.y,"by":b.y}
		for z in range(floori(rect.position.y/ROAD_BUCKET),floori(rect.end.y/ROAD_BUCKET)+1):
			for x in range(floori(rect.position.x/ROAD_BUCKET),floori(rect.end.x/ROAD_BUCKET)+1):
				var key := Vector2i(x,z)
				if not _haul_buckets.has(key): _haul_buckets[key]=[]
				_haul_buckets[key].append(record)

static func haul_sample(local: Vector2) -> Vector2:
	_prepare_haul_buckets()
	var key := Vector2i(floori(local.x/ROAD_BUCKET),floori(local.y/ROAD_BUCKET))
	var best := Vector2(INF,0)
	for row in _haul_buckets.get(key,[]):
		var a: Vector2=row.a
		var b: Vector2=row.b
		var t := clampf((local-a).dot(b-a)/maxf((b-a).length_squared(),.0001),0,1)
		var distance := local.distance_to(a.lerp(b,t))
		if distance<best.x: best=Vector2(distance,lerpf(float(row.ay),float(row.by),t))
	return best

static func terrain_height(local: Vector2) -> float:
	var radius := (local-PIT_CENTER).length()
	var rings := [Vector2(0,-28),Vector2(34,-28),Vector2(43,-21),Vector2(57,-21),Vector2(65,-14),Vector2(80,-14),Vector2(88,-7),Vector2(101,-7),Vector2(110,0),Vector2(170,0)]
	var height := 0.0
	for i in range(1,rings.size()):
		if radius<=rings[i].x:
			height=lerpf(rings[i-1].y,rings[i].y,inverse_lerp(rings[i-1].x,rings[i].x,radius))
			break
	var road := haul_sample(local)
	if road.x<12.0: height=lerpf(road.y,height,smoothstep(HAUL_WIDTH*.5,12.0,road.x))
	return height

static func machine_spawns() -> Array[Dictionary]:
	return [
		{"id":"mineradora_backhoe","archetype":"mining_backhoe","point":world(Vector3(24,-28,-20)),"yaw":.35},
		{"id":"mineradora_tractor","archetype":"mining_tractor","point":world(Vector3(-11,-28,5)),"yaw":0.0},
		{"id":"mineradora_haul","archetype":"mining_haul_truck","point":world(Vector3(-100,0,55)),"yaw":.12},
		{"id":"mineradora_haul_pit","archetype":"mining_haul_truck","point":world(Vector3(6,-28,6)),"yaw":PI*.5},
	]

static func cargo_spawns() -> Array[Vector3]:
	var result: Array[Vector3]=[]
	for p in [Vector3(-13,-28,-3),Vector3(-10.5,-28,-3),Vector3(-8,-28,-3),Vector3(-5,-28,-14),Vector3(-2,-28,-14),Vector3(-5,-28,-11),Vector3(-2,-28,-11)]: result.append(world(p))
	return result

static func reservation_clear(point: Vector2, radius := 0.0) -> bool:
	if not enabled(): return true
	if BOUNDS.grow(radius+4).has_point(point): return false
	for i in range(1,ACCESS.size()):
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,ACCESS[i-1],ACCESS[i]))<ACCESS_WIDTH*.5+radius+4: return false
	return true

static func worker_stations() -> Array[Dictionary]:
	return [
		{"id":"sample_breaker","point":Vector3(-20,-28,0),"yaw":-.45,"job":0},
		{"id":"ore_sorter","point":Vector3(-1,-28,11),"yaw":PI*.5,"job":1},
		{"id":"crusher_fitter","point":Vector3(20,-28,-5),"yaw":-PI*.5,"job":3},
		{"id":"shift_surveyor","point":Vector3(18,0,110),"yaw":.1,"job":2},
		{"id":"service_mechanic","point":Vector3(59,0,77),"yaw":0.0,"job":3},
		{"id":"gate_controller","point":Vector3(10.8,0,122),"yaw":PI*.5,"job":2},
	]

static func light_stations() -> Array[Dictionary]:
	return [
		{"id":"pit_west","point":Vector3(-27,-28,-28),"height":10.0,"range":38.0,"energy":2.8},
		{"id":"pit_east","point":Vector3(28,-28,-4),"height":11.0,"range":39.0,"energy":2.8},
		{"id":"haul_rim","point":Vector3(-94,0,80),"height":10.0,"range":38.0,"energy":2.5},
		{"id":"service_yard","point":Vector3(24,0,110),"height":9.0,"range":35.0,"energy":2.5},
		{"id":"parking","point":Vector3(-43,0,108),"height":7.0,"range":27.0,"energy":2.0},
		{"id":"gate","point":Vector3(12,0,131),"height":4.5,"range":20.0,"energy":1.5},
	]

static func world(local: Vector3) -> Vector3: return CENTER+local
