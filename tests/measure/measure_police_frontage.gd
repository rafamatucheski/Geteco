extends "res://tests/measure/measure.gd"
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var after := "--after" in OS.get_cmdline_user_args()
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
	var definition := preload("res://world/places/PlaceCatalog.gd").get_definition("harbor_police")
	var door: Vector3 = world.session.weapon_shop_entrance._door_position("harbor_police",definition)
	world.player.teleport(Vector3(68,.1,138))
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
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec()-start < 38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if now-start < 8000000: warm.append((now-last)/1000.0)
		else: frames.append((now-last)/1000.0)
		last = now
	var folder := "res://evidence/police-frontage-20260928/"+("after" if after else "before")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm}
	FileAccess.open(folder+"/performance.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/benchmark.png")
	print("POLICE_FRONTAGE_MEASURE ",JSON.stringify(report.summary))
	quit()

