extends "res://tests/measure/measure.gd"
## Run rendered, with --no-save; never reads/writes a personal journey.
var folder: String
var report: Dictionary
class InputBlocker extends Node:
	func _input(_event: InputEvent) -> void:
		get_viewport().set_input_as_handled()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	folder = "res://evidence/sky-menu-20260925/" + variant
	DirAccess.make_dir_recursive_absolute(folder)
	var input_blocker := InputBlocker.new()
	input_blocker.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(input_blocker)
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
	menu._main_enabled(false)
	current_scene = menu
	var has_sky: bool = menu.get("sky") != null
	if menu.get("sky") != null:
		# Exercise the saved-game sky without selecting any personal slot.
		menu.sky.boot_path("res://evidence/sky-menu-20260925/nonexistent.json")
		while not menu.sky.is_ready:
			await process_frame
	if "--confirm-gameplay" in OS.get_cmdline_user_args():
		# Same frozen preview, one bounded confirmation of the post-flight case.
		await create_timer(8.0, true).timeout
	else:
		await sample("menu")
	if not is_instance_valid(menu) or current_scene != menu:
		push_error("Invalid menu sample: active scene changed during measurement")
		quit(1)
		return
	if has_sky:
		world = menu.sky.world
		menu.starting = true
		menu.sky.continue_game()
		var transition_frames: Array[float] = []
		var previous_frame := Time.get_ticks_usec()
		while is_instance_valid(menu):
			await process_frame
			var now := Time.get_ticks_usec()
			transition_frames.append((now - previous_frame) / 1000.0)
			previous_frame = now
		report["flight"] = {"summary": stats(transition_frames), "frames_ms": transition_frames}
	else:
		menu.queue_free()
		await process_frame
		world = load("res://Main.tscn").instantiate()
		world.set_meta("skip_arrival", true)
		root.add_child(world)
		current_scene = world
		while world.session == null or not world.session.ready_for_play: await physics_frame
	world.player.controlled_automatically = true
	world.session.weather.weather_timer = 99999
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather._update()
	await sample("gameplay")
	world.free()
	quit()

func sample(scenario: String) -> void:
	var warm: Array[float] = []
	var frames: Array[float] = []
	var last := Time.get_ticks_usec()
	var begin := last
	var measured := 0.0
	while Time.get_ticks_usec() - begin < 8000000 or measured < 30000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		if now - begin < 8000000: warm.append(ms)
		else:
			frames.append(ms)
			measured += ms
		last = now
	if scenario == "menu": current_scene._main_enabled(true)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(scenario + ".png"))
	var result := {"scenario": scenario, "summary": stats(frames), "warmup": stats(warm), "frames_ms": frames, "warmup_ms": warm}
	report.cases.append(result)
	var file := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("SKY_MENU_BENCH ", scenario, " ", JSON.stringify(result.summary))
