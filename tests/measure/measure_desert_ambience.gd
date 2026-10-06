extends "res://tests/measure/measure_desert.gd"
## Paired on/off diagnostic in actual Main; retains population, weather and camera.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--benchmark" not in OS.get_cmdline_user_args() or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		quit(2)
		return
	seed(6102026)
	root.size = Vector2i(1280,720)
	output = FIXTURE.output_dir("desert-ambience")
	var snapshot := FIXTURE.full_snapshot(Vector3(300,.08,-742),true)
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region":"desert","position":[300,.08,-742]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): quit(1); return
	fingerprint = source_fingerprint()
	for file in ["res://audio/WorldAudio.gd", "res://audio/desert_ambience/DesertAmbience.gd"]: fingerprint[file] = FileAccess.get_sha256(file)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session == null or not world.session.ready_for_play or world.production.store.path != path: quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: quit(1); return
	var mix = world.find_child("DesertAmbience",true,false)
	if mix == null: push_error("Desert mix missing from real WorldAudio"); quit(1); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.god_mode = true
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	var normal := "--normal-cap" in OS.get_cmdline_user_args()
	if normal:
		Engine.max_fps = 60
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var setups := [{"id":"truckstop-day","point":Vector3(300,.08,-742),"hour":.45}, {"id":"town-night","point":Vector3(-185,.08,-890),"hour":.9}]
	if normal: setups = [setups[1]]
	for setup in setups:
		world.production.region.set_focus(setup.point)
		world.production.region.prepare_collision_at(setup.point)
		await physics_frame
		world.player.teleport(setup.point)
		world.session.weather.time_of_day = setup.hour
		world.session.weather._update()
		for active in ([true] if normal else [false, true]):
			mix.enabled = active
			mix.set_process(active)
			if not active:
				mix.wind.stop()
				mix.detail.stop()
				mix.gain = 0.0
			await create_timer(10).timeout
			await measure(setup.id + ("-on" if active else "-off"))
			if mix.wind.playing != active: push_error("Incorrect real wind activation"); quit(1); return
	# Ordinary interior entry/exit exercises the same mix attached to the real session.
	var definition := preload("res://world/places/PlaceCatalog.gd").get_definition("desert_bank")
	world.production.region.set_focus(definition.entry_position)
	world.production.region.prepare_collision_at(definition.entry_position)
	await physics_frame
	world.player.teleport(definition.entry_position + Vector3.UP * 0.08)
	if not await world.session.enter_place("desert_bank", false): quit(1); return
	await create_timer(6).timeout
	if mix.detail.playing or mix.gain > 0.13: push_error("Interior audio attenuation failed"); quit(1); return
	if not await world.session.leave_place(): quit(1); return
	await create_timer(6).timeout
	if not mix.wind.playing or mix.gain < 0.9: push_error("Exterior audio recovery failed"); quit(1); return
	var stable := fingerprint == source_fingerprint(fingerprint)
	var report := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"source_stable":stable,"source_start":fingerprint,"source_end":source_fingerprint(fingerprint),"scenarios":reports,"notes":"Paired diagnostic: desert audio disabled/enabled in live Main .NET. Population is live, not deterministic. 10s settling then 30s samples; no auditory quality certification."}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DESERT_AMBIENCE_MEASURE ", output, " stable=", stable)
	quit(0 if stable else 1)
