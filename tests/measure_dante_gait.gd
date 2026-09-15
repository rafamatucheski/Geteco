extends SceneTree

## Rendered 30-second native walk/sprint route in HarborGame.
## Run without --headless so GPU/frame-time results remain meaningful.
const GAME_PATH := "res://world/harbor/HarborGame.tscn"
const PREVIEW_PATH := "res://world/harbor/HarborPreview.tscn"
const WARMUP_FRAMES := 120
const SAMPLE_USEC := 30_000_000

var _out_dir := "D:/geteco/artifacts/dante-gait-0913"
var _label := "sample"
var _use_preview := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			_out_dir = arg.trim_prefix("out_dir=")
		elif arg.begins_with("label="):
			_label = arg.trim_prefix("label=")
		elif arg == "--preview":
			_use_preview = true

	seed(12092026)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)

	var packed := load(PREVIEW_PATH if _use_preview else GAME_PATH) as PackedScene
	var world := packed.instantiate()
	root.add_child(world)
	current_scene = world
	if not _use_preview:
		while not world.gameplay_ready:
			await process_frame
	else:
		for i in 90:
			await process_frame

	var player: Node2D = world.get_node("Player")
	player.global_position = Vector2(1700, 1130)
	var car: CharacterBody2D = world.get_node("PlayerCar")
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	world.call("_walk")
	for i in WARMUP_FRAMES:
		await process_frame

	var frame_ms: Array[float] = []
	var cpu_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var previous_position := player.global_position
	var travelled := 0.0
	var ambient_starts := {}
	for vehicle in get_nodes_in_group("modern_traffic"):
		if vehicle is Node2D:
			ambient_starts[vehicle.get_instance_id()] = vehicle.global_position
	var started := Time.get_ticks_usec()
	var previous := started
	Input.action_press("move_right")
	while Time.get_ticks_usec() - started < SAMPLE_USEC:
		await process_frame
		var seconds := float(Time.get_ticks_usec() - started) / 1000000.0
		var right := int(seconds / 2.0) % 2 == 0
		Input.action_release("move_left" if right else "move_right")
		Input.action_press("move_right" if right else "move_left")
		if seconds >= 15.0: Input.action_press("sprint")
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - previous) / 1000.0)
		previous = now
		travelled += player.global_position.distance_to(previous_position)
		previous_position = player.global_position
		cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	Input.action_release("move_right")
	Input.action_release("move_left")
	Input.action_release("sprint")

	var ambient_travelled := 0.0
	for vehicle in get_nodes_in_group("modern_traffic"):
		if vehicle is Node2D and ambient_starts.has(vehicle.get_instance_id()):
			ambient_travelled += vehicle.global_position.distance_to(ambient_starts[vehicle.get_instance_id()])
	var elapsed_s := float(previous - started) / 1_000_000.0
	var report := {
		"label": _label,
		"scene": "HarborPreview" if _use_preview else "HarborGame",
		"seconds": elapsed_s,
		"frames": frame_ms.size(),
		"fps": frame_ms.size() / elapsed_s,
		"frame_ms": _summary(frame_ms),
		"samples_ms": frame_ms,
		"render_cpu_ms": _summary(cpu_ms),
		"render_gpu_ms": _summary(gpu_ms),
		"draw_calls": _summary(draw_calls),
		"over_33_3_ms": frame_ms.filter(func(value: float) -> bool: return value > 33.3).size(),
		"over_66_7_ms": frame_ms.filter(func(value: float) -> bool: return value > 66.7).size(),
		"travelled_px": travelled,
		"ambient_travelled_px": ambient_travelled,
		"vehicle_count": get_nodes_in_group("vehicle").size(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"resolution": [root.size.x, root.size.y],
		"vsync": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps,
		"engine": Engine.get_version_info(),
	}
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var output_path := _out_dir.path_join(_label + ".json")
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		push_error("Could not write Dante gait benchmark: " + output_path)
		quit(1)
		return
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("DANTE_GAIT_PERF fps=", report.fps, " frame_ms=", report.frame_ms)
	print("DANTE_GAIT_PERF_REPORT " + output_path)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(_label + ".png"))
	world.queue_free()
	await process_frame
	quit(0 if travelled > 300.0 or ambient_travelled > 300.0 else 1)


func _summary(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value in ordered:
		total += value
	return {
		"average": total / ordered.size(),
		"p50": ordered[int((ordered.size() - 1) * 0.50)],
		"p95": ordered[int((ordered.size() - 1) * 0.95)],
		"p99": ordered[int((ordered.size() - 1) * 0.99)],
		"max": ordered[-1],
	}
