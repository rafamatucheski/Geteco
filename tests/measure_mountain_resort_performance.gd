extends SceneTree

## Medição de Performance do Resort Cume Branco (Mountain Pass Resort Performance)
## Segue estritamente C:/Users/rafae/.codex/skills/performance-do-jogo/SKILL.md:
## - Renderização real com janela e GPU
## - Medição de tempo real por frame (parede), p50/p95/p99 e contagem > 16.6ms / > 33.3ms
## - Cenários:
##   1. resort_concourse_overview (Visão geral do Porte-Cochère, Chalé, Boutique e Promenade)
##   2. promenade_brazier_walk (Caminhada no calçadão próximo ao braseiro aquecido e NPCs)
##   3. helipad_outpost (Plataforma octogonal do Heliponto, LEDs, biruta e bunker)
##   4. chairlift_and_slopes (Teleférico com cabos, cadeirinhas móveis e esquiadores)

const WARMUP_FRAMES := 60
const SETTLE_FRAMES := 30
const SAMPLE_FRAMES := 150

var mountain: Node2D
var camera: Camera2D
var _log_lines: PackedStringArray = []
var _out_dir := "D:/geteco/artifacts/resort-perf"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	mountain = preload("res://world/mountain_pass/MountainPass.gd").new()
	mountain.streamed_region = false
	root.add_child(mountain)
	current_scene = mountain

	camera = Camera2D.new()
	camera.name = "BenchmarkCamera"
	root.add_child(camera)
	camera.make_current()

	for i in WARMUP_FRAMES:
		await process_frame

	_log("MOUNTAIN_RESORT_PERF resolution=%dx%d renderer=%s adapter=%s" % [
		root.size.x, root.size.y,
		RenderingServer.get_video_adapter_type(),
		RenderingServer.get_video_adapter_name()
	])

	# Cenário 1: Concourse e Praça Central do Resort
	await _measure_scenario("resort_concourse_overview", func() -> void:
		camera.zoom = Vector2.ONE * 1.2
		camera.position = Vector2(7140, -2700)
	)

	# Cenário 2: Caminhada na Promenade com Braseiro e NPCs
	await _measure_scenario("promenade_brazier_and_shops", func() -> void:
		camera.zoom = Vector2.ONE * 1.6
		camera.position = Vector2(7210, -2710)
	)

	# Cenário 3: Heliponto e Bunker de Radar
	await _measure_scenario("helipad_and_bunker", func() -> void:
		camera.zoom = Vector2.ONE * 1.4
		camera.position = Vector2(6460, -2760)
	)

	# Cenário 4: Teleférico e Face Norte das Pistas
	await _measure_scenario("chairlift_and_slopes", func() -> void:
		camera.zoom = Vector2.ONE * 1.3
		camera.position = Vector2(6950, -3020)
	)

	# Salva relatório em disco
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var report_path := _out_dir + "/mountain_resort_perf.txt"
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(_log_lines) + "\n")
		file.close()
		print("Relatório salvo em: ", report_path)

	quit(0)

func _measure_scenario(scenario_name: String, setup_fn: Callable) -> void:
	setup_fn.call()
	for i in SETTLE_FRAMES:
		await process_frame

	var frame_times: Array[float] = []
	var t_start := Time.get_ticks_usec()
	var prev_tick := t_start

	for i in SAMPLE_FRAMES:
		await process_frame
		var cur_tick := Time.get_ticks_usec()
		var dt_ms := float(cur_tick - prev_tick) / 1000.0
		frame_times.append(dt_ms)
		prev_tick = cur_tick

	var t_end := Time.get_ticks_usec()
	var total_time_s := float(t_end - t_start) / 1000000.0
	var avg_fps := float(SAMPLE_FRAMES) / maxf(0.001, total_time_s)

	frame_times.sort()
	var p50 := frame_times[int(SAMPLE_FRAMES * 0.50)]
	var p95 := frame_times[int(SAMPLE_FRAMES * 0.95)]
	var p99 := frame_times[int(SAMPLE_FRAMES * 0.99)]
	var max_dt := frame_times[-1]

	var over_16 := 0
	var over_33 := 0
	for dt in frame_times:
		if dt > 16.67:
			over_16 += 1
		if dt > 33.33:
			over_33 += 1

	var line := "SCENARIO: %-28s | FPS: %6.1f | p50: %5.2fms | p95: %5.2fms | p99: %5.2fms | max: %5.2fms | >16.6ms: %3d | >33.3ms: %3d" % [
		scenario_name, avg_fps, p50, p95, p99, max_dt, over_16, over_33
	]
	_log(line)
	print(line)

func _log(msg: String) -> void:
	_log_lines.append(msg)
