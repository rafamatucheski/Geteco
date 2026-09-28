extends "res://tests/measure/measure.gd"
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	seed(28092026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.urban_operations.security.authorized_visit = true
	world.camera.set_process_unhandled_input(false)
	world.session.weather.set_process(false)
	var folder := "res://evidence/harbor-life-20260928/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var sites := [{"id":"quay-day","point":Vector3(254,.1,211),"time":.4}, {"id":"quay-night","point":Vector3(254,.1,211),"time":.9}, {"id":"terminal-night","point":Vector3(223,.1,203),"time":.9}, {"id":"terminal-rain","point":Vector3(223,.1,203),"time":.9,"weather":1}]
	for site in sites:
		world.session.weather.time_of_day = site.time
		world.session.weather.weather_state = site.get("weather",0)
		world.session.weather._update()
		world.player.teleport(site.point)
		world.session.weather._process(0)
		world.production.region.set_focus(site.point)
		world.camera.heading = 0
		world.camera.target_size = 62
		world.camera.initialized = false
		var warm: Array[float] = []
		var frames: Array[float] = []
		var start := Time.get_ticks_usec()
		var last := start
		while Time.get_ticks_usec()-start < 38000000:
			await process_frame
			var now := Time.get_ticks_usec()
			if now-start < 8000000: warm.append((now-last)/1000.0)
			else: frames.append((now-last)/1000.0)
			last = now
		var report := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm}
		FileAccess.open(folder+"/"+site.id+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+site.id+".png")
		print("HARBOR_MEASURE ",site.id," ",JSON.stringify(report.summary))
	quit()
