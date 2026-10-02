extends SceneTree
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")

func _initialize() -> void: run.call_deferred()

func capture(label: String) -> void:
	for i in 90: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/tunnel-chase-20261001/%s.png" % label)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	seed(28092026)
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1800:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.weather != null: break
	var car: CharacterBody3D = world.driving.car
	var point := Vector3(190, TUNNEL.floor_y(190) + .12, 63)
	world.production._update_physical_residency(point)
	world.production._update_logical_region(point)
	car.place(point, -PI * .5)
	for i in 3: await physics_frame
	for side in [-1, 1]:
		world.player.teleport(car.to_global(Vector3(side * (car.half_width + .65), .04, .15)))
		await physics_frame
		if world.driving.interact(): break
	car.set_external_driver(true)
	car.place(point, -PI * .5)
	if "--review" in OS.get_cmdline_user_args():
		for i in 600:
			await physics_frame
			if world.driving.transition == null and world.driving.occupied: break
		car.set_external_driver(true)
		car.input_locked = false
		await review(world, car)
		quit()
		return
	await capture("detail-before")
	var states := {}
	for part in car.visual.find_children("*", "MeshInstance3D", true, false):
		var mat: Material = part.material_override
		if mat is StandardMaterial3D:
			states[mat] = mat.cull_mode
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	await capture("diagnose-car-two-sided")
	for mat in states: mat.cull_mode = states[mat]
	# Compare with the same model before the door cut, without changing gameplay.
	car.visual.hide()
	var untouched: Node3D = preload("res://runtime/FleetCatalog.gd").create(car.archetype)
	car.add_child(untouched)
	untouched.transform = car.visual.transform
	preload("res://runtime/VehiclePaint.gd").new().bind(untouched, car.archetype)
	await capture("diagnose-car-original")
	untouched.queue_free()
	car.visual.show()
	point = Vector3(240, TUNNEL.floor_y(240) + .12, 63)
	world.production._update_physical_residency(point)
	car.place(point, -PI * .5)
	await capture("detail-glass-before")
	print("CHASE_SURFACES_CAPTURE_OK")
	quit()

func review(world: Variant, car: CharacterBody3D) -> void:
	var point := Vector3(240, TUNNEL.floor_y(240) + .12, 63)
	world.production._update_physical_residency(point)
	car.place(point, -PI * .5)
	await capture("final-glass-east")
	car.place(point, PI * .5)
	await capture("final-glass-west")
	car.place(Vector3(190, TUNNEL.floor_y(190) + .12, 63), -PI * .5)
	await capture("final-covered")
	var directory := "res://evidence/tunnel-chase-20261001/motion-drive"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	Engine.max_fps = 30 # Somente este processo de captura; não é benchmark.
	var began := Time.get_ticks_usec()
	var times: Array = []
	var index := 0
	while Time.get_ticks_usec() - began < 30000000:
		var elapsed := float(Time.get_ticks_usec() - began) / 1000000.0
		var moving := elapsed > 5.0 and elapsed < 26.0 and car.global_position.x < 338.0
		if not car.external_input: car.set_external_driver(true)
		car.input_locked = false
		car.throttle_input = 1.0 if moving and car.speed < 8.0 else 0.0
		car.brake_input = not moving
		car.steer_input = clampf(-.35 * (63.0 - car.global_position.z) + 2.5 * (-car.global_basis.z).z, -1.0, 1.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		frame.resize(960, 540, Image.INTERPOLATE_BILINEAR)
		var error := frame.save_jpg("%s/frame-%04d.jpg" % [directory, index], .85)
		if error != OK:
			push_error("Falha ao gravar sequência: " + str(error))
			return
		times.append({"frame": index, "seconds": float(Time.get_ticks_usec() - began) / 1000000.0, "x": car.global_position.x, "camera_blend": world.camera._tunnel_chase_blend})
		index += 1
	var output := FileAccess.open(directory + "/timing.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"frames": times, "duration_seconds": float(Time.get_ticks_usec() - began) / 1000000.0, "capture_limit_fps": 30, "not_benchmark": true}, "  "))
	print("CHASE_MOTION_CAPTURE frames=", index, " end=", car.global_position)
