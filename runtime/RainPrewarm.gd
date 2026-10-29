extends RefCounted
## Desenha a chuva leve e a forte sob a cortina antes do jogo. A primeira garoa numa sessão de
## release compilou pipelines no meio do jogo: quadro de 1.105 ms com 1.072 ms dentro do desenho
## (oeste, 20/10, docs/perf-auditfix-20261019.md); a rodada seguinte, já com o cache gravado, não
## repetiu. Nenhum pré-aquecimento passava pela chuva. Aqui o clima é forçado como a bancada faz
## (troca externa é instantânea), com chão molhado, e depois volta exatamente ao estado salvo.
## GETECO_RAIN_PREWARM=0 pula (A/B).
const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
const DRAW_FRAMES := 3
## Weather._update roda a cada 0,2 s: cada estado fica pelo menos isso para a chuva, as poças e o
## céu molhado chegarem a desenhar.
const MIN_SECONDS := .45
const MAX_WAIT_FRAMES := 90
static var enabled := OS.get_environment("GETECO_RAIN_PREWARM") != "0"
## Chamado depois de o Weather existir (22/10, 3ª rodada). Antes rodava dentro de
## ProductionWorld._prewarm_regions, mas o Weather só nasce depois dele: `session.weather` era nulo e
## este passo saía na primeira linha (a sonda de pipelines mediu 0,1 ms e nenhum pipeline; no estresse a
## poça e o para-brisa molhado compilavam no jogo). GETECO_RAIN_PREWARM_LATE=0 volta ao lugar antigo.
static var late := OS.get_environment("GETECO_RAIN_PREWARM_LATE") != "0"
## Desenha também um raio na tempestade: desligado por padrão (GETECO_RAIN_PREWARM_BOLT=1 liga); a sonda ainda viu
## o raio compilar no jogo com ele ligado, então o ganho não foi provado.
static var lightning := OS.get_environment("GETECO_RAIN_PREWARM_BOLT") == "1"
static var _drawn := false

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if not enabled or _drawn or DisplayServer.get_name() == "headless" or "--no-prewarm" in OS.get_cmdline_user_args(): return
	if not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var session: Variant = host.get("session")
	var weather: Variant = session.get("weather") if session != null else null
	if weather == null or not is_instance_valid(weather) or not ("weather_state" in weather): return
	var began := Time.get_ticks_usec()
	var saved := {"weather_state": weather.weather_state, "rain_intensity": weather.rain_intensity,
		"coastal_wetness": weather.coastal_wetness, "weather_timer": weather.weather_timer}
	var tree := host.get_tree()
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	var complete := true
	# Bancos de névoa (FogBanks, 29/10): o shader novo desenha junto com a chuva e fica retido no nó.
	var fog: Variant = weather.get("fog_banks")
	if fog != null and is_instance_valid(fog): fog.force = true
	# Garoa (1) e tempestade (2): materiais, partículas e o céu de cada intensidade.
	for state in [1, 2]:
		weather.weather_state = state
		if state == 1: weather.rain_intensity = .22
		weather.coastal_wetness = 1.0
		weather.weather_timer = 1.0e9
		var start_draws := draws[0]
		var start_ms := Time.get_ticks_msec()
		var ok := false
		var bolt_tried := false
		for frame in MAX_WAIT_FRAMES:
			await tree.process_frame
			if not GUARDS._covered_loading(host, curtain) or not GUARDS._current_camera(host, camera): break
			# Raio da tempestade (ImmediateMesh sem luz e emissivo): no estresse frio de 22/10 o primeiro
			# compilou no jogo (quadro de 100 ms). Sem trovão: o atraso é zerado logo depois do disparo.
			if state == 2 and not bolt_tried and draws[0] - start_draws >= 1 and lightning:
				bolt_tried = true
				var storm: Variant = weather.get("storm")
				if storm != null and is_instance_valid(storm) and storm.has_method("trigger_lightning") and storm.trigger_lightning():
					storm.thunder_delay = -1.0
					draws[0] = start_draws + 1
					start_ms = Time.get_ticks_msec()
			if draws[0] - start_draws >= DRAW_FRAMES and Time.get_ticks_msec() - start_ms >= MIN_SECONDS * 1000.0:
				ok = true
				break
		if not ok:
			complete = false
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw):
		RenderingServer.frame_post_draw.disconnect(count_draw)
	if lightning and is_instance_valid(weather):
		var storm: Variant = weather.get("storm")
		if storm != null and is_instance_valid(storm) and storm.has_method("cancel"): storm.cancel()
	if fog != null and is_instance_valid(fog): fog.force = false
	# Volta ao clima salvo; a troca externa reajusta rain_level no próximo _process.
	if is_instance_valid(weather):
		for key in saved: weather.set(key, saved[key])
	if complete: _drawn = true
	preload("res://runtime/StallWorkTrace.gd").finish_slow("prewarm.rain", began, 1000)
