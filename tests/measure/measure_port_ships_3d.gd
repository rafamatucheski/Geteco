extends "res://tests/measure/measure.gd"
## Rendered Main scene: fixed harbor views, then a 30 s south-port frame sample.
## Run with --no-save --skip-arrival --benchmark --population=24.
var output_root := "user://port-ships-v2"
var safe_port := false

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	label = "port-ships-v2"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=").validate_filename()
		if arg.begins_with("--output="): output_root = arg.trim_prefix("--output=")
		if arg == "--safe-port": safe_port = true
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root)) == OK)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1200:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		quit(1)
		return
	world.player.controlled_automatically = true
	if safe_port:
		world.player.set_physics_process(false)
		world.player.collision_layer = 0
		world.player.collision_mask = 0
		world.session.urban_operations.security.set_process(false)
		world.gameplay.set_process(false)
		world.gameplay.set_physics_process(false)
	world.camera.set_process_unhandled_input(false)
	world.session.weather.time_of_day = 0.32
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 1000
	world.session.weather._update()
	await _capture("northstar",Vector3(223,0.08,104),58.0)
	await _capture("santa-mare",Vector3(298,0.08,206),62.0)
	var origin := Vector3(298,0.08,220 if safe_port else 216)
	world.player.teleport(origin)
	world.production.region.set_focus(origin)
	world.camera.heading = 0.0
	world.camera.target_size = 58.0
	world.camera.initialized = false
	route = PackedVector3Array([origin,origin+Vector3(3,0,0)])
	world.player.speed = 1.5
	for i in 120: await process_frame
	started = Time.get_ticks_usec()
	previous = started

func _capture(id: String, focus: Vector3, view_size: float) -> void:
	world.player.teleport(focus)
	world.production.region.set_focus(focus)
	world.camera.heading = 0.0
	world.camera.target_size = view_size
	world.camera.initialized = false
	for i in 120: await process_frame
	await RenderingServer.frame_post_draw
	var path := output_root.path_join("%s-%s.png" % [label,id])
	var error := root.get_texture().get_image().save_png(path)
	assert(error == OK)
	print("PORT_SHIP_CAPTURE ",path)

func finish() -> void:
	var summary := stats(samples)
	var phases: Array[String] = []
	if world.session != null and world.session.urban_operations != null:
		for truck in world.session.urban_operations.cargo_handling.work_trucks: phases.append(str(truck.phase))
	var report := {
		"label":label,
		"engine":Engine.get_version_info().string,
		"gpu":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(),
		"resolution":str(root.size),
		"population":world.people.size(),
		"player_health_end":world.gameplay.health,
		"cargo_active_end":world.session.urban_operations.cargo_handling.active,
		"truck_phases_end":phases,
		"safe_port":safe_port,
		"vsync":DisplayServer.window_get_vsync_mode(),
		"max_fps":Engine.max_fps,
		"summary":summary,
		"warmup":stats(cold),
		"cpu_process":stats(cpu),
		"physics":stats(physics),
		"frame_intervals_ms":samples,
		"draw_calls_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	}
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_root.path_join(label+".png"))
	var file := FileAccess.open(output_root.path_join(label+".json"),FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("BENCHMARK ",label," ",JSON.stringify(summary))
	world.queue_free()
	await process_frame
	quit()
