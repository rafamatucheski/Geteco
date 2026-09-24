extends SceneTree
## Real MountainPass scene, fixed forest checkpoint, finite off/on samples.
var output := OS.get_temp_dir().path_join("geteco-forest-flashlight")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	create_timer(180).timeout.connect(func(): quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(output)
	root.get_node("SaveManager")._save_dir = output.path_join("saves") + "/"
	root.get_node("SaveManager").clear_pending_save()
	seed(19092026)
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
	while current_scene == null or not current_scene.region_ready: await process_frame
	var world = current_scene
	var player = world.player_instance
	player.global_position = Vector2(5850, 540)
	player.reset_physics_interpolation()
	player.get_node("Camera").reset_smoothing()
	player.personal_loadout_enabled = false
	player.weapon_inventory.pistol = true
	player.money = 1000
	player.health = 100000
	player.mountain_thermal_coat = true
	player.equip_weapon("pistol")
	player.customize_weapon("pistol", "install")
	world.storm_manager.dynamic_weather = false
	world.storm_manager.weather_clock = 0
	world.storm_manager.advance_weather(0)
	var weather = world.get_node("DayNightWeather")
	weather.time_of_day = 0.9
	weather.day_length_seconds = 100000000
	root.get_node("GameInput").touch_aim = Vector2.RIGHT
	await create_timer(8).timeout
	await sample("off", player)
	player.weapon_flashlight.toggle()
	if not player.weapon_flashlight.enabled:
		push_error("Forest flashlight failed to enable")
		quit(1)
		return
	await create_timer(3).timeout
	await sample("on", player)
	quit(0)
func sample(label: String, player: Node2D) -> void:
	var values: Array[float] = []
	var previous := Time.get_ticks_usec()
	var start := previous
	var csv := FileAccess.open(output.path_join(label + ".csv"), FileAccess.WRITE)
	csv.store_line("frame_ms")
	while Time.get_ticks_usec() - start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - previous) / 1000.0
		previous = now
		values.append(ms)
		csv.store_line(str(ms))
	csv.close()
	var elapsed := float(previous - start) / 1000000.0
	values.sort()
	var report := {"scenario":"MountainPass forest at night", "mode":label,
		"gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(),
		"resolution":str(root.size), "vsync":DisplayServer.window_get_vsync_mode(), "cap":Engine.max_fps,
		"seconds":elapsed, "frames":values.size(), "fps":values.size()/elapsed,
		"p50_ms":values[int(values.size()*.5)], "p95_ms":values[int(values.size()*.95)],
		"p99_ms":values[int(values.size()*.99)], "max_ms":values.back(),
		"over_33ms":values.filter(func(v): return v>33.3).size(),
		"over_66ms":values.filter(func(v): return v>66.7).size(),
		"light_enabled":player.weapon_flashlight.enabled, "player_position":str(player.global_position)}
	FileAccess.open(output.path_join(label + ".json"), FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FOREST_FLASHLIGHT ", JSON.stringify(report))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
