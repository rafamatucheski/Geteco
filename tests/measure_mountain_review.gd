extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(240).timeout.connect(func(): quit(2))
	seed(912)
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/mountain-review-0913/saves/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	for flag in [&"intro_completed", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null: await process_frame
	var scene = current_scene
	while not scene.gameplay_ready: await process_frame
	var stream = scene.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	scene.weather.is_dynamic_time = false
	scene.weather.time_of_day = 0.45
	scene.weather.set_weather(0)
	scene.weather._update_lighting()
	var camera := Camera2D.new()
	scene.add_child(camera)
	camera.zoom = Vector2.ONE
	var label := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	if "--final" in OS.get_cmdline_user_args(): label = "final"
	print("CLIFF_ENV ", RenderingServer.get_video_adapter_name(), " renderer=", RenderingServer.get_current_rendering_method(), " vsync=", DisplayServer.window_get_vsync_mode(), " cap=", Engine.max_fps)
	var scenarios: Array = [] if "--capture-only" in OS.get_cmdline_user_args() else [Vector2(6950,-250), Vector2(7140,-2760)]
	for point in scenarios:
		player.global_position = stream.mountain.to_global(point)
		camera.global_position = player.global_position
		camera.make_current()
		for i in 120: await process_frame
		var samples: Array[float] = []
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec()-start < 30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now-previous)/1000.0)
			previous = now
		var total := float(previous-start)/1000000.0
		var raw := samples.duplicate()
		samples.sort()
		var report := {"label":label,"point":str(point),"seconds":total,"frames":samples.size(),"fps":samples.size()/total,"p50":samples[int(samples.size()*.5)],"p95":samples[int(samples.size()*.95)],"p99":samples[int(samples.size()*.99)],"max":samples[-1],"over33":samples.filter(func(v): return v>33.3).size(),"over66":samples.filter(func(v): return v>66.7).size(),"samples_ms":raw}
		var prefix := "D:/geteco/artifacts/mountain-review-0913/%s-%d" % [label,abs(int(point.y))]
		FileAccess.open(prefix+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		report.erase("samples_ms")
		print("CLIFF_PERF ",JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(prefix+".png")
	await _capture_falls(scene, stream, camera)
	quit()

func _capture_falls(scene: Node, stream: Node, camera: Camera2D) -> void:
	var mountain: Node2D = stream.mountain
	var player: CharacterBody2D = scene.get_node("Player")
	for vehicle in get_nodes_in_group("vehicle"):
		if vehicle.get("is_driven_by_player") == true and vehicle.has_method("force_exit_vehicle"):
			vehicle.force_exit_vehicle()
	scene.call("_walk")
	var cliffs: Node2D = mountain.road.cliff_edges
	var patch: Dictionary = cliffs.patches[2]
	var lip: Vector2 = cliffs.to_global((patch.lip[0] + patch.lip[1]) * 0.5)
	player.global_position = lip - patch.normal * 40.0
	player._respawn_grace_active = false
	player.set_physics_process(false)
	camera.global_position = lip + Vector2(0, 30)
	camera.zoom = Vector2.ONE * 2.0
	camera.make_current()
	for i in 12: await process_frame
	if not player.visible or not cliffs._can_fall(player):
		push_error("Foot capture requires a visible, recoverable pedestrian")
		return
	await _picture("foot-before")
	cliffs._fall(player, patch.normal)
	await create_timer(0.35).timeout
	await _picture("foot-falling")
	await create_timer(0.55).timeout
	await _picture("foot-impact")
	var deadline := Time.get_ticks_msec() + 6000
	while (player.is_dead or player.is_recovering) and Time.get_ticks_msec() < deadline:
		await process_frame
	var car := preload("res://world/mountain_pass/MountainSUV.gd").new()
	car.position = mountain.to_local(lip - patch.normal * 40.0)
	mountain.add_child(car)
	player.global_position = car.global_position + Vector2(0, 35)
	player._respawn_grace_active = false
	car.enter_vehicle(player)
	await create_timer(2.4).timeout
	car.set_physics_process(false)
	camera.global_position = lip + Vector2(0, 30)
	camera.make_current()
	await _picture("car-before")
	cliffs._fall(car, patch.normal)
	await create_timer(0.35).timeout
	await _picture("car-falling")
	await create_timer(0.55).timeout
	camera.make_current()
	await _picture("car-impact")
	print("FALL_CAPTURE_COMPLETE")

func _picture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/mountain-review-0913/" + label + ".png")

