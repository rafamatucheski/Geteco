extends Node
## Benchmark controlado dentro do jogo (2026-10-14): o export ignora `--script`, e a pasta tests/ não vai no
## pacote. Mesmo circuito, hora, clima e câmera de tests/measure/benchmark_west_route.gd, para comparar editor
## e release com os mesmos interruptores (variáveis de ambiente).
## Uso: GetecoV2.exe -- --no-save --benchmark --no-dispatch --benchmark-route=oeste --play-at=harbor,64,82 --label=x
##      (porto: --benchmark-route=porto --play-at=harbor,150,82). Grava user://benchmark-west/<label>.json e sai.
## Noite e chuva (15/10): --benchmark-hour=H (0..24, padrão 12) e --benchmark-rain[=1|2] (2 tempestade, padrão;
## 1 garoa) com o chão já molhado. Exercitam o que o meio-dia seco não liga: postes/faróis/janelas, sombras de
## faróis, partículas de chuva, respingos e a captura do reflexo do chão molhado. Sem as opções, nada muda.
const ROUTE_WEST := [Vector3(64, 0, 82), Vector3(150, 0, 82), Vector3(143, 0, 60), Vector3(84, 0, 60), Vector3(84, 0, 123), Vector3(65, 0, 113)]
const ROUTE_PORT := [Vector3(150, 0, 82), Vector3(250, 0, 82), Vector3(250, 0, 30), Vector3(180, 0, 30), Vector3(180, 0, 82)]
## Pontos quentes das outras regiões (censo de 14/10). Serra: --play-at=mountain,650,-290; ponte cidade–serra:
## --play-at=harbor,440,-285; deserto (encontro de arrancada, trechos de 96 m): --play-at=desert,-1040,-1320.
const ROUTES := {
	"serra": [Vector3(650, 4, -290), Vector3(745, 4, -300), Vector3(745, 4, -425), Vector3(660, 4, -425)],
	"ponte": [Vector3(440, 0, -285), Vector3(600, 0, -285)],
	# Porto -> ponte -> serra e volta: o streaming entra em trechos novos com o jogo rodando (travadas de 15/10).
	"travessia": [Vector3(330, 0, -285), Vector3(600, 0, -285), Vector3(700, 4, -300), Vector3(745, 4, -420)],
	"deserto": [Vector3(-1040, 0, -1320), Vector3(-950, 0, -1320), Vector3(-950, 0, -1260), Vector3(-1040, 0, -1260)],
	# Northbank e canal concentram 6 dos 15 sobrados/terraços (A/B das janelas pintadas, 15/10).
	"sobrados": [Vector3(295, 0, 100), Vector3(340, 0, 100), Vector3(340, 0, -60), Vector3(295, 0, -60)],
}
const SPEED := 12.0
var WARMUP_LOOPS := 1
const MEASURE_LOOPS := 2
const TOGGLES := ["GETECO_POP_VC", "GETECO_SUN_SHADOW_NEAR", "GETECO_TRAFFIC_RAILS", "GETECO_PED_POSE_LOD", "GETECO_LIGHT_BUDGET",
	"GETECO_DETAIL_RANGE", "GETECO_BAKED_BUILDINGS", "GETECO_SKID_BUDGET", "GETECO_DASH_BATCH", "GETECO_DISPATCH_FAST",
	"GETECO_PED_DUMMY", "GETECO_BUILDING_BATCH", "GETECO_PROP_INSTANCING", "GETECO_GROUND_STACK", "GETECO_SHADOW_SHELL",
	"GETECO_BRIDGE_MERGE", "GETECO_FURNITURE_MERGE", "GETECO_CELL_MERGE", "GETECO_BRIDGE_LOOK", "GETECO_PAINTED_WINDOWS", "GETECO_PAINTED_FACADES",
	"GETECO_SUN_SPLITS"]

var world: Node
var route: Array = ROUTE_WEST
var label := "release"
var route_name := ""
var bench_hour := 12.0
var bench_rain := 0

static func requested() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--benchmark-route="): return true
	return false

func _ready() -> void:
	# Travessia mede a primeira passagem: sem volta de aquecimento.
	if "--benchmark-route=travessia" in OS.get_cmdline_user_args(): WARMUP_LOOPS = 0
	for argument in OS.get_cmdline_user_args():
		if argument == "--benchmark-route=porto": route = ROUTE_PORT
		var named := argument.trim_prefix("--benchmark-route=")
		if argument.begins_with("--benchmark-route=") and ROUTES.has(named):
			route = ROUTES[named]
			route_name = named
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument.begins_with("--benchmark-hour="): bench_hour = fposmod(float(argument.trim_prefix("--benchmark-hour=")), 24.0)
		if argument == "--benchmark-rain": bench_rain = 2
		elif argument.begins_with("--benchmark-rain="): bench_rain = clampi(int(argument.trim_prefix("--benchmark-rain=")), 0, 2)
	_run.call_deferred()

