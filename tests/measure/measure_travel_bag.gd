extends "res://tests/measure/measure.gd"
const FIXTURE = preload("res://tests/fixtures/TravelBagScene.gd")

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	var folder := "res://evidence/travel-bag-20261007/" + variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	seed(7102026)
	root.size = Vector2i(1280,720)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world); current_scene = world
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	var session = world.session
	if not FIXTURE.complete_through(session, "cobra_race"): quit(4); return
	FIXTURE.park_monaliza(world)
	world.player.teleport(session.personal_car._rear()+Vector3(0,.05,.8))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production.region.set_focus(world.player.position)
	world.camera.target_size = 18
	session.weather.set_process(false)
	session.weather.time_of_day = .4; session.weather.weather_state = 0; session.weather._update()
	for i in 30: await physics_frame
	session.personal_car.refresh()
	if session.state.economy.grid_snapshot().bag != "backpack": quit(5); return
	for scenario in ["closed", "trunk"]:
		if scenario == "trunk": session.field_inventory.open(true)
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
		var report := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(frames),"frames_ms":frames,"warmup":stats(warm),"warmup_ms":warm,"scenario":scenario,"variant":variant,"trunk_access":session.field_inventory.trunk_access()}
		FileAccess.open(folder+"/"+scenario+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+scenario+".png")
		print("TRAVEL_BAG_BENCH ",scenario," ",JSON.stringify(report.summary))
	world.free(); quit()
