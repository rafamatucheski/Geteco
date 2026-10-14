extends SceneTree
## Benchmark controlado do oeste do porto (2026-10-13): mesmo circuito, hora, clima e câmera em cada rodada,
## uma variável por vez. Responde quanto cada sistema custa de verdade em tempo de quadro e de GPU, em vez de
## comparar partidas livres (trajeto, polícia e clima diferentes). Não roda em --headless: precisa da GPU.
##
## Uso: "$GODOT" --path . --script res://tests/measure/benchmark_west_route.gd -- --no-save --benchmark --no-dispatch \
##        --play-at=harbor,64,82 --label=base [--sem-reflexos] [--sem-sombras]
## Interruptores do jogo valem como variável de ambiente: GETECO_BUILDING_BATCH=0, GETECO_PROP_INSTANCING=0,
## GETECO_GROUND_STACK=1; pessoas e trânsito com --population=0 --no-traffic.
## Grava evidence/benchmark-west/<label>.json (só o JSON é versionado).
const ROUTE_WEST := [Vector3(64, 0, 82), Vector3(150, 0, 82), Vector3(143, 0, 60), Vector3(84, 0, 60), Vector3(84, 0, 123), Vector3(65, 0, 113)]
## Pontos quentes de draw calls (2026-10-14): cais do Northstar (x 192–256, z 64–128) e ponte da fundição
## (x 192–256, z 0–64), os trechos com 2.100–2.600 draw calls no export. Use com --play-at=harbor,150,82.
const ROUTE_PORT := [Vector3(150, 0, 82), Vector3(250, 0, 82), Vector3(250, 0, 30), Vector3(180, 0, 30), Vector3(180, 0, 82)]
var ROUTE: Array = ROUTE_WEST
const SPEED := 12.0
const WARMUP_LOOPS := 1
const MEASURE_LOOPS := 2

var label := "medicao"
var no_reflections := false
var no_shadows := false
var hour := 12.0
var rain := false
var max_steps := 0
var world: Variant

func _initialize() -> void: run.call_deferred()

func _arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument == "--rota=porto": ROUTE = ROUTE_PORT
		if argument == "--sem-reflexos": no_reflections = true
		if argument == "--sem-sombras": no_shadows = true
		if argument.begins_with("--hora="): hour = float(argument.trim_prefix("--hora="))
		if argument == "--chuva": rain = true
		if argument.begins_with("--max-passos="): max_steps = int(argument.trim_prefix("--max-passos="))

func _route_point(distance: float) -> Dictionary:
	var lengths: Array[float] = []
	var total := 0.0
	for index in ROUTE.size():
		var a: Vector3 = ROUTE[index]
		var b: Vector3 = ROUTE[(index + 1) % ROUTE.size()]
		lengths.append(a.distance_to(b))
		total += lengths[-1]
	var along := fposmod(distance, total)
	for index in ROUTE.size():
		if along <= lengths[index]:
			var a: Vector3 = ROUTE[index]
			var b: Vector3 = ROUTE[(index + 1) % ROUTE.size()]
			var t := along / lengths[index]
			return {"point": a.lerp(b, t), "yaw": atan2(-(b - a).x, -(b - a).z), "total": total}
		along -= lengths[index]
	return {"point": ROUTE[0], "yaw": 0.0, "total": total}

func _reflection_node() -> Node:
	var found := root.find_children("CoastalPlanarReflections", "", true, false)
	return found[0] if not found.is_empty() else null

