extends SceneTree

var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var ordinary = load("res://PlayerCar.gd").new()
	ordinary.velocity = Vector2(200,0)
	ordinary._apply_steering_motion(1.0,0.1)
	check(ordinary.rotation > 0.0 and ordinary.rotation < ordinary.turn_speed * 0.1, "Ordinary cars build yaw progressively with speed-dependent steering")
	check(ordinary.velocity == Vector2(200,0), "Legacy steering must not modify ordinary car velocity")
	ordinary.free()
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 6: await physics_frame
	var car = scene.get_node("PlayerCar")
	for child in car.get_children():
		if child is CPUParticles2D and child.texture != null:
			check(child.scale_amount_max * child.texture.get_width() <= 32.01, "Routine particle must not dwarf the car: " + child.name)
	check(car.backfire_emitter.scale_amount_max * car.backfire_emitter.texture.get_width() <= 10, "Exhaust pop must not look like an explosion")
	check(car.backfire_emitter.position.x < -30 and car.backfire_emitter.emission_points.size() == 2, "Backfire must originate at the two rear exhausts, not the roof")
	car.set_physics_process(false)
	car.rotation = 0
	car.velocity = Vector2.ZERO
	for i in 60: car._apply_steering_motion(1.0,1.0/60.0)
	check(is_zero_approx(car.rotation), "Steering at rest must not rotate the body")
	check(car.steering_angle > 0.4, "Wheels can steer at rest")
	var angles: Array[float] = []
	for speed in [90.0,450.0]:
		car.rotation = 0
		car.velocity = Vector2(speed,0)
		car.steering_angle = 0
		for i in 60: car._apply_steering_motion(1.0,1.0/60.0)
		angles.append(car.steering_angle)
		check(absf(car.velocity.dot(car.global_transform.y)) < 0.1, "Rolling velocity must follow the body, not slide sideways")
	check(angles[1] < angles[0], "High speed needs a wider turning radius")
	car.rotation = 0
	car.velocity = Vector2(-90,0)
	car.steering_angle = 0
	for i in 30: car._apply_steering_motion(1.0,1.0/60.0)
	check(car.rotation < 0, "Reverse must invert yaw, not wheel steering")
	for i in 30: car._apply_steering_motion(0.0,1.0/60.0)
	check(is_zero_approx(car.steering_angle), "Release must center the steering")
	car.velocity = Vector2.ZERO
	car.set_physics_process(true)
	scene._drive()
	# Entry now animates the walk and door before driving input is armed.
	for i in 300:
		await physics_frame
		if car.is_driven_by_player and (not is_instance_valid(car._boarding) or not car._boarding.active): break
	check(car.is_driven_by_player, "Driver must complete boarding before native input")
	for i in 3: await physics_frame
	# Actual native movement/input, in an empty area to isolate handling from
	# authored junctions. Existing road/bridge tests cover authored geometry.
	# This fixture deliberately drives outside the city. Its perimeter recovery
	# would teleport the car back into downtown traffic during each curve.
	for child in scene.get_children():
		if child.get_script() == preload("res://world/harbor/WorldPerimeter.gd"):
			child.set_physics_process(false)
	for controls in [["move_up","move_right"],["move_up","move_left"],["move_down","move_right"]]:
		car.global_position = Vector2(28000,28000)
		car.rotation = 0
		car.velocity = Vector2.ZERO
		car.steering_angle = 0
		var health_before: int = car.health
		var travelled := 0.0
		var previous: Vector2 = car.global_position
		for action in controls: Input.action_press(action)
		for i in 120:
			await physics_frame
			travelled += car.global_position.distance_to(previous)
			previous = car.global_position
		for action in controls: Input.action_release(action)
		check(travelled > 150, "Native controls must drive a real curve")
		check(car.health == health_before, "Normal driving must not damage/explode the car")
		check(car.transform.is_finite(), "Turning must retain finite transform")
		check((car.rotation > 0) == (controls[1] == "move_right" and controls[0] == "move_up"), "Native steering direction mismatch")
		print("COUPE_NATIVE_TURN controls=%s travel=%.1f yaw=%.2f health=%d" % [controls,travelled,car.rotation,car.health])
	scene.queue_free()
	await process_frame
	print("COUPE_HANDLING_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)
