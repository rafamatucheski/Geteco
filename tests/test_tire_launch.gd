extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func exercise(car: Node2D) -> void:
	car.set_physics_process(false)
	car.set_process(false)
	car.is_driven_by_player = true
	car._drive_input_armed = true
	if car.has_method("_ensure_engine_audio"): car._ensure_engine_audio()
	car.global_position = Vector2(0, 300)
	car.rotation = 0
	car.velocity = Vector2.ZERO
	var start := car.global_position
	Input.action_press("move_up")
	Input.action_press("handbrake")
	for i in 100: car._physics_process(1.0 / 60.0)
	check(car.global_position.distance_to(start) < 0.1, car.name + " holds still while revving")
	check(car._engine_sound.rpm > 0.45, car.name + " audible free rev")
	Input.action_release("handbrake")
	for i in 25: car._physics_process(1.0 / 60.0)
	check(car.velocity.x > 50 and car.global_position.x > start.x + 5, car.name + " releases into forward launch")
	Input.action_release("move_up")
	car._physics_process(1.0 / 60.0)
	check(car._launch.release_remaining == 0, car.name + " throttle release cancels assistance")
	car.velocity = Vector2(120, 220)
	for i in 8:
		car.velocity = Vector2(120, 220)
		car._physics_process(1.0 / 60.0)
	var ink = current_scene.get_node_or_null("VehicleSkidMarks")
	check(ink != null and ink.marks.size() >= 2, car.name + " sideways tire contact leaves paired ground marks")
	car.velocity = Vector2.ZERO
	car._physics_process(1.0 / 60.0)
	var count: int = ink.marks.size()
	check(count > 0 and car._tire_trail.previous.is_empty(), "marks persist after drift with disconnected next stroke")
	if DisplayServer.get_name() != "headless":
		var camera = current_scene.get_node("ReviewCamera")
		camera.global_position = car.global_position - Vector2(30, 0)
		camera.make_current()
		for i in 8: await process_frame
		root.get_texture().get_image().save_png("D:/geteco/artifacts/tire-launch-0913/" + car.name + ".png")
	car.global_position += Vector2(10000, 0)
	car.velocity = Vector2(120, 220)
	for i in 8: car._physics_process(1.0 / 60.0)
	var valid := true
	for mark in ink.marks: valid = valid and mark.a.distance_to(mark.b) < 80.1
	check(valid, "teleport never draws a connecting stripe")
	car.repair_vehicle()
	check(car._tire_trail.previous.is_empty() and car._launch.charge == 0, "repair resets tire contact and launch")
	car.is_driven_by_player = false
	car.queue_free()

func run() -> void:
	root.get_node("GameInput").reset_bindings()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var road := Polygon2D.new()
	road.polygon = PackedVector2Array([Vector2(-1000,-1000),Vector2(15000,-1000),Vector2(15000,1000),Vector2(-1000,1000)])
	road.color = Color("50545a")
	road.z_index = -1
	world.add_child(road)
	var camera := Camera2D.new()
	camera.name = "ReviewCamera"
	camera.zoom = Vector2(3,3)
	world.add_child(camera)
	var traffic = ModernTrafficFactory.spawn_parked_vehicle(world, "TrafficSport", Vector2.ZERO, 0, "sport_coupe", 0, Color.RED)
	await physics_frame
	await exercise(traffic)
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	var personal = scene.get_node("PlayerCar")
	scene.remove_child(personal)
	scene.free()
	personal.name = "PersonalCoupe"
	world.add_child(personal)
	await physics_frame
	await exercise(personal)
	var slow = preload("res://cars/VehicleLaunchControl.gd").new()
	var fast = preload("res://cars/VehicleLaunchControl.gd").new()
	for launch in [slow, fast]:
		var top := 350.0 if launch == slow else 700.0
		launch.update(1.5, 0, 1, true, top, true)
		launch.update(0.016, 0, 1, false, top, true)
	check(fast.force_scale > slow.force_scale and fast.wheelspin > slow.wheelspin, "fast cars have stronger launch and visible slip")
	fast.update(0.016, 100, 1, true, 700, true)
	check(not fast.holding, "handbrake at speed remains a drift, not a stationary lock")
	fast.update(0.016, 0, 1, true, 700, false)
	check(not fast.holding and fast.charge == 0, "disabled vehicle cannot charge")
	var ink = world.get_node("VehicleSkidMarks")
	for i in 1300: ink.add_segment(Vector2(i, 0), Vector2(i+2, 0), 0.5)
	check(ink.marks.size() == ink.MAX_MARKS, "ground ink is bounded")
	ink._process(ink.LIFETIME + 0.1)
	check(ink.marks.is_empty(), "old marks expire")
	print("TIRE_LAUNCH_FAILURES ", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
