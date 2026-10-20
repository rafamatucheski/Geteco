extends Node
## Benchmark controlado dentro do jogo (2026-10-14): o export ignora `--script`, e a pasta tests/ não vai no
## pacote. Mesmo circuito, hora, clima e câmera de tests/measure/benchmark_west_route.gd, para comparar editor
## e release com os mesmos interruptores (variáveis de ambiente).
## Uso: GetecoV2.exe -- --no-save --benchmark --no-dispatch --benchmark-route=oeste --play-at=harbor,64,82 --label=x
##      (porto: --benchmark-route=porto --play-at=harbor,150,82). Grava user://benchmark-west/<label>.json e sai.
## Noite e chuva (15/10): --benchmark-hour=H (0..24, padrão 12) e --benchmark-rain[=1|2] (2 tempestade, padrão;
## 1 garoa) com o chão já molhado. Exercitam o que o meio-dia seco não liga: postes/faróis/janelas, sombras de
## faróis, partículas de chuva, respingos e a captura do reflexo do chão molhado. Sem as opções, nada muda.
## Caos (15/10): --benchmark-chaos=N (1..6) mantém N estrelas do começo ao fim, com a polícia sabendo onde o
## carro está, para medir despacho, viaturas, sirenes/luzes e reação civil. Sem --no-dispatch (senão não há
## despacho). As rotas e o resto da medição ficam iguais; o jogador fica invencível só nesse modo.
## Dirigindo (15/10): --benchmark-drive faz o carro andar a rota com a própria física e direção
## automática (BenchmarkAutopilot), para medir o custo de dirigir que o teleporte não exercita.
## Eventos de estrada (19/10): --benchmark-road-events, só na rota66, força uma van quebrada na ida e um
## bloqueio de bandidos na volta, em cada volta medida, nos trechos da Route 66 (DesertRoadEvents.force_start).
## O disparo do jogo pede o jogador ao volante (aqui o carro é teleportado e o jogador não entra nele) e
## sorteia o tipo e a hora, o que deixaria o A/B sem par. Com GETECO_DESERT_ROADSIDE=0 não existe evento e
## as chamadas não fazem nada: o lado desligado anda a mesma rota. Jogador e carro ficam invencíveis.
const ROUTE_WEST := [Vector3(64, 0, 82), Vector3(150, 0, 82), Vector3(143, 0, 60), Vector3(84, 0, 60), Vector3(84, 0, 123), Vector3(65, 0, 113)]
const ROUTE_PORT := [Vector3(150, 0, 82), Vector3(250, 0, 82), Vector3(250, 0, 30), Vector3(180, 0, 30), Vector3(180, 0, 82)]
## Pontos quentes das outras regiões (censo de 14/10). Serra: --play-at=mountain,650,-290; ponte cidade–serra:
## --play-at=harbor,440,-285; deserto (encontro de arrancada, trechos de 96 m): --play-at=desert,-1040,-1320.
const ROUTES := {
	"serra": [Vector3(650, 4, -290), Vector3(745, 4, -300), Vector3(745, 4, -425), Vector3(660, 4, -425)],
	"ponte": [Vector3(440, 0, -285), Vector3(600, 0, -285)],
	"ponte_norte": [Vector3(364.55,.032,-254),Vector3(342.5,2.4,-280),Vector3(342.5,2.4,-373.5),Vector3(342.5,0,-445)],
	"ponte_tronco": [Vector3(382.5,0,-130),Vector3(382.5,0,-248),Vector3(386,0,-278),Vector3(405,0,-282),Vector3(382.5,0,-248),Vector3(382.5,0,-130)],
	# Porto -> ponte -> serra e volta: o streaming entra em trechos novos com o jogo rodando (travadas de 15/10).
	"travessia": [Vector3(330, 0, -285), Vector3(600, 0, -285), Vector3(700, 4, -300), Vector3(745, 4, -420)],
	"deserto": [Vector3(-1040, 0, -1320), Vector3(-950, 0, -1320), Vector3(-950, 0, -1260), Vector3(-1040, 0, -1260)],
	# Estrada do sal: câmera e população reais ao lado do trajeto das cargas da madrugada.
	"carga_deserto": [Vector3(-700, 0, -1542.5), Vector3(-500, 0, -1542.5)],
	# Rota 66 do pedágio à estrada do sal (17/10): ~11 trechos novos se vestindo com o jogo rodando
	# (chão povoado do deserto, A/B com GETECO_DESERT_GROUND_COVER=0). --play-at=desert,342.5,-470.
	"rota66": [Vector3(347, 0, -470), Vector3(347, 0, -1500), Vector3(347, 0, -470)],
	# Cidade do deserto (20/10): rua principal de ponta a ponta, com o acabamento novo (calçadas, pátios,
	# fachadas) montando e estacionando. A/B com GETECO_DESERT_ROADSIDE=0. --play-at=desert,-360,-893.
	"cidade_deserto": [Vector3(-360, 0, -893), Vector3(-40, 0, -893), Vector3(-360, 0, -893)],
	# Estrada do Sal (20/10): motel, balança, capela e salinas ao lado da pista. --play-at=desert,-1150,-1542.5.
	"estrada_sal": [Vector3(-1150, 0, -1542.5), Vector3(150, 0, -1542.5)],
	# Northbank e canal concentram 6 dos 15 sobrados/terraços (A/B das janelas pintadas, 15/10).
	"sobrados": [Vector3(295, 0, 100), Vector3(340, 0, 100), Vector3(340, 0, -60), Vector3(295, 0, -60)],
}
const SPEED := 12.0
var WARMUP_LOOPS := 1
const MEASURE_LOOPS := 2
const TOGGLES := ["GETECO_OCCLUSION", "GETECO_PROC_LOD", "GETECO_TUNNEL_LIGHT_SHADOWS", "GETECO_LOCAL_SHADOW_PREWARM",
	"GETECO_HEADLIGHT_SHADOW_POLICY", "GETECO_SUN_SHADOW_TUNE", "GETECO_GROUND_OPAQUE", "GETECO_SUBVIEWPORT_MSAA_MATCH", "GETECO_POP_VC", "GETECO_SUN_SHADOW_NEAR", "GETECO_TRAFFIC_RAILS", "GETECO_PED_POSE_LOD", "GETECO_LIGHT_BUDGET",
	"GETECO_DETAIL_RANGE", "GETECO_BAKED_BUILDINGS", "GETECO_SKID_BUDGET", "GETECO_DASH_BATCH", "GETECO_DISPATCH_FAST",
	"GETECO_PED_DUMMY", "GETECO_BUILDING_BATCH", "GETECO_PROP_INSTANCING", "GETECO_GROUND_STACK", "GETECO_SHADOW_SHELL",
	"GETECO_BRIDGE_MERGE", "GETECO_FURNITURE_MERGE", "GETECO_CELL_MERGE", "GETECO_BRIDGE_LOOK", "GETECO_PAINTED_WINDOWS", "GETECO_PAINTED_FACADES",
	"GETECO_SUN_SPLITS", "GETECO_UNIFIED_BRIDGE", "GETECO_DESERT_CARGO_HEIST", "GETECO_DESERT_ROADSIDE", "GETECO_RAGDOLL"]
