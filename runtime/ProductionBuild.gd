extends RefCounted
## Carga do mundo do ProductionWorld: o corpo de build() (324 linhas com `await`) em etapas, na mesma ordem
## (save e cortina; ambiente e sol; jogador e veículo; sistemas; pré-aquecimento; veículo inicial; sistemas
## do mundo; edições e transporte; finalização), e o bloco de início (geografia em thread, ponto inicial,
## `--play-at`, assentamento do streaming). Separado em 01/11 (Onda 3) só para o ProductionWorld.gd caber
## na leitura. Não tem estado próprio: tudo o que a carga monta ou marca (environment, sun, region,
## session, ready_for_play, play_at_request, _geography_task...) continua no ProductionWorld, que mantém
## build() e cada função antiga como delegação de uma linha (com `await` onde esperam quadro).
## _apply_player_settings (ligado ao sinal das opções), _eager_preparation_for_benchmark, _audio e
## _exit_tree ficam no dono; SESSION_OPS recebe o dono como fonte, como antes.
## `g` fica como Node, e não como o script do ProductionWorld, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: o despacho continua o de antes. As
## `static var` do dono (sun_shadow_near_enabled, sun_shadow_splits, sun_shadow_tune) são lidas por
## `g.get_script()`. Roda na thread principal; só prepare_data da região inicial vai para o
## WorkerThreadPool, como antes (_prepare_geography).

