extends Node
## Benchmark controlado dentro do jogo (2026-10-14): o export ignora `--script`, e a pasta tests/ não vai no
## pacote. Mesmo circuito, hora, clima e câmera de tests/measure/benchmark_west_route.gd, para comparar editor
## e release com os mesmos interruptores (variáveis de ambiente).
## Uso: GetecoV2.exe -- --no-save --benchmark --no-dispatch --benchmark-route=oeste --play-at=harbor,64,82 --label=x
##      (porto: --benchmark-route=porto --play-at=harbor,150,82). Grava user://benchmark-west/<label>.json e sai.
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
}
const SPEED := 12.0
var WARMUP_LOOPS := 1
const MEASURE_LOOPS := 2
const TOGGLES := ["GETECO_POP_VC", "GETECO_SUN_SHADOW_NEAR", "GETECO_TRAFFIC_RAILS", "GETECO_PED_POSE_LOD", "GETECO_LIGHT_BUDGET",
	"GETECO_DETAIL_RANGE", "GETECO_BAKED_BUILDINGS", "GETECO_SKID_BUDGET", "GETECO_DASH_BATCH", "GETECO_DISPATCH_FAST",
	"GETECO_PED_DUMMY", "GETECO_BUILDING_BATCH", "GETECO_PROP_INSTANCING", "GETECO_GROUND_STACK", "GETECO_SHADOW_SHELL",
	"GETECO_BRIDGE_MERGE", "GETECO_FURNITURE_MERGE", "GETECO_CELL_MERGE", "GETECO_BRIDGE_LOOK"]

var world: Node
var route: Array = ROUTE_WEST
var label := "release"
var route_name := ""

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
	var weather: Variant = world.session.weather
	weather.time_of_day = 12.0 / 24.0
	if "weather_state" in weather: weather.weather_state = 0
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
		"frames_over_100ms": frames.filter(func(ms): return ms > 100.0).size(), "frames_over_250ms": frames.filter(func(ms): return ms > 250.0).size(),
		"resolution": str(get_viewport().get_visible_rect().size), "vehicles": world.production.vehicles.size(), "people": world.people.size()}
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
