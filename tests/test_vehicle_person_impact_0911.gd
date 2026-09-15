extends SceneTree
const IMPACT = preload("res://guns/combat/VehiclePersonImpact.gd")
const FACTORY = preload("res://emergency/ModernTrafficFactory.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	root.get_node("NPCMedicalCare").set_process(false)
	root.get_node("PresentationBudget").set_process(false)
	for id in ["bike_urban", "bike_sport", "bike_cruiser", "sedan_classic", "route_city"]:
		var car = FACTORY.spawn_parked_vehicle(world, "ImpactVehicle", Vector2(300,300), 0, id, 0, Color.RED)
		car.set_process(false)
		car.set_physics_process(false)
		car.is_driven_by_player = true
		# Measure the same drivetrain without a person, including mass tuning.
		# Each preceding case ends in idle. move_and_slide uses that frame's
		# delta outside physics, so both measurements must start in physics.
		await physics_frame
		var start: Vector2 = car.position
		car.velocity = Vector2(160,0)
		for frame in 12:
			car._physics_process(1.0/60.0)
			await physics_frame
		var coasting_speed: float = car.velocity.x
		var coasting_distance: float = car.position.x - start.x
		car.position = start
		car.velocity = Vector2.ZERO
		var actor := AnimatedPedestrian3D.new()
		actor.archetype_override = 0
		world.add_child(actor)
		actor.position = car.position + Vector2(car.collision.shape.size.x * 0.5 + 16.0, 0)
		actor.set_physics_process(false)
		await physics_frame
		await physics_frame
		check(not IMPACT.hit(car, actor, Vector2(30,0)) and not actor.is_incapacitated, id + " walking contact does not injure")
		check(not IMPACT.hit(car, actor, Vector2(-160,0)) and not actor.is_incapacitated, id + " driving away does not injure")
		var before: Vector2 = car.position
		car.velocity = Vector2(160,0)
		for frame in 12:
			car._physics_process(1.0/60.0)
			await physics_frame
		check(actor.is_incapacitated and not actor.is_dead, id + " actual motion injures without killing")
		check(coasting_distance > 0 and absf(car.position.x - before.x - coasting_distance) < 1.0 and absf(car.velocity.x - coasting_speed) < 1.0, id + " keeps moving with only normal coasting friction")
		check(car._hit_stop_frames == 0 and get_nodes_in_group("crash_bursts").is_empty(), id + " no wall feedback")
		check(actor.has_meta("vehicle_feedback_ms") and car.bloody_tires_timer > 0, id + " blood and body sound triggered")
		var count := get_nodes_in_group("ground_blood").size()
		IMPACT.hit(car, actor, Vector2(300,0))
		check(get_nodes_in_group("ground_blood").size() == count, id + " contact not charged twice")
		# Keep a fallen person's collider enabled to exercise deferred/retained
		# collision shapes, independently of the actor's normal disable callback.
		car.position = start
		actor.position = start + Vector2(car.collision.shape.size.x * 0.5 + 10.0, 0)
		actor.get_node("CollisionShape2D").disabled = false
		await physics_frame
		await physics_frame
		for frame in 12:
			car.velocity = Vector2(160, 0)
			car._physics_process(1.0/60.0)
			await physics_frame
		check(car.position.x > start.x + 25.0, id + " fallen body with active collider does not block vehicle")
		car.queue_free()
		actor.queue_free()
		await process_frame
	var lethal := AnimatedPedestrian3D.new()
	world.add_child(lethal)
	lethal.position = Vector2(500,300)
	lethal.set_physics_process(false)
	lethal.get_run_over(Vector2(280,0))
	check(lethal.is_dead and lethal.health == 0, "fast impact remains lethal")
	var stain = get_nodes_in_group("ground_blood").back()
	for frame in 50:
		lethal._physics_process(1.0/60.0)
		stain._process(1.0/60.0)
	check(stain.global_position.distance_to(lethal.global_position + Vector2(0,3)) < 1.0, "death blood settles with landing body")
	var driver = preload("res://characters/CarjackedDriver.tscn").instantiate()
	world.add_child(driver)
	driver.set_physics_process(false)
	driver.get_run_over(Vector2(120,0))
	check(driver.is_incapacitated and not driver.is_dead and driver.health == 1, "former driver survives moderate impact")
	check(driver.has_meta("vehicle_feedback_ms"), "former driver gets body impact feedback")
	driver.queue_free()
	await process_frame
	# A solid wall still stops a vehicle with the new person sweep enabled.
	var car = FACTORY.spawn_parked_vehicle(world, "WallVehicle", Vector2(300,600), 0, "bike_urban", 0, Color.RED)
	car.set_process(false)
	car.set_physics_process(false)
	car.is_driven_by_player = true
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(10,100)
	wall.add_child(shape)
	world.add_child(wall)
	wall.position = Vector2(355,600)
	await physics_frame
	await physics_frame
	for frame in 24:
		car.velocity = Vector2(180,0)
		car._physics_process(1.0/60.0)
		await physics_frame
	check(car.position.x < 350, "solid wall is still impassable")
	check(not get_nodes_in_group("crash_bursts").is_empty(), "wall retains rigid collision feedback")
	print("VEHICLE_PERSON_IMPACT failures=", failures)
	world.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