## Distância ao longo da volta da rota66 (ida para o sul de z -470, volta a partir de z -1500) em que cada
## evento nasce, 240 m antes do ponto, como o jogo faria: a van na mão da ida, o bloqueio na mão da volta
## (o carro do benchmark anda na faixa leste nos dois sentidos, então desvia dele pela outra mão).
const ROAD_EVENT_CUES := [
	{"at": 290.0, "kind": "breakdown", "point": Vector2(342.5, -1000), "direction": Vector2(0, -1)},
	{"at": 1300.0, "kind": "roadblock", "point": Vector2(342.5, -990), "direction": Vector2(0, 1)},
]

const AUTOPILOT := preload("res://runtime/BenchmarkAutopilot.gd")

var world: Node
var route: Array = ROUTE_WEST
var label := "release"
var route_name := ""
var bench_hour := 12.0
var bench_rain := 0
var chaos_stars := 0
var _chaos_clock := 0.0
var _chaos_peak_units := 0
var _cargo_peak_trucks := 0
var _cargo_peak_guards := 0
var _cargo_peak_alive_guards := 0
var _cargo_observation_due := 0
var _cargo_observed_seconds := 0
var road_events := false
var _road_events_fired := {}
var _road_event_log: Array = []
var _road_event_engaged_frames := 0

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
		if argument.begins_with("--benchmark-chaos="): chaos_stars = clampi(int(argument.trim_prefix("--benchmark-chaos=")), 0, 6)
		if argument == "--benchmark-road-events": road_events = true
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
	var autopilot: RefCounted = AUTOPILOT.new(self, car, route, SPEED) if AUTOPILOT.requested() else null
	if autopilot != null: autopilot.begin()
	else: car.set_physics_process(false)
	car.visible = true
	world.player.set_physics_process(false)
	world.player.visible = false
	# O jogador é posto no carro a cada quadro, mas sem entrar nele: a cápsula dele (camada 2)
	# continuava sólida e o carro (máscara 7) colidia com ela e era empurrado pelo chão. Na
	# rodada dirigindo de 17/10 foram 236 quedas e 0,34 m/s de média. Driving zera a camada
	# ao entrar no carro; aqui fazemos o mesmo.
	world.player.collision_layer = 0
	world.camera.target = car
	if chaos_stars > 0 and not world.gameplay.god_mode: world.gameplay.toggle_god_mode()
	road_events = road_events and route_name == "rota66"
	if road_events:
		# O carro passa a ser o alvo, como ao volante no jogo: com o jogador escondido e dentro da
		# lataria, police_can_see nunca via ninguém e o bloqueio não atirava (primeira rodada de 19/10,
		# 0 quadros em combate). Driving só põe o jogador na posição do carro, o que o benchmark já faz;
		# o carro segue teleportado, sem velocidade, então o disparo natural de evento não acontece.
		world.driving.occupied = true
		if not world.gameplay.god_mode: world.gameplay.toggle_god_mode()
		car.set_meta(preload("res://gameplay/DamageProtection.gd").META, true)
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
		if autopilot == null:
			car.global_position = sample.point + Vector3.UP * .1
			car.rotation = Vector3(0, sample.yaw, 0)
		world.player.global_position = sample.point if autopilot == null else car.global_position
		if chaos_stars > 0: _sustain_chaos(sample.point)
		if route_name == "carga_deserto" and distance >= total * WARMUP_LOOPS: _observe_cargo()
		if road_events and distance >= total * WARMUP_LOOPS: _road_events(distance, total)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := (now - previous) / 1000.0
		previous = now
		if autopilot != null: distance = autopilot.drive(minf(frame_ms, 100.0) / 1000.0)
		else: distance += SPEED * minf(frame_ms, 100.0) / 1000.0
		if distance < total * WARMUP_LOOPS: continue
		frames.append(frame_ms)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if autopilot != null: autopilot.finish()
	var toggles := {}
	for name in TOGGLES: toggles[name] = OS.get_environment(name)
	var measured_ms := 0.0
	for frame_ms in frames: measured_ms += frame_ms
	var report := {"label": label, "build": "editor" if OS.has_feature("editor") else ("export_release" if OS.has_feature("release") else "export_debug"),
		"route": route_name if route_name != "" else ("porto" if route == ROUTE_PORT else "oeste"), "frames": frames.size(), "frame_ms": _stats(frames),
		"duration_ms": measured_ms, "average_fps": frames.size()*1000.0/maxf(measured_ms,.001), "frame_samples_ms": frames,
		"gpu_ms_main": _stats(gpu), "draw_calls": _stats(draws), "toggles": toggles,
		"frames_over_66_7ms": frames.filter(func(ms): return ms > 66.7).size(),
		"frames_over_100ms": frames.filter(func(ms): return ms > 100.0).size(),
		"frames_over_6_9ms": frames.filter(func(ms): return ms > 6.94).size(), "frames_over_16_7ms": frames.filter(func(ms): return ms > 16.7).size(),
		"frames_over_33ms": frames.filter(func(ms): return ms > 33.3).size(), "playable_ms": playable_ms, "frames_over_250ms": frames.filter(func(ms): return ms > 250.0).size(),
		"resolution": str(get_viewport().get_visible_rect().size), "viewport_pixels": str(get_viewport().size), "msaa": get_viewport().msaa_3d,
		"hour": bench_hour, "rain": bench_rain, "vehicles": world.production.vehicles.size(), "people": world.people.size(),
		"requested_population": world.production.requested_population, "vsync_mode": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(), "graphics": _graphics_report()}
	if chaos_stars > 0:
		report.chaos = {"stars_requested": chaos_stars, "stars_final": int(world.gameplay.stars), "dispatch_units_peak": _chaos_peak_units,
			"dispatch_units_final": world.dispatch.units.size() if is_instance_valid(world.get("dispatch")) else -1}
	if autopilot != null: report.drive = autopilot.summary()
	if road_events:
		report.road_events = {"cues": _road_event_log, "engaged_frames": _road_event_engaged_frames,
			"scope": "Eventos forçados na rota66 (van na ida, bloqueio na volta) em cada volta medida; sem eles com GETECO_DESERT_ROADSIDE=0."}
	if route_name == "carga_deserto":
		report.cargo = {"trucks_peak":_cargo_peak_trucks,"guards_peak":_cargo_peak_guards,"alive_guards_peak":_cargo_peak_alive_guards,
			"scope":"Rota renderizada da estrada do sal; observação de carga ativa, sem simular combate ou abertura.",
			"activity_observed":_cargo_peak_trucks > 0,"activity_observed_seconds":_cargo_observed_seconds}
	print("BENCH_RELEASE ", JSON.stringify({"label": label, "frame_p50": report.frame_ms.p50, "frame_p95": report.frame_ms.p95, "draws_p50": report.draw_calls.p50}))
	var folder := "user://benchmark-west"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder + "/" + label + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	get_tree().quit(0)

