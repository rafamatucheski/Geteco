extends SceneTree

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func run() -> void:
	create_timer(40).timeout.connect(func(): quit(2))
	root.get_node("PresentationBudget").set_process(false)
	root.get_node("WantedManager").set_process(false)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	player.add_child(shape)
	world.add_child(player)
	player.set_physics_process(false)
	for id in ["sport_coupe", "towmaster", "bike_urban"]:
		var car = ModernTrafficFactory.spawn_parked_vehicle(world, "ExitNPC", Vector2.ZERO, 0.7, id, 0, Color.GRAY)
		car.ensure_presentation()
		car._detached_from_lane = false
		car.refresh_motorcycle_rider()
		player.global_position = car.to_global(Vector2(-8, 65))
		car.enter_vehicle(player)
		var driver: Node2D
		for child in world.get_children():
			if child is CarjackedDriver: driver = child
		check(driver != null and car.is_driven_by_player, id + " real driver exits on takeover")
		if driver == null:
			car.queue_free()
			continue
		var landing := driver.global_position
		var probe = load("res://cars/VehicleBoarding.gd").new()
		probe.car = car
		probe.actor = driver
		var anchor: Vector2
		var side := -1.0 if car.to_local(landing).y < 0 else 1.0
		if id == "bike_urban":
			anchor = probe._project_anchor(Vector3(side * 0.62, 0, 0.18))
		else:
			var hinge: Vector3 = car._side_doors[side].hinge.position
			anchor = probe._project_anchor(Vector3(hinge.x + side * 0.43, 0, car._side_doors[side].entry_center_z))
		check(landing.distance_to(car.to_global(anchor)) <= 24.01, id + " NPC lands beside actual door")
		probe.free()
		await create_timer(0.3).timeout
		check(driver.global_position.distance_to(landing) < 0.5, id + " NPC stays at landing during exit reaction")
		if id == "towmaster":
			car._boarding._finish()
			await process_frame
			var obstruction := StaticBody2D.new()
			var solid := CollisionShape2D.new()
			solid.shape = RectangleShape2D.new()
			solid.shape.size = Vector2(400, 400)
			obstruction.add_child(solid)
			world.add_child(obstruction)
			await physics_frame
			await process_frame
			car.exit_vehicle()
			check(car.is_driven_by_player and not player.visible and not player.is_physics_processing(), "blocked doors keep actor safely seated")
			check(not car.has_meta("vehicle_boarding"), "blocked exit releases transition state")
			obstruction.queue_free()
			await physics_frame
			await process_frame
			car.exit_vehicle()
			check(car.has_meta("vehicle_boarding") and car._boarding.active, "exit retries when door becomes free")
		car.force_exit_vehicle()
		player.set_physics_process(false)
		driver.queue_free()
		car.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	await process_frame
	print("NPC EXIT: ", failures.size(), " failures ", failures)
	quit(0 if failures.is_empty() else 1)
