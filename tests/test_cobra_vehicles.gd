extends SceneTree

var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 12:
		await physics_frame
	var cars = scene.get_node("CobraVehicles")
	var car = cars.secret_car
	var player = scene.get_node("Player")
	check(car != null and cars.workshop_truck != null, "Both authored cars must exist")
	check(car.max_speed > scene.get_node("PlayerCar").max_speed, "Exploration coupe must improve stock Harbor top speed")
	check(cars.workshop_truck.max_speed < car.max_speed, "Work truck and coupe need different handling")
	check(car.spinners.size() == 4, "Secret coupe retains articulated 3D wheels")
	var query := PhysicsShapeQueryParameters2D.new()
	for vehicle in [car, cars.workshop_truck]:
		query.shape = vehicle.get_node("Collision").shape
		query.transform = vehicle.get_node("Collision").global_transform
		query.collision_mask = 1
		query.exclude = [vehicle.get_rid()]
		check(scene.get_world_2d().direct_space_state.intersect_shape(query).is_empty(), "Parked vehicle may not overlap walls or buildings")
	# Fixture places only the player beside the discovery. The car begins at its
	# authored parking spot, then moves using its unchanged driving controller.
	player.global_position = car.global_position + Vector2(0, 42)
	for i in 3:
		await physics_frame
	car.enter_vehicle(player)
	check(car.is_driven_by_player and not player.visible, "Discovery car can be entered")
	check(car.camera.is_current(), "Boarding transfers the camera to the secret car")
	car.rotation = 0.0
	var start: Vector2 = car.global_position
	var wheel_angle: float = car.spinners[0].rotation.x
	Input.action_press("ui_up")
	for i in 24:
		await physics_frame
	Input.action_release("ui_up")
	check(car.global_position.x > start.x + 15, "Secret coupe drives physically out of its parking spot")
	check(absf(car.spinners[0].rotation.x - wheel_angle) > 0.1, "Wheels rotate during travel")
	car.velocity = Vector2.ZERO
	car.repaint_vehicle(Color("254b66"))
	check(car.paint_color == Color("254b66") and car.body_model.paint.albedo_color == car.paint_color, "Existing paint contract preserves 3D body material")
	car.exit_vehicle()
	for i in 8:
		await physics_frame
	check(player.visible and not car.is_driven_by_player, "Car can be exited normally")
	print("COBRA_VEHICLES failures=%d travel=%.3f" % [failures, car.global_position.distance_to(start)])
	scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
