extends "res://tests/measure/measure.gd"
const LAYOUT := preload("res://activities/skate/SkateParkLayout.gd")
var baseline := false
var on_skate := false
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	baseline = "--baseline" in OS.get_cmdline_user_args()
	on_skate = "--ride" in OS.get_cmdline_user_args()
	label = "baseline" if baseline else "after"
	if on_skate: label = "riding"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	Engine.set_meta("skate_benchmark_baseline", baseline)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(2); return
	var session = world.session
	if not session.state.place_id.is_empty(): await session.leave_place()
	session.state.intro.stage = "complete"
	session.weather.time_of_day = .45
	session.weather.weather_state = 0
	session.weather.weather_timer = 1000
	session.weather._update()
	world.player.teleport(LAYOUT.ENTRY + Vector3(.8, .1, 0))
	world.production.region.set_focus(LAYOUT.ENTRY)
	world.player.controlled_automatically = true
	world.player.speed = 0
	world.camera.heading = PI
	world.camera.target_size = 24
	world.camera.initialized = false
	await create_timer(5).timeout
	if on_skate:
		if not session.interact() or not session.skate.mounted: quit(3); return
	# Stable 30 second real frame intervals, including active ordinary population.
	var intervals: Array[float] = []
	var began := Time.get_ticks_usec()
	var last := began
	var mounted_usec := 0
	while Time.get_ticks_usec() - began < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if on_skate and session.skate.mounted: mounted_usec += now - last
		intervals.append((now - last) / 1000.0)
		last = now
		if on_skate and session.skate.mounted:
			var board = session.skate.player_board
			Input.action_press("move_up", .4 if board.speed < 2.2 else 0)
			Input.action_press("move_left", .75)
			if board.position.y < -3: push_error("Skate lost floor"); quit(4); return
	Input.action_release("move_up")
	Input.action_release("move_left")
	var sorted := intervals.duplicate()
	sorted.sort()
	var over33 := 0
	var over66 := 0
	for ms in intervals:
		if ms > 33.3: over33 += 1
		if ms > 66.7: over66 += 1
	var report := {"label": label, "baseline_system_disabled": baseline, "riding": on_skate, "engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps, "population": world.people.size(), "traffic": world.production.vehicles.size(), "ambient": session.skate.ambient.size(), "summary": {"frames": intervals.size(), "seconds": (last - began) / 1000000.0, "fps": intervals.size() * 1000000.0 / (last - began), "p50_ms": sorted[floori(sorted.size() * .50)], "p95_ms": sorted[floori(sorted.size() * .95)], "p99_ms": sorted[floori(sorted.size() * .99)], "max_ms": sorted[-1], "over33": over33, "over66": over66}, "intervals_ms": intervals}
	report["mounted_seconds"] = mounted_usec / 1000000.0
	report["mounted_at_end"] = session.skate.mounted
	DirAccess.make_dir_recursive_absolute("res://evidence/skate-20261001")
	FileAccess.open("res://evidence/skate-20261001/performance-" + label + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SKATE_PERFORMANCE ", JSON.stringify(report.summary))
	world.free()
	quit()
