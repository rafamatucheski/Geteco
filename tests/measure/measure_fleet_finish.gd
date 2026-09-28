extends "res://tests/measure/measure.gd"
## Real city intersection, deterministic seed, normal settings, no saves.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	seed(28092026)
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play or not world.production.no_save: quit(3); return
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(Vector3(66,.15,129))
	world.production.region.set_focus(world.player.global_position)
	world.camera.target_size = 38
	world.session.weather.set_process(false)
	var folder := "res://evidence/fleet-finish-20260928/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for night in [false,true]:
		world.session.weather.time_of_day = .93 if night else .4
		world.session.weather.weather_state = 1 if night else 0
		world.session.weather._update()
		world.production.state.world_state.time = .93 if night else .4
		world.production.state.world_state.weather = 1 if night else 0
		var warm: Array[float] = []
		var frames: Array[float] = []
		var start := Time.get_ticks_usec()
		var last := start
		var total := 0.0
		while total < 30000:
			await process_frame
			var now := Time.get_ticks_usec()
			var ms := (now-last)/1000.0
			if now-start < 8000000: warm.append(ms)
			else:
				frames.append(ms)
				total += ms
			last = now
		var scenario := "night-rain" if night else "day"
		var report := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,"vehicles":world.production.vehicles.size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
		FileAccess.open(folder+"/"+scenario+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+scenario+".png")
		print("FLEET_BENCH ",scenario," ",JSON.stringify(report.summary))
	world.free()
	await process_frame
	quit()
