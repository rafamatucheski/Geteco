extends SceneTree

## Etapa 1 da revisão de 09/09 (viatura girando, ambulância cortando pela
## quadra, prisão sem retirada, corpo não recolhido, coletável atrás de
## geometria, queda de FPS em 1080p): medir ANTES de alterar qualquer coisa.
##
## Pilota o player/carro/câmera REAIS dentro de HarborGame.tscn -- a cena
## principal real do jogo (project.godot run/main_scene) -- na região
## delegacia/hospital, com chuva real e uma perseguição policial real
## disparada via WantedManager.report_crime (viaturas de verdade são
## despachadas e dirigidas pela IA real; nada é teleportado ou tem colisão
## desligada). Roda com o binário Godot de verdade (janela + Vulkan), não em
## --headless, então os números de draw call/fill-rate são reais.
##
## Isto é um bot-script segurando "acelerar"/"virar" durante a amostra, não
## um humano jogando manualmente -- documentado assim porque não há como
## pilotar a janela nativa do Godot com mouse/teclado real nesta sessão.
##
## Uma amostra por invocação (isola carregamento e estado entre amostras):
##   Godot..._console.exe --path D:/geteco/game --script res://tests/measure_review_0909.gd -- res=720 sample=1 out_dir=D:/geteco/perf-review-0909
##   res=720  -> janela 1280x720, content_scale_mode=CANVAS_ITEMS (== modo "Janela" real do jogo)
##   res=1080 -> tela cheia sem bordas 1920x1080, content_scale_mode=VIEWPORT (== modo "Tela Cheia" real do jogo)
## Ambos os caminhos chamam SettingsManager.apply_display_settings() --
## o mesmo código usado pelo jogo real em SettingsMenu, não uma cópia paralela.

const GAME_SCENE := "res://district/harbor_preview/HarborGame.tscn"
const WARMUP_FRAMES := 90
const STABILIZE_SECONDS := 3.0
const SAMPLE_SECONDS := 60.0

var _out_dir := "D:/geteco/perf-review-0909"
var _res := 720
var _sample := 1
var _duration_s := SAMPLE_SECONDS
var game: Node2D
var _log_lines: PackedStringArray = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_parse_args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var t_boot_start := Time.get_ticks_msec()

	# SettingsManager autoload loads the user's persisted config (config.cfg)
	# at boot, which may already hold a real fullscreen 1920x1080 resolution
	# from prior manual play. Reset resolution explicitly for both branches so
	# the 720p run isn't left with a stale 1920x1080 window size.
	var settings := root.get_node("SettingsManager")
	if _res == 1080:
		settings.set_resolution(Vector2i(1920, 1080))
		settings.set_window_mode(1)
	else:
		settings.set_resolution(Vector2i(1280, 720))
		settings.set_window_mode(0)

	for i in 5:
		await process_frame

	var packed := load(GAME_SCENE) as PackedScene
	game = packed.instantiate() as Node2D
	root.add_child(game)
	current_scene = game

	for i in WARMUP_FRAMES:
		await process_frame

	var t_load_ms := Time.get_ticks_msec() - t_boot_start

	_log("REVIEW0909_PERF res=%d sample=%d window_size=%s content_scale_size=%s content_scale_mode=%d renderer=%s api=%s load_ms=%d" % [
		_res, _sample, str(root.size), str(root.content_scale_size), root.content_scale_mode,
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_api_version(),
		t_load_ms,
	])

	await _setup_scenario()

	# Estabilização (não entra na amostra): dá tempo do carro acelerar e a
	# perseguição realmente engatar antes de contar como "partida estável".
	var settle_elapsed := 0.0
	while settle_elapsed < STABILIZE_SECONDS:
		var settle_t0 := Time.get_ticks_usec()
		Input.action_press("ui_up")
		await process_frame
		settle_elapsed += (Time.get_ticks_usec() - settle_t0) / 1000000.0

	await _measure(_duration_s)

	Input.action_release("ui_up")
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	_write_report()
	quit(0)

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("res="):
			_res = int(arg.substr(4))
		elif arg.begins_with("sample="):
			_sample = int(arg.substr(7))
		elif arg.begins_with("out_dir="):
			_out_dir = arg.substr(8)
		elif arg.begins_with("duration="):
			_duration_s = float(arg.substr(9))

