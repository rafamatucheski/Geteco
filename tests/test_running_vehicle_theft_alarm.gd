extends SceneTree

var failures: Array[String] = []
var player: CharacterBody2D

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func leave(car: Node) -> void:
	while car.has_meta("vehicle_boarding"): await process_frame
	car.exit_vehicle()
	while car.has_meta("vehicle_boarding"): await process_frame
	player.set_physics_process(false)

func run() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("PresentationBudget").set_process(false)
	root.get_node("WantedManager").set_process(false)
	player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	# Taking a running vehicle never arms an alarm on the next boarding either.
	for archetype in ["sedan_classic", "bike_sport", "bike_cruiser", "bike_urban"]:
		var lane := Path2D.new()
		lane.curve = Curve2D.new()
		lane.curve.add_point(Vector2(4000, 1500))
		lane.curve.add_point(Vector2(6500, 1500))
		world.add_child(lane)
		var moving = ModernTrafficFactory.spawn_moving_vehicle(lane, "MovingTheft", archetype, 0.4, 90, 0)
		moving.has_theft_alarm = true
		moving.set_physics_process(false)
		player.global_position = moving.global_position + Vector2(0,30)
		moving.enter_vehicle(player)
		check(moving.is_driven_by_player and not moving.is_alarm_active, archetype + " running theft is silent")
		await leave(moving)
		player.global_position = moving.global_position + Vector2(0,30)
		moving.enter_vehicle(player)
		check(moving.is_driven_by_player and not moving.is_alarm_active, archetype + " reentry after running theft is silent")
		await leave(moving)
		moving.queue_free()
		lane.queue_free()
	print("RUNNING_THEFT failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
