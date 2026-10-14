extends "res://tests/measure/measure.gd"
## Rendered A/B/C and night comparison in production Main; never saves.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var variant := "before"
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	var folder := "res://evidence/coastal-weather-20261013/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	seed(13102026)
	root.size = Vector2i(1280,720)
	DisplayServer.window_move_to_foreground()
	world = load("res://Main.tscn").instantiate()
	print("COASTAL_BENCH_SCRIPTS_LOADED")
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 3600:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.player.teleport(Vector3(66,.15,129))
	world.production.region.set_focus(world.player.position)
	world.camera.heading = 0
	world.camera.target_size = 48
	world.camera.initialized = false
	var weather = world.session.weather
	weather.weather_timer = 100000
	var report := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"seed":13102026,"cases":[]}
	report.source_hashes = {}
	for path in ["res://world/city_look/CoastalPlanarReflections.gd","res://world/city_look/CoastalFacadeBatches.gd","res://runtime/Settings.gd","res://scripts/CameraRig.gd","res://scripts/Vehicle.gd","res://runtime/ProductionWorld.gd"]:
		report.source_hashes[path] = FileAccess.get_sha256(path)
	var settings := root.get_node("V2Settings")
	report.settings = {"shadows":settings.shadow_quality,"atlas":settings.SHADOW_ATLAS[settings.shadow_quality],"msaa":root.msaa_3d,"scale":root.scaling_3d_scale}
	var planar: Node = world.get_node("CityLook/CoastalPlanarReflections")
	# Diagnostic only: compare with the same world/materials and capture manager
	# suspended. Never changes the saved settings or production defaults.
	var without_planar := "--without-planar" in OS.get_cmdline_user_args()
	if without_planar:
		planar.set_process(false)
		planar._disable()
	report.without_planar = without_planar
	var views := [root,planar.ground_view,planar.facade_view]
	for view in views: RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	var cases := [["a-dry",.72,0],["b-marine",.72,3],["c-rain",.45,1],["night-rain",.93,1]]
	var isolate_planar := "--isolate-planar" in OS.get_cmdline_user_args()
	if isolate_planar:
		cases = [["c-rain-on-1",.45,1],["c-rain-off-1",.45,1],["c-rain-on-2",.45,1],["c-rain-off-2",.45,1]]
	elif "--append-isolation" in OS.get_cmdline_user_args():
		isolate_planar = true
		cases.append_array([["c-rain-on-1",.45,1],["c-rain-off-1",.45,1],["c-rain-on-2",.45,1],["c-rain-off-2",.45,1]])
	for entry in cases:
		if not only.is_empty() and entry[0] not in only.split(","): continue
		if isolate_planar:
			without_planar = "-off-" in entry[0]
			planar.set_process(not without_planar)
			if without_planar: planar._disable()
		weather.time_of_day = entry[1]
		weather.weather_state = entry[2]
		weather.rain_intensity = .25
		if weather.get("coastal_wetness") != null: weather.coastal_wetness = 1.0 if entry[2]==1 else 0.0
		# Settle weather before timing; the dedicated transition capture observes fades.
		for i in 200:
			weather.atmosphere_step = .2
			weather._update()
		var puddles = world.get_node_or_null("RainPuddles")
		if puddles != null: puddles.wetness = 1.0 if entry[2]==1 else 0.0
		var warm: Array[float] = []
		var measured: Array[float] = []
		var profiles := {"cpu":[],"physics":[],"main_gpu":[],"ground_gpu":[],"facade_gpu":[],"render_cpu":[],"draws":[],"coastal_cpu":[],"batch_cpu":[],"dynamic_cpu":[],"registration_cpu":[],"batch_rebuilds":[],"hidden_dynamic":[]}
		var rebuild_names := {}
		var unfocused_frames := 0
		var begin := Time.get_ticks_usec()
		var last := begin
		while Time.get_ticks_usec()-begin < 38000000:
			await process_frame
			var now := Time.get_ticks_usec()
			if now-begin<8000000: warm.append((now-last)/1000.0)
			else:
				measured.append((now-last)/1000.0)
				if not DisplayServer.window_is_focused(): unfocused_frames += 1
				profiles.cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
				profiles.physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
				profiles.main_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
				profiles.ground_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(planar.ground_view.get_viewport_rid()))
				profiles.facade_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(planar.facade_view.get_viewport_rid()))
				profiles.render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
				profiles.draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				profiles.coastal_cpu.append(0.0 if without_planar else float(planar.last_process_usec)/1000.0)
				profiles.batch_cpu.append(0.0 if without_planar else float(planar.last_batch_usec)/1000.0)
				profiles.dynamic_cpu.append(0.0 if without_planar else float(planar.last_dynamic_usec)/1000.0)
				profiles.registration_cpu.append(0.0 if without_planar else float(planar.last_registration_usec)/1000.0)
				profiles.batch_rebuilds.append(0 if without_planar else planar.last_batch_rebuilds)
				profiles.hidden_dynamic.append(0 if without_planar else planar.last_hidden_dynamic_count)
				if not without_planar:
					for batch_name in planar.last_rebuilt_batch_names: rebuild_names[batch_name] = int(rebuild_names.get(batch_name,0))+1
			last = now
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+entry[0]+".png")
		var entry_report := {"id":entry[0],"time":entry[1],"weather":entry[2],"population":world.people.size(),"position":str(world.player.position),"camera_size":world.camera.size,"camera_position":str(world.camera.global_position),"summary":stats(measured),"warmup":stats(warm),"frames_ms":measured,"warmup_ms":warm}
		entry_report.profiles = profiles
		entry_report.unfocused_frames = unfocused_frames
		entry_report.rebuilt_batches = rebuild_names
		entry_report.without_planar = without_planar
		entry_report.reflections = {"registered":planar._registered.size(),"dynamic":planar._dynamic.size(),"batches":planar._batches.size(),"facade_visible":planar._facade_visible}
		entry_report.profile_summary = {}
		for key in profiles:
			var sorted: Array = profiles[key].duplicate()
			sorted.sort()
			entry_report.profile_summary[key] = {"p50":sorted[sorted.size()/2],"p95":sorted[int(sorted.size()*.95)],"max":sorted[-1]}
		report.cases.append(entry_report)
		FileAccess.open(folder+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		print("COASTAL_WEATHER ",entry[0]," ",JSON.stringify(entry_report.summary))
	world.queue_free()
	await process_frame
	quit()
