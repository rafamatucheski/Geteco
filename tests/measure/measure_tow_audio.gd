extends "res://tests/measure/measure_drag_ui.gd"
## Identical Main scene and real tow transitions before/after event wiring.
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	seed(7102026)
	root.size = Vector2i(1280,720)
	output = FIXTURE.output_dir("tow-audio")
	var at := Vector3(-37.0,.12,61.0)
	var data: Dictionary = FIXTURE.full_snapshot(at+Vector3(6,0,0),true)
	data.campaign = FIXTURE.prefix(1)
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path: quit(1); return
	world.dispatch.router.nearest_edge(at)
	if world.dispatch.router._native==null: quit(1); return
	if world.session.modal: world.session.close_menu()
	var mission = world.session.mission_world
	var job: Dictionary = preload("res://data/catalogs/TowJobs.gd").JOBS[0].duplicate(true)
	job.merge({"index":0,"token":"tow_1"})
	# Fixture starts with the customer already beside the truck, in the active
	# region. The measured load/unload still uses the production physical gate.
	mission.tow_job = job
	mission.truck = world.production.spawn_vehicle("towmaster",at,PI)
	if mission.truck == null: push_error("tow benchmark truck setup rejected"); quit(1); return
	mission.truck.set_physics_process(false)
	mission.cargo = world.production.spawn_vehicle("ranch_single",mission.truck.to_global(Vector3(0,.1,mission.truck.half_length+2)),PI)
	if mission.cargo == null: push_error("tow benchmark cargo setup rejected"); quit(1); return
	mission.cargo.engine_disabled = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	world.session.weather.time_of_day = .45
	await hold(8)
	var successful := 0
	begin_sample()
	for i in 15:
		if mission._tow_toggle(): successful += 1
		await hold(2.0)
	end_sample("tow-transitions")
	results.environment = {"size":"1280x720","vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"renderer":RenderingServer.get_current_rendering_method(),"successful_toggles":successful,"expected_toggles":15,"mission_sha256":FileAccess.get_sha256("res://runtime/MissionWorld.gd"),"bridge_sha256":FileAccess.get_sha256("res://audio/v1_ambience/ActivityAudioBridge.gd")}
	var file := FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results))
	file.close()
	print("TOW_AUDIO_METRICS ",output," successful=",successful)
	world.queue_free()
	await process_frame
	quit(0 if successful==15 else 1)
