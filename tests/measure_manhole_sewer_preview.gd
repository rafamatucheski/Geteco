extends SceneTree

## Rendered A/B/C comparison in the full HarborPreview district:
## baseline without the node, closed event-only cover, and active sewer.
const PREVIEW := preload("res://world/harbor/HarborPreview.tscn")
const SEWER_SCRIPT := preload("res://world/harbor/sewer/HarborManholeSewer.gd")
const MANHOLE_POSITION := SEWER_SCRIPT.STREET_POSITION

var output := "D:/geteco/artifacts/manhole-sewer/perf-preview"
var sample_seconds := 30.0
var cycling := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("MANHOLE_PREVIEW_PERF requires a real renderer")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="):
			output = arg.trim_prefix("out_dir=")
		elif arg.begins_with("seconds="):
			sample_seconds = maxf(1.0, float(arg.trim_prefix("seconds=")))
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	if not OS.get_cmdline_user_args().has("--normal-cap"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	root.get_node("SaveManager").clear_pending_save()
	seed(12092026)
	var world := PREVIEW.instantiate()
	world.review_mode = false
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 60000
	while not world.world_build_ready and Time.get_ticks_msec() < deadline:
		await process_frame
	if not world.world_build_ready:
		push_error("MANHOLE_PREVIEW_PERF harbor preview did not become ready")
		quit(1)
		return
	world.call("_walk")
	var player := world.get_node("Player") as CharacterBody2D
	player.global_position = MANHOLE_POSITION + Vector2(-54.0, 2.0)
	player.velocity = Vector2.ZERO
	player.is_control_disabled = true
	var camera := player.get_node("Camera") as Camera2D
	camera.make_current()
	camera.reset_smoothing()
	await create_timer(5.0).timeout
	var animation_only := OS.get_cmdline_user_args().has("--animation")
	if not animation_only:
		await _sample("baseline_without_node")
	var sewer := SEWER_SCRIPT.new()
	sewer.name = "PoliceManholeSewer"
	sewer.position = MANHOLE_POSITION
	world.get_node("Interiors/InteriorSpaces").add_child(sewer)
	await process_frame
	await physics_frame
	await _sample("closed_cover")
	if animation_only:
		cycling = true
		_cycle_ladder.call_deferred(sewer, player)
		await _sample("ladder_cycles")
		cycling = false
		while sewer.state != SEWER_SCRIPT.State.SURFACE:
			await process_frame
		world.queue_free()
		await process_frame
		await process_frame
		quit(0)
		return
	sewer.debug_enter_immediately(player)
	player.is_control_disabled = true
	camera.reset_smoothing()
	await process_frame
	await physics_frame
	await _sample("active_sewer")
	sewer.debug_exit_immediately()
	world.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _cycle_ladder(sewer: Node, player: CharacterBody2D) -> void:
	while cycling:
		player.global_position = MANHOLE_POSITION + Vector2(-22.0, 0.0)
		player.is_control_disabled = false
		sewer.request_interaction(player)
		while sewer.state != SEWER_SCRIPT.State.INSIDE:
			await process_frame
		sewer._begin_exit()
		while sewer.state != SEWER_SCRIPT.State.SURFACE:
			await process_frame

func _sample(label: String) -> void:
	var samples: Array[float] = []
	var process_samples: Array[float] = []
	var physics_samples: Array[float] = []
	var draws: Array[int] = []
	var total_ms := 0.0
	var previous := Time.get_ticks_usec()
	while total_ms < sample_seconds * 1000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - previous) / 1000.0
		previous = now
		total_ms += frame_ms
		samples.append(frame_ms)
		process_samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var raw := samples.duplicate()
	samples.sort()
	var over_33 := 0
	var over_66 := 0
	for value in samples:
		if value > 33.3:
			over_33 += 1
		if value > 66.7:
			over_66 += 1
	var report := {
		"scenario": label,
		"frame_ms": raw,
		"seconds": total_ms / 1000.0,
		"frames": samples.size(),
		"fps": samples.size() * 1000.0 / total_ms,
		"p50_ms": samples[int(samples.size() * 0.50)],
		"p95_ms": samples[int(samples.size() * 0.95)],
		"p99_ms": samples[int(samples.size() * 0.99)],
		"max_ms": samples[-1],
		"over_33ms": over_33,
		"over_66ms": over_66,
		"process_mean_ms": _mean(samples, process_samples),
		"physics_mean_ms": _mean(samples, physics_samples),
		"draw_calls_mean": _mean_int(draws),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"resolution": str(root.size),
		"vsync": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps,
	}
	var file := FileAccess.open(output.path_join(label + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	report.erase("frame_ms") # Keep raw samples in the artifact, not the console.
	print("MANHOLE_PREVIEW_PERF ", JSON.stringify(report))

func _mean(frame_samples: Array[float], values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(1.0, frame_samples.size())

func _mean_int(values: Array[int]) -> float:
	var total := 0
	for value in values:
		total += value
	return float(total) / maxf(1.0, values.size())
