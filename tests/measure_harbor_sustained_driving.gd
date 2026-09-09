extends SceneTree

## Isolated, single-scenario measurement: real renderer, drive continuously for
## an extended sample with no scenario switching in between (the full
## measure_harbor_performance.gd suite showed run-to-run drift when many
## scenarios/weather toggles were exercised back-to-back in one process; this
## script exists to get a trustworthy steady-state number for ordinary,
## continuous play instead).
## Run with: godot --path <project> --script res://tests/measure_harbor_sustained_driving.gd

const WARMUP_FRAMES := 90
const SAMPLE_FRAMES := 600

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var preview := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(preview)
	current_scene = preview
	for i in WARMUP_FRAMES:
		await process_frame

	var player := preview.get_node("Player") as Node2D
	player.global_position = Vector2(2200, 1050)
	var car := preview.get_node("PlayerCar") as CharacterBody2D
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	preview.call("_drive")
	for i in 30:
		await process_frame

	var timings_ms: Array[float] = []
	var start_position := car.global_position
	var previous_position := start_position
	var distance_travelled := 0.0
	Input.action_press("ui_up")
	for i in SAMPLE_FRAMES:
		var t0 := Time.get_ticks_usec()
		await process_frame
		var t1 := Time.get_ticks_usec()
		timings_ms.append((t1 - t0) / 1000.0)
		if "trace" in OS.get_cmdline_user_args() and t1 - t0 > 30000:
			print("SLOW_FRAME index=%d ms=%.2f position=%s root_cpu_ms=%.2f root_gpu_ms=%.2f draws=%d physics_ms=%.2f" % [i, (t1-t0)/1000.0, car.global_position, RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()), RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0])
		distance_travelled += car.global_position.distance_to(previous_position)
		previous_position = car.global_position
	Input.action_release("ui_up")
	print("DRIVING_MOTION start=%s end=%s travelled_px=%.1f displacement_px=%.1f" % [start_position, car.global_position, distance_travelled, start_position.distance_to(car.global_position)])

	var total := 0.0
	var worst := 0.0
	var best := 999999.0
	var over_16ms := 0
	for t in timings_ms:
		total += t
		worst = maxf(worst, t)
		best = minf(best, t)
		if t > 16.67:
			over_16ms += 1
	var avg_ms: float = total / float(timings_ms.size())
	var avg_fps: float = 1000.0 / avg_ms

	# Percentile view: sorted so we can report p50/p90/p99, since a single
	# avg/worst pair hides how often frames actually miss the 60fps budget.
	var sorted_timings := timings_ms.duplicate()
	sorted_timings.sort()
	var p50: float = sorted_timings[int(sorted_timings.size() * 0.50)]
	var p90: float = sorted_timings[int(sorted_timings.size() * 0.90)]
	var p99: float = sorted_timings[int(sorted_timings.size() * 0.99)]

	print("HARBOR_SUSTAINED_DRIVING avg_fps=%.1f avg_ms=%.2f best_ms=%.2f worst_ms=%.2f p50_ms=%.2f p90_ms=%.2f p99_ms=%.2f frames_over_16.67ms=%d/%d (%.1f%%)" % [
		avg_fps, avg_ms, best, worst, p50, p90, p99, over_16ms, timings_ms.size(), 100.0 * over_16ms / timings_ms.size()
	])
	preview.queue_free()
	await process_frame
	quit(0 if distance_travelled > 300.0 else 1)
