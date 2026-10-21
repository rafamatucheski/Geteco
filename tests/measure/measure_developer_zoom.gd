extends SceneTree
## Rendered diagnostic: production desert, developer framing, streaming and recovery.
var world: Node3D
var out := "res://artifacts/developer-zoom-streaming-20261021/before"
var samples: Array[float] = []

func _initialize() -> void:
	root.gui_disable_input = true
	run.call_deferred()

func isolate_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_size(Vector2i(1280,720))
	DisplayServer.window_set_position(Vector2i(5000,5000))


func sample(label: String) -> void:
	var times: Array[float] = []
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec() - started < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - previous) / 1000.0)
		previous = now
	var chronological := times.duplicate()
	times.sort()
	var slow33 := 0
	var slow66 := 0
	for value in times:
		if value > 33.3: slow33 += 1
		if value > 66.7: slow66 += 1
	var desired: Dictionary = world.production.region.get("developer_view_cells")
	var missing := 0
	for key in desired:
		if not world.production.region.chunks.has(key): missing += 1
	var result := {"map_cells": desired.size(), "missing_map_cells": missing, "frames": times.size(), "fps": times.size() * 1000000.0 / (previous - started),
		"p50_ms": times[int(times.size()*.5)], "p95_ms": times[int(times.size()*.95)],
		"p99_ms": times[int(times.size()*.99)], "max_ms": times[-1], "over33": slow33, "over66": slow66,
		"chunks": world.production.region.chunks.size(), "pending": world.production.region.pending.size(),
		"jobs": world.production.region.build_jobs.size(), "memory": OS.get_static_memory_usage(),
		"raw_ms": chronological}
	var file := FileAccess.open(out.path_join(label + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result)); file.close()
	result.erase("raw_ms")
	print("ZOOM_MEASURE ", label, " ", JSON.stringify(result))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label + ".png"))

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	create_timer(600, true).timeout.connect(func(): push_error("ZOOM_MEASURE_TIMEOUT"); quit(3))
	isolate_window()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play: await process_frame
	isolate_window()
	world.pause_panel.developer_panel.set_process_input(false)
	world.pause_panel.set_process_unhandled_input(false)
	var tools = world.pause_panel.developer_panel.tools
	print("ZOOM_MEASURE_READY ", world.session.state.region_id)
	await create_timer(5).timeout
	await sample("01-normal")
	tools.set_active(true)
	tools.set_camera_zoom(25, 1)
	tools.overview.stop()
	await create_timer(5).timeout
	await sample("02-wide-baseline")
	tools.set_camera_zoom(25, 1)
	var zoom_started := Time.get_ticks_msec()
	await create_timer(2).timeout
	while not world.production.region.is_streaming_idle() and Time.get_ticks_msec()-zoom_started < 240000:
		await process_frame
	print("ZOOM_LOAD_MS ", Time.get_ticks_msec()-zoom_started, " idle=", world.production.region.is_streaming_idle())
	await create_timer(5).timeout
	await sample("03-wide-loaded")
	tools.reset_camera_zoom()
	tools.set_active(false)
	await create_timer(10).timeout
	await sample("04-restored")
	world.queue_free()
	await process_frame
	quit()