func _route_point(distance: float) -> Dictionary:
	var lengths: Array[float] = []
	var total := 0.0
	for index in route.size():
		lengths.append((route[index] as Vector3).distance_to(route[(index + 1) % route.size()]))
		total += lengths[-1]
	var along := fposmod(distance, total)
	for index in route.size():
		if along <= lengths[index]:
			var a: Vector3 = route[index]
			var b: Vector3 = route[(index + 1) % route.size()]
			return {"point": a.lerp(b, along / lengths[index]), "yaw": atan2(-(b - a).x, -(b - a).z), "total": total}
		along -= lengths[index]
	return {"point": route[0], "yaw": 0.0, "total": total}

func _run() -> void:
	# Sem v-sync nem limite de fps: preso em 60/144 Hz o tempo de quadro esconde diferenças.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# Com --no-save o jogo começa novo: o mundo fica segurado em pausa e logo depois o
	# filme da balsa roda ~70 s com o 3D desligado. Sem esperar, a medição pegava essa
	# tela: 11 draw calls e 0,6 ms (15/10). Exige 3 s seguidos de mundo jogável e
	# visível, porque o filme só começa ~1 s depois de ready_for_play.
	var stable_since := -1
	while stable_since < 0 or Time.get_ticks_msec() - stable_since < 3000:
		await get_tree().process_frame
		var playable: bool = not get_tree().paused and world.session.ready_for_play and not get_viewport().disable_3d
		if not playable: stable_since = -1
		elif stable_since < 0: stable_since = Time.get_ticks_msec()
	# Do início do processo até jogável e visível (carregamento, pré-aquecimentos e
	# filme pulado pela espera acima): mede o custo de loading na mesma rodada.
	var playable_ms := stable_since
	var weather: Variant = world.session.weather
	weather.time_of_day = bench_hour / 24.0
	if "weather_state" in weather: weather.weather_state = bench_rain
	# Chuva já assentada: a umidade da costa leva minutos para subir sozinha e o reflexo do chão
	# só liga acima de 0,015. Sem chuva continua seco, como antes.
	if bench_rain > 0 and "coastal_wetness" in weather: weather.coastal_wetness = 1.0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	var car: CharacterBody3D = world.driving.car
	car.set_physics_process(false)
	car.visible = true
	world.player.set_physics_process(false)
	world.player.visible = false
	world.camera.target = car
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var total: float = _route_point(0.0).total
	var distance := 0.0
	var frames: Array[float] = []
	var gpu: Array[float] = []
	var draws: Array[float] = []
	var previous := Time.get_ticks_usec()
	while distance < total * (WARMUP_LOOPS + MEASURE_LOOPS):
		var sample := _route_point(distance)
		car.global_position = sample.point + Vector3.UP * .1
		car.rotation = Vector3(0, sample.yaw, 0)
		world.player.global_position = sample.point
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := (now - previous) / 1000.0
		previous = now
		distance += SPEED * minf(frame_ms, 100.0) / 1000.0
		if distance < total * WARMUP_LOOPS: continue
		frames.append(frame_ms)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var toggles := {}
	for name in TOGGLES: toggles[name] = OS.get_environment(name)
	var report := {"label": label, "build": "editor" if OS.has_feature("editor") else ("export_release" if OS.has_feature("release") else "export_debug"),
		"route": route_name if route_name != "" else ("porto" if route == ROUTE_PORT else "oeste"), "frames": frames.size(), "frame_ms": _stats(frames),
		"gpu_ms_main": _stats(gpu), "draw_calls": _stats(draws), "toggles": toggles,
		"frames_over_100ms": frames.filter(func(ms): return ms > 100.0).size(),
		"frames_over_6_9ms": frames.filter(func(ms): return ms > 6.94).size(), "frames_over_16_7ms": frames.filter(func(ms): return ms > 16.7).size(),
		"frames_over_33ms": frames.filter(func(ms): return ms > 33.3).size(), "playable_ms": playable_ms, "frames_over_250ms": frames.filter(func(ms): return ms > 250.0).size(),
		"resolution": str(get_viewport().get_visible_rect().size), "viewport_pixels": str(get_viewport().size), "msaa": get_viewport().msaa_3d,
		"hour": bench_hour, "rain": bench_rain, "vehicles": world.production.vehicles.size(), "people": world.people.size()}
	print("BENCH_RELEASE ", JSON.stringify({"label": label, "frame_p50": report.frame_ms.p50, "frame_p95": report.frame_ms.p95, "draws_p50": report.draw_calls.p50}))
	var folder := "user://benchmark-west"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder + "/" + label + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	get_tree().quit(0)

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	for value in sorted: sum += value
	var count := sorted.size()
	return {"mean": snappedf(sum / count, 0.01), "p50": snappedf(sorted[count / 2], 0.01),
		"p95": snappedf(sorted[mini(count - 1, int(count * .95))], 0.01), "p99": snappedf(sorted[mini(count - 1, int(count * .99))], 0.01),
		"max": snappedf(sorted[-1], 0.01)}
