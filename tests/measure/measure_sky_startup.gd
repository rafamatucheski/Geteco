extends "res://tests/measure/measure_sky_menu.gd"
## Includes every cold-start frame: do not hide loading stalls in warm-up.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	folder = "res://evidence/sky-menu-fixes-20260925/" + variant
	DirAccess.make_dir_recursive_absolute(folder)
	var blocker := InputBlocker.new()
	blocker.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(blocker)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	var settings = root.get_node("V2Settings")
	settings.window_mode = 0
	settings.resolution = 0
	settings.vsync = true
	settings.fps_limit = 1
	settings.apply_settings()
	root.get_node("V2Launch").direct_start_consumed = true
	report = {"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps, "cases": []}
	var menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	menu.sky.boot_path("res://evidence/sky-menu-fixes-20260925/nonexistent.json")
	var frames: Array[float] = []
	var slow_frames: Array[Dictionary] = []
	var last := Time.get_ticks_usec()
	var deadline := last + 180000000
	while not menu.sky.is_ready and not menu.sky.failed and Time.get_ticks_usec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		frames.append(ms)
		if ms > 33.3:
			var curtain = menu.sky.world.get_node_or_null("LoadingCurtain") if is_instance_valid(menu.sky.world) else null
			slow_frames.append({"ms": ms, "stage": curtain._target if curtain != null else -1.0})
		last = now
	if not menu.sky.is_ready:
		push_error("Sky boot timed out or failed")
		quit(1)
		return
	world = menu.sky.world
	report["startup"] = {"summary": stats(frames), "frames_ms": frames, "slow_frames": slow_frames}
	print("SKY_STARTUP ", JSON.stringify(report.startup.summary))
	if "--startup-only" in OS.get_cmdline_user_args():
		var file := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
		world.queue_free()
		await process_frame
		quit()
		return
	await sample("menu")
	menu.starting = true
	menu.sky.continue_game()
	frames = []
	var snapshots: Array = []
	last = Time.get_ticks_usec()
	while is_instance_valid(menu):
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		var car = world.driving.car
		snapshots.append({"position": str(car.global_position), "interpolated": str(car.get_global_transform_interpolated().origin), "visible": car.is_visible_in_tree(), "meshes": car.visual.get_child_count()})
	report["flight"] = {"summary": stats(frames), "frames_ms": frames, "car": snapshots}
	world.player.controlled_automatically = true
	world.session.weather.weather_timer = 99999
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather._update()
	await sample("gameplay")
	world.queue_free()
	await process_frame
	quit()
