extends SceneTree

## Diagnóstico complementar da Etapa 1 (NÃO é a correção -- é isolamento de
## causa). A medição principal (measure_review_0909.gd) mostrou 720p e 1080p
## estatisticamente iguais (~44fps mediana, ~16k draw calls em ambos) com
## forte stutter em p95/p99 nas duas resoluções, 249 SubViewports ativos e
## ~16k draw calls para só 58 veículos + 66 pedestres. Este script isola,
## dentro da MESMA cena real (HarborGame.tscn, 1080p), o custo de cada grupo
## via toggles temporários de process/visibilidade -- a mesma técnica já
## usada em tests/measure_harbor_performance.gd (_set_group_processing) para
## bisecção, não como atalho de "melhoria". Nada é removido permanentemente;
## roda uma única invocação do processo e reporta todas as fases.

const GAME_SCENE := "res://world/harbor/HarborGame.tscn"
const WARMUP_FRAMES := 90
const PHASE_SECONDS := 20.0

var game: Node2D
var _log_lines: PackedStringArray = []
var _all_subviewports: Array[SubViewport] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var settings := root.get_node("SettingsManager")
	settings.set_resolution(Vector2i(1920, 1080))
	settings.set_window_mode(1)
	for i in 5:
		await process_frame

	var packed := load(GAME_SCENE) as PackedScene
	game = packed.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	for i in WARMUP_FRAMES:
		await process_frame

	var car := game.get_node("PlayerCar") as CharacterBody2D
	var player := game.get_node("Player") as CharacterBody2D
	car.global_position = Vector2(1450, 1900)
	car.rotation = 0.0
	car.velocity = Vector2.ZERO
	player.global_position = car.global_position + Vector2(-48, 0)
	for i in 3:
		await physics_frame
	game.call("_drive")

	var weather: CanvasModulate = game.get("weather")
	weather.time_of_day = 0.5
	weather.set_biome(weather.current_biome)
	weather.set_weather(1)

	var wanted = root.get_node("WantedManager")
	wanted.reset_crime()
	for i in 3:
		await process_frame
	wanted.report_crime(120)

	_collect_subviewports(game)
	_log("REVIEW0909_BISECT subviewport_count=%d" % [_all_subviewports.size()])

	await _phase("baseline_all_on")

	_set_group_processing("pedestrian", false)
	await _phase("pedestrians_disabled")

	_set_group_processing("vehicle", false)
	await _phase("pedestrians_and_vehicles_disabled")

	_set_group_processing("pedestrian", true)
	_set_group_processing("vehicle", true)
	await _phase("restored_all_on")

	_set_subviewport_update(false)
	await _phase("subviewports_paused_actors_on")

	_set_subviewport_update(true)
	Input.action_release("ui_up")
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	_write_report()
	quit(0)

func _collect_subviewports(node: Node) -> void:
	if node is SubViewport:
		_all_subviewports.append(node)
	for child in node.get_children():
		_collect_subviewports(child)

func _set_subviewport_update(enabled: bool) -> void:
	for vp in _all_subviewports:
		if is_instance_valid(vp):
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled else SubViewport.UPDATE_DISABLED

func _set_group_processing(group: String, enabled: bool) -> void:
	for node in get_nodes_in_group(group):
		if node is Node:
			node.set_process(enabled)
			node.set_physics_process(enabled)

func _phase(phase_name: String) -> void:
	var frame_ms: Array[float] = []
	var elapsed := 0.0
	var draw_calls_samples: Array[int] = []
	var frame_i := 0
	while elapsed < PHASE_SECONDS:
		var ph := int(elapsed) % 6
		Input.action_press("ui_up")
		if ph < 2:
			Input.action_press("ui_left"); Input.action_release("ui_right")
		elif ph >= 3 and ph < 5:
			Input.action_press("ui_right"); Input.action_release("ui_left")
		else:
			Input.action_release("ui_left"); Input.action_release("ui_right")

		var t0 := Time.get_ticks_usec()
		await process_frame
		var t1 := Time.get_ticks_usec()
		var dt := (t1 - t0) / 1000.0
		frame_ms.append(dt)
		elapsed += dt / 1000.0
		frame_i += 1
		if frame_i % 10 == 0:
			draw_calls_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))

	frame_ms.sort()
	var n := frame_ms.size()
	var median: float = frame_ms[n / 2]
	var p95: float = frame_ms[int(n * 0.95)]
	var total := 0.0
	for t in frame_ms:
		total += t
	var avg_ms: float = total / float(n)
	var avg_draw := 0.0
	for d in draw_calls_samples:
		avg_draw += d
	avg_draw = avg_draw / float(draw_calls_samples.size()) if not draw_calls_samples.is_empty() else -1.0

	_log("REVIEW0909_BISECT_PHASE phase=%s frames=%d avg_fps=%.1f median_fps=%.1f p95_fps=%.1f avg_ms=%.2f median_ms=%.2f p95_ms=%.2f draw_calls=%.0f t_process_ms=%.2f t_physics_ms=%.2f" % [
		phase_name, n,
		1000.0 / avg_ms if avg_ms > 0.0 else 0.0,
		1000.0 / median if median > 0.0 else 0.0,
		1000.0 / p95 if p95 > 0.0 else 0.0,
		avg_ms, median, p95, avg_draw,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
	])

func _log(line: String) -> void:
	print(line)
	_log_lines.append(line)

## Saida vai para docs/measurements/review-0909/ dentro do projeto, como o
## resto dos scripts de captura deste repositorio ja faz -- e nao para uma
## pasta absoluta fora dele, que nao seria versionada nem encontrada por
## quem clonasse o projeto.
const DEFAULT_OUT_DIR := "res://docs/measurements/review-0909"

## Resolve res:// para caminho de sistema; DirAccess/FileAccess de escrita
## precisam do caminho absoluto.
static func _resolve_out_dir(dir: String) -> String:
	return ProjectSettings.globalize_path(dir) if dir.begins_with("res://") else dir

func _write_report() -> void:
	var out_dir := _resolve_out_dir(DEFAULT_OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir.path_join("review0909_bisect.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log_lines))
		f.close()
	print("REVIEW0909_BISECT_REPORT " + path)
