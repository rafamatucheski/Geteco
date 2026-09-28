extends "res://tests/measure/measure.gd"
## Same real Main scene, camera, population and six parcels for both variants.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	seed(26092026)
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	var use_new := "--with-new" in OS.get_cmdline_user_args()
	var kinds := ["urban_setback","urban_twin","urban_slab","urban_deco","urban_infill","urban_podium"]
	var sizes := [Vector2(18,16),Vector2(24,18),Vector2(24,12),Vector2(14,14),Vector2(8,12),Vector2(26,22)]
	var heights := [32.0,36.0,20.0,30.0,18.0,38.0]
	var lowrise := "--lowrise" in OS.get_cmdline_user_args()
	if lowrise:
		kinds = ["house_gable","house_duplex","warehouse_sawtooth","warehouse_loading"]
		sizes = [Vector2(11,12),Vector2(16,12),Vector2(24,30),Vector2(30,22)]
		heights = [6.0,9.0,9.0,10.0]
	var data := preload("res://world/editing/WorldEditData.gd")
	var doc := data.empty_document()
	for i in kinds.size():
		var row := data.new_entity("building",Vector2(-85+i%3*35,80+i/3*35))
		row.id = "new/urban_bench_"+str(i)
		var baseline_kind := ("cobra_house" if i < 2 else "warehouse") if lowrise else "office"
		row.merge({"model":kinds[i] if use_new else baseline_kind,"size":[sizes[i].x,sizes[i].y],"height":heights[i],"color":"9baba8"},true)
		doc.regions.harbor[row.id] = row
	Engine.set_meta("geteco_world_edit_document",doc)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	var settings := root.get_node("V2Settings")
	settings.window_mode = 0
	settings.resolution = 0
	settings.vsync = true
	settings.fps_limit = 1
	settings.apply_settings()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_dispatch",true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play or not world.production.no_save:
		quit(1)
		return
	world.player.controlled_automatically = true
	world.player.teleport(Vector3(-46,.08,49))
	world.camera.set_process_unhandled_input(false)
	world.camera.target_size = 85
	world.camera.size = 85
	world.camera.set_process(false)
	world.camera.position = Vector3(30,95,190)
	world.camera.look_at(Vector3(-50,10,95),Vector3.UP)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.session.weather.set_process(false)
	var folder := "res://evidence/urban-assets-20260926/"+variant
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		push_error("Cannot create benchmark evidence directory")
		quit(2)
		return
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"seed":26092026,"new_assets":use_new,"cases":[]}
	for night in [false,true]:
		if "--night-only" in OS.get_cmdline_user_args() and not night: continue
		world.session.weather.time_of_day = .9 if night else .45
		world.session.weather.weather_state = 1 if night else 0
		world.session.weather._update()
		var warm: Array[float] = []
		var measured: Array[float] = []
		var begin := Time.get_ticks_usec()
		var last := begin
		var total := 0.0
		while Time.get_ticks_usec()-begin < 8000000 or total < 30000:
			await process_frame
			var now := Time.get_ticks_usec()
			var ms := (now-last)/1000.0
			if now-begin < 8000000: warm.append(ms)
			else:
				measured.append(ms)
				total += ms
			last = now
		var scenario := "night-rain" if night else "day"
		var result := {"scenario":scenario,"summary":stats(measured),"warmup":stats(warm),"frames_ms":measured,"warmup_ms":warm,"population":world.people.size(),"vehicles":world.production.vehicles.size(),"camera_size":world.camera.size,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
		report.cases.append(result)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(scenario+".png"))
		FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		print("URBAN_ASSETS_BENCH ",scenario," ",JSON.stringify(result.summary))
	world.free()
	await process_frame
	quit()
