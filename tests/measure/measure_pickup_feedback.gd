extends "res://tests/measure/measure.gd"
## Same rendered city, closed/open inventory, finite samples; no personal saves.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	seed(28092026)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.teleport(Vector3(132,.15,72))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production.region.set_focus(world.player.global_position)
	world.camera.target_size = 38
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	var field = world.session.field_inventory
	var source: Dictionary = field.sources[0]
	world.player.teleport(source.point+Vector3(0,.1,2))
	world.production.region.set_focus(world.player.position)
	world.camera.target_size = 14
	for i in 90: await physics_frame
	field._refresh_world()
	var folder := "res://evidence/pickup-feedback/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for opened in [false]:
		if opened: world.session.show_inventory()
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
			else: frames.append(ms); total += ms
			last = now
		var scenario := "open" if opened else "closed"
		var report := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(frames),"frames_ms":frames,"warmup_ms":warm,"comparison_caveat":"Concurrent Godot processes detected before baseline; diagnostic only unless environment is isolated."}
		FileAccess.open(folder+"/"+scenario+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+scenario+".png")
		print("INVENTORY_BENCH ",scenario," ",JSON.stringify(report.summary))
	world.free()
	quit()
