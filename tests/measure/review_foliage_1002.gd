extends SceneTree
var world
var folder: String
var tag := "before"
var samples: Array[float] = []
var capture_times: Array[float] = []
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await process_frame
func place(point: Vector3) -> void:
	world.production._update_physical_residency(point)
	world.player.teleport(point + Vector3.UP * .3)
	world.production._update_logical_region(point)
	world.production.region.set_focus(point)
	world.camera.focus = point
	world.camera.global_position = point + Vector3(0,34,24)
	world.camera.look_at(point)
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if label.begins_with("motion_"):
		frame.save_jpg(folder.path_join(label+".jpg"), .82)
	else:
		frame.save_png(folder.path_join(label+".png"))
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	folder = "D:/geteco/artifacts/foliage-1002/"+tag
	DirAccess.make_dir_recursive_absolute(folder)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	world.production.set_process(false)
	world.player.set_physics_process(false)
	world.camera.set_process(false)
	world.camera.set_process_unhandled_input(false)
	world.camera.size = 24
	world.camera.locked = true
	world.camera.make_current()
	world.session.weather.time_of_day = .5
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	world.hud.hide()
	var sites := {"promenade":Vector3(320,0,149),"park":Vector3(370,0,119)}
	for label in sites:
		place(sites[label])
		await frames(120)
		for i in 1200:
			await process_frame
			if world.production.region.pending.is_empty(): break
		await frames(30)
		await shot(label)
		print("REVIEW_SITE ",label," ",sites[label])
	place(Vector3(330.625,0,152))
	world.camera.global_position = Vector3(330.625,34,174.31)
	world.camera.look_at(Vector3(330.625,.6,150.31))
	world.camera.size = 8
	await frames(60)
	await shot("bench-detail")
	world.camera.size = 24
	if "--visual-only" in OS.get_cmdline_user_args():
		print("FOLIAGE_VISUAL_CAPTURE_COMPLETE")
		quit()
		return
	# Fixed-camera sample in the real city scene.
	var start_point: Vector3 = sites.values()[0]
	place(start_point)
	await frames(120)
	var started := Time.get_ticks_usec()
	var previous := started
	var next_capture := 0.0
	var capture_index := 0
	while Time.get_ticks_usec()-started < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-previous)/1000.0)
		previous = now
		var elapsed := float(now-started)/1000000.0
		pass # Fixed camera keeps the same foliage and city load throughout sampling.
		if "--temporal" in OS.get_cmdline_user_args() and elapsed >= next_capture:
			await shot("motion_%03d" % capture_index)
			capture_times.append(float(Time.get_ticks_usec()-started)/1000000.0)
			capture_index += 1
			next_capture = elapsed+1.0/30.0
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for s in samples:
		total += s
		if s>33.3: over33+=1
		if s>66.7: over66+=1
	var report := {"tag":tag,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"frames":samples.size(),"duration_ms":total,"fps":samples.size()*1000.0/total,"p50_ms":sorted[int((sorted.size()-1)*.5)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted[-1],"over33":over33,"over66":over66,"capture_times_s":capture_times,"benchmark_valid":capture_times.is_empty(),"sites":sites}
	var f := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"))
	print("FOLIAGE_REVIEW ",JSON.stringify(report))
	quit()
