extends SceneTree
## Vulkan real; entrada atual de GameInput, aquecimento e rota determinística.
var output := "after"
var rows: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Medição requer renderização real.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("label="): output = arg.trim_prefix("label=")
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var settings := root.get_node("SettingsManager")
	settings.window_mode = 0
	settings.resolution = Vector2i(1280, 720)
	settings.apply_display_settings()
	root.size = Vector2i(1280, 720)
	if output == "before":
		for child in root.get_node("SettingsManager").get_children():
			if child.get_script() == preload("res://RenderQuality.gd"): child.free()
		root.msaa_2d = Viewport.MSAA_DISABLED
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	seed(911)
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world: Node = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 180: await process_frame
	if not world.gameplay_ready or paused:
		push_error("Checkpoint não ficou jogável.")
		quit(1)
		return
	world.weather.time_of_day = 0.45
	world.weather.set_weather(0)
	world.weather.set_process(false)
	var player: Node2D = world.get_node("Player")
	var car: CharacterBody2D = world.get_node("PlayerCar")
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	player.global_position = car.global_position + Vector2(0, 50)
	car.enter_vehicle(player)
	car.reset_physics_interpolation()
	for i in 120: await process_frame
	await _measure("stationary", car, false)
	await _measure("driving", car, true)
	var path := "res://docs/measurements/aa-performance-0911/" + output
	FileAccess.open(path + ".json", FileAccess.WRITE).store_string(JSON.stringify(rows, "\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path + ".png")
	world.queue_free()
	await process_frame
	quit(0 if float(rows[-1].distance) > 100 else 1)

func _measure(label: String, car: CharacterBody2D, drive: bool) -> void:
	var samples: Array[float] = []
	var distance := 0.0
	var previous := car.global_position
	var physics := 0.0
	if drive: Input.action_press("move_up")
	for i in 300:
		var started := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		distance += car.global_position.distance_to(previous)
		previous = car.global_position
		physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	Input.action_release("move_up")
	var total := 0.0
	for value in samples: total += value
	samples.sort()
	var result := {"scenario":label, "fps":300000.0 / total, "mean_ms":total / 300.0,
		"p50_ms":samples[150], "p90_ms":samples[270], "p99_ms":samples[297],
		"physics_ms":physics / 300.0, "distance":distance,
		"gpu":RenderingServer.get_video_adapter_name(), "msaa_2d":root.msaa_2d,
		"resolution":str(root.size), "renderer":RenderingServer.get_current_rendering_method()}
	rows.append(result)
	print("AA_PERFORMANCE ", JSON.stringify(result))