## Todas as opções gráficas que valeram na rodada (auditoria 19/10, §1): antes o JSON só tinha resolução,
## MSAA e vsync, e o settings.cfg do jogador mudou SSAO, névoa, escala e sombra entre rodadas sem deixar
## rastro. Grava a preferência lida (settings) e o que o motor está usando (applied), porque os dois podem
## divergir: o benchmark desliga vsync/FPS, e SSAO/névoa só valem no Forward+.
func _graphics_report() -> Dictionary:
	const SETTINGS := preload("res://runtime/Settings.gd")
	var view := get_viewport()
	var report := {"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"project_rendering_method": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"video_adapter": RenderingServer.get_video_adapter_name(), "video_api": RenderingServer.get_video_adapter_api_version(),
		"settings_path": "", "settings_file_found": false, "preset": "", "settings": {},
		"engine_args": OS.get_cmdline_args(), "user_args": OS.get_cmdline_user_args(),
		# override.cfg ao lado do exe muda o projeto sem recompilar (bancada: GETECO_TRACK_CALL_STACKS=1).
		"always_track_call_stacks": bool(ProjectSettings.get_setting("debug/settings/gdscript/always_track_call_stacks", false)),
		"override_cfg_present": FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join("override.cfg"))}
	var settings: Node = get_node_or_null("/root/V2Settings")
	if settings != null:
		var path: String = SETTINGS.default_path()
		report.settings_path = path
		report.settings_file_found = FileAccess.file_exists(path)
		# graphics_preset() só existe com as opções gráficas novas; sem elas, "personalizado".
		var preset: int = settings.graphics_preset() if settings.has_method("graphics_preset") else 0
		report.preset = ["personalizado", "baixa", "media", "alta"][clampi(preset, 0, 3)]
		var chosen := {}
		for key in ["msaa", "render_scale", "shadow_quality", "aa_mode", "upscale_mode", "shadow_distance", "anisotropy",
				"reflection_quality", "detail_quality", "ssao", "volumetric_fog", "glow", "glow_strength"]:
			chosen[key] = settings.get(key)
		for key in ["window_mode", "resolution", "vsync", "fps_limit", "brightness"]: chosen[key] = settings.get(key)
		chosen["resolution_size"] = str(SETTINGS.RESOLUTIONS[clampi(int(settings.resolution), 0, SETTINGS.RESOLUTIONS.size() - 1)])
		chosen["fps_limit_value"] = SETTINGS.FPS_LIMITS[clampi(int(settings.fps_limit), 0, SETTINGS.FPS_LIMITS.size() - 1)]
		chosen["shadow_atlas"] = SETTINGS.SHADOW_ATLAS[clampi(int(settings.shadow_quality), 0, 2)]
		chosen["shadow_distance_m"] = settings.shadow_distance_metres()
		report.settings = chosen
	var environment: Environment = view.find_world_3d().environment if view.find_world_3d() != null else null
	report.applied = {"msaa_3d": view.msaa_3d, "screen_space_aa": view.screen_space_aa, "use_taa": view.use_taa,
		"scaling_3d_mode": view.scaling_3d_mode, "scaling_3d_scale": view.scaling_3d_scale,
		"anisotropic_filtering_level": view.anisotropic_filtering_level, "mesh_lod_threshold": view.mesh_lod_threshold,
		"pipeline_msaa_3d": int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)),
		"max_fps": Engine.max_fps, "vsync_mode": DisplayServer.window_get_vsync_mode(),
		"window_mode": DisplayServer.window_get_mode(), "window_size": str(DisplayServer.window_get_size()),
		"screen_size": str(DisplayServer.screen_get_size()), "screen_scale": DisplayServer.screen_get_scale(),
		"viewport_pixels": str(view.size), "max_physics_steps": Engine.max_physics_steps_per_frame,
		"environment_found": environment != null}
	if environment != null:
		report.applied.merge({"ssao": environment.ssao_enabled, "ssr": environment.ssr_enabled, "ssil": environment.ssil_enabled,
			"sdfgi": environment.sdfgi_enabled, "volumetric_fog": environment.volumetric_fog_enabled,
			"glow": environment.glow_enabled, "glow_intensity": environment.glow_intensity, "fog": environment.fog_enabled})
	return report

