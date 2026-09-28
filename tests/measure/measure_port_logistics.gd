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
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	var folder := "res://evidence/port-logistics-20260928/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var sites := [{"id":"port","point":Vector3(298,.1,219)}, {"id":"warehouse","point":Vector3(-6,.1,58)}, {"id":"road","point":Vector3(130,.1,140)}, {"id":"vertice","point":Vector3(-340,.1,-28)}, {"id":"interior","point":Vector3(-305,.1,-66)}, {"id":"forest","point":Vector3(-200,.1,34)}]
	if "--detail-only" in OS.get_cmdline_user_args():
		sites = [{"id":"vertice","point":Vector3(-340,.1,-28)}, {"id":"warehouse-interior","point":Vector3(-340,.1,-74)}, {"id":"night","point":Vector3(-340,.1,-28),"time":.9}, {"id":"rain-interior","point":Vector3(-305,.1,-66),"weather":1}]
	if "--weather-only" in OS.get_cmdline_user_args():
		sites = [{"id":"night","point":Vector3(-340,.1,-28),"time":.9,"weather":0}, {"id":"rain","point":Vector3(-340,.1,-28),"time":.4,"weather":1}]
	if "--rain-only" in OS.get_cmdline_user_args():
		sites = [{"id":"rain","point":Vector3(-340,.1,-28),"time":.4,"weather":1}, {"id":"rain-interior","point":Vector3(-305,.1,-66),"time":.4,"weather":1}]
	if "--undercroft-only" in OS.get_cmdline_user_args():
		sites = [{"id":"undercroft","point":Vector3(-364,.1,-94.2)}]
		if "--night" in OS.get_cmdline_user_args(): sites[0]["time"] = .9
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--site="):
			var selected := arg.trim_prefix("--site=")
			sites = sites.filter(func(site): return site.id==selected)
	for site in sites:
		world.session.weather.time_of_day = site.get("time",.4)
		world.session.weather.weather_state = site.get("weather",0)
		world.session.weather._update()
		world.player.teleport(site.point)
		world.session.weather._process(0)
		world.production.region.set_focus(site.point)
		world.camera.heading = 0
		world.camera.target_size = 62
		world.camera.initialized = false
		if site.id == "undercroft":
			if not await world.session.enter_place("vertice_undercroft",false,"vertice_undercroft"): quit(4); return
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
		print("LOGISTICS_MEASURE ",site.id," ",JSON.stringify(report.summary))
	if "--undercroft-only" in OS.get_cmdline_user_args(): quit(); return
	# Authored overview is a review photograph only, outside timing samples.
	world.player.teleport(Vector3(-340,.1,-50))
	world.production.region.set_focus(world.player.position)
	for i in 90: await process_frame
	var review := Camera3D.new()
	review.projection = Camera3D.PROJECTION_ORTHOGONAL
	review.size = 110
	world.add_child(review)
	review.global_position = Vector3(-245,88,42)
	review.look_at(Vector3(-340,0,-59))
	review.make_current()
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/vertice-overview.png")
	quit()
