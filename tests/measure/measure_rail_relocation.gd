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
	var folder := "res://evidence/rail-relocation-20261014/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var sites := [{"id":"footbridge","point":Vector3(120,.1,78),"time":.55},{"id":"neco","point":Vector3(-24,.12,64),"time":.55},{"id":"northgate","point":Vector3(374,.12,-167),"time":.55}]
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
	if variant != "before" and "--benchmark-only" not in OS.get_cmdline_user_args():
		for site in [{"id":"station_platform","point":Vector3(-16.4,12.95,52),"size":52,"time":.55},{"id":"station_night","point":Vector3(-24,.12,64),"size":52,"time":.92}]:
			world.session.weather.time_of_day=site.time
			world.session.weather._update()
			world.player.teleport(site.point)
			world.production.region.set_focus(site.point,true)
			world.camera.target_size=site.size
			world.camera.initialized=false
			await create_timer(3).timeout
			for frame in 6:
				world.camera.heading=float(frame)*.025
				await create_timer(.25).timeout
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder+"/"+site.id+"-%02d.png"%frame)
		if "--night-sequence" in OS.get_cmdline_user_args():
			var sequence_dir := folder+"/night-sequence"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sequence_dir))
			var original_cap := Engine.max_fps
			Engine.max_fps=30
			var timeline: Array=[]
			var sequence_start := Time.get_ticks_msec()
			var frame := 0
			while Time.get_ticks_msec()-sequence_start<30000:
				var elapsed := (Time.get_ticks_msec()-sequence_start)/1000.0
				world.camera.heading=0.0 if elapsed<10 else sin((elapsed-10)*.5)*.10
				if elapsed>20:
					world.player.automatic_direction=Vector3.LEFT if elapsed<24 else Vector3.RIGHT if elapsed<28 else Vector3.ZERO
				await process_frame
				await RenderingServer.frame_post_draw
				var stamp := Time.get_ticks_msec()
				root.get_texture().get_image().save_jpg(sequence_dir+"/%04d.jpg"%frame,.82)
				timeline.append({"frame":frame,"ms":stamp-sequence_start,"point":str(world.player.global_position),"heading":world.camera.heading})
				frame+=1
			world.player.automatic_direction=Vector3.ZERO
			Engine.max_fps=original_cap
			FileAccess.open(sequence_dir+"/timeline.json",FileAccess.WRITE).store_string(JSON.stringify(timeline))
	quit()