func _road_events(distance: float, total: float) -> void:
	var session = world.session
	var events: Variant = null
	if session.desert != null and is_instance_valid(session.desert.frontier) and is_instance_valid(session.desert.frontier.get("roadside")):
		events = session.desert.frontier.roadside.get("events")
	if not is_instance_valid(events): return
	if not events.event.is_empty() and events.event.get("engaged", false): _road_event_engaged_frames += 1
	var loop := int(distance / total)
	var along := fposmod(distance, total)
	for index in ROAD_EVENT_CUES.size():
		var cue: Dictionary = ROAD_EVENT_CUES[index]
		var key := "%d:%d" % [loop, index]
		if along < float(cue.at) or _road_events_fired.has(key): continue
		# Como no jogo: sem o chão do ponto pronto, tenta de novo no quadro seguinte (até 150 m depois).
		var started: bool = events.force_start(str(cue.kind), cue.point, cue.direction)
		if not started and along < float(cue.at) + 150.0: continue
		_road_events_fired[key] = true
		_road_event_log.append({"loop": loop, "kind": str(cue.kind), "started": started, "late_m": snappedf(along - float(cue.at), .1), "at_msec": Time.get_ticks_msec()})

func _observe_cargo() -> void:
	# Uma leitura por segundo registra a carga alcançada sem varrer entidades por quadro.
	var now := Time.get_ticks_msec()
	if now < _cargo_observation_due: return
	_cargo_observation_due = now + 1000
	var desert: Variant = world.session.get("desert")
	if desert == null: return
	var heist: Variant = desert.get("heist")
	if heist == null: return
	_cargo_peak_trucks = maxi(_cargo_peak_trucks, 1 if is_instance_valid(heist.get("truck")) else 0)
	if is_instance_valid(heist.get("truck")): _cargo_observed_seconds += 1
	var guards: Variant = heist.get("guards")
	if guards is Array or guards is Dictionary:
		var present := 0
		var alive := 0
		for guard in (guards.values() if guards is Dictionary else guards):
			if not is_instance_valid(guard): continue
			present += 1
			if not guard.dead: alive += 1
		_cargo_peak_guards = maxi(_cargo_peak_guards, present)
		_cargo_peak_alive_guards = maxi(_cargo_peak_alive_guards, alive)

## Uma vez por segundo repõe o crime que faltar para N estrelas e informa a posição atual do carro
## (o benchmark teleporta o carro; sem o contato a polícia perderia o alvo e as estrelas cairiam).
func _sustain_chaos(point: Vector3) -> void:
	var units: int = world.dispatch.units.size() if is_instance_valid(world.get("dispatch")) else 0
	_chaos_peak_units = maxi(_chaos_peak_units, units)
	var now := Time.get_ticks_msec() / 1000.0
	if now < _chaos_clock: return
	_chaos_clock = now + 1.0
	var gameplay = world.gameplay
	if int(gameplay.stars) < chaos_stars:
		var needed: int = int(gameplay.STAR_THRESHOLDS[chaos_stars]) - int(gameplay.crime_points)
		gameplay.register_crime(maxi(needed, 1), point, "benchmark_chaos")
	gameplay.report_contact(point)

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
