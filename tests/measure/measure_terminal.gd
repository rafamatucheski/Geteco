extends "res://tests/measure/measure.gd"
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var after := "--after" in OS.get_cmdline_user_args()
	Engine.set_meta("geteco_world_edit_document",preload("res://world/editing/WorldEditData.gd").empty_document())
	seed(26092026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	if "--control" in OS.get_cmdline_user_args():
		world.production.urban_transit.terminal_operations.free()
		world.production.urban_transit.terminal_operations = null
	world.player.teleport(Vector3(106.25,.1,72))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production._update_physical_residency(world.player.position)
	world.camera.heading = 0
	world.camera.target_size = 48
	world.camera.initialized = false
	world.camera.set_process_unhandled_input(false)
	world.session.weather.time_of_day = .35
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	var warm: Array[float] = []
	var frames: Array[float] = []
	var process_samples: Array[float] = []
	var physics_samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec()-start < 38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if now-start < 8000000: warm.append((now-last)/1000.0)
		else:
			frames.append((now-last)/1000.0)
			process_samples.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
			physics_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
		last = now
	var folder := "res://evidence/terminal-20260926/"+("after" if after else "before")
	if "--control" in OS.get_cmdline_user_args(): folder = "res://evidence/terminal-20260926/control"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): folder = "res://evidence/terminal-20260926/"+arg.trim_prefix("--variant=").validate_filename()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm}
	report.process_monitor_ms = process_samples
	report.physics_monitor_ms = physics_samples
	FileAccess.open(folder+"/performance.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/benchmark.png")
	print("TERMINAL_MEASURE ",JSON.stringify(report.summary))
	quit()
