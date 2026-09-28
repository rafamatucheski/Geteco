extends "res://tests/measure/measure.gd"

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180).timeout.connect(func(): push_error("Precinct benchmark timed out"); quit(2))
	seed(28092026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if not await world.session.enter_place("harbor_police",false): quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.state.grant_weapon("pistol")
	world.session.state.equip_weapon("pistol")
	var frames: Array[float] = []
	var warm: Array[float] = []
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec()-start < 38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if now-start < 8000000: warm.append((now-last)/1000.0)
		else: frames.append((now-last)/1000.0)
		last = now
	var phase := "after" if "--after" in OS.get_cmdline_user_args() else "before"
	var folder := OS.get_temp_dir().path_join("geteco-precinct-threat-20260928/")
	DirAccess.make_dir_recursive_absolute(folder)
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm}
	print("PRECINCT_MEASURE_FILE ",folder+phase+".json", " max_fps=",Engine.max_fps)
	print("PRECINCT_MEASURE ",phase," ",JSON.stringify(report.summary))
	var output := FileAccess.open(folder+phase+".json",FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(report))
	else: push_error("Cannot write benchmark: " + str(FileAccess.get_open_error()))
	quit()
