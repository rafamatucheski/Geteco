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
	var folder := "res://evidence/harbor-material-diversity-20261014/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var sites := [{"id":"civic","point":Vector3(67,.1,108),"time":.55},{"id":"foundry","point":Vector3(59,.1,52),"time":.55},{"id":"promenade","point":Vector3(392,.1,96),"time":.55}]
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
	if "--visual-check" in OS.get_cmdline_user_args():
		for view in [{"id":"foundry_night","time":.05,"weather":0},{"id":"foundry_rain","time":.55,"weather":2}]:
			world.player.teleport(Vector3(59,.1,52))
			world.production.region.set_focus(Vector3(59,.1,52))
			world.session.weather.time_of_day = view.time
			world.session.weather.weather_state = view.weather
			world.session.weather._update()
			world.session.weather._process(0)
			world.camera.heading = 0
			world.camera.target_size = 52
			world.camera.initialized = false
			await create_timer(4).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/"+view.id+".png")
		world.session.weather.weather_state = 0
		world.session.weather._update()
		world.session.weather._process(0)
		var toned := {}
		for mesh in world.find_children("*","MeshInstance3D",true,false):
			if not mesh.has_meta("harbor_facade_tone"): continue
			var building = mesh.get_parent()
			while building != null and not building is UrbanBuildingBase: building = building.get_parent()
			if building != null: toned[building.building_id] = int(toned.get(building.building_id,0))+1
		FileAccess.open(folder+"/facade_instances.json",FileAccess.WRITE).store_string(JSON.stringify(toned))
		var movement := []
		world.player.automatic_direction = Vector3.RIGHT
		# Continuous rendered frames document the material seam in motion.
		for frame in 120:
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/motion_%03d.png"%frame)
			movement.append({"frame":frame,"usec":Time.get_ticks_usec(),"position":str(world.player.global_position)})
		world.player.automatic_direction = Vector3.ZERO
		FileAccess.open(folder+"/motion.json",FileAccess.WRITE).store_string(JSON.stringify(movement))
	quit()
