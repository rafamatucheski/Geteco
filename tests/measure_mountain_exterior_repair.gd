extends SceneTree

## Rendered gameplay comparison for the mountain road and lake. Run once before
## and once after a change with the same machine, resolution, and other settings.
const SAMPLE_SECONDS := 30.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Mountain exterior measurement requires a rendered window")
		quit(1)
		return
	create_timer(240.0).timeout.connect(func(): quit(2))
	var label := "sample"
	var output := OS.get_temp_dir().path_join("geteco-mountain-exterior-0923")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("label="): label = arg.trim_prefix("label=")
		if arg.begins_with("out_dir="): output = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(output.path_join("saves"))
	var saves := root.get_node("SaveManager")
	saves._save_dir = output.path_join("saves") + "/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	seed(23092026)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 60
	var campaign := root.get_node("CampaignState")
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.gameplay_ready:
		await process_frame
	var world := current_scene
	var stream := world.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing:
		await process_frame
	var mountain: Node2D = stream.mountain
	var player: CharacterBody2D = world.get_node("Player")
	player.set_physics_process(false)
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = 0.9
	world.weather.set_weather(0)
	world.weather._update_lighting()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2.ONE
	for scenario in [
		{"name": "lake_and_junction", "point": Vector2(7040, 80)},
		{"name": "summit_and_resort", "point": Vector2(7140, -2700)},
	]:
		player.global_position = mountain.to_global(scenario.point)
		player.reset_physics_interpolation()
		camera.global_position = player.global_position
		camera.make_current()
		for _frame in 120:
			await process_frame
		var samples: Array[float] = []
		var started := Time.get_ticks_usec()
		var previous := started
		while Time.get_ticks_usec() - started < int(SAMPLE_SECONDS * 1000000.0):
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now - previous) / 1000.0)
			previous = now
		var elapsed := float(previous - started) / 1000000.0
		samples.sort()
		var report := {
			"scenario": scenario.name, "label": label,
			"renderer": RenderingServer.get_current_rendering_method(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"resolution": root.size, "vsync": DisplayServer.window_get_vsync_mode(),
			"fps_limit": Engine.max_fps, "seconds": elapsed, "frames": samples.size(),
			"fps_mean": float(samples.size()) / elapsed,
			"p50_ms": samples[int((samples.size() - 1) * .50)],
			"p95_ms": samples[int((samples.size() - 1) * .95)],
			"p99_ms": samples[int((samples.size() - 1) * .99)],
			"max_ms": samples.back(),
			"over_33_ms": samples.filter(func(value: float): return value > 33.3).size(),
			"over_66_ms": samples.filter(func(value: float): return value > 66.7).size(),
		}
		var prefix := output.path_join(label + "-" + scenario.name)
		FileAccess.open(prefix + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
		print("MOUNTAIN_EXTERIOR_PERF ", JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(prefix + ".png")
	# The dirt-road connection needs a closer daylight view than the timed route.
	world.weather.time_of_day = 0.45
	world.weather._update_lighting()
	player.global_position = mountain.to_global(Vector2(6250, 340))
	player.reset_physics_interpolation()
	camera.global_position = player.global_position
	camera.make_current()
	for _frame in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + "-east_vale_junction.png"))
	world.queue_free()
	await process_frame
	quit(0)
