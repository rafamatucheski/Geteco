extends "res://tests/measure/measure.gd"
## Serial, rendered Main-scene comparison for the session-log lifecycle fixes.
## Teleports establish each diagnostic site; they do not validate access routes.
var results: Array[Dictionary] = []

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=").validate_filename()
	create_timer(240).timeout.connect(func(): push_error("Lifecycle measurement timed out"); quit(3))
	seed(10102026)
	Engine.set_meta("geteco_world_edit_document",preload("res://world/editing/WorldEditData.gd").empty_document())
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play:
		await process_frame
	assert(world.production.no_save)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.set_process_input(false)
	world.session.set_process_unhandled_input(false)
	world.camera.set_process_unhandled_input(false)
	world.session.state.economy.grant_outfit("dante_ski")
	world.session.state.economy.equip_outfit("dante_ski")
	world.session.apply_outfit()
	world.session.weather.time_of_day = .35
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for site in [
		{"id":"terminal","position":Vector3(106.25,.1,72)},
		{"id":"cemetery","position":Vector3(-40.625,.1,99)},
		{"id":"forge","position":Vector3(716,.1,-339)}]:
		world.player.teleport(site.position)
		world.production._update_physical_residency(site.position)
		world.production._update_logical_region(site.position)
		world.camera.heading = 0
		world.camera.target_size = 32
		world.camera.initialized = false
		await sample_site(site.id)
	var report := {"label":label,"engine":Engine.get_version_info().string,
		"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"resolution":str(root.size),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),
		"notes":"Main scene, normal directors; seeded start; fixed daylight/weather; 10s warmup + 30s per site; teleported setup; no-save", "sites":results}
	FileAccess.open("res://evidence/"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	world.queue_free()
	await process_frame
	await process_frame
	quit()

func _process(_delta: float) -> bool:
	return false

func sample_site(site: String) -> void:
	var values: Array[float] = []
	var warmup: Array[float] = []
	var gpu_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var process_ms: Array[float] = []
	var focused := 0
	var began := Time.get_ticks_usec()
	var previous := began
	while Time.get_ticks_usec()-began < 40000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now-previous)/1000.0
		previous = now
		if now-began < 10000000:
			warmup.append(ms)
			continue
		values.append(ms)
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		if DisplayServer.window_is_focused(): focused += 1
	var report := {"site":site,"summary":stats(values),"warmup":stats(warmup),
		"frame_ms":values,"warmup_ms":warmup,"gpu_ms":stats(gpu_ms),"physics_ms":stats(physics_ms),"process_ms":stats(process_ms),
		"focused_frames":focused,"people":world.people.size(),"cars":world.production.vehicles.size(),
		"position":str(world.player.global_position),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"native_router":world.dispatch.router.get("_native") != null}
	results.append(report)
	print("LIFECYCLE_PERF ",site," ",JSON.stringify(report.summary))
