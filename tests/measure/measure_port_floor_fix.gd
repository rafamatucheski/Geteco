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
	var folder := "res://evidence/port-floor-fix-20261014/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var sites := [{"id":"northstar","point":Vector3(204,.1,110),"time":.55},{"id":"santa-mare","point":Vector3(288,.1,186),"time":.55},{"id":"police-day","point":Vector3(67,.1,108),"time":.55}, {"id":"east-day","point":Vector3(392,.1,96),"time":.55}, {"id":"police-rain","point":Vector3(67,.1,108),"time":.55,"weather":1}]
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
	if "--capture" in OS.get_cmdline_user_args(): await capture_port()
	quit()


func capture_port() -> void:
	Engine.max_fps=30
	var folder := "res://evidence/port-floor-fix-20261014/temporal"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var report: Array = []
	for site in [["northstar",Vector3(209,.1,110),26.0],["santa-mare",Vector3(288,.1,186),52.0],["northstar-return",Vector3(209,.1,110),26.0]]:
		world.player.automatic_direction=Vector3.ZERO
		world.player.teleport(site[1])
		world.production.region.set_focus(site[1],true)
		world.camera.heading=0
		world.camera.target_size=site[2]
		world.camera.initialized=false
		for i in 180:
			await process_frame
			if i>60 and world.production.region.is_streaming_idle(): break
		for i in 90:
			world.player.automatic_direction=Vector3.RIGHT if site[0].begins_with("northstar") and i<25 else Vector3.ZERO
			world.camera.heading=float(i)*.001
			await process_frame
			await RenderingServer.frame_post_draw
			var at: Vector3=world.player.global_position
			var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*2,at-Vector3.UP*4,1)
			var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
			var path := "%s/%s-%03d.jpg"%[folder,site[0],i]
			root.get_texture().get_image().save_jpg(path,.90)
			report.append({"site":site[0],"frame":i,"ticks_ms":Time.get_ticks_msec(),"position":str(at),"support":str(hit.get("position","none")),"image":path})
		print("HARBOR_TOUR ",site[0]," at=",world.player.position)
	FileAccess.open(folder+"/frames.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
