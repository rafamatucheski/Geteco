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
	var folder := "res://evidence/desert-floor-fix-20261014/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var sites := [{"id":"paddock","point":Vector3(-970,.1,-1262),"time":.55},{"id":"truck-apron","point":Vector3(240,.1,-750),"time":.55},{"id":"digo-apron","point":Vector3(-130,.1,-905),"time":.55}]
	if "--port-confirm" in OS.get_cmdline_user_args():
		sites.push_front({"id":"northstar-confirm","point":Vector3(204,.1,110),"time":.55,"region":"harbor"})
	for site in sites:
		if not selected.is_empty() and site.id not in selected: continue
		if site.get("region","desert")=="desert" and world.production.region.region_id!="desert":
			await world.production._travel_checked("desert",Vector3(-970,.1,-1262))
			if world.production.region.region_id!="desert": quit(4); return
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
		print("DESERT_MEASURE ",site.id," ",JSON.stringify(report.summary))
		if site.id=="northstar-confirm":
			world.player.teleport(Vector3(209,.1,110))
			world.production.region.set_focus(Vector3(209,.1,110),true)
			world.player.automatic_direction=Vector3.RIGHT
			await create_timer(2.5).timeout
			world.player.automatic_direction=Vector3.ZERO
			await RenderingServer.frame_post_draw
			var position: Vector3=world.player.global_position
			var support: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position+Vector3.UP*.2,position-Vector3.UP*2,1))
			root.get_texture().get_image().save_png(folder+"/northstar-crossing.png")
			FileAccess.open(folder+"/northstar-crossing.json",FileAccess.WRITE).store_string(JSON.stringify({"position":str(position),"support":str(support.get("position","none")),"crossed":position.x>212.0,"time_seconds":2.5}))
	if "--capture" in OS.get_cmdline_user_args():
		if world.production.region.region_id!="desert": await world.production._travel_checked("desert",Vector3(-970,.1,-1262))
		var ok: bool=await preload("res://tests/capture/capture_desert_floor_fix.gd").capture(self,world)
		if not ok: quit(5); return
	quit()