func run() -> void:
	_arguments()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	# Sem v-sync nem limite de fps: com 60 Hz o tempo de quadro fica preso em 16,7 ms e esconde diferenças.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if max_steps > 0: Engine.max_physics_steps_per_frame = max_steps
	# Condições fixas (meio-dia e céu limpo por padrão), sem troca de clima durante a rodada.
	var weather: Variant = world.session.weather
	weather.time_of_day = hour / 24.0
	if "weather_state" in weather: weather.weather_state = 1 if rain else 0
	if rain and "rain_intensity" in weather: weather.rain_intensity = .25
	if rain and "coastal_wetness" in weather: weather.coastal_wetness = 1.0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	var reflections := _reflection_node()
	if no_reflections and reflections != null:
		reflections.set_process(false)
		for view_name in ["ground_view", "facade_view"]:
			var view: SubViewport = reflections.get(view_name)
			if view != null: view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if no_shadows:
		for light in root.find_children("*", "DirectionalLight3D", true, false):
			if light.get_world_3d() == root.world_3d: light.shadow_enabled = false
	# Carro como alvo da câmera (enquadramento de direção); o jogador acompanha para o streaming seguir.
	var car: CharacterBody3D = world.driving.car
	car.set_physics_process(false)
	car.visible = true
	world.player.set_physics_process(false)
	world.player.visible = false
	world.camera.target = car
	var viewports: Array[RID] = [root.get_viewport_rid()]
	if reflections != null:
		for view_name in ["ground_view", "facade_view"]:
			var view: SubViewport = reflections.get(view_name)
			if view != null: viewports.append(view.get_viewport_rid())
	for rid in viewports: RenderingServer.viewport_set_measure_render_time(rid, true)
	var total: float = _route_point(0.0).total
	var distance := 0.0
	var frames: Array[float] = []
	var gpu: Array[float] = []
	var gpu_main: Array[float] = []
	var draws: Array[float] = []
	var primitives: Array[float] = []
	var previous := Time.get_ticks_usec()
	while distance < total * (WARMUP_LOOPS + MEASURE_LOOPS):
		var sample := _route_point(distance)
		car.global_position = sample.point + Vector3.UP * .1
		car.rotation = Vector3(0, sample.yaw, 0)
		world.player.global_position = sample.point
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := (now - previous) / 1000.0
		previous = now
		# Distância pelo tempo real: quadro lento anda mais, como no jogo.
		distance += SPEED * minf(frame_ms, 100.0) / 1000.0
		if distance < total * WARMUP_LOOPS: continue
		frames.append(frame_ms)
		var gpu_total := 0.0
		for rid in viewports: gpu_total += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		gpu.append(gpu_total)
		gpu_main.append(RenderingServer.viewport_get_measured_render_time_gpu(viewports[0]))
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var report := {
		"label": label, "build": "editor" if OS.has_feature("editor") else ("export_release" if OS.has_feature("release") else "export_debug"),
		"frames": frames.size(), "frame_ms": _stats(frames), "gpu_ms_total": _stats(gpu), "gpu_ms_main": _stats(gpu_main),
		"draw_calls": _stats(draws), "primitives": _stats(primitives),
		"settings": {"sem_reflexos": no_reflections, "sem_sombras": no_shadows, "rota": "porto" if ROUTE == ROUTE_PORT else "oeste", "hora": hour, "chuva": rain, "max_passos_fisica": Engine.max_physics_steps_per_frame,
			"motor_fisica": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
			"args": OS.get_cmdline_user_args(), "toggles": _toggles()},
		"vehicles": world.production.vehicles.size(), "people": world.people.size(),
		"scope": "circuito fixo no oeste a %.0f m/s, 1 volta de aquecimento e %d medidas; gpu_ms_total soma a tela e as vistas de reflexo" % [SPEED, MEASURE_LOOPS],
	}
	var folder := "res://evidence/benchmark-west"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder + "/" + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BENCH_WEST ", JSON.stringify({"label": label, "frame_p50": report.frame_ms.p50, "frame_p95": report.frame_ms.p95, "gpu_total_p50": report.gpu_ms_total.p50, "gpu_main_p50": report.gpu_ms_main.p50, "draws_p50": report.draw_calls.p50, "frames": frames.size()}))
	quit(0)

func _toggles() -> Dictionary:
	var result := {}
	for name in ["GETECO_POP_VC", "GETECO_SUN_SHADOW_NEAR", "GETECO_TRAFFIC_RAILS", "GETECO_PED_POSE_LOD", "GETECO_LIGHT_BUDGET",
			"GETECO_DETAIL_RANGE", "GETECO_BAKED_BUILDINGS", "GETECO_SKID_BUDGET", "GETECO_DASH_BATCH", "GETECO_DISPATCH_FAST", "GETECO_PED_DUMMY",
			"GETECO_BUILDING_BATCH", "GETECO_PROP_INSTANCING", "GETECO_GROUND_STACK"]:
		result[name] = OS.get_environment(name)
	return result

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted: total += value
	var count := sorted.size()
	return {"mean": snappedf(total / count, 0.01), "p50": snappedf(sorted[count / 2], 0.01),
		"p95": snappedf(sorted[mini(count - 1, int(count * .95))], 0.01), "p99": snappedf(sorted[mini(count - 1, int(count * .99))], 0.01),
		"max": snappedf(sorted[-1], 0.01)}
