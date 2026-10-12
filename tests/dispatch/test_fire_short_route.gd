extends SceneTree
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	KIT.add_wall(scene,Vector3(0,-.5,0),Vector3(100,1,200))
	var roads := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	roads.configure([{"id":"road","width":12.0,"points":PackedVector3Array([Vector3(0,0,90),Vector3(0,0,-90)])}])
	var truck := preload("res://gameplay/dispatch/DispatchVehicle.gd").new()
	truck.archetype="rescue_pumper"
	truck.position=Vector3(3,.08,0)
	scene.add_child(truck)
	truck.ensure_equipment(scene)
	truck.equipment.siren_on=true
	var blocked := []
	for z in [-24.0,-31.0]:
		var car := preload("res://scripts/Vehicle.gd").new()
		car.position=Vector3(3,.08,z)
		scene.add_child(car)
		car.traffic=true
		car.set_physics_process(false)
		blocked.append(car)
	var driver := preload("res://gameplay/dispatch/DispatchDriver.gd").new()
	driver.setup(truck,10.0,2.0)
	driver.enable_overtaking(roads)
	var route := Curve3D.new()
	route.add_point(Vector3(3,0,0))
	route.add_point(Vector3(3,0,-45))
	route.set_meta("traffic_open",true)
	driver.set_route(route)
	var waited := false
	var health: float=truck.health
	for frame in 480:
		driver.tick(1.0/60)
		waited=waited or driver.overtake.last_reason=="route_ends"
		await physics_frame
	check(waited,"short trip cannot fit full overtake")
	check(truck.position.z<-8,"truck keeps approaching safely instead of freezing remotely")
	check(truck.position.z>-20,"truck remains behind occupied space")
	check(is_equal_approx(truck.health,health),"approach preserves collision safety")
	driver.discard_overtaking("test_end")
	driver.disable_overtaking()
	scene.free()
	await physics_frame
	print("FIRE_SHORT_ROUTE failures=",failures)
	quit(0 if failures.is_empty() else 1)
