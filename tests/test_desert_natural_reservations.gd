extends SceneTree
## Pure geometry regression: actual landforms stay protected, adjacent unused
## broad-phase space remains available to the unchanged authored salt works.
const LAND := preload("res://world/desert/expansion/DesertLandforms.gd")
const NORTH := preload("res://world/desert/north_pass/DesertNorthPassLayout.gd")
const ROADSIDE := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	print("NATURAL_RESERVATIONS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func _initialize() -> void:
	run.call_deferred()

func border_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	var result := INF
	for i in polygon.size():
		result = minf(result, point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i+1)%polygon.size()])))
	return result

func run() -> void:
	check(NORTH.enabled(), "production north-pass policy enabled")
	var polygon := LAND.wash_footprint()
	check(polygon.size() == 90, "both complete dry-wash banks retained")
	for i in 45:
		var t := float(i)/44.0
		check(not LAND.reservation_clear(LAND.wash_point(t)), "wash bed and curves protected " + str(i))
	for point in polygon:
		check(not LAND.reservation_clear(point), "every authored bank vertex protected " + str(point))
	var clear_samples := 0
	for i in range(4,40):
		var a := polygon[i]
		var b := polygon[i+1]
		var middle := (a+b)*.5
		var edge := (b-a).normalized()
		var outward := Vector2(-edge.y, edge.x)
		if Geometry2D.is_point_in_polygon(middle+outward*.1,polygon): outward = -outward
		check(not LAND.reservation_clear(middle+outward*1.25), "wash 1.5m shoulder protected " + str(i))
		check(not LAND.reservation_clear(middle+outward*2.25,1.0), "query radius extends wash shoulder " + str(i))
		var outside := middle+outward*3.25
		if not Geometry2D.is_point_in_polygon(outside,polygon) and border_distance(outside,polygon)>2.5:
			clear_samples += 1
			check(LAND.reservation_clear(outside,1.0), "ground outside real bank and shoulder available " + str(i))
	check(clear_samples>20, "meaningful bank exterior coverage")
	for road in NORTH.roads():
		for i in range(road.points.size()-1):
			var a: Vector3 = road.points[i]
			var b: Vector3 = road.points[i+1]
			for t in [0.0,.5,1.0]:
				var point := a.lerp(b,t)
				for x in [-11.5,0.0,11.5]:
					check(not NORTH.reservation_clear(Vector2(point.x+x,point.z)), "north road and shoulders protected " + str(point) + "/" + str(x))
	for worker in NORTH.workers():
		check(not NORTH.reservation_clear(Vector2(worker.position.x,worker.position.z),.4), "worker footprint protected")
	for z in [-1229.0,-1200.0,-1170.0,-1156.0,-1116.0,-1076.0]:
		for x in [308.1,329.9,355.1,376.9]:
			check(not NORTH.reservation_clear(Vector2(x,z)), "both complete cliff footprints protected")
	for x in [330.0,342.5,355.0]:
		check(not NORTH.reservation_clear(Vector2(x,NORTH.GATE.z)), "worksite gate and landslide protected")
	check(not NORTH.reservation_clear(Vector2(304.5,-1150)), "cliff 4m safety shoulder protected")
	check(not NORTH.reservation_clear(Vector2(303.0,-1150),2.0), "query radius extends cliff safety shoulder")
	check(NORTH.reservation_clear(Vector2(300.0,-1150),2.0), "unused ground beyond cliff shoulder available")
	var salt := ROADSIDE.site("salt_works")
	check(salt.center == Vector2(240,-960), "salt works retains its authored compact anchor")
	var sampled := 0
	var blocked_land: Array[Vector2] = []
	var blocked_north: Array[Vector2] = []
	# Keep all 104x76m of the original test footprint, with its original 2m grid.
	for x in range(-52,53,2):
		for z in range(-40,37,2):
			var at := ROADSIDE.at(salt,Vector3(x,0,z))
			var point := Vector2(at.x,at.z)
			sampled += 1
			if not LAND.reservation_clear(point,.5): blocked_land.append(point)
			if not NORTH.reservation_clear(point,.5): blocked_north.append(point)
	check(sampled == 2067, "unchanged full salt-works footprint sampled at 2067 points")
	check(blocked_land.is_empty(), "salt works clear of actual wash: " + str(blocked_land.slice(0,8)))
	check(blocked_north.is_empty(), "salt works clear of actual north road and cliffs: " + str(blocked_north.slice(0,8)))
	print("NATURAL_RESERVATIONS_DONE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