func _setup_scenario() -> void:
	# Região delegacia/hospital: PatrolAccess (1080,2085) / ClinicAccess
	# (1910,1705) em district/harbor_preview/HarborDistrict.gd. Ponto
	# intermediário mantém as duas em alcance durante a amostra.
	var car := game.get_node("PlayerCar") as CharacterBody2D
	var player := game.get_node("Player") as CharacterBody2D
	car.global_position = Vector2(1450, 1900)
	car.rotation = 0.0
	car.velocity = Vector2.ZERO
	player.global_position = car.global_position + Vector2(-48, 0)
	player.velocity = Vector2.ZERO
	for i in 3:
		await physics_frame
	game.call("_drive") # entra no carro real e assume a câmera de condução real

	var weather: CanvasModulate = game.get("weather")
	weather.time_of_day = 0.5
	weather.set_biome(weather.current_biome)
	weather.set_weather(1) # chuva real

	var wanted = root.get_node("WantedManager")
	wanted.reset_crime()
	for i in 3:
		await process_frame
	wanted.report_crime(120) # gera perseguição real (viaturas despachadas de verdade, não simuladas)

func _measure(duration_seconds: float) -> void:
	var frame_ms: Array[float] = []
	var elapsed := 0.0
	var draw_calls_samples: Array[int] = []
	var physics_objects_samples: Array[int] = []
	var subviewport_counts: Array[int] = []
	var frame_i := 0
	while elapsed < duration_seconds:
		# Mantém condução real e faz curvas periódicas para não empacar numa
		# parede nem sair da região delegacia/hospital durante a amostra.
		var phase := int(elapsed) % 6
		Input.action_press("ui_up")
		if phase < 2:
			Input.action_press("ui_left")
			Input.action_release("ui_right")
		elif phase >= 3 and phase < 5:
			Input.action_press("ui_right")
			Input.action_release("ui_left")
		else:
			Input.action_release("ui_left")
			Input.action_release("ui_right")

		var t0 := Time.get_ticks_usec()
		await process_frame
		var t1 := Time.get_ticks_usec()
		var dt := (t1 - t0) / 1000.0
		frame_ms.append(dt)
		elapsed += dt / 1000.0
		frame_i += 1
		if frame_i % 15 == 0:
			draw_calls_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			physics_objects_samples.append(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS))
			subviewport_counts.append(_count_subviewports(game))

	frame_ms.sort()
	var n := frame_ms.size()
	var median: float = frame_ms[n / 2]
	var p95: float = frame_ms[int(n * 0.95)]
	var p99: float = frame_ms[mini(int(n * 0.99), n - 1)]
	var total := 0.0
	for t in frame_ms:
		total += t
	var avg_ms: float = total / float(n)

	var avg_draw := _avg_int(draw_calls_samples)
	var avg_phys := _avg_int(physics_objects_samples)
	var avg_subvp := _avg_int(subviewport_counts)

	var pop: Dictionary = {}
	if game.has_node("Life"):
		pop = game.get_node("Life").call("get_population_snapshot")

	var active_emergency := 0
	for em in get_nodes_in_group("emergency_vehicle"):
		if is_instance_valid(em) and em.visible:
			active_emergency += 1

	_log("REVIEW0909_SAMPLE res=%d sample=%d frames=%d elapsed_s=%.1f avg_fps=%.1f median_fps=%.1f p95_fps=%.1f p99_fps=%.1f avg_ms=%.2f median_ms=%.2f p95_ms=%.2f p99_ms=%.2f worst_ms=%.2f best_ms=%.2f draw_calls=%.0f physics_2d_active=%.0f subviewports=%.1f vehicles=%d pedestrians=%d emergency_active=%d t_process_ms=%.2f t_physics_ms=%.2f" % [
		_res, _sample, n, elapsed,
		1000.0 / avg_ms if avg_ms > 0.0 else 0.0,
		1000.0 / median if median > 0.0 else 0.0,
		1000.0 / p95 if p95 > 0.0 else 0.0,
		1000.0 / p99 if p99 > 0.0 else 0.0,
		avg_ms, median, p95, p99, frame_ms[n - 1], frame_ms[0],
		avg_draw, avg_phys, avg_subvp,
		pop.get("vehicles", -1), pop.get("pedestrians", -1), active_emergency,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
	])

func _count_subviewports(node: Node) -> int:
	var count := 0
	if node is SubViewport:
		count += 1
	for child in node.get_children():
		count += _count_subviewports(child)
	return count

func _avg_int(arr: Array[int]) -> float:
	if arr.is_empty():
		return -1.0
	var total := 0
	for v in arr:
		total += v
	return float(total) / float(arr.size())

func _log(line: String) -> void:
	print(line)
	_log_lines.append(line)

func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var path := _out_dir.path_join("review0909_res%d_sample%d.txt" % [_res, _sample])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log_lines))
		f.close()
	print("REVIEW0909_REPORT " + path)
