extends "res://tests/capture/video_review_final.gd"
## A/B diagnosis: same actor, camera and meshes, only the silhouette overlay
## is removed for one screenshot, then restored. No runtime file is changed.

func run() -> void:
	if DisplayServer.get_name() == "headless" or not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	capture_prefix = "ablation-"
	report_filename = "ablation-captures.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-prefix="): capture_prefix = arg.trim_prefix("--capture-prefix=")
		if arg.begins_with("--capture-report="): report_filename = arg.trim_prefix("--capture-report=")
	silhouette_ablation = true
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for frame in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		failures.append("Main failed to start")
		await finish()
		return
	print("SILHOUETTE_ABLATION Main loaded")
	await wait_startup_curtain()
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.camera.target_size = 8.0
	world.camera.size = 8.0
	await motorcycle_theft()
	if world.driving.occupied:
		await finish()
		return
	await exterior_occlusion_control()
	if await enter("harbor_bank"):
		await capture("bank-first-render")
		await bank_occlusion_pair()
		await capture_without_silhouette("bank-behind-without-silhouette")
		await leave("harbor_bank")
	await finish()

func exterior_occlusion_control() -> void:
	var center: Vector3 = world.maciota_place.exterior_origin
	for z_offset in [.8, .4, 0.0, -.4]:
		var point := center + Vector3(0, .08, z_offset)
		if not world.session.position_clear(point): continue
		world.player.teleport(point)
		world.camera.initialized = false
		world.camera._process(1.0)
		await frames(18)
		var query := PhysicsRayQueryParameters3D.create(world.camera.global_position, world.player.global_position + Vector3.UP, 1)
		var blocker: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		if blocker.is_empty(): continue
		records.append({"exterior_control_occluder": str(blocker.collider), "player_position": str(world.player.global_position)})
		await capture("exterior-behind-building")
		await capture_without_silhouette("exterior-behind-building-without-silhouette")
		return
	failures.append("native exterior occlusion control position unavailable")