const ACTOR := preload("res://scripts/Actor.gd")
const CURTAIN := preload("res://runtime/StartupCurtain.gd")
const PIPELINE_PROBE := preload("res://runtime/PipelineProbe.gd")
const SESSION_OPS := preload("res://runtime/SessionOperations.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const WORLD_SEA := preload("res://world/shape/WorldSea.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

## Corpo de build() em etapas, na ordem de antes. Cada etapa termina esperando a seguinte (`await`), em vez
## de voltar para cá: assim toda saída antecipada de antes (`return` quando a geografia falha, o mundo sai
## da árvore ou as filas tardias não terminam) continua encerrando a carga inteira, sem conferência nova
## entre etapas, e os `await`, add_child e connect seguem na mesma ordem.
func run() -> void:
	var diagnostic_build := SESSION_OPS.begin(g, "world", "startup")
	var startup_traced := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	await _load_save_and_curtain(diagnostic_build, startup_traced)

## Etapa 1: lê o save (ou o pedido do --play-at), adota ou cria a cortina e espera a apresentação dela.
func _load_save_and_curtain(diagnostic_build: int, startup_traced: int) -> void:
	g.no_save = "--no-save" in OS.get_cmdline_user_args()
	var launch = g.get_node_or_null("/root/V2Launch")
	if launch != null: g.store.path = launch.selected_path
	if g.world.has_meta("menu_save_path"): g.store.path = str(g.world.get_meta("menu_save_path"))
	if not g.no_save or g.world.has_meta("menu_save_path"):
		var result: Dictionary = g.store.load_into(g.state)
		if result.get("invalid",false): g.block_saving("o save escolhido não passou na validação")
		g.loaded_save = result.get("ok",false)
	# O menu pode ler uma jornada, mas nunca pode persistir mudanças feitas na prévia.
	if g.world.has_meta("menu_preview"): g.no_save = true
	# "Jogar aqui" do editor de mundo: Dante nasce no ponto pedido, sem gravar nada.
	g.play_at_request = g._play_at_argument()
	if not g.play_at_request.is_empty():
		g.no_save = true
		# Direto nos campos: set_location consulta world.player, que ainda não existe.
		g.state.region_id = str(g.play_at_request.region)
		g.state.place_id = ""
		g.state.world_state["pedestrian"] = {"region":g.play_at_request.region,"position":[g.play_at_request.point.x,0.0,g.play_at_request.point.z]}
	g.state.world = g.world
	# O menu já abriu a tela de carregamento na raiz; o mundo a adota. Início direto
	# (testes, --no-save pelo menu) cria a sua.
	var curtain = CURTAIN.existing(g.get_tree())
	if curtain != null: curtain.reparent(g.world)
	else:
		curtain = CURTAIN.new()
		curtain.stage_only = g.world.has_meta("menu_preview")
		curtain.variant = CURTAIN.variant_for(g.state.region_id)
		SESSION_OPS.attach(g.world, curtain, g, diagnostic_build)
	curtain.set_stage(.12, "Montando " + ("a serra" if g.state.region_id == "mountain" else "o deserto" if g.state.region_id == "desert" else "o porto") + "…")
	if not g.world.has_meta("menu_preview"): g._request_fleet_scenes_early()
	await curtain.prepare_presentation()
	PIPELINE_PROBE.stage("curtain")
	if g.world.has_meta("menu_preview"):
		await g._hold_fleet_scenes_incremental()
	await _build_environment_and_sun(diagnostic_build, startup_traced, curtain)

## Etapa 2 (ambiente e sol): WorldEnvironment, as opções de vídeo do jogador, o sol com as cascatas e o
## Maciota; espera um quadro, como antes.
func _build_environment_and_sun(diagnostic_build: int, startup_traced: int, curtain: CanvasLayer) -> void:
	g.environment = WorldEnvironment.new()
	g.environment.environment = Environment.new()
	g.environment.environment.background_mode = Environment.BG_COLOR
	g.environment.environment.background_color = Color("829da6")
	g.environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	g.environment.environment.ambient_light_color = Color("c0d0e2")
	g.environment.environment.ambient_light_energy = .65
	g.environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	SESSION_OPS.attach(g.world, g.environment, g, diagnostic_build)
	# Brilho escolhido pelo jogador (Configurações > Vídeo), aplicado agora e a cada mudança.
	var player_settings: Node = g.get_node_or_null("/root/V2Settings")
	if player_settings != null:
		player_settings.apply_environment(g.environment.environment)
		player_settings.applied.connect(g._apply_player_settings)
	g.sun = DirectionalLight3D.new()
	g.sun.rotation_degrees = Vector3(-52,-30,0)
	g.sun.light_color = Color("fffdf5")
	g.sun.light_energy = 1.6
	g.sun.shadow_enabled = true
	g.sun.directional_shadow_max_distance = 55 if g.get_script().sun_shadow_near_enabled else 110
	if player_settings != null and g.get_script().sun_shadow_near_enabled: g.sun.directional_shadow_max_distance = player_settings.shadow_distance_metres()
	if g.get_script().sun_shadow_splits < 4:
		g.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if g.get_script().sun_shadow_splits >= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
	if g.get_script().sun_shadow_tune:
		g.sun.directional_shadow_split_1 = g.SUN_SHADOW_SPLIT_2_CASCADES if g.get_script().sun_shadow_splits == 2 else g.SUN_SHADOW_SPLITS.x
		g.sun.directional_shadow_split_2 = g.SUN_SHADOW_SPLITS.y
		g.sun.directional_shadow_split_3 = g.SUN_SHADOW_SPLITS.z
		g.sun.directional_shadow_fade_start = g.SUN_SHADOW_FADE_START
	SESSION_OPS.attach(g.world, g.sun, g, diagnostic_build)
	g.world.maciota_place = SESSION_OPS.instantiate(preload("res://world/maciota/MaciotaPlace.gd"), g)
	g.world.maciota_place.exterior_origin = preload("res://world/maciota/MaciotaPlace.gd").INDUSTRIAL_ORIGIN
	g.world.maciota_place.interior_origin = Vector3(0,0,-2000)
	SESSION_OPS.attach(g.world, g.world.maciota_place, g, diagnostic_build)
	await g.get_tree().process_frame
	await _build_player_and_vehicle(diagnostic_build, startup_traced, curtain)

## Etapa 3 (jogador e veículo): geografia da região inicial em thread, montagem, Dante, câmera, HUD,
## Driving com o cupê e o nó do trânsito. Sai da carga inteira se a geografia não ficou pronta.
func _build_player_and_vehicle(diagnostic_build: int, startup_traced: int, curtain: CanvasLayer) -> void:
	# Escolhe a célula salva/pedida pelo jogador antes de o _ready montar qualquer geometria.
	# Antes montávamos primeiro o spawn padrão da região e depois o jogávamos fora.
	var first_focus: Vector3 = Vector3.INF if g._eager_preparation_for_benchmark() else g._startup_focus_hint()
	var initial_region: Node3D = g._build_region(g.state.region_id,first_focus)
	if not await g._prepare_geography(initial_region): return
	g._region_cache[g.state.region_id] = initial_region
	g.region = g._mount_region(g.state.region_id,first_focus)
	var startup_position: Vector3 = g._startup_position()
	g.region.set_focus(startup_position,true)
	g.world.street = g.region
	g._refresh_route_consumers()
	await g.get_tree().process_frame
	PIPELINE_PROBE.stage("region_mount")
	g.world.player = ACTOR.new()
	g.world.player.is_player = true
	g.world.player.name = "Dante"
	if g.world.has_meta("menu_preview"): g.world.player.controlled_automatically = true
	g.world.player.position = startup_position
	g.region.set_focus(g.world.player.position)
	SESSION_OPS.attach(g.world, g.world.player, g, diagnostic_build)
	g._update_physical_residency(g.world.player.position)
	g.world.camera = SESSION_OPS.instantiate(preload("res://scripts/CameraRig.gd"), g)
	g.world.camera.target = g.world.player
	SESSION_OPS.attach(g.world, g.world.camera, g, diagnostic_build)
	g.world.player.camera = g.world.camera
	g.world._build_hud()
	g.world.driving = SESSION_OPS.instantiate(preload("res://scripts/Driving.gd"), g)
	g.world.driving.world = g.world
	SESSION_OPS.attach(g.world, g.world.driving, g, diagnostic_build)
	g.world.driving.car.vehicle_id = "player_coupe"
	g.world.driving.car.set_meta("region_id",g.state.region_id)
	g.vehicles.append(g.world.driving.car)
	g.world.traffic = Node3D.new()
	SESSION_OPS.attach(g.world, g.world.traffic, g, diagnostic_build)
	await _build_systems(diagnostic_build, startup_traced, curtain)

## Etapa 4 (sistemas): Gameplay, reações, motoristas, despacho, cessão de passagem e a FullSession (espera
## o startup_finished dela), estacionamento, rotinas e transporte urbano.
func _build_systems(diagnostic_build: int, startup_traced: int, curtain: CanvasLayer) -> void:
	g.world.gameplay = SESSION_OPS.instantiate(preload("res://gameplay/Gameplay.gd"), g)
	g.world.gameplay.configure(g.world,g.world.player,g.world.camera,g.state)
	SESSION_OPS.attach(g.world, g.world.gameplay, g, diagnostic_build)
	g.civilian_reactions = SESSION_OPS.instantiate(preload("res://gameplay/civilian_reactions/CivilianReactionDirector.gd"), g)
	g.civilian_reactions.name = "CivilianReactionDirector"
	g.civilian_reactions.configure(g.world,g.world.gameplay)
	SESSION_OPS.attach(g.world, g.civilian_reactions, g, diagnostic_build)
	if preload("res://gameplay/traffic/TrafficDriverPool.gd").enabled():
		g.traffic_drivers = SESSION_OPS.instantiate(preload("res://gameplay/traffic/TrafficDriverPool.gd"), g)
		g.traffic_drivers.name = "TrafficDriverPool"
		g.traffic_drivers.configure(g.world)
		SESSION_OPS.attach(g.world, g.traffic_drivers, g, diagnostic_build)
	if not g.world.get_meta("skip_dispatch",false) and not "--no-dispatch" in OS.get_cmdline_user_args():
		g.world.dispatch = SESSION_OPS.instantiate(preload("res://gameplay/dispatch/DispatchController.gd"), g)
		g.world.dispatch.configure(g.world,g.world.gameplay,g.traffic_routes)
		SESSION_OPS.attach(g.world, g.world.dispatch, g, diagnostic_build)
		g.world.dispatch.set_enabled(true)
		g.world.dispatch.set_physics_process(false)
	if not g.world.get_meta("skip_traffic_yield",false) and not "--no-traffic-yield" in OS.get_cmdline_user_args():
		g.world.traffic_yield = SESSION_OPS.instantiate(preload("res://gameplay/traffic_yield/TrafficYieldController.gd"), g)
		g.world.traffic_yield.configure(g.world,g.traffic_routes)
		SESSION_OPS.attach(g.world, g.world.traffic_yield, g, diagnostic_build)
		g.world.traffic_yield.set_physics_process(false)
	g.world.session = SESSION_OPS.instantiate(preload("res://runtime/FullSession.gd"), g)
	g.world.session.world = g.world
	g.world.session.controller = g
	g.world.session.incremental_startup = true
	SESSION_OPS.attach(g.world, g.world.session, g, diagnostic_build)
	PIPELINE_PROBE.stage("gameplay_nodes")
	if not g.world.session.startup_complete: await g.world.session.startup_finished
	PIPELINE_PROBE.stage("session_startup")
	g.session = g.world.session
	if "--parking-baseline" not in OS.get_cmdline_user_args():
		g.roadside_parking = SESSION_OPS.instantiate(preload("res://runtime/RoadsideParking.gd"), g)
		g.roadside_parking.configure(g.world,g)
		SESSION_OPS.attach(g.world, g.roadside_parking, g, diagnostic_build)
	var v1_routines = SESSION_OPS.instantiate(preload("res://gameplay/routines_v1/RoutineDirector.gd"), g)
	v1_routines.configure(g.world,g.session,g)
	SESSION_OPS.attach(g.world, v1_routines, g, diagnostic_build)
	g.urban_transit = SESSION_OPS.instantiate(preload("res://runtime/UrbanTransitPresentation.gd"), g)
	g.urban_transit.configure(g)
	SESSION_OPS.attach(g.world, g.urban_transit, g, diagnostic_build)
	await _prewarm_under_curtain(diagnostic_build, startup_traced, curtain)

## Etapa 5: foco e colisão no veículo salvo, população pedida e o pré-aquecimento das regiões sob a cortina.
func _prewarm_under_curtain(diagnostic_build: int, startup_traced: int, curtain: CanvasLayer) -> void:
	var saved_vehicle: Dictionary = g.starting_vehicle()
	if not saved_vehicle.is_empty() and saved_vehicle.get("was_driven",false) and saved_vehicle.region == g.state.region_id and g.state.place_id.is_empty():
		g.region.set_focus(Vector3(saved_vehicle.position[0],saved_vehicle.position[1],saved_vehicle.position[2]))
	if g.session.cold != null and not saved_vehicle.is_empty() and saved_vehicle.region == g.state.region_id:
		g.session.cold.prepare_collision_at(Vector3(saved_vehicle.position[0],saved_vehicle.position[1],saved_vehicle.position[2]))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--population="): g.requested_population = clampi(arg.split("=")[1].to_int(),0,g.MAX_POPULATION)
	curtain.set_stage(.3, "Assentando o terreno…")
	for i in 12: await g.get_tree().physics_frame
	await g._prewarm_regions(curtain)
	if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
	await _place_starting_vehicle(diagnostic_build, startup_traced, curtain, saved_vehicle)

## Etapa 6 (veículo): estaciona o cupê padrão ou restaura o veículo salvo.
func _place_starting_vehicle(diagnostic_build: int, startup_traced: int, curtain: CanvasLayer, saved_vehicle: Dictionary) -> void:
	curtain.set_stage(.84, "Acendendo a cidade…")
	var road_point: Vector3 = g.nearest_road(g.world.player.position)
	# O cupê protótipo antes usava a faixa de circulação mais próxima. Depois
	# da mudança da oficina isso punha um carro padrão novo atravessado nas duas
	# chegadas guiadas. Veículos salvos mantêm a própria restauração abaixo; só o
	# padrão não salvo ganha uma pose de estacionamento apoiada fora da rua no pátio de carga.
	var default_car_parked := false
	if saved_vehicle.is_empty() and g.state.region_id == "harbor":
		for offset in [Vector3(-18.5,.12,6.3),Vector3(-20,.12,7.0),Vector3(-18.5,.12,4.9)]:
			var parking: Vector3 = g.world.maciota_place.exterior_origin+offset
			if not g.vehicle_position_clear(g.world.driving.car,parking,0.0): continue
			g.world.driving.car.place(parking,0.0)
			default_car_parked = true
			break
	if not default_car_parked: g.world.driving.car.place(road_point+Vector3.UP*.12,g.road_yaw(road_point))
	g._restore_player_vehicle()
	# Um checkpoint a pé remoto pode escolher uma rua fora dos chunks iniciais
	# (por exemplo, a rodovia acima da pedreira). O carro inicial não salvo precisa pedir
	# o chão antes de a física começar, como fazem os veículos distantes restaurados.
	if saved_vehicle.is_empty() and not g.vehicle_position_clear(g.world.driving.car,g.world.driving.car.position,g.world.driving.car.rotation.y):
		g.world.driving.car.set_meta("awaiting_ground",true)
		g.world.driving.car.set_physics_process(false)
	await _build_world_systems(diagnostic_build, startup_traced, curtain)

## Etapa 7: clima, CityLook, física de rua, poças, fauna, beira de estrada e grama, e o pré-aquecimento
## tardio (em filas paralelas ou em série).
func _build_world_systems(diagnostic_build: int, startup_traced: int, curtain: CanvasLayer) -> void:
	# O clima precisa existir antes de o mundo ser marcado ready_for_play: o
	# ambiente/sol começam nos padrões crus definidos em build() acima
	# (uma cor de céu pálida e chapada), e é o Weather._ready() que os ajusta para
	# a hora do dia/estação salva. Criá-lo depois de ready_for_play deixava uma
	# janela de quadros em que o jogador já via e podia andar pelo
	# mundo com esse visual padrão cru, que parecia uma cena gelada e lavada
	# até o Weather alcançar.
	var weather = SESSION_OPS.instantiate(preload("res://runtime/Weather.gd"), g)
	weather.controller = g
	SESSION_OPS.attach(g.world, weather, g, diagnostic_build)
	g.session.weather = weather
	var city_look = SESSION_OPS.instantiate(preload("res://world/city_look/CityLook.gd"), g)
	city_look.controller = g
	SESSION_OPS.attach(g.world, city_look, g, diagnostic_build)
	var street_physics = SESSION_OPS.instantiate(preload("res://gameplay/street_physics/StreetPhysics.gd"), g)
	street_physics.controller = g
	SESSION_OPS.attach(g.world, street_physics, g, diagnostic_build)
	var rain_puddles = SESSION_OPS.instantiate(preload("res://world/rain/RainPuddles3D.gd"), g)
	rain_puddles.controller = g
	SESSION_OPS.attach(g.world, rain_puddles, g, diagnostic_build)
	var wildlife = SESSION_OPS.instantiate(preload("res://gameplay/wildlife/MountainWildlife.gd"), g)
	wildlife.controller = g
	SESSION_OPS.attach(g.world, wildlife, g, diagnostic_build)
	var roadside = SESSION_OPS.instantiate(preload("res://world/mountain_detail/MountainRoadside3D.gd"), g)
	roadside.controller = g
	SESSION_OPS.attach(g.world, roadside, g, diagnostic_build)
	var grass = SESSION_OPS.instantiate(preload("res://world/mountain_detail/MountainGrass3D.gd"), g)
	grass.controller = g
	SESSION_OPS.attach(g.world, grass, g, diagnostic_build)
	PIPELINE_PROBE.stage("session_systems")
	# Depois do Weather, do CityLook e da StreetPhysics: chuva (RainPrewarm.late; antes saía sem fazer nada),
	# efeitos de rua (StreetEffectsPrewarm), reações, interior do carro e combate. Em paralelo como os de
	# _prewarm_regions (GETECO_PREWARM_PARALLEL, ligado por padrão desde 24/10; =0 volta à série).
	var late_steps: Array[String] = ["street_fx", "reaction_visuals", "vehicle_interior", "combat_effects", "late_surfaces"]
	if preload("res://runtime/RainPrewarm.gd").late: late_steps.push_front("rain")
	if OS.get_environment("GETECO_PREWARM_PARALLEL") != "0":
		var pending: Array[int] = [late_steps.size()]
		for step in late_steps: g._prewarm_lane([step], pending, curtain)
		if not await g._await_lanes(pending): return
		PIPELINE_PROBE.stage("late_parallel_draws")
	else:
		for step in late_steps:
			await g._draw_prewarm_step(step, curtain)
			if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
			PIPELINE_PROBE.stage(step)
	await _prepare_world_edits_and_transit(diagnostic_build, startup_traced, curtain)

## Etapa 8: edições do mundo, estações e linha 510 sob a cortina, mar do mundo e o mirante costeiro.
func _prepare_world_edits_and_transit(diagnostic_build: int, startup_traced: int, curtain: CanvasLayer) -> void:
	g._install_world_edits()
	# Estações de tubo e rodoviária montadas sob a cortina (depois das edições, que as movem): montadas ao
	# chegar perto custavam 84-140 ms num quadro (teleporte de aquecimento do benchmark, 16/10).
	if is_instance_valid(g.urban_transit):
		await g.urban_transit.prepare_startup_stations()
		if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
	# Linha 510 montada aqui, depois das edições do mundo (mexem nas estações) e antes de
	# `ready_for_play`: montada no primeiro tique jogável, custava ~100 ms (pico de
	# 140–195 ms em `urban.physics` em todas as rotas do benchmark de 16/10).
	if is_instance_valid(g.urban_transit) and is_instance_valid(g.urban_transit.urban_service):
		await g.urban_transit.urban_service.prepare_startup()
		if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
	# Mar em volta das ilhas e chão-base para a vista de longe (world/shape/WorldSea.gd): ~1,5 s de
	# montagem em fatias de 5 ms, sempre sob a cortina; GETECO_WORLD_SEA=0 desliga.
	if WORLD_SEA.enabled() and not is_instance_valid(g.world_sea):
		var sea_began := STALL_WORK.begin()
		g.world_sea = WORLD_SEA.new()
		g.world_sea.configure(g)
		g.world.add_child(g.world_sea)
		await g.world_sea.build_sliced(g.get_tree())
		if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
		STALL_WORK.finish("startup.world_sea", sea_began)
		await g.world_sea.prewarm(g.world, curtain)
		if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
		PIPELINE_PROBE.stage("world_sea")
	# O mirante costeiro monta seus modelos em fatias desde o _ready da sessão (antes, ~11 s num quadro
	# só, 16/10); num carregamento rápido elas ainda podem estar correndo, e cairiam no jogo.
	while is_instance_valid(g.session) and g.session.coastal_lookout != null and g.session.coastal_lookout.is_preparing():
		await g.get_tree().process_frame
		if not is_instance_valid(g.world) or g.world.is_queued_for_deletion() or not g.world.is_inside_tree(): return
	PIPELINE_PROBE.stage("world_edits_and_transit")
	await _finish_startup(diagnostic_build, startup_traced, curtain)

## Etapa 9 (finalização): ready_for_play, volta ao ponto salvo, população, áudio, assentamento do
## streaming, terminal, estacionamento, busca antecipada, a cortina sobe e a sessão é liberada.
func _finish_startup(diagnostic_build: int, startup_traced: int, curtain: CanvasLayer) -> void:
	g.ready_for_play = true
	curtain.set_stage(.93, "Levando você ao ponto salvo…")
	await g.session.restore_location()
	if not g.play_at_request.is_empty(): await g._place_at_request()
	g.set_population(g.requested_population)
	g.world_audio = g._audio()
	SESSION_OPS.attach(g.world, g.world_audio, g, diagnostic_build)
	g._update_chairlift_schedule()
	curtain.set_stage(.97, "Finalizando…")
	# O GarageRewards admite um motorista salvo de forma assíncrona a partir de restore_location.
	# A animação de corpo dele é dona da entrada até terminar; travar a sessão cedo
	# faria o Driving cancelar essa restauração no próximo quadro de física.
	while g._startup_driver_pending():
		await g.get_tree().physics_frame
	var restored_session_ready: bool = g.session.ready_for_play
	var restored_player_automatic: bool = g.world.player.controlled_automatically
	var restored_player_direction: Vector3 = g.world.player.automatic_direction
	var restored_car: CharacterBody3D = g.world.driving.car
	var restored_car_lock: bool = restored_car.input_locked
	g.session.ready_for_play = false
	g.world.player.controlled_automatically = true
	g.world.player.automatic_direction = Vector3.ZERO
	restored_car.input_locked = true
	PIPELINE_PROBE.stage("restore_location")
	g.startup_streaming_settled = await g._settle_startup()
	if not g.startup_streaming_settled:
		push_warning("Startup streaming still has pending work after its settling budget; runtime streaming will continue.")
	PIPELINE_PROBE.stage("settle_startup")
	# Antes do terminal: assim o JIT fica neste span em qualquer local de início.
	g._prewarm_route_jit()
	# O jogador já está no ponto salvo: estações próximas na árvore ainda sob a cortina (só recolocadas).
	if is_instance_valid(g.urban_transit): g.urban_transit.refresh(true)
	# A primeira resolução de rota em C# precisa terminar enquanto a cortina de partida é dona da entrada.
	# Reaproveita a curva real do terminal depois; mantém o custo no trace de carregamento.
	if is_instance_valid(g.urban_transit) and is_instance_valid(g.urban_transit.terminal_operations):
		g.urban_transit.terminal_operations.prepare_startup_route()
		await g.urban_transit.terminal_operations.prepare_startup_passenger_meshes()
		g.urban_transit.terminal_operations.prepare_startup_build()
		await g.get_tree().process_frame
	if is_instance_valid(g.roadside_parking) and not g.world.has_meta("menu_preview"):
		g.roadside_parking.initialize_nearby()
		await g.get_tree().physics_frame
	# Pedidos da busca antecipada já vêm prontos do começo da carga; espera no máximo mais 3 s.
	var prefetch_traced := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	await preload("res://runtime/BackgroundRegionPreparation.gd").prefetch_collect(g.get_tree(), Time.get_ticks_msec() + 3000)
	g._trace_cost("startup:background_prefetch",prefetch_traced)
	preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd").release_hidden()
	PIPELINE_PROBE.stage("before_lift")
	if not g.world.has_meta("menu_preview"): await curtain.lift()
	PIPELINE_PROBE.stage("curtain_lift")
	g.session.ready_for_play = restored_session_ready
	g.world.player.controlled_automatically = restored_player_automatic
	g.world.player.automatic_direction = restored_player_direction
	if is_instance_valid(restored_car): restored_car.input_locked = restored_car_lock
	g._trace_cost("startup:prepared",startup_traced)
	SESSION_OPS.finish(diagnostic_build)
	if g.world.has_meta("menu_preview"):
		await g.world.get_meta("menu_preview").hold_world(g.world)
		if g.world.is_queued_for_deletion(): return
	g.session.arrival.start_or_resume(g.loaded_save or "--skip-arrival" in OS.get_cmdline_user_args() or g.world.get_meta("skip_arrival",false))
	if is_instance_valid(g.world.dispatch):
		g.session.sync_dispatch_location()
		g.world.dispatch.set_physics_process(true)
	if is_instance_valid(g.world.traffic_yield): g.world.traffic_yield.set_physics_process(true)
	if is_instance_valid(g.background_preparation): g.background_preparation.set_process(true)

func _startup_driver_pending() -> bool:
	if g.world.driving.is_body_transition_active(): return true
	for car in g.vehicles:
		if is_instance_valid(car) and car.get_meta("garage_driver_pending", false): return true
	return false

func _settle_startup() -> bool:
	# Termina o streaming do destino e as primeiras atualizações de áudio/física antes do fade.
	# A admissão pode legitimamente deixar trabalho distante pendente; mantém a espera limitada.
	var stable_frames := 0
	for frame in 240:
		await g.get_tree().process_frame
		var idle := true
		for resident in g.regions.values():
			if is_instance_valid(resident) and not resident.is_streaming_idle(): idle = false
		stable_frames = stable_frames + 1 if idle else 0
		if stable_frames >= 8: return true
	return false

func _prepare_geography(candidate: Node3D) -> bool:
	if candidate == null: return false
	# Um worker é dono de uma região fora da árvore. Nenhuma mutação na árvore de cena nem
	# consumidor do jogo pode acessar os dicionários mutáveis dela até a tarefa ter sido unida.
	# A renderização dummy mantém o caminho sequencial dos testes de contrato.
	if DisplayServer.get_name() == "headless":
		candidate.prepare_data()
		return true
	g._geography_candidate = candidate
	g._geography_task = WorkerThreadPool.add_task(candidate.prepare_data,false,"Loading region geography")
	while not WorkerThreadPool.is_task_completed(g._geography_task):
		await g.get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(g._geography_task)
	g._geography_task = -1
	var usable: bool = is_instance_valid(g.world) and g.world.is_inside_tree() and not g.world.is_queued_for_deletion()
	if usable and candidate.has_method("prepare_presentation_incremental"):
		await candidate.prepare_presentation_incremental(g.get_tree(), g.world)
		usable = is_instance_valid(g.world) and g.world.is_inside_tree() and not g.world.is_queued_for_deletion()
	g._geography_candidate = null
	if not usable and is_instance_valid(candidate): candidate.free()
	return usable

## Lugares montados pela sessão (Vértice, Torque...) só recebem as edições do editor de mundo
## por observação da árvore; sem linhas desses lugares no documento nada é instalado.
func _install_world_edits() -> void:
	var document: Dictionary = Engine.get_meta("geteco_world_edit_document",{})
	if document.is_empty(): document = preload("res://world/editing/WorldEditData.gd").read_document().document
	if not document.is_empty(): preload("res://world/editing/WorldSessionEdits.gd").install(g.get_tree(),g.world,document)

static func _play_at_argument() -> Dictionary:
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--play-at="): continue
		var parts := argument.trim_prefix("--play-at=").split(",")
		if parts.size() != 3 or parts[0] not in ["harbor","mountain","desert"] or not parts[1].is_valid_float() or not parts[2].is_valid_float(): return {}
		return {"region":parts[0],"point":Vector3(parts[1].to_float(),0.0,parts[2].to_float())}
	return {}

## A altura só existe depois que a região está montada: grava no ponto de retomada do pedestre.
func _resolve_play_at() -> void:
	var point: Vector3 = g.play_at_request.point
	var ground := 0.0
	if g.region.get("terrain") != null: ground = g.region.terrain.surface_height_at(Vector2(point.x,point.z))
	elif g.state.region_id == "desert": ground = g.region._ground_height(Vector2(point.x,point.z))
	g.state.world_state["pedestrian"] = {"region":g.play_at_request.region,"position":[point.x,ground+.08,point.z]}

## O ponto escolhido no editor pode cair dentro de uma peça (ou de um prédio): procura o chão livre
## mais próximo, em anéis de até 8 m. Em cada coluna escolhe, entre as superfícies que um raio
## atravessa, a mais próxima do chão da região (não o telhado de cima).
func _place_at_request() -> void:
	var wanted: Vector3 = g.play_at_request.point
	g.region.set_focus(wanted)
	if g.session.cold != null: g.session.cold.prepare_collision_at(wanted)
	for i in 4: await g.get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = g.world.get_world_3d().direct_space_state
	for ring in [0.0,1.5,3.0,4.5,6.0,8.0]:
		for step in (1 if ring == 0.0 else 8):
			var offset: Vector3 = Vector3(cos(TAU*step/8.0),0,sin(TAU*step/8.0))*ring
			var column: Vector3 = wanted+offset
			var nominal := 0.0
			if g.region.get("terrain") != null: nominal = g.region.terrain.surface_height_at(Vector2(column.x,column.z))
			elif g.state.region_id == "desert": nominal = g.region._ground_height(Vector2(column.x,column.z))
			var best := Vector3.INF
			var excluded: Array[RID] = []
			for layer in 8:
				var query := PhysicsRayQueryParameters3D.create(Vector3(column.x,400,column.z),Vector3(column.x,-100,column.z),1)
				query.exclude = excluded
				var hit: Dictionary = space.intersect_ray(query)
				if hit.is_empty(): break
				excluded.append(hit.rid)
				if not best.is_finite() or absf(hit.position.y-nominal) < absf(best.y-nominal): best = hit.position
			if not best.is_finite(): continue
			var point: Vector3 = best+Vector3.UP*.08
			if g.session.position_clear(point):
				g.world.player.teleport(point)
				return

func _startup_focus_hint() -> Vector3:
	if not g.play_at_request.is_empty(): return g.play_at_request.point
	if not g.state.place_id.is_empty(): return Vector3.INF
	var vehicle: Dictionary = g.starting_vehicle()
	if not vehicle.is_empty() and vehicle.get("was_driven",false) and vehicle.get("region","") == g.state.region_id:
		var position: Array = vehicle.get("position",[])
		if position.size() == 3: return Vector3(float(position[0]),float(position[1]),float(position[2]))
	var pedestrian: Dictionary = g.state.world_state.get("pedestrian",{})
	var coordinates: Array = pedestrian.get("position",[])
	if pedestrian.get("region","") == g.state.region_id and coordinates.size() == 3:
		var point := Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))
		if g.state.region_id == "desert": return preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").restore_point(point,g.state.world_state)
		if g.state.region_id == "harbor": return preload("res://world/railway/RailwayNetwork.gd").restore_harbor_pedestrian(point)
		return point
	return Vector3.INF

