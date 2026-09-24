extends SceneTree

var failures := 0
var output := "D:/geteco/game/_codex_diag/theft-sequence"

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	seed(20092026)
	root.size = Vector2i(960, 640)
	root.content_scale_size = root.size
	root.get_node("PresentationBudget").set_process(false)
	root.get_node("WantedManager").set_process(false)
	var render := DisplayServer.get_name() != "headless"
	if render: DirAccess.make_dir_recursive_absolute(output)
	var colors := {}
	for i in 18:
		var model = preload("res://prototypes/living_cast/CivilianDriverModel.gd").new()
		root.add_child(model)
		colors[model.coat_color] = true
		model.queue_free()
	check(colors.size() >= 6, "Civilian occupants have varied clothing")
	for scenario in ["sport_coupe", "bike_urban", "fallen_bike", "parked_car", "cancel"]:
		var world := Node2D.new()
		root.add_child(world)
		current_scene = world
		var ground := Polygon2D.new()
		ground.polygon = PackedVector2Array([Vector2(-1000,-1000), Vector2(1000,-1000), Vector2(1000,1000), Vector2(-1000,1000)])
		ground.color = Color("77827b")
		world.add_child(ground)
		var actor = load("res://characters/Player.gd").new()
		var camera := Camera2D.new()
		camera.name = "Camera"
		actor.add_child(camera)
		var collider := CollisionShape2D.new()
		collider.shape = CircleShape2D.new()
		collider.shape.radius = 8.0
		actor.add_child(collider)
		world.add_child(actor)
		actor.set_physics_process(false)
		var car = load("res://cars/traffic/TrafficVehicle.tscn").instantiate()
		world.add_child(car)
		car.apply_archetype("bike_urban" if "bike" in scenario else "sport_coupe", Color("af4734"))
		car.ensure_presentation()
		car.rotation = -0.45
		if scenario in ["fallen_bike", "parked_car"]: car.configure_as_parked()
		if scenario == "fallen_bike":
			car._rider_fallen = true
			car.body_model.set_meta("fallen_motorcycle", true)
			car.body_model.rotation.z = 1.25
		actor.position = car.to_global(Vector2(-8,-48))
		await physics_frame
		car.enter_vehicle(actor)
		check(is_instance_valid(car._boarding), scenario + " starts boarding")
		var boarding: Node = car._boarding
		boarding.motion.pause()
		var sequence: Node = boarding.theft_sequence
		if scenario == "parked_car":
			check(sequence == null, "Empty parked car invents no occupant")
			boarding._finish()
		else:
			check(is_instance_valid(sequence), scenario + " has preparation stage")
			var victim: Node = sequence.victim
			if victim != null:
				check(not victim.visible and not victim.is_physics_processing(), "Victim is not spawned visibly on pavement")
				check(victim.driver_model.get_parent() == car.body_model, "Occupant shares cabin depth")
			var review := Camera2D.new()
			review.zoom = Vector2.ONE * 5.0
			world.add_child(review)
			car.camera.enabled = false
			review.make_current()
			var start: Vector2 = car.global_position
			for t in [0.15, 0.45, 0.72, 0.95]:
				sequence.progress = t
				boarding._process(0)
				check(actor.is_control_disabled and car.has_meta("vehicle_boarding"), "Cannot drive or attack during extraction/lift")
				check(actor.left_upper_arm.transform.is_finite() and actor.left_lower_leg.transform.is_finite(), "Finite articulated pose")
				if render:
					await process_frame
					await RenderingServer.frame_post_draw
					check(root.get_texture().get_image().save_png(output.path_join("%s_%02d.png" % [scenario, roundi(t*100)])) == OK, "Capture saved")
			check(car.global_position.distance_to(start) < 0.1, "Vehicle remains still")
			if scenario == "cancel":
				car.force_exit_vehicle()
				check(not actor.is_control_disabled and not car.has_meta("vehicle_boarding"), "Cancellation releases controls")
			else:
				sequence.finish()
				if victim != null:
					check(victim.visible and victim.driver_model.get_parent() == victim.driver_viewport, "Same occupant becomes a walking pedestrian")
					check(victim.global_position.distance_to(sequence.landing) < 0.1 and victim.collision_layer == 4, "Victim lands at checked physical exit")
				if "bike" in scenario: check(absf(car.body_model.rotation.z) < 0.01, "Motorcycle is raised before mounting")
				boarding.progress = 0.65
				boarding._process(0)
				boarding._finish()
				check(not actor.visible and not actor.is_control_disabled, "Boarding completes")
				await process_frame
				car.exit_vehicle()
				car._boarding.motion.pause()
				car._boarding._finish_exit()
				var exit_position: Vector2 = actor.global_position
				await physics_frame
				await physics_frame
				await process_frame
				check(actor.global_position.distance_to(exit_position) < 0.5, scenario + " idle exit remains physically stable")
		world.queue_free()
		await process_frame
		await process_frame
	print("VEHICLE_THEFT_SEQUENCE failures=%d" % failures)
	quit(1 if failures else 0)
