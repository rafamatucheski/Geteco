extends SceneTree

## Run with a real renderer (not --headless):
##   godot --path <project> --script res://tests/measure_harbor_performance.gd
## Samples real per-frame wall time (not the smoothed Engine.get_frames_per_second()
## estimate) across the documented review scenarios and writes a plain-text report.
## Never teleports actors for the review flows it can reach via public API
## (request_interaction, the existing _walk()/_drive() review shortcuts); it only
## repositions cameras directly, exactly like tests/capture_harbor_preview.gd already does.

const WARMUP_FRAMES := 60
const SETTLE_FRAMES := 30
const SAMPLE_FRAMES := 150

var preview: Node2D
var _log_lines: PackedStringArray = []
var _out_dir := "D:/geteco/harbor-perf/final"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("out_dir="):
			_out_dir = arg.substr(len("out_dir="))

	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	preview = load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(preview)
	current_scene = preview
	for i in WARMUP_FRAMES:
		await process_frame

	_log("HARBOR_PERF resolution=%dx%d renderer=%s api_version=%s" % [
		root.size.x, root.size.y,
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_api_version()
	])

	await _measure_scenario("overview", func() -> void:
		var cam := preview.get_node("OverviewCamera") as Camera2D
		cam.zoom = Vector2.ONE * 0.12
		cam.position = Vector2(3320, -450)
		cam.make_current()
	)

	await _measure_scenario("busy_block_walk", func() -> void:
		preview.call("_walk")
		var player := preview.get_node("Player") as Node2D
		player.global_position = Vector2(1620, 900)
		player.velocity = Vector2.ZERO
	)

	await _measure_scenario("driving_across_district", func() -> void:
		var player := preview.get_node("Player") as Node2D
		player.global_position = Vector2(2200, 1050)
		preview.call("_drive")
	)

	# Bisection/weather variants below all continue from the same driving
	# state established above (car stays driven, same camera) so only the
	# one variable named in each scenario actually changes.
	await _measure_scenario("driving_bisect_no_vehicles", func() -> void:
		_set_group_processing("vehicle", false)
	)
	await _measure_scenario("driving_bisect_no_pedestrians", func() -> void:
		_set_group_processing("vehicle", true)
		_set_group_processing("pedestrian", false)
	)
	await _measure_scenario("driving_bisect_restored", func() -> void:
		_set_group_processing("vehicle", true)
		_set_group_processing("pedestrian", true)
	)

	await _measure_scenario("driving_night_only", func() -> void:
		var weather: CanvasModulate = preview.get("weather")
		weather.time_of_day = 0.90
		weather.set_biome(weather.current_biome)
		weather.set_weather(0)
	)
	await _measure_scenario("driving_rain_only", func() -> void:
		var weather: CanvasModulate = preview.get("weather")
		weather.time_of_day = 0.45
		weather.set_biome(weather.current_biome)
		weather.set_weather(1)
	)
	await _measure_scenario("driving_night_rain", func() -> void:
		var weather: CanvasModulate = preview.get("weather")
		weather.time_of_day = 0.90
		weather.set_biome(weather.current_biome)
		weather.set_weather(1)
	)
	await _measure_scenario("driving_day_clear_restored", func() -> void:
		var weather: CanvasModulate = preview.get("weather")
		weather.time_of_day = 0.45
		weather.set_biome(weather.current_biome)
		weather.set_weather(0)
	)

	await _measure_scenario("garage_interior", func() -> void:
		preview.call("_walk")
		var player := preview.get_node("Player") as Node2D
		var entrance := preview.get_node("District/Garage/Entrance")
		var state: Dictionary = entrance.call("get_entrance_state")
		player.global_position = state.get("approach_position", entrance.global_position)
		player.velocity = Vector2.ZERO
		# The sensor's Area2D overlap (is_actor_in_range) needs at least one
		# physics step after the teleport before request_interaction sees it.
		for i in 10:
			await physics_frame
		var opened: bool = entrance.call("request_interaction", player)
		print("HARBOR_PERF_DEBUG garage_request_interaction_opened=%s player_pos=%s" % [opened, player.global_position])
		# Wait for the open-door animation + camera reframe to actually complete.
		for i in 60:
			await process_frame
	, 30)

	_write_report()
	quit(0)

func _measure_scenario(scenario_name: String, setup: Callable, settle_frames: int = SETTLE_FRAMES) -> void:
	await setup.call()
	for i in settle_frames:
		await process_frame

	var timings_ms: Array[float] = []
	for i in SAMPLE_FRAMES:
		var t0 := Time.get_ticks_usec()
		await process_frame
		var t1 := Time.get_ticks_usec()
		timings_ms.append((t1 - t0) / 1000.0)

	var total := 0.0
	var worst := 0.0
	var best := 999999.0
	for t in timings_ms:
		total += t
		worst = maxf(worst, t)
		best = minf(best, t)
	var avg_ms: float = total / float(timings_ms.size())
	var avg_fps: float = 1000.0 / avg_ms if avg_ms > 0.0 else 0.0
	var worst_fps: float = 1000.0 / worst if worst > 0.0 else 0.0

	var vehicles := -1
	var pedestrians := -1
	if preview.has_node("Life"):
		var pop: Dictionary = preview.get_node("Life").call("get_population_snapshot")
		vehicles = pop.get("vehicles", -1)
		pedestrians = pop.get("pedestrians", -1)

	var cam := root.get_camera_2d()
	var cam_pos := cam.global_position if cam else Vector2.ZERO
	var cam_zoom := cam.zoom if cam else Vector2.ONE

	var t_process := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var t_physics := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var t_nav := Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var node_count := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphan_count := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	_log("HARBOR_PERF scenario=%s avg_fps=%.1f worst_fps=%.1f avg_ms=%.2f worst_ms=%.2f best_ms=%.2f samples=%d cam_pos=%s cam_zoom=%s vehicles=%d pedestrians=%d t_process_ms=%.2f t_physics_ms=%.2f t_nav_ms=%.2f draw_calls=%d nodes=%d orphans=%d" % [
		scenario_name, avg_fps, worst_fps, avg_ms, worst, best, timings_ms.size(), str(cam_pos), str(cam_zoom), vehicles, pedestrians, t_process, t_physics, t_nav, draw_calls, node_count, orphan_count
	])

func _set_group_processing(group: String, enabled: bool) -> void:
	for node in get_nodes_in_group(group):
		if node is Node:
			node.set_process(enabled)
			node.set_physics_process(enabled)

func _log(line: String) -> void:
	print(line)
	_log_lines.append(line)

func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var path := _out_dir.path_join("REPORT.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log_lines))
		f.close()
	print("HARBOR_PERF_REPORT " + path)
