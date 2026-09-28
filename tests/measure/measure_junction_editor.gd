extends "res://tests/measure/measure.gd"
const DATA := preload("res://world/editing/WorldEditData.gd")
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var loaded := DATA.read_document()
	if not loaded.error.is_empty(): quit(3); return
	Engine.set_meta("geteco_world_edit_document",loaded.document)
	var map_hash := DATA.disk_hash()
	seed(27092026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.teleport(Vector3(110,.1,95))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production._update_physical_residency(world.player.position)
	world.camera.heading = 0
	world.camera.target_size = 90
	world.camera.initialized = false
	world.camera.set_process_unhandled_input(false)
	world.session.weather.time_of_day = .35
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	var warm: Array[float] = []
	var frames: Array[float] = []
	var stalls := []
	var began := Time.get_ticks_usec()
	var previous := began
	while Time.get_ticks_usec()-began<38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if now-began<8000000: warm.append((now-previous)/1000.0)
		else: frames.append((now-previous)/1000.0)
		if now-began>=8000000 and now-previous>33300:
			stalls.append({"at_seconds":(now-began)/1000000.0,"frame_ms":(now-previous)/1000.0,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000})
		previous = now
	var folder := "res://evidence/junction-editor/"+("after" if "--after" in OS.get_cmdline_user_args() else "before")
	if "--confirm" in OS.get_cmdline_user_args(): folder="res://evidence/junction-editor/after-confirm"
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder+"/performance.json",FileAccess.WRITE).store_string(JSON.stringify({"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,"stalls":stalls,"map_hash":map_hash,"gpu":RenderingServer.get_video_adapter_name(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"limit":Engine.max_fps}))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/world.png")
	print("EDITED_TRAFFIC_PERF ",stats(frames)," map_unchanged=",map_hash==DATA.disk_hash())
	world.free()
	quit()

