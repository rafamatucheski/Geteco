extends "res://tests/measure/measure.gd"
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var variant := "before"
	var selected := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
		if arg.begins_with("--sites="): selected = arg.trim_prefix("--sites=").split(",")
	seed(28092026)
	if "--native-res" not in OS.get_cmdline_user_args(): root.size = Vector2i(1280,720)
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
	var folder := "res://evidence/harbor-rebuild-20261013/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var sites := [{"id":"police-day","point":Vector3(67,.1,108),"time":.55}, {"id":"east-day","point":Vector3(392,.1,96),"time":.55}, {"id":"police-rain","point":Vector3(67,.1,108),"time":.55,"weather":1}]
	if "--districts" in OS.get_cmdline_user_args(): sites.clear()
	if "--districts" in OS.get_cmdline_user_args() or "--all-sites" in OS.get_cmdline_user_args():
		sites.append_array([{"id":"skate","point":Vector3(381,.1,132.5),"time":.55},{"id":"cobra","point":Vector3(481.25,.1,106.25),"time":.55},{"id":"port","point":Vector3(296,.1,212),"time":.55},{"id":"cemetery","point":Vector3(-40.625,.1,82),"time":.55}])
	for site in sites:
		if not selected.is_empty() and site.id not in selected: continue
		world.session.weather.time_of_day = site.time
		world.session.weather.weather_state = site.get("weather",0)
		world.session.weather._update()
		world.player.teleport(site.point)
		world.session.weather._process(0)
		world.production.region.set_focus(site.point)
		world.camera.heading = 0
		world.camera.target_size = 52
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
		report["site"] = site.id
		report["position"] = str(world.player.global_position)
		report["weather"] = site.get("weather",0)
		report["camera_size"] = 52
		report["engine"] = Engine.get_version_info().string
		FileAccess.open(folder+"/"+site.id+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+site.id+".png")
		print("HARBOR_MEASURE ",site.id," ",JSON.stringify(report.summary))
	quit()
