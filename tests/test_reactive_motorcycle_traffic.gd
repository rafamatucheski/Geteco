extends SceneTree
const FACTORY = preload("res://emergency/ModernTrafficFactory.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("PresentationBudget").set_process(false)
	var path := Path2D.new()
	path.curve = Curve2D.new()
	path.curve.add_point(Vector2(0, 200))
	path.curve.add_point(Vector2(2000, 200))
	world.add_child(path)
	var bike = FACTORY.spawn_moving_vehicle(path,"CrashBike","bike_urban",.2,90,0)
	var original_follow := bike.get_parent() as PathFollow2D
	bike.set_process(false)
	bike.set_physics_process(false)
	bike.receive_vehicle_impact(30.0, Vector2.RIGHT)
	check(not bike._rider_fallen, "light touch does not knock rider down")
	bike.receive_vehicle_impact(400.0, Vector2.RIGHT)
	bike.receive_vehicle_impact(400.0, Vector2.RIGHT)
	await process_frame
	await process_frame
	check(bike._detached_from_lane and bike.get_parent() == world, "impact stops autonomous motorcycle")
	check(not bike.body_model.rider.visible, "mounted rider removed")
	check(not bike.has_theft_alarm, "Traffic impact does not arm a theft alarm on the fallen motorcycle")
	var fallen: CarjackedDriver
	var count := 0
	for child in world.get_children():
		if child is CarjackedDriver:
			fallen = child
			count += 1
	check(count == 1, "repeated contact creates only one fallen rider")
	if fallen:
		# This case specifically tests the remount reaction.
		fallen.motorcycle_reaction = 0
		fallen.set_physics_process(false)
		check(not fallen.is_dead and fallen.fall_presentation.airborne, "rider falls alive with launch arc")
		check(fallen.motorcycle_appearance_seed == int(bike.get_meta("driver_appearance_seed", -2)), "fallen rider keeps the mounted rider identity")
		check(fallen.motorcycle_jacket_color.is_equal_approx(bike.body_model.rider_jacket.albedo_color) and fallen.motorcycle_helmet_color.is_equal_approx(bike.body_model.rider_helmet.albedo_color), "fallen rider keeps the mounted jacket and helmet")
		var origin := fallen.global_position
		for i in 120:
			fallen._physics_process(1.0/60.0)
			fallen._process(1.0/60.0)
		check(fallen.global_position.distance_to(origin) > 25.0 and fallen.global_position.distance_to(origin) < 240.0, "bounded rider throw")
		check(fallen.motorcycle_fall_timer > 0.0, "rider remains stunned")
		for i in 12:
			fallen._physics_process(1.0/60.0)
			fallen._process(1.0/60.0)
		check(fallen.motorcycle_recovery_active and fallen.fall_presentation.recovery_active, "rider begins an authored get-up animation")
		var grounded_pitch := fallen.driver_model.rotation.x
		for i in 42:
			fallen._physics_process(1.0/60.0)
			fallen._process(1.0/60.0)
		check(fallen.driver_model.rotation.x < grounded_pitch - 0.25 and not fallen.civilian_routine, "get-up visibly raises the same rider before locomotion")
		for i in 50:
			fallen._physics_process(1.0/60.0)
			fallen._process(1.0/60.0)
		check(not fallen.fall_presentation.started and not fallen.motorcycle_recovery_active and fallen.motorcycle_returning and not fallen.civilian_routine, "rider gets up and returns to the recoverable motorcycle")
		for i in 240:
			if not is_instance_valid(fallen) or fallen.motorcycle_mounting: break
			fallen._physics_process(1.0/60.0)
			fallen._process(1.0/60.0)
		check(fallen.motorcycle_mounting, "rider physically reaches the motorcycle before mounting")
		await create_timer(0.9).timeout
		check(not is_instance_valid(fallen), "fallen presentation is removed only after mounting")
		check(bike.get_parent() == original_follow and not bike._detached_from_lane and not bike._rider_fallen, "motorcycle returns to its original lane with its rider")
		check(bike.body_model.rider.visible, "same rider presentation is seated again")
		var resumed_at := original_follow.progress
		bike.advance_on_lane(0.25)
		check(original_follow.progress > resumed_at, "remounted motorcycle resumes traffic")
	var shot_bike = FACTORY.spawn_moving_vehicle(path,"ShotBike","bike_urban",.35,90,0)
	shot_bike.set_physics_process(false)
	var bullet = preload("res://guns/Bullet.gd").new()
	world.add_child(bullet)
	bullet._hit(shot_bike, shot_bike.global_position, Vector2.LEFT)
	await process_frame
	await process_frame
	check(shot_bike._rider_fallen and shot_bike._detached_from_lane, "bullet knocks motorcycle out of traffic")
	check(not shot_bike.body_model.rider.visible, "bullet removes seated rider")
	var car = FACTORY.spawn_moving_vehicle(path,"AvoidCar","union_sedan",.5,90,0)
	car.set_process(false)
	car.set_physics_process(false)
	await physics_frame
	car.block_wait_timer = 1.0
	car._update_traffic_avoidance(0.1, car.get_parent(), {"hard":true}, {})
	check(absf(car.position.y) > 0.0 and absf(car.position.y) <= 1.81, "clear lateral correction is gradual")
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 200)
	shape.shape = rect
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = car.global_position + Vector2(90, 0)
	await physics_frame
	await physics_frame
	check(not car._traffic_sweep_clear(Vector2(150, 0)), "full hull sweep rejects solid obstacle")
	world.queue_free()
	await process_frame
	print("REACTIVE MOTORCYCLE TRAFFIC: %d failures" % failures)
	quit(1 if failures else 0)
