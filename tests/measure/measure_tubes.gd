extends "res://tests/measure/measure.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var doc := preload("res://world/editing/WorldEditData.gd").empty_document()
	var after := "--after" in OS.get_cmdline_user_args()
	if after:
		var id := "piece/transit/urban_station_2"
		doc.regions.harbor[id] = {"id":id,"type":"piece","position":[17.53125,57.625],"rotation":5.0,"stretch":[1.1,1.1],"source_record":"transit/urban_station_2"}
	Engine.set_meta("geteco_world_edit_document",doc)
	seed(26092026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.teleport(Vector3(20,.1,55))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production._update_physical_residency(world.player.position)
	world.camera.heading = 0
	world.camera.target_size = 45
	world.camera.initialized = false
	world.camera.set_process_unhandled_input(false)
	world.session.weather.time_of_day = .35
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	var warm: Array[float] = []
	var frames: Array[float] = []
	var began := Time.get_ticks_usec()
	var previous := began
	while Time.get_ticks_usec()-began<38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if now-began<8000000: warm.append((now-previous)/1000.0)
		else: frames.append((now-previous)/1000.0)
		previous = now
	var folder := "res://evidence/tube-editor/"+("after" if after else "before")
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder+"/performance.json",FileAccess.WRITE).store_string(JSON.stringify({"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,"gpu":RenderingServer.get_video_adapter_name(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"limit":Engine.max_fps}))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/world.png")
	print("TUBE_PERF ",stats(frames))
	world.free()
	quit()