func _startup_position() -> Vector3:
	if not g.play_at_request.is_empty(): g._resolve_play_at()
	# Monta e enquadra o destino salvo desde o primeiro quadro renderizado. A
	# encenação antiga com o Maciota primeiro expunha chunks pálidos de terreno/prédio não carregados
	# por vários segundos antes de restore_location teletransportar o Dante para o save.
	var fallback: Vector3 = g.world.maciota_place.exterior_return+Vector3(0,.08,2) if g.state.region_id == "harbor" else g.region.spawn_position+Vector3.UP*.08
	if not g.state.place_id.is_empty(): return fallback
	var saved_vehicle: Dictionary = g.starting_vehicle()
	if not saved_vehicle.is_empty() and saved_vehicle.get("was_driven",false) and saved_vehicle.get("region","") == g.state.region_id:
		var vehicle_position: Array = saved_vehicle.get("position",[])
		if vehicle_position.size() == 3:
			return Vector3(float(vehicle_position[0]),float(vehicle_position[1]),float(vehicle_position[2]))
	var pedestrian: Dictionary = g.state.world_state.get("pedestrian",{})
	var coordinates: Array = pedestrian.get("position",[])
	if pedestrian.get("region","") == g.state.region_id and coordinates.size() == 3:
		var point:=Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))
		if g.state.region_id=="desert":
			var restored:=preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").restore_point(point,g.state.world_state)
			if restored!=point: return restored+Vector3.UP*.08
		if g.state.region_id == "harbor": return preload("res://world/railway/RailwayNetwork.gd").restore_harbor_pedestrian(point)
		return point
	return fallback
