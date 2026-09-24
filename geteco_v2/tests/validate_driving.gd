extends SceneTree
var world
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func wait_body_transition(limit := 240) -> void:
	for i in limit:
		if not world.driving.is_body_transition_active(): return
		await physics_frame
	check(false,"Vehicle body transition timed out")

func run() -> void:
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	await frames(10)
	var driving = world.driving
	var car = driving.car
	check(world.traffic.cars.size() == 6,"Six traffic cars must be present")
	check(car.wheels.size() == 4,"Original wheels must rotate about four authored centers")
	check(not driving.interact(),"Cannot enter a distant car")
	world.player.teleport(car.to_global(Vector3(-1.65,0.04,0.15)))
	await frames(2)
	check(driving.interact(),"Can enter next to a door")
	await wait_body_transition()
	check(driving.occupied and not world.player.visible and world.player.collision_layer == 0,"Driver must leave exterior collision and presentation")
	check(world.camera.target == car,"Camera must follow occupied vehicle")
	var accelerator := InputEventKey.new()
	accelerator.physical_keycode = KEY_W
	accelerator.pressed = true
	Input.parse_input_event(accelerator)
	var origin: Vector3 = car.position
	await frames(75)
	check(car.position.distance_to(origin) > 2,"Throttle must move vehicle")
	check(car.speed > 3,"Vehicle must accelerate")
	check(not driving.leave(),"Cannot exit a moving vehicle")
	accelerator.pressed = false
	Input.parse_input_event(accelerator)
	var brake := InputEventKey.new()
	brake.physical_keycode = KEY_SPACE
	brake.pressed = true
	Input.parse_input_event(brake)
	await frames(90)
	brake.pressed = false
	Input.parse_input_event(brake)
	check(absf(car.speed) < 0.01,"Brake must stop vehicle")
	check(driving.leave(),"Can exit stopped vehicle")
	await wait_body_transition()
	check(world.player.visible and world.player.collision_mask == 7 and world.camera.target == world.player,"Exit restores walking, collisions and camera")
	# Place car in an isolated test area, then block one / both door sides.
	car.place(Vector3(18,0.04,37),PI/2)
	world.player.teleport(car.to_global(Vector3(-1.65,0.04,0.15)))
	await frames(2)
	check(driving.interact(),"Can re-enter a rotated vehicle")
	await wait_body_transition()
	var walls: Array[Node] = []
	for side in [-1,1]:
		var wall = world.street.collider(car.to_global(Vector3(side*1.7,0.9,0)),Vector3(5,1.8,0.5),"ExitTestWall")
		walls.append(wall)
		await frames(2)
		if side == -1:
			var exit: Vector3 = driving.exit_position()
			check(exit.is_finite(),"One blocked door must allow the opposite door")
			check(car.to_local(exit).x > 0,"Exit must choose the clear door")
	check(not driving.leave(),"Both blocked doors must refuse exit")
	check(driving.occupied,"Failed exit must retain driver")
	for wall in walls:
		world.street.solids.erase(wall)
		wall.queue_free()
	await frames(2)
	check(driving.leave(),"Exit works once obstruction is removed")
	await wait_body_transition()
	# Sweep at full speed into a solid. Body cannot tunnel or climb.
	car.place(Vector3(-10,0.04,8),0)
	world.player.teleport(Vector3(-11.65,0.04,8))
	await frames(2)
	check(driving.interact(),"Can enter for collision test")
	await wait_body_transition()
	car.external_input = true
	car.throttle_input = 1
	car.brake_input = false
	car.speed = 15
	await frames(100)
	check(car.position.z >= 4.9,"Fast vehicle must not tunnel through crate")
	check(absf(car.position.y) < 0.1,"Vehicle must not climb solid objects")
	car.throttle_input = 0
	car.brake_input = true
	await frames(60)
	check(driving.leave(),"Driver can leave after collision")
	await wait_body_transition()
	car.place(Vector3(-4.25,0.04,9),0)
	world.player.teleport(Vector3(-8.3,0.04,3))
	# Traffic uses real route progress and physical motion, with no teleport wrap.
	var traffic_before: Array[float] = []
	for vehicle in world.traffic.cars: traffic_before.append(vehicle.distance_travelled)
	await frames(4800)
	for i in world.traffic.cars.size():
		var vehicle = world.traffic.cars[i]
		print("TRAFFIC ",i," travelled=",vehicle.distance_travelled-traffic_before[i]," laps=",vehicle.route_laps," position=",vehicle.position," blocked=",vehicle.blocked)
		check(vehicle.distance_travelled-traffic_before[i] > 300,"Traffic must keep circulating for 80 seconds")
		check(vehicle.route_laps >= 1,"Traffic must complete a loop")
	# A real NPC ahead must be sensed and the traffic vehicle must yield.
	var lead = world.traffic.cars[0]
	lead.place(Vector3(-1.8,0.04,-15),PI)
	lead.speed = 5.5
	var resident = world.people[0]
	resident.set_physics_process(false)
	resident.teleport(Vector3(-1.8,0.04,-9))
	await frames(2)
	check(lead.obstacle_ahead(),"Traffic must detect a pedestrian ahead")
	await frames(100)
	check(lead.position.z < -11.3,"Traffic must stop before pedestrian")
	check(absf(lead.speed) < 0.1,"Yielding vehicle must brake to rest")
	resident.teleport(Vector3(-8.2,0.04,-8.2))
	resident.set_physics_process(true)
	await frames(120)
	check(lead.speed > 1,"Traffic resumes after obstruction clears")
	# Activity requires the occupied vehicle, ordered checkpoints and a full stop.
	world.player.teleport(car.to_global(Vector3(-1.65,0.04,0.15)))
	await frames(2)
	check(driving.interact(),"Can enter for route activity")
	await wait_body_transition()
	world.activity.stage = 0
	world.activity.completed = false
	world.activity.dwell = 0
	for index in world.activity.points.size():
		car.place(world.activity.points[index]+Vector3.UP*0.04,0)
		car.external_input = true
		car.brake_input = true
		await frames(65)
		check(world.activity.stage == index+1,"Activity must advance one ordered stop")
	check(world.activity.completed,"All stops complete the route")
	world._toggle_pause()
	var paused_position: Vector3 = car.position
	for i in 5: await process_frame
	check(car.position.is_equal_approx(paused_position),"Pause must freeze vehicle simulation")
	check(not driving.interact(),"Cannot interact through pause menu")
	world._toggle_pause()
	var report := {"checks":checks,"failures":failures}
	var file := FileAccess.open("res://evidence/driving-functional.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("DRIVING_VALIDATION ",JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
