extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
		push_error(detail)

func _run() -> void:
	seed(907)
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 20:
		await physics_frame
	var player = world.get_node("Player")
	var cars: Array = get_nodes_in_group("modern_traffic").duplicate()
	var tested := 0
	var worst_step := 0.0
	for car in cars:
		if not is_instance_valid(car) or car.is_broken or car.is_in_group("harbor_transit_bus"):
			continue
		var before: Transform2D = car.global_transform
		var hp: int = car.health
		player.global_position = car.global_position + Vector2(0, 35)
		Input.action_press("interact")
		car.enter_vehicle(player)
		check(car.global_transform.is_equal_approx(before), "Entry preserves world transform: " + car.name)
		for frame in 5:
			await physics_frame
			worst_step = maxf(worst_step, before.origin.distance_to(car.global_position))
			check(car.is_driven_by_player, "Held entry key must not immediately eject: " + car.name)
		check(car.health == hp and not car.is_broken, "Entry must not damage car: " + car.name)
		check(before.origin.distance_to(car.global_position) < 20.0, "Stationary entry must not teleport: " + car.name)
		Input.action_release("interact")
		await physics_frame
		car.exit_vehicle()
		car._apply_crash_deformation(Vector2.LEFT, 450.0, car.global_position + Vector2(30, 0))
		check(car.dents_container == null or car.dents_container.get_child_count() == 0, "No protruding polygon dents")
		tested += 1
	check(tested >= 38, "Test a broad sample of real world cars")
	# Repeated real wall contacts during one scrape must not exhaust the car.
	var crash_car = load("res://world/shared/traffic/TrafficVehicle.tscn").instantiate()
	world.add_child(crash_car)
	crash_car.configure_as_parked()
	crash_car.global_position = Vector2(12000, 10000)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20, 200)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.global_position = crash_car.global_position + Vector2(60, 0)
	crash_car.enter_vehicle(player)
	crash_car._last_collision_damage_ms = -999999
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 450:
		crash_car.velocity = Vector2(500, 0)
		await physics_frame
	check(crash_car.health >= 70 and crash_car.health < 100, "Repeated wall contact applies one impact, not frame-by-frame fatal damage")
	check(not crash_car.is_broken, "Scraping a wall must not trigger immediate combustion")
	print("WALL_CONTACT health=%d" % crash_car.health)
	crash_car.exit_vehicle()
	print("CARJACK_CONTINUITY tested=%d max_stationary_displacement=%.3f failures=%d" % [tested, worst_step, failures])
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
