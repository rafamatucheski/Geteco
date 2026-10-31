extends "res://tests/measure/measure_amusement_park.gd"
## Mesmos cenários integrados de estação/passeio antes e depois da revisão da montanha-russa.
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(180).timeout.connect(func(): quit(3))
	seed(100726)
	label = "before" if "--before" in OS.get_cmdline_user_args() else "after"
	folder = FIXTURE.output_dir("coaster-"+label)
	source_before = fingerprints()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"save.json",FIXTURE.full_snapshot(Vector3(166,.08,112.8),false)))
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.session.state.economy.grant_reward("coaster_measure",100)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: quit(5); return
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	var point := Vector3(-183,.16,93)
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	world.player.teleport(point)
	world.session.amusement_park._update_residency()
	await sample("first_visit",8)
	await sample("warmup",5)
	var overview := Camera3D.new()
	world.add_child(overview)
	overview.global_position = Vector3(-198,52,114)
	overview.look_at(Vector3(-198,0,73))
	overview.make_current()
	await sample("station_warmup",3)
	await sample("station",30)
	await capture("station")
	world.camera.make_current()
	overview.queue_free()
	var park = world.session.amusement_park
	if not park.start_ride(): quit(6); return
	await sample("ride_warmup",3)
	phase = "ride"
	last_tick = Time.get_ticks_usec()
	tracing = true
	var end := Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<end:
		if not park.active and not park.start_ride(): quit(7); return
		await process_frame
	tracing = false
	await capture("ride")
	park.leave()
	var summary := {}
	for key in intervals:
		var values: Array[float] = []
		values.assign(intervals[key])
		if not values.is_empty(): summary[key] = stats(values)
	var report := {"label":label,"summary":summary,"samples_ms":intervals,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"people":world.people.size(),"cars":world.production.vehicles.size(),"native":world.dispatch.router._native!=null,"source_before":source_before,"source_after":fingerprints()}
	report.source_stable = report.source_before == report.source_after
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COASTER_MEASURE ",folder," ",JSON.stringify(summary))
	quit()
