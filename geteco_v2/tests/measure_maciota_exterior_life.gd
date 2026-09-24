extends SceneTree
## A/B at the real Main.tscn garage approach. No save writes.

var world: Variant
var details: Array[Node3D] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	if output.is_empty():
		quit(2)
		return
	seed(22092026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.weather != null:
			break
	if world.production == null or not world.production.ready_for_play or world.session == null or world.session.weather == null:
		push_error("Maciota benchmark world did not finish loading")
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	for frame in 3:
		await process_frame
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	var point: Vector3 = world.maciota_place.exterior_return + Vector3(0, .08, 2.5)
	world.production._update_physical_residency(point)
	world.production._update_logical_region(point)
	world.player.teleport(point)
	world.camera.heading = 0.0
	world.camera.target_size = 24.0
	world.camera.focus = point
	world.camera.initialized = true
	world.session.weather.time_of_day = .84
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	for child in world.maciota_place.facade.get_children():
		if child.name == "MaciotaExteriorDetails" or child.name == "MaciotaName" or str(child.name).begins_with("MaciotaWorkLamp"):
			details.append(child)
	if details.size() != 4:
		push_error("Expected four dress nodes, found %d" % details.size())
		quit(1)
		return
	var cases := []
	for enabled in [false, true, false]:
		for child in details:
			child.visible = enabled
		var warmup := await sample(5.0)
		var stable := await sample(30.0)
		cases.append({"dressed": enabled, "warmup": warmup, "stable": stable, "draw_calls_last_frame": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		print("MACIOTA_EXTERIOR_BENCHMARK ", "dressed" if enabled else "undressed", " ", JSON.stringify(stable.summary))
	var report := {
		"scene": "res://Main.tscn", "location": "Maciota exterior return + 2.5 m south", "cases": cases,
		"engine": Engine.get_version_info().string, "gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size),
		"vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"population": world.people.size(), "traffic": world.production.vehicles.size(),
		"time_of_day": world.session.weather.time_of_day,
		"camera_heading": world.camera.heading, "camera_size": world.camera.size,
		"notes": "A/B/A in one rendered process; undressed hides only the four new visual nodes. Other Godot processes must be inventoried separately."
	}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Could not write benchmark report: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	world.queue_free()
	await process_frame
	quit()


func sample(seconds: float) -> Dictionary:
	var values: Array[float] = []
	var focused := 0
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(seconds * 1000000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		values.append(float(now - last) / 1000.0)
		last = now
		if DisplayServer.window_is_focused():
			focused += 1
	return {"summary": stats(values), "frame_intervals_ms": values, "focused_frames": focused, "focus_ratio": float(focused) / maxf(1.0, float(values.size()))}


func stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var over_33 := 0
	var over_66 := 0
	for value in values:
		total += value
		if value > 33.3:
			over_33 += 1
		if value > 66.7:
			over_66 += 1
	return {"frames": values.size(), "seconds": total / 1000.0, "fps": float(values.size()) * 1000.0 / total, "p50_ms": sorted[int((sorted.size() - 1) * .50)], "p95_ms": sorted[int((sorted.size() - 1) * .95)], "p99_ms": sorted[int((sorted.size() - 1) * .99)], "max_ms": sorted[-1], "over_33_3_ms": over_33, "over_66_7_ms": over_66}
