extends "res://tests/measure/measure.gd"
## Station scene sampler. A variant label does not disable content or create a
## historical baseline; paired runs require independently prepared versions.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STOPS := {"harbor":Vector3(135,.12,72),"mountain":Vector3(739.8125,.12,-418.125),"desert":Vector3(-185,.12,-886)}
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var variant := "current"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=")
	var folder := FIXTURE.output_dir("regional-coach-" + variant)
	var snapshot := FIXTURE.full_snapshot(STOPS.harbor, true)
	snapshot.campaign.aftermath = {"call_complete":true}
	var path := FIXTURE.write_fixture(folder, "save.json", snapshot)
	if path.is_empty(): quit(2); return
	seed(7102026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path", path)
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await process_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.session.weather.set_process(false)
	var summary := {}
	for id in STOPS:
		if world.session.state.region_id != id:
			if not world.production.travel(id, STOPS[id]): quit(3); return
			while world.production.travel_busy: await process_frame
		if world.session.state.region_id != id: quit(4); return
		world.camera.heading = 0
		world.camera.target_size = 32
		world.camera.initialized = false
		world.session.weather.time_of_day = .4
		world.session.weather.weather_state = 0
		world.session.weather._update()
		var warm: Array[float] = []
		var frames: Array[float] = []
		var started_at := Time.get_ticks_usec()
		var previous_at := started_at
		while Time.get_ticks_usec() - started_at < 38000000:
			await process_frame
			var now := Time.get_ticks_usec()
			if now - started_at < 8000000: warm.append((now-previous_at)/1000.0)
			else: frames.append((now-previous_at)/1000.0)
			previous_at = now
		var report := {"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,
			"position":str(world.player.position),"gpu":RenderingServer.get_video_adapter_name(),
			"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),
			"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,
			"map_hash":preload("res://world/editing/WorldEditData.gd").disk_hash()}
		FileAccess.open(folder.path_join(id+".json"),FileAccess.WRITE).store_string(JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(id+".png"))
		summary[id] = report.summary
		print("REGIONAL_PERF ",id," ",report.summary)
	print("REGIONAL_PERF_DONE ",folder," ",summary)
	quit()
