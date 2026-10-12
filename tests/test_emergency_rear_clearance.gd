extends SceneTree
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	KIT.add_wall(scene,Vector3(0,-.5,0),Vector3(100,1,200))
	var graph := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	graph.configure([{"id":"road","width":12.0,"points":PackedVector3Array([Vector3(0,0,90),Vector3(0,0,-90)])}])
	var truck := preload("res://gameplay/dispatch/DispatchVehicle.gd").new()
	truck.archetype="rescue_pumper"
	truck.position=Vector3(3,.08,0)
	scene.add_child(truck)
	truck.set_meta("dispatch_unit",true)
	truck.set_meta("dispatch_needs_room",true)
	var follower := VEHICLE.new()
	follower.archetype="union_sedan"
	follower.position=Vector3(3,.08,truck.half_length+follower.half_length+1)
	scene.add_child(follower)
	follower.position.z=truck.half_length+follower.half_length+1
	follower.route=graph.route_near(follower.position,0,Vector3.FORWARD)
	follower.route_distance=follower.route.get_closest_offset(follower.position)
	follower.traffic=true
	var driver := preload("res://gameplay/dispatch/DispatchDriver.gd").new()
	driver.setup(truck,8,2)
	var coordinator := preload("res://gameplay/traffic_yield/TrafficYieldController.gd").new()
	coordinator.configure(scene,graph,func():return [follower],func():return [truck])
	scene.add_child(coordinator)
	await physics_frame
	await physics_frame
	check(not driver._rear_clear(),"rear queue initially blocks truck reverse")
	var initial: Vector3=follower.position
	var cleared := false
	for frame in 900:
		await physics_frame
		if driver._rear_clear(): cleared=true; break
	check(cleared,"stationary dispatch opens a rear corridor")
	check(follower.position.distance_to(initial)>.5,"civilian physically moves to release truck")
	var rear := KIT.add_wall(scene,follower.position+follower.global_basis.z*(follower.half_length+1),Vector3(4,2,1))
	await physics_frame
	await physics_frame
	check(not follower.traffic_rear_clear(),"civilian refuses reverse into an occupied rear space")
	rear.free()
	coordinator.release_all("test_end")
	driver.discard_overtaking("test_end")
	scene.free()
	await physics_frame
	print("EMERGENCY_REAR_CLEARANCE failures=",failures)
	quit(0 if failures.is_empty() else 1)
