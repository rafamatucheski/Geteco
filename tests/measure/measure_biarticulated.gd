extends "res://tests/measure/measure.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	seed(28092026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("measure_urban_service",true)
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	if "--without-urban-service" in OS.get_cmdline_user_args():
		var service = world.production.urban_transit.urban_service
		world.production.urban_transit.urban_service = null
		service.queue_free()
		await process_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.session.weather.set_process(false)
	for scenario in [{"id":"station","point":Vector3(110,.1,129),"time":.35,"weather":0},{"id":"junction_night","point":Vector3(180,.1,35),"time":.9,"weather":1}]:
		world.player.teleport(scenario.point)
		world.production._update_physical_residency(world.player.position)
		world.camera.heading = 0
		world.camera.target_size = 65
		world.camera.initialized = false
		world.session.weather.time_of_day = scenario.time
		world.session.weather.weather_state = scenario.weather
		world.session.weather._update()
		var warm: Array[float] = []
		var frames: Array[float] = []
		var cpu_ms := []
		var physics_ms := []
		var began := Time.get_ticks_usec()
		var last := began
		while Time.get_ticks_usec()-began < 38000000:
			await process_frame
			var now := Time.get_ticks_usec()
			if now-began < 8000000: warm.append((now-last)/1000.0)
			else:
				frames.append((now-last)/1000.0)
				cpu_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
				physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
			last = now
		var folder: String = "res://evidence/biarticulated/"+variant+"/"+scenario.id
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		var report := {"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,"cpu_ms":cpu_ms,"physics_ms":physics_ms,"map_hash":preload("res://world/editing/WorldEditData.gd").disk_hash(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps}
		var service = world.production.urban_transit.urban_service
		if is_instance_valid(service):
			report.service_cpu_ms=float(service.measured_usec)/maxi(1,service.measured_ticks)/1000.0
			service.measured_usec=0; service.measured_ticks=0
		FileAccess.open(folder+"/performance.json",FileAccess.WRITE).store_string(JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/world.png")
		print("TRANSIT_PERF ",scenario.id," ",report.summary)
	quit()
