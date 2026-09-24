extends SceneTree

## Daylight review of the continuous Harbor-to-mountain crossing.
const SAMPLE_SECONDS := 30.0

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(180.0).timeout.connect(func(): quit(2))
	var output := OS.get_temp_dir().path_join("geteco-mountain-access-bridge")
	var fast := OS.get_cmdline_user_args().has("fast")
	DirAccess.make_dir_recursive_absolute(output.path_join("saves"))
	var saves := root.get_node("SaveManager")
	saves._save_dir = output.path_join("saves") + "/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
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
	# The campaign owns the clock during play; freeze it only for controlled
	# daylight/night captures. Timed gameplay keeps its normal campaign work.
	if fast:
		world.get_node("CobraCampaign").set_process(false)
	var stream := world.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing:
		await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	player.set_physics_process(false)
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = 0.45
	world.weather.set_weather(0)
	world.weather._update_lighting()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2.ONE
	for sample in [
		{"name": "west_deck", "point": Vector2(6650, -4560)},
		{"name": "east_taper", "point": Vector2(7130, -4560)},
		{"name": "mountain_seam", "point": Vector2(7310, -4560)},
	]:
		player.global_position = sample.point
		player.reset_physics_interpolation()
		camera.global_position = sample.point
		camera.make_current()
		for frame in 90:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(sample.name + ".png"))
		print("BRIDGE_REVIEW ", sample.name, " ", sample.point)
	var overlay: CanvasItem = world.get_node("Gateway/MountainConnector/GapFillOverlay")
	var variants := [{"name": "without_overlay", "visible": false}, {"name": "with_overlay", "visible": true}]
	if fast:
		variants.clear()
	elif OS.get_cmdline_user_args().has("reverse"):
		variants.reverse()
	for variant in variants:
		overlay.visible = variant.visible
		player.global_position = Vector2(7130, -4560)
		player.reset_physics_interpolation()
		camera.global_position = player.global_position
		for frame in 90:
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
			"scenario": variant.name,
			"renderer": RenderingServer.get_current_rendering_method(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"resolution": root.size,
			"frames": samples.size(),
			"fps_mean": float(samples.size()) / elapsed,
			"p95_ms": samples[int((samples.size() - 1) * 0.95)],
			"p99_ms": samples[int((samples.size() - 1) * 0.99)],
			"over_33_ms": samples.filter(func(value: float): return value > 33.3).size(),
		}
		FileAccess.open(output.path_join(variant.name + ".json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
		print("BRIDGE_PERF ", JSON.stringify(report))
	overlay.visible = true
	world.weather.time_of_day = 0.1
	world.weather._update_lighting()
	player.global_position = Vector2(7310, -4560)
	player.reset_physics_interpolation()
	camera.global_position = player.global_position
	for frame in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("night_seam.png"))
	world.queue_free()
	await process_frame
	quit(0)
