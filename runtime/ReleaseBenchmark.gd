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
## Atropelamento (19/10): --benchmark-runover atropela, a cada RUNOVER_SECONDS da parte medida, um pedestre
## de uma reserva montada no aquecimento, logo à frente do carro e com o impacto do jogo (BodyFlight3D a
## 10 m/s, não letal, com o diretor de rua). Quem cai é levantado depois de 3 s e volta à reserva. A/B do
## ragdoll com GETECO_RAGDOLL=0 (voo varrido antigo) na mesma rota e no mesmo export.
## Gravação (21/10): --benchmark-save=S chama o salvamento automático real (FullSession.save_game) a cada S
## segundos da parte medida, num arquivo da bancada (user://benchmark-west/save-probe/<label>.json), nunca no
## slot do jogador. Na partida de 21/10 (binário do editor) foram 29 salvamentos de ~33 ms. O JSON ganha
## save_probe com o tempo de cada chamada e as etapas de SaveStore (spans save.*); A/B da verificação por
## bytes com GETECO_SAVE_VERIFY=0 no mesmo export.
## Estresse (21/10, pedido do jogador: "liso com chuva, nessa resolução, tiro, alta velocidade"): opções que
## se somam às de cima. --benchmark-speed=V anda a rota a V m/s (padrão 12; também o alvo do piloto
## automático); --benchmark-shoot dá um fuzil com munição e atira à frente do carro sempre que a arma
## deixa (Gameplay.fire_at, o caminho do jogo, com recarga); --benchmark-explode=S destrói a cada S s um
## carro do trânsito a 10–50 m (explosão, fogo e carcaça do jogo); --benchmark-measure-seconds=N mede N s
## (em voltas quantas couberem) em vez de 2 voltas; --benchmark-cold mede desde o primeiro quadro jogável
## (sem volta de aquecimento) e o JSON ganha first_60s. --benchmark-stress liga o pacote: chuva forte,
## 3 estrelas (despacho LIGADO: rodar sem --no-dispatch), carro como alvo, tiro, explosão a cada 8 s,
## 25 m/s e 90 s medidos. Cada parte continua desligável pelo seu interruptor do jogo (GETECO_*).
const ROUTE_WEST := [Vector3(64, 0, 82), Vector3(150, 0, 82), Vector3(143, 0, 60), Vector3(84, 0, 60), Vector3(84, 0, 123), Vector3(65, 0, 113)]
const ROUTE_PORT := [Vector3(150, 0, 82), Vector3(250, 0, 82), Vector3(250, 0, 30), Vector3(180, 0, 30), Vector3(180, 0, 82)]
## Pontos quentes das outras regiões (censo de 14/10). Serra: --play-at=mountain,650,-290; ponte cidade–serra:
## --play-at=harbor,440,-285; deserto (encontro de arrancada, trechos de 96 m): --play-at=desert,-900,-800.
const ROUTES := {
	"serra": [Vector3(650, 4, -290), Vector3(745, 4, -300), Vector3(745, 4, -425), Vector3(660, 4, -425)],
	"ponte": [Vector3(440, 0, -285), Vector3(600, 0, -285)],
	"ponte_norte": [Vector3(364.55,.032,-254),Vector3(342.5,2.4,-280),Vector3(342.5,2.4,-373.5),Vector3(342.5,0,-445)],
	"ponte_tronco": [Vector3(382.5,0,-130),Vector3(382.5,0,-248),Vector3(386,0,-278),Vector3(405,0,-282),Vector3(382.5,0,-248),Vector3(382.5,0,-130)],
	# Porto -> ponte -> serra e volta: o streaming entra em trechos novos com o jogo rodando (travadas de 15/10).
	"travessia": [Vector3(330, 0, -285), Vector3(600, 0, -285), Vector3(700, 4, -300), Vector3(745, 4, -420)],
	"deserto": [Vector3(-900,0,-800), Vector3(-810,0,-800), Vector3(-810,0,-740), Vector3(-900,0,-740)],
	# Estrada do sal: câmera e população reais ao lado do trajeto das cargas da madrugada.
	"carga_deserto": [Vector3(-560,0,-902.5), Vector3(-360,0,-902.5)],
	# Rota 66 do pedágio à estrada do sal (17/10): ~11 trechos novos se vestindo com o jogo rodando
	# (chão povoado do deserto, A/B com GETECO_DESERT_GROUND_COVER=0). --play-at=desert,342.5,-470.
	"rota66": [Vector3(347, 0, -470), Vector3(347, 0, -860), Vector3(347, 0, -470)],
	# Cidade do deserto (20/10): rua principal de ponta a ponta, com o acabamento novo (calçadas, pátios,
	# fachadas) montando e estacionando. A/B com GETECO_DESERT_ROADSIDE=0. --play-at=desert,-360,-553.
	"cidade_deserto": [Vector3(-360,0,-553), Vector3(-40,0,-553), Vector3(-360,0,-553)],
	# Estrada do Sal (20/10): motel, balança, capela e salinas ao lado da pista. --play-at=desert,-1010,-902.5.
	"estrada_sal": [Vector3(-1010, 0, -902.5), Vector3(290, 0, -902.5)],
	# Cavernas (20/10): passa a ~30 m da caverna do coiote e a ~50 m da do Vicente, cruzando a
	# estrada do sal; cada morro monta a 110 m. A/B com GETECO_DESERT_WILDS=0. --play-at=desert,-980,-960.
	"cavernas": [Vector3(-980,0,-960),Vector3(-1260,0,-960),Vector3(-1260,0,-1120),Vector3(-1050,0,-1120),Vector3(-980,0,-960)],
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
	"GETECO_SUN_SPLITS", "GETECO_UNIFIED_BRIDGE", "GETECO_DESERT_CARGO_HEIST", "GETECO_DESERT_ROADSIDE", "GETECO_RAGDOLL",
	"GETECO_SAVE_VERIFY", "GETECO_CITY_LIFE_AUDIO", "GETECO_GTA_CHASE", "GETECO_RAIN_PREWARM"]
