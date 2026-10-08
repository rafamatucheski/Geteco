extends "res://tests/test_armored_guard_service_path.gd"
const TRANSPORT := preload("res://gameplay/armored/ArmoredTransport.gd")
const DRIVER := preload("res://gameplay/armored/ArmoredTrafficDriver.gd")
const VEHICLE := preload("res://gameplay/dispatch/DispatchVehicle.gd")
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
func run() -> void:
	var world := World.new()
	root.add_child(world)
	current_scene = world
	world.player = Node3D.new()
	world.add_child(world.player)
	world.player.position = Vector3(40,0,40)
	world.gameplay.player = world.player
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120,.2,120)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -.1
	world.add_child(floor_body)
	var route := Curve3D.new()
	route.add_point(Vector3(0,0,30))
	route.add_point(Vector3(0,0,-80))
	route.set_meta("traffic_open",true)
	var key := JUNCTIONS.key_of(Vector3.ZERO)
	JUNCTIONS.junctions[key] = Vector3.ZERO
	JUNCTIONS.axes[key] = Vector2.RIGHT
	var truck = preload("res://gameplay/armored/ArmoredTruck.gd").new()
	truck.position = Vector3(0,.04,-12)
	world.add_child(truck)
	truck.set_physics_process(false)
	var civil = VEHICLE.new()
	civil.archetype = "sedan_classic"
	civil.position = Vector3(0,.04,-4.8)
	civil.route = route
	civil.traffic = true
	world.add_child(civil)
	civil.set_physics_process(false)
	var crossing = VEHICLE.new()
	crossing.position = Vector3(-12,.04,0)
	world.add_child(crossing)
	crossing.set_physics_process(false)
	for frame in 3: await physics_frame
	var driver := DRIVER.new()
	driver.setup(truck,5.5,4)
	driver.disable_overtaking()
	driver.set_route(route)
	truck.set_physics_process(true)
	civil.set_physics_process(true)
	# Reproduce the old policy: own hull is outside the intersection, so it holds.
	for frame in 90:
		await physics_frame
		driver.holding = true
		driver.tick(1.0/60.0)
	truck._junction_list = JUNCTIONS.along(route)
	check(not JUNCTIONS.occupies(key,truck.get_instance_id()),"waiting truck itself is already outside the junction footprint")
	check(civil.blocked and civil.blocker == truck and JUNCTIONS.occupies(key,civil.get_instance_id()),"truck formation hold physically traps the following civilian inside the junction")
	check(not JUNCTIONS.request(key,crossing.get_instance_id(),Vector3.RIGHT,0,0),"civilian lease correctly denies the crossing escort while the exit is blocked")
	var event = TRANSPORT.new()
	check(event._occupies_crossing(truck),"convoy exit protection includes the following hull and its stop gap")
	var released := false
	for frame in 600:
		await physics_frame
		driver.holding = not event._occupies_crossing(truck)
		driver.tick(1.0/60.0)
		if not JUNCTIONS.occupies(key,civil.get_instance_id()) and JUNCTIONS.request(key,crossing.get_instance_id(),Vector3.RIGHT,0,0):
			released = true
			break
	check(truck.global_position.z < -17 and civil.global_position.z < -9,"normal vehicle physics advances both hulls beyond the exit without teleportation")
	check(released,"civilian releases its own reservation and the crossing escort is admitted normally")
	for frame in 90:
		await physics_frame
		driver.holding = not event._occupies_crossing(truck)
		driver.tick(1.0/60.0)
	check(not event._occupies_crossing(truck) and absf(truck.speed) < .2,"convoy resumes formation waiting after leaving adequate exit space")
	JUNCTIONS._approaches[key] = [{"width":40.0}]
	check(event._occupies_crossing(truck),"authored wide junction footprint expands the protected exit space")
	JUNCTIONS.junctions[key] = Vector3(0,-8,0)
	check(not event._occupies_crossing(truck),"a junction on a separate lower road cannot hold this route")
	event.free()
	world.free()
	print("ARMORED_JUNCTION_EXIT_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
