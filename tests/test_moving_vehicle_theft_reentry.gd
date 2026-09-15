extends "res://tests/test_police_car_alarm_theft.gd"

func run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("PresentationBudget").set_process(false)
	player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	var theft_lane_y := 5000.0
	for archetype in ["sedan_classic", "bike_urban", "bike_sport", "bike_cruiser"]:
		theft_lane_y += 1000.0
		var lane := ModernTrafficFactory.create_lane(world, "TheftLane", PackedVector2Array([Vector2(5000, theft_lane_y), Vector2(7500, theft_lane_y)]))
		var moving = ModernTrafficFactory.spawn_moving_vehicle(lane, "MovingTheft", archetype, 0.4, 90, 0)
		moving.ensure_presentation()
		moving.set_physics_process(false)
		moving.has_theft_alarm = true
		player.global_position = moving.global_position + Vector2(0, 30)
		moving.enter_vehicle(player)
		check(moving.is_driven_by_player and not moving.is_alarm_active, archetype + " carjacking is silent")
		await leave(moving)
		player.global_position = moving.global_position + Vector2(0, 30)
		moving.enter_vehicle(player)
		check(moving.is_driven_by_player and not moving.is_alarm_active, archetype + " keys from driver keep re-entry silent")
		await leave(moving)
		moving.queue_free()
		lane.queue_free()
		await process_frame
	print("MOVING_THEFT failures=", failures)
	quit(0 if failures.is_empty() else 1)