## Distância ao longo da volta da rota66 (ida para o sul de z -470, volta a partir de z -860) em que cada
## evento nasce, 100 m antes do ponto, como o jogo faria: a van na mão da ida, o bloqueio na mão da volta
## (o carro do benchmark anda na faixa leste nos dois sentidos, então desvia dele pela outra mão).
const ROAD_EVENT_CUES := [
	{"at": 130.0, "kind": "breakdown", "point": Vector2(342.5, -700), "direction": Vector2(0, -1)},
	{"at": 490.0, "kind": "roadblock", "point": Vector2(342.5, -660), "direction": Vector2(0, 1)},
]

const AUTOPILOT := preload("res://runtime/BenchmarkAutopilot.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const RUNOVER_SECONDS := 1.5
const RUNOVER_POOL := 6

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
var runover := false
var _runover_pool: Array = []
var _runover_due := 0
var _runover_launch_ms: Array[float] = []
var _runover_ragdolls := 0
var _runover_director: Node
var save_every := 0.0
var _save_clock := 0.0
var _save_ms: Array[float] = []
var _save_failures := 0
var _save_stages := {}
var speed := SPEED
var measure_seconds := 0.0
var shoot := false
var _shots := 0
var _shot_attempts := 0
var _shots_by_weapon := {}
var explode_every := 0.0
var _explode_clock := 0.0
var _explosions := 0
var _explode_misses := 0
var cold := false
## --benchmark-weapon-cycle=S: troca de arma a cada S s (pistola, submetralhadora, escopeta, fuzil) e
## segue atirando com a da vez; mede a montagem do modelo na mão (span gameplay.weapon_visual).
const CYCLE_WEAPONS := ["pistol", "smg", "shotgun", "ak47"]
var weapon_cycle := 0.0
var _weapon_clock := 0.0
var _weapon_index := 0
var _weapon_switches := 0
var _weapon_switch_ms: Array[float] = []

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
		if argument == "--benchmark-runover": runover = true
		if argument.begins_with("--benchmark-save="): save_every = maxf(0.0, float(argument.trim_prefix("--benchmark-save=")))
	var args := OS.get_cmdline_user_args()
	if "--benchmark-stress" in args:
		bench_rain = 2
		chaos_stars = maxi(chaos_stars, 3)
		shoot = true
		explode_every = 8.0
		speed = 25.0
		measure_seconds = 90.0
	for argument in args:
		if argument.begins_with("--benchmark-speed="): speed = clampf(float(argument.trim_prefix("--benchmark-speed=")), 1.0, 80.0)
		if argument.begins_with("--benchmark-measure-seconds="): measure_seconds = maxf(0.0, float(argument.trim_prefix("--benchmark-measure-seconds=")))
		if argument == "--benchmark-shoot": shoot = true
		if argument.begins_with("--benchmark-explode="): explode_every = maxf(0.0, float(argument.trim_prefix("--benchmark-explode=")))
		if argument == "--benchmark-cold": cold = true
		if argument.begins_with("--benchmark-weapon-cycle="): weapon_cycle = maxf(0.0, float(argument.trim_prefix("--benchmark-weapon-cycle=")))
	if weapon_cycle > 0.0: shoot = true
	if cold: WARMUP_LOOPS = 0
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
	# De novo aqui (22/10): a bancada nasce antes de a cortina sair, e o LoadingTurbo devolve o teto do
	# jogador (144) no lift; no A/B o lado "depois" mediu com teto e o p50 do deserto ficou preso em 6,96 ms.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var weather: Variant = world.session.weather
	weather.time_of_day = bench_hour / 24.0
	if "weather_state" in weather: weather.weather_state = bench_rain
	# Chuva já assentada: a umidade da costa leva minutos para subir sozinha e o reflexo do chão
	# só liga acima de 0,015. Sem chuva continua seco, como antes.
	if bench_rain > 0 and "coastal_wetness" in weather: weather.coastal_wetness = 1.0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	var car: CharacterBody3D = world.driving.car
	var autopilot: RefCounted = AUTOPILOT.new(self, car, route, speed) if AUTOPILOT.requested() else null
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
	# Perseguição (21/10): --benchmark-chase põe o carro como alvo (jogador "ao volante"), como os eventos
	# de estrada; com --benchmark-chaos e --benchmark-drive a polícia persegue o carro andando. A/B da
	# perseguição estilo GTA com GETECO_GTA_CHASE=0 no mesmo export. Carro protegido: sem PIT nem batida.
	if _chase_requested():
		world.driving.occupied = true
		if not world.gameplay.god_mode: world.gameplay.toggle_god_mode()
		car.set_meta(preload("res://gameplay/DamageProtection.gd").META, true)
	if shoot: _shoot_prepare()
	road_events = road_events and route_name == "rota66"
	if road_events:
		# O carro passa a ser o alvo, como ao volante no jogo: com o jogador escondido e dentro da
		# lataria, police_can_see nunca via ninguém e o bloqueio não atirava (primeira rodada de 19/10,
		# 0 quadros em combate). Driving só põe o jogador na posição do carro, o que o benchmark já faz;
		# o carro segue teleportado, sem velocidade, então o disparo natural de evento não acontece.
		world.driving.occupied = true
		if not world.gameplay.god_mode: world.gameplay.toggle_god_mode()
		car.set_meta(preload("res://gameplay/DamageProtection.gd").META, true)
	if runover: _runover_prepare()
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var total: float = _route_point(0.0).total
	var distance := 0.0
	var frames: Array[float] = []
	var gpu: Array[float] = []
	var draws: Array[float] = []
	var previous := Time.get_ticks_usec()
	var measured_clock := 0.0
	# Intervalo entre desenhos (22/10): o tempo do laço abaixo é medido no retorno do await, e corrotinas
	# que esperam process_frame (fusões por trecho, fila de vídeo) mudam de lugar dentro do quadro e
	# empurram trabalho de um intervalo para o seguinte. Na 1ª rodada a bancada viu 6 quadros > 33 ms nos
	# sobrados e o registro da sessão, 2. frame_post_draw marca o fim de cada desenho: é o que vai à tela.
	var present_stamps: Array[int] = []
	var measuring_present := [false]
	var on_present := func() -> void:
		if measuring_present[0]: present_stamps.append(Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(on_present)
	while _keep_measuring(distance, total, measured_clock):
		var sample := _route_point(distance)
		if autopilot == null:
			car.global_position = sample.point + Vector3.UP * .1
			car.rotation = Vector3(0, sample.yaw, 0)
		world.player.global_position = sample.point if autopilot == null else car.global_position
		var chaos_span := STALL_WORK.begin()
		if chaos_stars > 0: _sustain_chaos(sample.point)
		STALL_WORK.finish_slow("bench.chaos", chaos_span, 2000)
		if route_name == "carga_deserto" and distance >= total * WARMUP_LOOPS: _observe_cargo()
		if road_events and distance >= total * WARMUP_LOOPS: _road_events(distance, total)
		if runover and distance >= total * WARMUP_LOOPS: _runover(sample.point, sample.yaw)
		if distance >= total * WARMUP_LOOPS:
			var heading: float = sample.yaw if autopilot == null else car.rotation.y
			var at: Vector3 = sample.point if autopilot == null else car.global_position
			# Spans (22/10): este laço roda no sinal process_frame, antes de qualquer _process; o custo de tiro,
			# troca de arma e explosão (caminhos do jogo) aparece aqui com nome.
			var bench_span := STALL_WORK.begin()
			if weapon_cycle > 0.0: _cycle_weapon(measured_clock)
			STALL_WORK.finish_slow("bench.weapon_cycle", bench_span, 2000)
			bench_span = STALL_WORK.begin()
			if shoot: _shoot(at, heading)
			STALL_WORK.finish_slow("bench.shoot", bench_span, 2000)
			bench_span = STALL_WORK.begin()
			if explode_every > 0.0: _explode_near(at, heading, measured_clock)
			STALL_WORK.finish_slow("bench.explode", bench_span, 2000)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := (now - previous) / 1000.0
		previous = now
		if autopilot != null: distance = autopilot.drive(minf(frame_ms, 100.0) / 1000.0)
		else: distance += speed * minf(frame_ms, 100.0) / 1000.0
		if distance < total * WARMUP_LOOPS: continue
		measuring_present[0] = true
		measured_clock += frame_ms / 1000.0
		frames.append(frame_ms)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if save_every > 0.0:
			_save_clock += frame_ms / 1000.0
			if _save_clock >= save_every:
				_save_clock = 0.0
				_probe_save()
	if autopilot != null: autopilot.finish()
	measuring_present[0] = false
	RenderingServer.frame_post_draw.disconnect(on_present)
	var present: Array[float] = []
	for index in range(1, present_stamps.size()): present.append((present_stamps[index] - present_stamps[index - 1]) / 1000.0)
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
	# Primeiro minuto medido: com --benchmark-cold é o minuto logo depois de jogável (p99 de 197 ms na
	# partida de 21/10, ainda no binário do editor e com parte sob a cortina).
	var first_minute: Array[float] = []
	var first_clock := 0.0
	for frame_ms in frames:
		if first_clock >= 60000.0: break
		first_minute.append(frame_ms)
		first_clock += frame_ms
	report.first_60s = _stats(first_minute)
	report.first_60s_over_33ms = first_minute.filter(func(ms): return ms > 33.3).size()
	report.present_ms = _stats(present)
	report.present_over_33ms = present.filter(func(ms): return ms > 33.3).size()
	report.present_over_16_7ms = present.filter(func(ms): return ms > 16.7).size()
	report.present_samples_ms = present
	report.cold_start = cold
	report.speed_mps = speed
	if shoot or explode_every > 0.0 or "--benchmark-stress" in OS.get_cmdline_user_args():
		report.stress = {"shots": _shots, "shot_attempts": _shot_attempts, "shots_by_weapon": _shots_by_weapon, "explosions": _explosions, "explosion_misses": _explode_misses,
			"explode_every_s": explode_every, "chase": _chase_requested(), "dispatch": is_instance_valid(world.get("dispatch")),
			"stars_final": int(world.gameplay.stars), "city_life_audio": OS.get_environment("GETECO_CITY_LIFE_AUDIO") != "0",
			"weapon_cycle_s": weapon_cycle, "weapon_switches": _weapon_switches, "weapon_switch_call_ms": _stats(_weapon_switch_ms),
			"weapon_template": OS.get_environment("GETECO_WEAPON_TEMPLATE") != "0",
			"scope": "Tiro do jogador por Gameplay.fire_at (fuzil, recarga do jogo) com o carro como alvo da polícia; explosão = carro do trânsito destruído pelo dano do jogo."}
	if _chase_requested() and is_instance_valid(world.get("dispatch")):
		var radio_voice: Variant = world.dispatch.get("radio_voice")
		report.chase = {"gta_chase": OS.get_environment("GETECO_GTA_CHASE") != "0", "stats": world.dispatch.pursuit_stats.duplicate(),
			"radio_voice_played": int(radio_voice.played) if radio_voice != null and is_instance_valid(radio_voice) else -1}
	if chaos_stars > 0:
		report.chaos = {"stars_requested": chaos_stars, "stars_final": int(world.gameplay.stars), "dispatch_units_peak": _chaos_peak_units,
			"dispatch_units_final": world.dispatch.units.size() if is_instance_valid(world.get("dispatch")) else -1}
	if autopilot != null: report.drive = autopilot.summary()
	if save_every > 0.0:
		report.save_probe = {"every_s": save_every, "calls": _save_ms.size(), "failures": _save_failures,
			"save_game_ms": _stats(_save_ms), "save_game_samples_ms": _save_ms, "stages": _save_stages,
			"byte_verify": OS.get_environment("GETECO_SAVE_VERIFY") != "0",
			"scope": "FullSession.save_game() inteiro (snapshots da sessão + SaveStore.save) num arquivo da bancada; stages = spans save.* somados (usec)."}
	if runover:
		report.runover = {"launches": _runover_launch_ms.size(), "ragdolls": _runover_ragdolls, "launch_ms": _stats(_runover_launch_ms),
			"scope": "Impacto disparado direto (BodyFlight3D.launch a 10 m/s, não letal) à frente do carro teleportado; não mede a varredura do para-choque."}
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

func _chase_requested() -> bool:
	var args := OS.get_cmdline_user_args()
	return "--benchmark-chase" in args or "--benchmark-stress" in args

## Sem --benchmark-measure-seconds: aquecimento + 2 voltas, como sempre. Com ele: aquecimento e então
## N segundos medidos, em quantas voltas couberem (a 25 m/s a rota oeste dá uma volta em ~17 s).
func _keep_measuring(distance: float, total: float, measured_clock: float) -> bool:
	if measure_seconds <= 0.0: return distance < total * (WARMUP_LOOPS + MEASURE_LOOPS)
	return distance < total * WARMUP_LOOPS or measured_clock < measure_seconds

func _shoot_prepare() -> void:
	# Arsenal de depuração do jogo (Economy.activate_arsenal_cheat: todas as armas, 9999 de reserva, fora do
	# inventário e do save). Com grant_weapon/add_ammo o inventário em grade de um jogo novo recusava fuzil e
	# munição: em 22/10 só pistola e escopeta entravam, 31 tiros em 90 s.
	world.session.state.economy.activate_arsenal_cheat()
	_equip("ak47")

## Com o carro como alvo da polícia (driving.occupied) o jogo não deixa empunhar nem atirar: até 22/10
## a troca falhava calada e os "tiros" do estresse eram socos (fire_at com os punhos). Libera só durante
## a chamada, como no disparo.
func _equip(id: String) -> bool:
	var occupied: bool = world.driving.occupied
	world.driving.occupied = false
	var ok: bool = world.gameplay.equip_slot(id)
	world.driving.occupied = occupied
	return ok

## Troca para a próxima arma da lista; a montagem do modelo acontece no quadro seguinte (visual da
## Gameplay), então o tempo aqui é só o da troca e o custo do modelo aparece no quadro medido.
func _cycle_weapon(measured_clock: float) -> void:
	if measured_clock < _weapon_clock: return
	_weapon_clock = measured_clock + weapon_cycle
	_weapon_index = (_weapon_index + 1) % CYCLE_WEAPONS.size()
	var began := Time.get_ticks_usec()
	if _equip(CYCLE_WEAPONS[_weapon_index]): _weapon_switches += 1
	_weapon_switch_ms.append((Time.get_ticks_usec() - began) / 1000.0)

## Atira à frente do carro, alternando os lados, sempre que a arma deixa. Com o carro como alvo da
## polícia (driving.occupied), o jogo não deixa atirar de dentro; libera só durante o disparo.
func _shoot(point: Vector3, yaw: float) -> void:
	var gameplay = world.gameplay
	if gameplay.cooldown > 0 or gameplay.reload_timer > 0: return
	_shot_attempts += 1
	if weapon_cycle <= 0.0 and world.session.state.equipped_weapon != "ak47": _equip("ak47")
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var side := forward.cross(Vector3.UP) * (6.0 if _shot_attempts % 2 == 0 else -6.0)
	var occupied: bool = world.driving.occupied
	world.driving.occupied = false
	if gameplay.fire_at(point + forward * 18.0 + side + Vector3.UP):
		_shots += 1
		var weapon := str(gameplay.equipped())
		_shots_by_weapon[weapon] = int(_shots_by_weapon.get(weapon, 0)) + 1
	world.driving.occupied = occupied

## Destrói um carro do trânsito a 10–50 m à frente (o mais perto), com o dano e a explosão do jogo.
func _explode_near(point: Vector3, yaw: float, measured_clock: float) -> void:
	if measured_clock < _explode_clock: return
	_explode_clock = measured_clock + explode_every
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var best: Node3D = null
	var best_distance := INF
	for vehicle in world.production.vehicles:
		if not is_instance_valid(vehicle) or vehicle == world.driving.car or not vehicle.is_inside_tree() or not vehicle.visible: continue
		if not vehicle.has_method("receive_damage") or float(vehicle.get("health")) <= 0.0: continue
		var offset: Vector3 = vehicle.global_position - point
		var flat := Vector2(offset.x, offset.z).length()
		if flat < 10.0 or flat > 50.0 or offset.normalized().dot(forward) < 0.2: continue
		if flat < best_distance:
			best_distance = flat
			best = vehicle
	if best == null:
		_explode_misses += 1
		return
	best.receive_damage(float(best.get("health")) + 1.0, null)
	if float(best.get("health")) <= 0.0: _explosions += 1
	else: _explode_misses += 1

## Salvamento automático real, desviado para um arquivo da bancada: --no-save desliga a gravação no
## controlador, então liga só durante a chamada e devolve o caminho e o estado logo depois.
func _probe_save() -> void:
	var controller: Object = world.session.controller
	var store: Object = controller.store
	var was_no_save: bool = controller.no_save
	var old_path: String = store.path
	store.path = "user://benchmark-west/save-probe/%s.json" % label
	controller.no_save = false
	STALL_WORK.start_aggregate()
	var began := Time.get_ticks_usec()
	var ok: bool = world.session.save_game()
	_save_ms.append((Time.get_ticks_usec() - began) / 1000.0)
	var stages: Dictionary = STALL_WORK.stop_aggregate().labels
	controller.no_save = was_no_save
	store.path = old_path
	if not ok: _save_failures += 1
	for stage in stages:
		if not str(stage).begins_with("save."): continue
		var row: Dictionary = _save_stages.get(stage, {"calls": 0, "total_usec": 0, "max_usec": 0})
		row.calls += int(stages[stage].calls)
		row.total_usec += int(stages[stage].total_usec)
		row.max_usec = maxi(int(row.max_usec), int(stages[stage].max_usec))
		_save_stages[stage] = row

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

## Reserva montada no aquecimento: o corpo do Meshy custa a montar e não pode entrar na medição.
func _runover_prepare() -> void:
	for node in world.find_children("*", "Node", true, false):
		if node.has_method("on_body_landed") and node.has_method("vehicle_pre_move"):
			_runover_director = node
			break
	for index in RUNOVER_POOL:
		var walker: CharacterBody3D = preload("res://scripts/Actor.gd").new()
		walker.controlled_automatically = true
		world.add_child(walker)
		_runover_park(walker)
		_runover_pool.append({"actor": walker, "down_at": -1})

func _runover_park(walker: CharacterBody3D) -> void:
	walker.teleport(Vector3(0, -200, 0))
	walker.set_physics_process(false)
	walker.hide()

func _runover(point: Vector3, yaw: float) -> void:
	var now := Time.get_ticks_msec()
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	for entry in _runover_pool:
		var walker: CharacterBody3D = entry.actor
		if not is_instance_valid(walker): continue
		if walker.has_meta("street_down") and not walker.has_meta("street_flying"):
			if entry.down_at < 0: entry.down_at = now
			elif now - int(entry.down_at) > 3000: walker.recover_from_injury()
		elif entry.down_at >= 0 and not walker.has_meta("street_down"):
			entry.down_at = -1
			_runover_park(walker)
	if now < _runover_due: return
	for entry in _runover_pool:
		var walker: CharacterBody3D = entry.actor
		if not is_instance_valid(walker) or walker.visible or walker.has_meta("street_down"): continue
		_runover_due = now + int(RUNOVER_SECONDS * 1000.0)
		walker.show()
		walker.teleport(point + forward * 5.0 + Vector3.UP * .05)
		walker.set_physics_process(true)
		var began := Time.get_ticks_usec()
		var flight = preload("res://gameplay/street_physics/BodyFlight3D.gd").launch(walker, forward * 10.0, false, _runover_director, world.driving.car, true)
		_runover_launch_ms.append((Time.get_ticks_usec() - began) / 1000.0)
		if flight != null and flight.ragdoll != null: _runover_ragdolls += 1
		return

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
