extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	seed(13092026)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.get_node("SaveManager").clear_pending_save()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 30: await physics_frame
	paused = false
	world.get_node("Player").global_position = Vector2(1750, 1315)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(1830, 1490)
	camera.zoom = Vector2.ONE * 2.0
	camera.make_current()
	world.weather.time_of_day = 0.45
	world.weather.weather_state = 0
	world.weather.set_rain_intensity(0.0)
	world.weather._update_lighting()
	await create_timer(5.0).timeout
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		previous = now
	var elapsed := (previous - start) / 1000000.0
	var slow := 0
	var very_slow := 0
	for sample in samples:
		if sample > 33.3: slow += 1
		if sample > 66.7: very_slow += 1
	var label := "baseline" if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args()[0]
	var out := "D:/geteco/artifacts/hospital-geodata-0913/"
	DirAccess.make_dir_recursive_absolute(out)
	var raw := FileAccess.open(out + label + ".json", FileAccess.WRITE)
	raw.store_string(JSON.stringify(samples))
	raw.close()
	samples.sort()
	print("HOSPITAL_PERF ", label, " GPU=", RenderingServer.get_video_adapter_name(), " max_fps=", Engine.max_fps, " vsync=", DisplayServer.window_get_vsync_mode(), " seconds=", elapsed, " frames=", samples.size(), " fps=", samples.size()/elapsed, " p50=", samples[int(samples.size()*.5)], " p95=", samples[int(samples.size()*.95)], " p99=", samples[int(samples.size()*.99)], " max=", samples.back(), " over33=", slow, " over66=", very_slow)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + label + ".png")
	quit()
