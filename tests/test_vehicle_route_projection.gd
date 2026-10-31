extends SceneTree
## Equivalência real da projeção em Curve3D depois de movimento, reatribuição e edições.
const VEHICLE := preload("res://scripts/Vehicle.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func matches(car, point: Vector3, label: String) -> float:
	var expected: float = car.route.get_closest_offset(point)
	var actual: float = car._traffic_route_offset(point)
	check(actual == expected, label)
	return actual

func run() -> void:
	var car := VEHICLE.new()
	var first := Curve3D.new()
	first.bake_interval = .25
	first.add_point(Vector3.ZERO)
	first.add_point(Vector3(10,0,0))
	first.add_point(Vector3(20,0,5))
	car.route = first
	var point := Vector3(2,0,0)
	var initial := matches(car,point,"Initial projection matches native API exactly")
	for i in 3: matches(car,point,"Unmoved vehicle preserves projection %d" % i)
	point.x += .000001
	var tiny_move := matches(car,point,"Movement below approximate-equality tolerance recomputes projection")
	check(tiny_move != initial,"Tiny movement is observable by the native projection")
	point = Vector3(17,0,3)
	matches(car,point,"Teleport recomputes projection")
	car.route_distance = 123456.0
	matches(car,point,"External route_distance write cannot contaminate projection")
	var second := Curve3D.new()
	second.add_point(Vector3(20,0,5))
	second.add_point(Vector3.ZERO)
	car.route = second
	matches(car,point,"New route at identical position recomputes projection")
	check(not first.changed.is_connected(car._invalidate_route_projection),"Old route releases its invalidation subscription")
	car.route = first
	matches(car,point,"Returning to previous route recomputes projection")
	first.set_point_position(1,Vector3(5,0,-5))
	matches(car,point,"In-place point edit invalidates projection")
	first.set_point_out(0,Vector3(3,0,8))
	first.set_point_in(1,Vector3(-2,0,5))
	matches(car,point,"In-place tangent edits invalidate projection")
	first.bake_interval = 2.0
	matches(car,point,"Bake interval change invalidates projection")
	first.add_point(Vector3(17,0,3))
	matches(car,point,"Adding a point invalidates projection")
	first.remove_point(first.point_count-1)
	matches(car,point,"Removing a point invalidates projection")
	car.route = null
	car.speed = 3.0
	car._drive_traffic(1.0/60.0)
	check(car.speed == 3.0 and car.route_distance == 123456.0,"Null route keeps the original drive early return")
	car.route = first
	matches(car,point,"Restoring route after null resumes exact projection")
	car.free()
	check(first.changed.get_connections().is_empty(),"Vehicle destruction releases curve subscriptions")
	print("VEHICLE_ROUTE_PROJECTION checks=%d failures=%s" % [checks,failures])
	quit(0 if failures.is_empty() else 1)
