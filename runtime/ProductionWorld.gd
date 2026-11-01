extends Node
const SESSION_OPS := preload("res://runtime/SessionOperations.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const HEAVY_FRAME := preload("res://runtime/HeavyFrameClaim.gd")
const GPU_RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const ACTOR := preload("res://scripts/Actor.gd")
## População de rua (densidade, revisão e criação de pedestres) separada em 01/11 só para este arquivo
## caber na leitura; estado e campos continuam aqui e cada função antiga delega em uma linha.
const POPULATION := preload("res://runtime/ProductionPopulation.gd")
var _population: POPULATION = POPULATION.new(self)
## Trânsito (rede de rotas, grade da pista, nascimento e admissão de carros) separado em 01/11 (Onda 2):
## componente com estado próprio só para o que ninguém de fora lê; cada função antiga delega em uma linha.
const TRAFFIC := preload("res://runtime/ProductionTraffic.gd")
var _traffic: TRAFFIC = TRAFFIC.new(self)
## Pré-aquecimento sob a cortina (_prewarm_regions em etapas, filas, frota) separado em 01/11 (Onda 2):
## estado só dele mora lá; cada função antiga delega em uma linha, com `await` onde espera quadro.
const PREWARM := preload("res://runtime/ProductionPrewarm.gd")
var _prewarm: PREWARM = PREWARM.new(self)
const DESERT_POPULATION := preload("res://runtime/desert/DesertPopulation.gd")
const DESERT_SOCIAL_ACTOR := preload("res://runtime/desert/DesertSocialActor.gd")
var _desert_social_slots: Array[Dictionary] = DESERT_POPULATION.slots()
const FOOTBRIDGE_CROSSERS := preload("res://gameplay/crowd/FootbridgeCrossers.gd")
var footbridge_crossers := FOOTBRIDGE_CROSSERS.new()
var population_layout := preload("res://gameplay/crowd/AmbientPopulationLayout.gd").new()
var ambient_journeys := preload("res://gameplay/AmbientJourney.gd").new()
const VEHICLE := preload("res://scripts/Vehicle.gd")
const PORT_POLICY := preload("res://gameplay/urban_v1/HarborPortPolicy.gd")
const CANAL_TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const WORLD_SEA := preload("res://world/shape/WorldSea.gd")
# Orçamento medido em 2026-09-23 (RTX 4060 Laptop, 1280x720): 100 pedestres + 100 carros
# + 3 estrelas custavam 25,8 ms de física/scripts por quadro e derrubavam para 34,5 FPS;
# 40 pedestres mantiveram 59,8 FPS no mesmo cenário.
const MAX_POPULATION := 40
const TRAFFIC_TARGET := 40
static var population_vc_enabled := OS.get_environment("GETECO_POP_VC") != "0"
static var sun_shadow_near_enabled := OS.get_environment("GETECO_SUN_SHADOW_NEAR") != "0"
# A/B de cascatas do sol (fase 2 da revisão de desempenho, 15/10): padrão continua 4.
# Na câmera ortográfica o alcance real vem do far, não dos 55 m da preferência.
# Quatro cascatas podem repetir casters em passadas distintas. GETECO_SUN_SPLITS=2
# mede o custo de 2 cascatas antes de qualquer troca de padrão (troca visual: menos
# resolução de sombra perto da câmera).
static var sun_shadow_splits := clampi(int(OS.get_environment("GETECO_SUN_SPLITS")) if OS.get_environment("GETECO_SUN_SPLITS") != "" else 4, 1, 4)
## Cascatas do sol para a câmera ortográfica (auditoria Godot 4.7 de 19/10, §4 "Sombra do sol").
## A câmera de jogo fica a ~36 m do foco (CameraRig) e o chão visível vai de ~25 a ~55 m de
## profundidade. Conferido no Godot 4.7.2-stable, renderer_scene_cull.cpp:1965–1969 (29/10):
## com câmera ortográfica o `directional_shadow_max_distance` é ignorado e as cascatas dividem near..far,
## isto é,
## 0,1..180 m (EXTERIOR_FAR). Com os padrões (0,1 / 0,2 / 0,5) a 1ª cascata (0–18 m) quase não tem
## chão visível e a 3ª/4ª (36–90 / 90–180 m) cobrem sobretudo o que está fora da tela. Os valores
## abaixo são frações de 180 m que põem as três primeiras na faixa visível e o esmaecimento depois
## dela. Na perseguição do túnel (perspectiva) o max_distance volta a valer e as mesmas frações
## caem perto da câmera, onde a perspectiva precisa de resolução. GETECO_SUN_SHADOW_TUNE=0 volta
## aos padrões do Godot (A/B). GETECO_CAMERA_FAR é outro experimento, desligado por padrão:
## reduz o alcance exterior com piso geométrico e compensa as frações enquanto a câmera é ortográfica.
static var sun_shadow_tune := OS.get_environment("GETECO_SUN_SHADOW_TUNE") != "0"
const SUN_SHADOW_SPLITS := Vector3(.16, .22, .32)
## Com 2 cascatas (GETECO_SUN_SPLITS=2) a divisão fica no fim da faixa visível (~60 m).
const SUN_SHADOW_SPLIT_2_CASCADES := .33
const SUN_SHADOW_FADE_START := .4
const VC_MAX_POPULATION := 25
const VC_TRAFFIC_TARGET := 16
# Os 51/25 m do reVC valem para a câmera baixa em perspectiva dele. A nossa fica a ~30 m de altura e,
# no ultrawide, quase tudo até 30 m do carro está na tela: com 30 m fora da tela não sobrava anel de
# admissão e o benchmark F (2026-10-13) terminava com 3 pedestres. Por isso o anel acompanha o quadro.
const VC_PEDESTRIAN_VISIBLE_DISTANCE := 95.0
const VC_PEDESTRIAN_HIDDEN_DISTANCE := 60.0
const VC_PEDESTRIAN_SPAWN_MAX := 55.0
var _pedestrian_review_cursor := 0
var _pedestrian_review_credit := 0.0
var _p1_count_started := false
const RELEASE_BENCHMARK := preload("res://runtime/ReleaseBenchmark.gd")
var _release_benchmark_started := false
# Densidade dinâmica, como no GTA: com emergência em cena o teto de pedestres e de trânsito
# civil cai para sobrar orçamento de física à polícia (45 carros ≈ 4–5 ms e 41 pessoas ≈ 2 ms
# por passo no caos, medido 2026-09-29). Cai rápido, volta devagar; quem passa do teto some
# fora do quadro, um por vez, e ninguém novo nasce acima dele.
# Os quatro valores moram em ProductionPopulation (as funções estáticas de alvo precisam deles sem
# preload do dono); a reexportação mantém ProductionWorld.DENSITY_* para testes e chamadores.
const DENSITY_PER_UNIT := POPULATION.DENSITY_PER_UNIT
const DENSITY_MIN := POPULATION.DENSITY_MIN
const DENSITY_STARS := POPULATION.DENSITY_STARS
const DENSITY_STARS_SCALE := POPULATION.DENSITY_STARS_SCALE
const DENSITY_TRIM_MIN_DISTANCE := 30.0
var density_scale := 1.0
# Demanda de rua escrita e independente; os tetos de emergência e de área não se somam.
var area_density_scale := Vector2.ONE
# Como em GTA: gente e trânsito ambiente nascem e somem num anel em volta do jogador,
# sempre fora do quadro da câmera, para nada aparecer ou desaparecer na tela.
const POPULATION_SPAWN_MIN := 45.0
const POPULATION_SPAWN_MAX := 95.0
const POPULATION_DESPAWN := 120.0
const CURTAIN := preload("res://runtime/StartupCurtain.gd")
const PIPELINE_PROBE := preload("res://runtime/PipelineProbe.gd")
## Trânsito sem progresso por esse tempo (fora de fila de sinal) sai de cena quando
## ninguém está olhando e ele não está perto do jogador.
const STUCK_DESPAWN_SECONDS := 15.0
const STUCK_DESPAWN_DISTANCE := 30.0
const TRAFFIC_ROSTER := preload("res://runtime/TrafficFleetRoster.gd")
static var TRAFFIC_CAR_TYPES: Array[String] = TRAFFIC_ROSTER.all_car_types()
const TRAFFIC_MOTORCYCLE_TYPES := ["bike_urban", "bike_sport", "bike_cruiser"]
signal logical_region_changed(previous_region: String, next_region: String)
const CONNECTION_PRELOAD_DISTANCE := 240.0
const CONNECTION_RELEASE_DISTANCE := 320.0
## Obra da passagem norte: também mora na conexão (NorthGateway).
const NORTH_CONNECTION_ANCHOR := Vector3(342.5,2.4,-373.5)
const NORTH_CONNECTION_PRELOAD := 150.0
## GETECO_SEAM_HOLD=0 desliga a folga da emenda (A/B).
static var _seam_hold_enabled := OS.get_environment("GETECO_SEAM_HOLD") != "0"
var _seam_retention := false
var world
var state = preload("res://runtime/GameState.gd").new()
var store = preload("res://runtime/SaveStore.gd").new()
var region: Node3D
var regions: Dictionary = {}
var connection: Node3D
var sun: DirectionalLight3D
var environment: WorldEnvironment
var vehicles: Array[CharacterBody3D] = []
var no_save := false
## Um sistema não conseguiu restaurar o próprio bloco do save: gravar agora trocaria o dado
## bom do disco pelo padrão, então o salvamento fica desligado nesta sessão. Antes isso era
## silencioso (o autosave só parava); agora vai para o log e para o aviso fixo do HUD.
var save_invalid := false:
	set(value):
		if value and not save_invalid:
			push_warning("Salvamento desligado nesta sessão: %s" % (save_invalid_reason if not save_invalid_reason.is_empty() else "um sistema não restaurou o save"))
		save_invalid = value
var save_invalid_reason := ""
var loaded_save := false
var ready_for_play := false
var startup_streaming_settled := false
var travel_busy := false
var population_clock := 0.0
var _population_jobs: Array[String] = []
var requested_population := MAX_POPULATION
var session
var urban_transit: Node3D
## Mar do mundo orgânico (etapa 1 do plano de 26/10): montado uma vez sob a cortina e retido.
var world_sea: Node3D
var roadside_parking: Node
var world_audio: Node
var civilian_reactions: Node
## Motoristas visíveis nos carros do trânsito perto da câmera (pool; GETECO_TRAFFIC_DRIVERS=0 desliga).
var traffic_drivers: Node
var traffic_routes = preload("res://gameplay/NativeTrafficRoutes.gd").new()
var ambient_traffic_routes = preload("res://gameplay/NativeTrafficRoutes.gd").new()
var ambient_roads_cache: Array[Dictionary] = []
var chairlift_schedule_initialized := false
var chairlift_operating := false
## Regiões preparadas fora da árvore: reentrar não repete a preparação (~340 ms em Mountain).
var _region_cache: Dictionary = {}
var background_preparation: Node
var background_loading_status: Dictionary = {}
## Cenas dos modelos de trânsito mantidas vivas. FleetCatalog.create faz load() a cada
## nascimento; quando o último carro de um modelo saía de cena, o recurso era liberado
## e o próximo nascimento relia o arquivo: 1,7 s num quadro (medido 2026-09-23).
var _fleet_scenes: Array[Resource] = []
var _fleet_extra: Array[Resource] = []
var _geography_task := -1
var _geography_candidate: Node3D

## Desliga o salvamento dizendo qual sistema causou; o primeiro motivo é o que vale.
func block_saving(reason: String) -> void:
	if save_invalid_reason.is_empty(): save_invalid_reason = reason
	save_invalid = true

## Texto do aviso fixo e da recusa do F5 enquanto o salvamento estiver desligado.
func save_block_text() -> String:
	var reason := String(TranslationServer.translate(save_invalid_reason if not save_invalid_reason.is_empty() else "um sistema não restaurou o save"))
	return String(TranslationServer.translate("Salvamento desligado nesta sessão (%s). O arquivo do save no disco foi preservado sem mudanças.")) % reason

func build() -> void:
	var diagnostic_build := SESSION_OPS.begin(self, "world", "startup")
	var startup_traced := Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	no_save = "--no-save" in OS.get_cmdline_user_args()
	var launch = get_node_or_null("/root/V2Launch")
	if launch != null: store.path = launch.selected_path
	if world.has_meta("menu_save_path"): store.path = str(world.get_meta("menu_save_path"))
	if not no_save or world.has_meta("menu_save_path"):
		var result: Dictionary = store.load_into(state)
		if result.get("invalid",false): block_saving("o save escolhido não passou na validação")
		loaded_save = result.get("ok",false)
	# O menu pode ler uma jornada, mas nunca pode persistir mudanças feitas na prévia.
	if world.has_meta("menu_preview"): no_save = true
	# "Jogar aqui" do editor de mundo: Dante nasce no ponto pedido, sem gravar nada.
	play_at_request = _play_at_argument()
	if not play_at_request.is_empty():
		no_save = true
		# Direto nos campos: set_location consulta world.player, que ainda não existe.
		state.region_id = str(play_at_request.region)
		state.place_id = ""
		state.world_state["pedestrian"] = {"region":play_at_request.region,"position":[play_at_request.point.x,0.0,play_at_request.point.z]}
	state.world = world
	# O menu já abriu a tela de carregamento na raiz; o mundo a adota. Início direto
	# (testes, --no-save pelo menu) cria a sua.
	var curtain = CURTAIN.existing(get_tree())
	if curtain != null: curtain.reparent(world)
	else:
		curtain = CURTAIN.new()
		curtain.stage_only = world.has_meta("menu_preview")
		curtain.variant = CURTAIN.variant_for(state.region_id)
		SESSION_OPS.attach(world, curtain, self, diagnostic_build)
	curtain.set_stage(.12, "Montando " + ("a serra" if state.region_id == "mountain" else "o deserto" if state.region_id == "desert" else "o porto") + "…")
	if not world.has_meta("menu_preview"): _request_fleet_scenes_early()
	await curtain.prepare_presentation()
	PIPELINE_PROBE.stage("curtain")
	if world.has_meta("menu_preview"):
		await _hold_fleet_scenes_incremental()
	environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("829da6")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c0d0e2")
	environment.environment.ambient_light_energy = .65
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	SESSION_OPS.attach(world, environment, self, diagnostic_build)
	# Brilho escolhido pelo jogador (Configurações > Vídeo), aplicado agora e a cada mudança.
	var player_settings := get_node_or_null("/root/V2Settings")
	if player_settings != null:
		player_settings.apply_environment(environment.environment)
		player_settings.applied.connect(_apply_player_settings)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-30,0)
	sun.light_color = Color("fffdf5")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55 if sun_shadow_near_enabled else 110
	if player_settings != null and sun_shadow_near_enabled: sun.directional_shadow_max_distance = player_settings.shadow_distance_metres()
	if sun_shadow_splits < 4:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if sun_shadow_splits >= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
	if sun_shadow_tune:
		sun.directional_shadow_split_1 = SUN_SHADOW_SPLIT_2_CASCADES if sun_shadow_splits == 2 else SUN_SHADOW_SPLITS.x
		sun.directional_shadow_split_2 = SUN_SHADOW_SPLITS.y
		sun.directional_shadow_split_3 = SUN_SHADOW_SPLITS.z
		sun.directional_shadow_fade_start = SUN_SHADOW_FADE_START
	SESSION_OPS.attach(world, sun, self, diagnostic_build)
	world.maciota_place = SESSION_OPS.instantiate(preload("res://world/maciota/MaciotaPlace.gd"), self)
	world.maciota_place.exterior_origin = preload("res://world/maciota/MaciotaPlace.gd").INDUSTRIAL_ORIGIN
	world.maciota_place.interior_origin = Vector3(0,0,-2000)
	SESSION_OPS.attach(world, world.maciota_place, self, diagnostic_build)
	await get_tree().process_frame
	# Escolhe a célula salva/pedida pelo jogador antes de o _ready montar qualquer geometria.
	# Antes montávamos primeiro o spawn padrão da região e depois o jogávamos fora.
	var first_focus := Vector3.INF if _eager_preparation_for_benchmark() else _startup_focus_hint()
	var initial_region := _build_region(state.region_id,first_focus)
	if not await _prepare_geography(initial_region): return
	_region_cache[state.region_id] = initial_region
	region = _mount_region(state.region_id,first_focus)
	var startup_position := _startup_position()
	region.set_focus(startup_position,true)
	world.street = region
	_refresh_route_consumers()
	await get_tree().process_frame
	PIPELINE_PROBE.stage("region_mount")
	world.player = ACTOR.new()
	world.player.is_player = true
	world.player.name = "Dante"
	if world.has_meta("menu_preview"): world.player.controlled_automatically = true
	world.player.position = startup_position
	region.set_focus(world.player.position)
	SESSION_OPS.attach(world, world.player, self, diagnostic_build)
	_update_physical_residency(world.player.position)
	world.camera = SESSION_OPS.instantiate(preload("res://scripts/CameraRig.gd"), self)
	world.camera.target = world.player
	SESSION_OPS.attach(world, world.camera, self, diagnostic_build)
	world.player.camera = world.camera
	world._build_hud()
	world.driving = SESSION_OPS.instantiate(preload("res://scripts/Driving.gd"), self)
	world.driving.world = world
	SESSION_OPS.attach(world, world.driving, self, diagnostic_build)
	world.driving.car.vehicle_id = "player_coupe"
	world.driving.car.set_meta("region_id",state.region_id)
	vehicles.append(world.driving.car)
	world.traffic = Node3D.new()
	SESSION_OPS.attach(world, world.traffic, self, diagnostic_build)
	world.gameplay = SESSION_OPS.instantiate(preload("res://gameplay/Gameplay.gd"), self)
	world.gameplay.configure(world,world.player,world.camera,state)
	SESSION_OPS.attach(world, world.gameplay, self, diagnostic_build)
	civilian_reactions = SESSION_OPS.instantiate(preload("res://gameplay/civilian_reactions/CivilianReactionDirector.gd"), self)
	civilian_reactions.name = "CivilianReactionDirector"
	civilian_reactions.configure(world,world.gameplay)
	SESSION_OPS.attach(world, civilian_reactions, self, diagnostic_build)
	if preload("res://gameplay/traffic/TrafficDriverPool.gd").enabled():
		traffic_drivers = SESSION_OPS.instantiate(preload("res://gameplay/traffic/TrafficDriverPool.gd"), self)
		traffic_drivers.name = "TrafficDriverPool"
		traffic_drivers.configure(world)
		SESSION_OPS.attach(world, traffic_drivers, self, diagnostic_build)
	if not world.get_meta("skip_dispatch",false) and not "--no-dispatch" in OS.get_cmdline_user_args():
		world.dispatch = SESSION_OPS.instantiate(preload("res://gameplay/dispatch/DispatchController.gd"), self)
		world.dispatch.configure(world,world.gameplay,traffic_routes)
		SESSION_OPS.attach(world, world.dispatch, self, diagnostic_build)
		world.dispatch.set_enabled(true)
		world.dispatch.set_physics_process(false)
	if not world.get_meta("skip_traffic_yield",false) and not "--no-traffic-yield" in OS.get_cmdline_user_args():
		world.traffic_yield = SESSION_OPS.instantiate(preload("res://gameplay/traffic_yield/TrafficYieldController.gd"), self)
		world.traffic_yield.configure(world,traffic_routes)
		SESSION_OPS.attach(world, world.traffic_yield, self, diagnostic_build)
		world.traffic_yield.set_physics_process(false)
	world.session = SESSION_OPS.instantiate(preload("res://runtime/FullSession.gd"), self)
	world.session.world = world
	world.session.controller = self
	world.session.incremental_startup = true
	SESSION_OPS.attach(world, world.session, self, diagnostic_build)
	PIPELINE_PROBE.stage("gameplay_nodes")
	if not world.session.startup_complete: await world.session.startup_finished
	PIPELINE_PROBE.stage("session_startup")
	session = world.session
	if "--parking-baseline" not in OS.get_cmdline_user_args():
		roadside_parking = SESSION_OPS.instantiate(preload("res://runtime/RoadsideParking.gd"), self)
		roadside_parking.configure(world,self)
		SESSION_OPS.attach(world, roadside_parking, self, diagnostic_build)
	var v1_routines = SESSION_OPS.instantiate(preload("res://gameplay/routines_v1/RoutineDirector.gd"), self)
	v1_routines.configure(world,session,self)
	SESSION_OPS.attach(world, v1_routines, self, diagnostic_build)
	urban_transit = SESSION_OPS.instantiate(preload("res://runtime/UrbanTransitPresentation.gd"), self)
	urban_transit.configure(self)
	SESSION_OPS.attach(world, urban_transit, self, diagnostic_build)
	var saved_vehicle := starting_vehicle()
	if not saved_vehicle.is_empty() and saved_vehicle.get("was_driven",false) and saved_vehicle.region == state.region_id and state.place_id.is_empty():
		region.set_focus(Vector3(saved_vehicle.position[0],saved_vehicle.position[1],saved_vehicle.position[2]))
	if session.cold != null and not saved_vehicle.is_empty() and saved_vehicle.region == state.region_id:
		session.cold.prepare_collision_at(Vector3(saved_vehicle.position[0],saved_vehicle.position[1],saved_vehicle.position[2]))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--population="): requested_population = clampi(arg.split("=")[1].to_int(),0,MAX_POPULATION)
	curtain.set_stage(.3, "Assentando o terreno…")
	for i in 12: await get_tree().physics_frame
	await _prewarm_regions(curtain)
	if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return
	curtain.set_stage(.84, "Acendendo a cidade…")
	var road_point := nearest_road(world.player.position)
	# O cupê protótipo antes usava a faixa de circulação mais próxima. Depois
	# da mudança da oficina isso punha um carro padrão novo atravessado nas duas
	# chegadas guiadas. Veículos salvos mantêm a própria restauração abaixo; só o
	# padrão não salvo ganha uma pose de estacionamento apoiada fora da rua no pátio de carga.
	var default_car_parked := false
	if saved_vehicle.is_empty() and state.region_id == "harbor":
		for offset in [Vector3(-18.5,.12,6.3),Vector3(-20,.12,7.0),Vector3(-18.5,.12,4.9)]:
			var parking: Vector3 = world.maciota_place.exterior_origin+offset
			if not vehicle_position_clear(world.driving.car,parking,0.0): continue
			world.driving.car.place(parking,0.0)
			default_car_parked = true
			break
	if not default_car_parked: world.driving.car.place(road_point+Vector3.UP*.12,road_yaw(road_point))
	_restore_player_vehicle()
	# Um checkpoint a pé remoto pode escolher uma rua fora dos chunks iniciais
	# (por exemplo, a rodovia acima da pedreira). O carro inicial não salvo precisa pedir
	# o chão antes de a física começar, como fazem os veículos distantes restaurados.
	if saved_vehicle.is_empty() and not vehicle_position_clear(world.driving.car,world.driving.car.position,world.driving.car.rotation.y):
		world.driving.car.set_meta("awaiting_ground",true)
		world.driving.car.set_physics_process(false)
	# O clima precisa existir antes de o mundo ser marcado ready_for_play: o
	# ambiente/sol começam nos padrões crus definidos em build() acima
	# (uma cor de céu pálida e chapada), e é o Weather._ready() que os ajusta para
	# a hora do dia/estação salva. Criá-lo depois de ready_for_play deixava uma
	# janela de quadros em que o jogador já via e podia andar pelo
	# mundo com esse visual padrão cru, que parecia uma cena gelada e lavada
	# até o Weather alcançar.
	var weather = SESSION_OPS.instantiate(preload("res://runtime/Weather.gd"), self)
	weather.controller = self
	SESSION_OPS.attach(world, weather, self, diagnostic_build)
	session.weather = weather
	var city_look = SESSION_OPS.instantiate(preload("res://world/city_look/CityLook.gd"), self)
	city_look.controller = self
	SESSION_OPS.attach(world, city_look, self, diagnostic_build)
	var street_physics = SESSION_OPS.instantiate(preload("res://gameplay/street_physics/StreetPhysics.gd"), self)
	street_physics.controller = self
	SESSION_OPS.attach(world, street_physics, self, diagnostic_build)
	var rain_puddles = SESSION_OPS.instantiate(preload("res://world/rain/RainPuddles3D.gd"), self)
	rain_puddles.controller = self
	SESSION_OPS.attach(world, rain_puddles, self, diagnostic_build)
	var wildlife = SESSION_OPS.instantiate(preload("res://gameplay/wildlife/MountainWildlife.gd"), self)
	wildlife.controller = self
	SESSION_OPS.attach(world, wildlife, self, diagnostic_build)
	var roadside = SESSION_OPS.instantiate(preload("res://world/mountain_detail/MountainRoadside3D.gd"), self)
	roadside.controller = self
	SESSION_OPS.attach(world, roadside, self, diagnostic_build)
	var grass = SESSION_OPS.instantiate(preload("res://world/mountain_detail/MountainGrass3D.gd"), self)
	grass.controller = self
	SESSION_OPS.attach(world, grass, self, diagnostic_build)
	PIPELINE_PROBE.stage("session_systems")
	# Depois do Weather, do CityLook e da StreetPhysics: chuva (RainPrewarm.late; antes saía sem fazer nada),
	# efeitos de rua (StreetEffectsPrewarm), reações, interior do carro e combate. Em paralelo como os de
	# _prewarm_regions (GETECO_PREWARM_PARALLEL, ligado por padrão desde 24/10; =0 volta à série).
	var late_steps: Array[String] = ["street_fx", "reaction_visuals", "vehicle_interior", "combat_effects", "late_surfaces"]
	if preload("res://runtime/RainPrewarm.gd").late: late_steps.push_front("rain")
	if OS.get_environment("GETECO_PREWARM_PARALLEL") != "0":
		var pending: Array[int] = [late_steps.size()]
		for step in late_steps: _prewarm_lane([step], pending, curtain)
		if not await _await_lanes(pending): return
		PIPELINE_PROBE.stage("late_parallel_draws")
	else:
		for step in late_steps:
			await _draw_prewarm_step(step, curtain)
			if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return
			PIPELINE_PROBE.stage(step)
	_install_world_edits()
	# Estações de tubo e rodoviária montadas sob a cortina (depois das edições, que as movem): montadas ao
	# chegar perto custavam 84-140 ms num quadro (teleporte de aquecimento do benchmark, 16/10).
	if is_instance_valid(urban_transit):
		await urban_transit.prepare_startup_stations()
		if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return
	# Linha 510 montada aqui, depois das edições do mundo (mexem nas estações) e antes de
	# `ready_for_play`: montada no primeiro tique jogável, custava ~100 ms (pico de
	# 140–195 ms em `urban.physics` em todas as rotas do benchmark de 16/10).
	if is_instance_valid(urban_transit) and is_instance_valid(urban_transit.urban_service):
		await urban_transit.urban_service.prepare_startup()
		if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return
	# Mar em volta das ilhas e chão-base para a vista de longe (world/shape/WorldSea.gd): ~1,5 s de
	# montagem em fatias de 5 ms, sempre sob a cortina; GETECO_WORLD_SEA=0 desliga.
	if WORLD_SEA.enabled() and not is_instance_valid(world_sea):
		var sea_began := STALL_WORK.begin()
		world_sea = WORLD_SEA.new()
		world_sea.configure(self)
		world.add_child(world_sea)
		await world_sea.build_sliced(get_tree())
		if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return
		STALL_WORK.finish("startup.world_sea", sea_began)
		await world_sea.prewarm(world, curtain)
		if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return
		PIPELINE_PROBE.stage("world_sea")
	# O mirante costeiro monta seus modelos em fatias desde o _ready da sessão (antes, ~11 s num quadro
	# só, 16/10); num carregamento rápido elas ainda podem estar correndo, e cairiam no jogo.
	while is_instance_valid(session) and session.coastal_lookout != null and session.coastal_lookout.is_preparing():
		await get_tree().process_frame
		if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return
	PIPELINE_PROBE.stage("world_edits_and_transit")
	ready_for_play = true
	curtain.set_stage(.93, "Levando você ao ponto salvo…")
	await session.restore_location()
	if not play_at_request.is_empty(): await _place_at_request()
	set_population(requested_population)
	world_audio = _audio()
	SESSION_OPS.attach(world, world_audio, self, diagnostic_build)
	_update_chairlift_schedule()
	curtain.set_stage(.97, "Finalizando…")
	# O GarageRewards admite um motorista salvo de forma assíncrona a partir de restore_location.
	# A animação de corpo dele é dona da entrada até terminar; travar a sessão cedo
	# faria o Driving cancelar essa restauração no próximo quadro de física.
	while _startup_driver_pending():
		await get_tree().physics_frame
	var restored_session_ready: bool = session.ready_for_play
	var restored_player_automatic: bool = world.player.controlled_automatically
	var restored_player_direction: Vector3 = world.player.automatic_direction
	var restored_car: CharacterBody3D = world.driving.car
	var restored_car_lock: bool = restored_car.input_locked
	session.ready_for_play = false
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	restored_car.input_locked = true
	PIPELINE_PROBE.stage("restore_location")
	startup_streaming_settled = await _settle_startup()
	if not startup_streaming_settled:
		push_warning("Startup streaming still has pending work after its settling budget; runtime streaming will continue.")
	PIPELINE_PROBE.stage("settle_startup")
	# Antes do terminal: assim o JIT fica neste span em qualquer local de início.
	_prewarm_route_jit()
	# O jogador já está no ponto salvo: estações próximas na árvore ainda sob a cortina (só recolocadas).
	if is_instance_valid(urban_transit): urban_transit.refresh(true)
	# A primeira resolução de rota em C# precisa terminar enquanto a cortina de partida é dona da entrada.
	# Reaproveita a curva real do terminal depois; mantém o custo no trace de carregamento.
	if is_instance_valid(urban_transit) and is_instance_valid(urban_transit.terminal_operations):
		urban_transit.terminal_operations.prepare_startup_route()
		await urban_transit.terminal_operations.prepare_startup_passenger_meshes()
		urban_transit.terminal_operations.prepare_startup_build()
		await get_tree().process_frame
	if is_instance_valid(roadside_parking) and not world.has_meta("menu_preview"):
		roadside_parking.initialize_nearby()
		await get_tree().physics_frame
	# Pedidos da busca antecipada já vêm prontos do começo da carga; espera no máximo mais 3 s.
	var prefetch_traced := Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	await preload("res://runtime/BackgroundRegionPreparation.gd").prefetch_collect(get_tree(), Time.get_ticks_msec() + 3000)
	_trace_cost("startup:background_prefetch",prefetch_traced)
	preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd").release_hidden()
	PIPELINE_PROBE.stage("before_lift")
	if not world.has_meta("menu_preview"): await curtain.lift()
	PIPELINE_PROBE.stage("curtain_lift")
	session.ready_for_play = restored_session_ready
	world.player.controlled_automatically = restored_player_automatic
	world.player.automatic_direction = restored_player_direction
	if is_instance_valid(restored_car): restored_car.input_locked = restored_car_lock
	_trace_cost("startup:prepared",startup_traced)
	SESSION_OPS.finish(diagnostic_build)
	if world.has_meta("menu_preview"):
		await world.get_meta("menu_preview").hold_world(world)
		if world.is_queued_for_deletion(): return
	session.arrival.start_or_resume(loaded_save or "--skip-arrival" in OS.get_cmdline_user_args() or world.get_meta("skip_arrival",false))
	if is_instance_valid(world.dispatch):
		session.sync_dispatch_location()
		world.dispatch.set_physics_process(true)
	if is_instance_valid(world.traffic_yield): world.traffic_yield.set_physics_process(true)
	if is_instance_valid(background_preparation): background_preparation.set_process(true)

func _prewarm_regions(curtain: CanvasLayer = null) -> void: await _prewarm._prewarm_regions(curtain)

func _prewarm_audio_banks() -> void: await _prewarm._prewarm_audio_banks()

func _prewarm_weapon_templates() -> void: await _prewarm._prewarm_weapon_templates()

func _prewarm_resident_regions() -> void: await _prewarm._prewarm_resident_regions()

func _apply_player_settings() -> void:
	if is_instance_valid(environment): V2Settings.apply_environment(environment.environment)
	if is_instance_valid(sun) and sun_shadow_near_enabled:
		sun.directional_shadow_max_distance = V2Settings.shadow_distance_metres()

func _eager_preparation_for_benchmark() -> bool:
	return OS.is_debug_build() and world.get_meta("background_loading_baseline",false)

func _hold_fleet_scenes() -> void: _prewarm._hold_fleet_scenes()

func _prewarm_dispatch_models() -> void: await _prewarm._prewarm_dispatch_models()

func _collect_traffic_door_materials() -> void: await _prewarm._collect_traffic_door_materials()

func _prewarm_fleet_shaders(_incremental: bool, curtain: CanvasLayer = null) -> void: await _prewarm._prewarm_fleet_shaders(_incremental, curtain)

func _compile_fleet_hidden(ids: Array, curtain: CanvasLayer) -> bool: return await _prewarm._compile_fleet_hidden(ids, curtain)

func _dim_emissive_lenses(model: Node3D) -> int: return _prewarm._dim_emissive_lenses(model)

func _hold_fleet_scenes_incremental() -> void: await _prewarm._hold_fleet_scenes_incremental()

func _request_fleet_scenes_early() -> void: _prewarm._request_fleet_scenes_early()

func _retain_fleet_paths(paths: Array[String], retained: Array[Resource]) -> void: await _prewarm._retain_fleet_paths(paths, retained)

func _startup_driver_pending() -> bool:
	if world.driving.is_body_transition_active(): return true
	for car in vehicles:
		if is_instance_valid(car) and car.get_meta("garage_driver_pending", false): return true
	return false

func _settle_startup() -> bool:
	# Termina o streaming do destino e as primeiras atualizações de áudio/física antes do fade.
	# A admissão pode legitimamente deixar trabalho distante pendente; mantém a espera limitada.
	var stable_frames := 0
	for frame in 240:
		await get_tree().process_frame
		var idle := true
		for resident in regions.values():
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
	_geography_candidate = candidate
	_geography_task = WorkerThreadPool.add_task(candidate.prepare_data,false,"Loading region geography")
	while not WorkerThreadPool.is_task_completed(_geography_task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(_geography_task)
	_geography_task = -1
	var usable: bool = is_instance_valid(world) and world.is_inside_tree() and not world.is_queued_for_deletion()
	if usable and candidate.has_method("prepare_presentation_incremental"):
		await candidate.prepare_presentation_incremental(get_tree(), world)
		usable = is_instance_valid(world) and world.is_inside_tree() and not world.is_queued_for_deletion()
	_geography_candidate = null
	if not usable and is_instance_valid(candidate): candidate.free()
	return usable

func _exit_tree() -> void:
	if _geography_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_geography_task)
		_geography_task = -1
	if is_instance_valid(_geography_candidate): _geography_candidate.free()
	_geography_candidate = null
	for cached in _region_cache.values():
		if is_instance_valid(cached): cached.free()
	_region_cache.clear()
	if is_instance_valid(_parked_connection) and _parked_connection.get_parent() == null: _parked_connection.free()
	_parked_connection = null

## Lugares montados pela sessão (Vértice, Torque...) só recebem as edições do editor de mundo
## por observação da árvore; sem linhas desses lugares no documento nada é instalado.
func _install_world_edits() -> void:
	var document: Dictionary = Engine.get_meta("geteco_world_edit_document",{})
	if document.is_empty(): document = preload("res://world/editing/WorldEditData.gd").read_document().document
	if not document.is_empty(): preload("res://world/editing/WorldSessionEdits.gd").install(get_tree(),world,document)

## `--play-at=região,x,z` (só com --no-save). Devolve {} se ausente ou inválido.
var play_at_request: Dictionary = {}
static func _play_at_argument() -> Dictionary:
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--play-at="): continue
		var parts := argument.trim_prefix("--play-at=").split(",")
		if parts.size() != 3 or parts[0] not in ["harbor","mountain","desert"] or not parts[1].is_valid_float() or not parts[2].is_valid_float(): return {}
		return {"region":parts[0],"point":Vector3(parts[1].to_float(),0.0,parts[2].to_float())}
	return {}

## A altura só existe depois que a região está montada: grava no ponto de retomada do pedestre.
func _resolve_play_at() -> void:
	var point: Vector3 = play_at_request.point
	var ground := 0.0
	if region.get("terrain") != null: ground = region.terrain.surface_height_at(Vector2(point.x,point.z))
	elif state.region_id == "desert": ground = region._ground_height(Vector2(point.x,point.z))
	state.world_state["pedestrian"] = {"region":play_at_request.region,"position":[point.x,ground+.08,point.z]}

## O ponto escolhido no editor pode cair dentro de uma peça (ou de um prédio): procura o chão livre
## mais próximo, em anéis de até 8 m. Em cada coluna escolhe, entre as superfícies que um raio
## atravessa, a mais próxima do chão da região (não o telhado de cima).
func _place_at_request() -> void:
	var wanted: Vector3 = play_at_request.point
	region.set_focus(wanted)
	if session.cold != null: session.cold.prepare_collision_at(wanted)
	for i in 4: await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for ring in [0.0,1.5,3.0,4.5,6.0,8.0]:
		for step in (1 if ring == 0.0 else 8):
			var offset: Vector3 = Vector3(cos(TAU*step/8.0),0,sin(TAU*step/8.0))*ring
			var column: Vector3 = wanted+offset
			var nominal := 0.0
			if region.get("terrain") != null: nominal = region.terrain.surface_height_at(Vector2(column.x,column.z))
			elif state.region_id == "desert": nominal = region._ground_height(Vector2(column.x,column.z))
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
			if session.position_clear(point):
				world.player.teleport(point)
				return

func _startup_focus_hint() -> Vector3:
	if not play_at_request.is_empty(): return play_at_request.point
	if not state.place_id.is_empty(): return Vector3.INF
	var vehicle := starting_vehicle()
	if not vehicle.is_empty() and vehicle.get("was_driven",false) and vehicle.get("region","") == state.region_id:
		var position: Array = vehicle.get("position",[])
		if position.size() == 3: return Vector3(float(position[0]),float(position[1]),float(position[2]))
	var pedestrian: Dictionary = state.world_state.get("pedestrian",{})
	var coordinates: Array = pedestrian.get("position",[])
	if pedestrian.get("region","") == state.region_id and coordinates.size() == 3:
		var point := Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))
		if state.region_id == "desert": return preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").restore_point(point,state.world_state)
		if state.region_id == "harbor": return preload("res://world/railway/RailwayNetwork.gd").restore_harbor_pedestrian(point)
		return point
	return Vector3.INF

func _startup_position() -> Vector3:
	if not play_at_request.is_empty(): _resolve_play_at()
	# Monta e enquadra o destino salvo desde o primeiro quadro renderizado. A
	# encenação antiga com o Maciota primeiro expunha chunks pálidos de terreno/prédio não carregados
	# por vários segundos antes de restore_location teletransportar o Dante para o save.
	var fallback: Vector3 = world.maciota_place.exterior_return+Vector3(0,.08,2) if state.region_id == "harbor" else region.spawn_position+Vector3.UP*.08
	if not state.place_id.is_empty(): return fallback
	var saved_vehicle := starting_vehicle()
	if not saved_vehicle.is_empty() and saved_vehicle.get("was_driven",false) and saved_vehicle.get("region","") == state.region_id:
		var vehicle_position: Array = saved_vehicle.get("position",[])
		if vehicle_position.size() == 3:
			return Vector3(float(vehicle_position[0]),float(vehicle_position[1]),float(vehicle_position[2]))
	var pedestrian: Dictionary = state.world_state.get("pedestrian",{})
	var coordinates: Array = pedestrian.get("position",[])
	if pedestrian.get("region","") == state.region_id and coordinates.size() == 3:
		var point:=Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))
		if state.region_id=="desert":
			var restored:=preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").restore_point(point,state.world_state)
			if restored!=point: return restored+Vector3.UP*.08
		if state.region_id == "harbor": return preload("res://world/railway/RailwayNetwork.gd").restore_harbor_pedestrian(point)
		return point
	return fallback

func _audio() -> Node:
	var audio = preload("res://audio/WorldAudio.gd").new()
	audio.world = world
	return audio

func _physical_focus() -> Vector3:
	if session != null and is_instance_valid(session.regional_coach) and session.regional_coach.riding and is_instance_valid(session.regional_coach.train): return session.regional_coach.train.global_position
	if session != null and is_instance_valid(session.jessica) and session.jessica.riding and is_instance_valid(session.jessica.car): return session.jessica.car.global_position
	if session != null and is_instance_valid(session.arrival) and session.arrival.riding and is_instance_valid(session.arrival.car): return session.arrival.car.global_position
	if is_instance_valid(world.driving) and world.driving.occupied and is_instance_valid(world.driving.car):
		return world.driving.car.global_position
	if session != null and is_instance_valid(session.passenger_transport) and session.passenger_transport.riding and is_instance_valid(session.passenger_transport.car):
		return session.passenger_transport.car.global_position
	return world.player.global_position if is_instance_valid(world.player) else Vector3.ZERO

func _mount_region(id: String, requested_focus: Vector3 = Vector3.INF) -> Node3D:
	# Voltou a ser preciso antes da desmontagem adiada: fica montada.
	_pending_unmounts.erase(id)
	if regions.has(id) and is_instance_valid(regions[id]): return regions[id]
	var traced := Time.get_ticks_usec() if is_instance_valid(world) and (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	var mount_token := SESSION_OPS.begin(self, "streaming", "mount_region", {"region":id, "cached":_region_cache.has(id)})
	var mounted_region := _mount_region_now(id,requested_focus)
	SESSION_OPS.finish(mount_token, "mounted" if mounted_region != null else "missing")
	_trace_cost("mount_region:"+id,traced)
	return mounted_region

func _build_region(id: String, first_focus := Vector3.INF) -> Node3D:
	if id == "desert": return preload("res://world/editing/EditableDesertRegion.gd").build_region(id,first_focus)
	return REGION.build_region(id,first_focus)

func _mount_region_now(id: String, requested_focus: Vector3) -> Node3D:
	if is_instance_valid(background_preparation): background_preparation.take(id)
	var first_focus := requested_focus if requested_focus.is_finite() else (_physical_focus() if is_instance_valid(world.player) else Vector3.INF)
	var mounted: Node3D = null
	if _region_cache.has(id) and is_instance_valid(_region_cache[id]):
		mounted = _region_cache[id]
		_region_cache.erase(id)
		mounted.initial_focus = first_focus
	else:
		mounted = _build_region(id,first_focus)
	if mounted == null: return null
	if id=="desert": mounted.set_north_pass_completed(preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").completed(state.world_state))
	regions[id] = mounted
	# Spans (22/10): remontar o porto guardado custava 13 ms num quadro na serra, perto da ponte.
	var stage := STALL_WORK.begin()
	world.add_child(mounted)
	STALL_WORK.finish_slow("mount.add_child", stage, 2000)
	if stage != 0 and OS.get_environment("GETECO_MOUNT_CENSUS") == "1": _mount_census(mounted)
	if chairlift_schedule_initialized and mounted.has_method("set_chairlift_operating"): mounted.set_chairlift_operating(chairlift_operating)
	stage = STALL_WORK.begin()
	if first_focus.is_finite(): mounted.set_focus(first_focus)
	STALL_WORK.finish_slow("mount.set_focus", stage, 2000)
	_request_route_refresh()
	return mounted

## Rotas refeitas no quadro seguinte à montagem/desmontagem, já jogando (22/10): remontar o porto na serra
## somava montagem (8 ms), foco, conexão da ponte e os consumidores de rota (dispatch, cruzamentos,
## população, 3–5 ms) num quadro de 35–38 ms. Montagem e desmontagem no mesmo quadro refazem uma vez só.
## Sob a cortina e em teste continua no ato. GETECO_ROUTE_REFRESH_DEFER=0 volta ao ato sempre.
var _route_refresh_pending := false
func _request_route_refresh() -> void:
	if OS.get_environment("GETECO_ROUTE_REFRESH_DEFER") != "0" and ready_for_play and DisplayServer.get_name() != "headless":
		_route_refresh_pending = true
	else:
		_refresh_route_consumers()

## Diagnóstico (GETECO_MOUNT_CENSUS=1 com o log ligado): quantos nós cada filho direto da região remontada traz.
func _mount_census(mounted: Node) -> void:
	var rows: Array = []
	for child in mounted.get_children():
		rows.append([str(child.name), child.get_class(), child.get_child_count(), child.find_children("*", "", true, false).size()])
	rows.sort_custom(func(a, b): return a[3] > b[3])
	print("MOUNT_CENSUS ", mounted.name, " ", JSON.stringify(rows.slice(0, 20)))

## Desmontagem pela residência física, já jogando, espera um quadro sem outro trabalho pesado
## (HeavyFrameClaim): aos 3 s no deserto ela caía junto da etapa de estradas do chão (27/10).
## Sob a cortina, em teste e com GETECO_UNMOUNT_DEFER=0, desmonta no ato.
var _pending_unmounts: Dictionary = {}
func _queue_unmount(id: String) -> void:
	if OS.get_environment("GETECO_UNMOUNT_DEFER") != "0" and ready_for_play and DisplayServer.get_name() != "headless":
		if regions.has(id): _pending_unmounts[id] = true
	else:
		_unmount_region(id)

func _drain_pending_unmount() -> void:
	if _pending_unmounts.is_empty() or not HEAVY_FRAME.claim("world.unmount"): return
	var id: String = _pending_unmounts.keys()[0]
	_pending_unmounts.erase(id)
	_unmount_region(id)

func _unmount_region(id: String) -> void:
	_pending_unmounts.erase(id)
	if id == state.region_id or not regions.has(id): return
	var stall_began := STALL_WORK.begin()
	var mounted: Node3D = regions[id]
	regions.erase(id)
	if is_instance_valid(mounted):
		mounted.release_chunks()
		if mounted.has_method("hand_off_retiring"): mounted.hand_off_retiring()
		var detach_began := STALL_WORK.begin()
		world.remove_child(mounted)
		STALL_WORK.finish("unmount.remove_child", detach_began, {"region": id})
		_region_cache[id] = mounted
	_request_route_refresh()
	STALL_WORK.finish("world.unmount_region", stall_began, {"region": id})

func _resident_roads() -> Array: return _traffic._resident_roads()

## Grafos de rota por conjunto de regiões residentes. configure() cruza todos os
## trechos entre si (~55 + 65 ms com Harbor e Mountain); na costura isso se repetia a
## cada montagem/desmontagem de Mountain. Cópias rasas: configure() esvazia no lugar.
var _route_cache: Dictionary = {}

func _route_key() -> String: return _traffic._route_key()

static func _graph_snapshot(graph) -> Array: return TRAFFIC._graph_snapshot(graph)

static func _graph_restore(graph, snapshot: Array) -> void: TRAFFIC._graph_restore(graph, snapshot)

func _configure_routes() -> void: _traffic._configure_routes()

func _refresh_route_consumers() -> void: _traffic._refresh_route_consumers()

func _persistent_vehicle_support() -> Dictionary:
	var support := {"harbor":[],"mountain":[],"desert":[]}
	if is_instance_valid(urban_transit) and is_instance_valid(urban_transit.urban_service):
		for bus in urban_transit.urban_service.fleet:
			if not is_instance_valid(bus) or not bus.active: continue
			var bus_region: String = bus.get_meta("region_id","harbor")
			if not support.has(bus_region): continue
			for index in bus.sections.size():
				support[bus_region].append({"position":bus.sections[index].global_position,"radius":bus.LENGTHS[index]*.5+1.0})
			# Retém a célula de antecipação admitida e também o casco atual.
			# Senão o streaming pode despejá-la antes do próximo passo de física.
			support[bus_region].append({"position":bus.global_position-bus.global_basis.z*8,"radius":2.0})
	for car in vehicles:
		if not is_instance_valid(car) or car.is_queued_for_deletion() or not car.visible: continue
		# Um corpo suspenso pelo streaming ainda é dono do pedido de chão. Excluí-lo
		# aqui despejaria o chunk antes de a checagem de chão poder retomá-lo.
		if not car.is_physics_processing() and not car.has_meta("awaiting_ground") and not car.has_meta("desert_drag_physics") and not car.get_meta("armored_transport",false): continue
		if _is_ambient_traffic(car) and car != world.driving.car and not car.get_meta("gang_hostile",false): continue
		var persistent: bool = _is_persistent_vehicle(car)
		if not persistent:
			if car.traffic: continue
			if car.global_position.distance_to(world.player.global_position) > 145:
				# Aposenta antes de soltar o chão, não no tick de população até
				# .25 s depois. Donos de save nunca podem ver um carro estacionado caindo.
				car.set_meta("distance_despawn", true)
				car.set_physics_process(false)
				car.queue_free()
				continue
		# Nearby parked cars need support too, including across a cell boundary.
		var id: String = WORLD_CONNECTION.logical_region(car.global_position)
		var radius: float = Vector2(car.half_width,car.half_length).length()+0.5
		support[id].append({"position":car.global_position,"radius":radius})
		if car.get_meta("port_work_vehicle",false) or car.get_meta("race_owned",false) or car.get_meta("armored_transport",false):
			# O PortLogistics admite este mesmo ponto antes de mover. Mantém o chunk
			# até o pedido seguir adiante; só o raio do casco não o cobre.
			support[id].append({"position":car.global_position-car.global_basis.z*(car.half_length+3),"radius":0.0})
	return support

func _is_persistent_vehicle(car: Node) -> bool:
	return car == world.driving.car or car.vehicle_id in ["neco_tow_truck","story_tow_vehicle"] or car.get_meta("residence_vehicle",false) or car.get_meta("garage_reward",false) or car.get_meta("port_work_vehicle",false) or car.get_meta("secret_discovery_vehicle",false) or car.get_meta("race_owned",false) or car.has_meta("desert_drag_physics") or car.get_meta("armored_transport",false)

## Rede de segurança para veículos que importam ao jogador. No release de 2026-10-13 a moto salva,
## restaurada a 200 m na serra, acordou quando o chão apareceu e caiu sem fim (até y≈-1300) quando o
## chunk saiu da memória; o caminho exato dependia do save e não foi reproduzido. Qualquer persistente
## que despencar bem abaixo do mundo volta ao último ponto apoiado e espera o chão de novo.
const BENCHMARK_AUTOPILOT := preload("res://runtime/BenchmarkAutopilot.gd")
const FALL_RESCUE_DEPTH := 30.0
const FALL_RESCUE_BELOW_Y := -60.0

func _rescue_fallen_vehicles() -> void:
	for car in vehicles:
		if not is_instance_valid(car) or car.is_queued_for_deletion() or not _is_persistent_vehicle(car): continue
		# Ponto de espera também conta como apoiado: é onde o veículo deveria ficar.
		if car.has_meta("awaiting_ground") or (car.is_physics_processing() and car.is_on_floor()):
			car.set_meta("last_supported_position", car.global_position)
			continue
		if not car.is_physics_processing() or not car.has_meta("last_supported_position"): continue
		var anchor: Vector3 = car.get_meta("last_supported_position")
		if car.global_position.y > FALL_RESCUE_BELOW_Y or car.global_position.y > anchor.y - FALL_RESCUE_DEPTH: continue
		var driven: bool = world.driving.occupied and car == world.driving.car
		# O piloto do benchmark conta as próprias quedas (8 m abaixo da rota) e recoloca o carro
		# sozinho; resgatar aqui apagaria a queda do relatório que mede justamente isso.
		if driven and BENCHMARK_AUTOPILOT.requested(): continue
		car.place(anchor, car.rotation.y)
		car.set_meta("awaiting_ground", true)
		car.set_physics_process(false)
		if driven: _rescue_driver(car)
		push_warning("Veículo %s caiu abaixo do mundo; devolvido a %s até o chão carregar." % [car.vehicle_id, anchor])

## Antes o carro dirigido ficava de fora e o jogador caía junto sem fim. O motorista continua
## sentado: Driving copia car.position para o jogador a cada passo de física, então basta
## alinhar agora (sem esperar o próximo passo) e pedir à câmera que recentre, como o teleporte.
func _rescue_driver(car: Node) -> void:
	world.player.position = car.position
	world.player.velocity = Vector3.ZERO
	world.player.reset_physics_interpolation()
	world.driving.set("_last_vehicle_position", car.global_position)
	if is_instance_valid(world.camera): world.camera.initialized = false
	if is_instance_valid(world.session) and world.session.has_method("show_message"):
		world.session.show_message("O carro caiu do mapa e voltou para a estrada.")

func _active_dispatch_support() -> Dictionary:
	var support := {"harbor":[],"mountain":[],"desert":[]}
	var dispatch: Variant = world.get("dispatch") if is_instance_valid(world) else null
	if not is_instance_valid(dispatch): return support
	for unit in dispatch.units:
		if unit.finished: continue
		var car: CharacterBody3D = unit.vehicle
		if not is_instance_valid(car) or car.is_queued_for_deletion(): continue
		var resume_requested: bool = unit.suspended and dispatch.distance_to_player(car.global_position) <= preload("res://gameplay/dispatch/DispatchRules.gd").RESUME_DISTANCE
		if unit.suspended and not resume_requested: continue
		if not resume_requested and not car.is_visible_in_tree(): continue
		if not resume_requested and not car.is_physics_processing() and not car.get_meta("awaiting_ground",false): continue
		var radius: float = Vector2(car.half_width,car.half_length).length()+0.5
		var ahead := car.global_position-car.global_basis.z*12.0
		for point: Vector3 in [car.global_position,ahead]:
			var source_owner := WORLD_CONNECTION.logical_region(point)
			# Este pedido só retém células num dono já residente. Não pode
			# montar regiões distantes nem mudar a política de residência do jogador.
			if not regions.has(source_owner) or not is_instance_valid(regions[source_owner]): continue
			support[source_owner].append({"position":point,"radius":radius if point == car.global_position else 0.0})
	# Recalculado a partir das unidades vivas: suspensão, conclusão e remoção o soltam.
	return support

func _update_physical_residency(point: Vector3) -> void:
	var physical_region := WORLD_CONNECTION.logical_region(point)
	var support := _persistent_vehicle_support()
	_mount_region(physical_region,point)
	var seam_distance := Vector2(point.x-WORLD_CONNECTION.SEAM.x,point.z-WORLD_CONNECTION.SEAM.z).length()
	var north_distance := Vector2(point.x-NORTH_CONNECTION_ANCHOR.x,point.z-NORTH_CONNECTION_ANCHOR.z).length()
	var north_preload := north_distance<NORTH_CONNECTION_PRELOAD
	var north_keep := north_distance<230.0
	if north_preload:
		_mount_region("harbor",point)
		_mount_region("desert",point)
	var seam_anchor := point
	var seam_preload := seam_distance <= CONNECTION_PRELOAD_DISTANCE
	var seam_keep := seam_distance <= CONNECTION_RELEASE_DISTANCE
	# Folga da emenda: perto da ponte porto e serra guardam o raio maior. Antes o raio trocava 2<->1
	# entre as duas ao cruzar a divisa no meio da ponte: uma descartava uma faixa de trechos e a outra
	# carregava outra no mesmo instante, e andar perto da divisa repetia isso (relato do jogador, 16/10).
	# Liga a CONNECTION_PRELOAD_DISTANCE e só desliga depois de CONNECTION_RELEASE_DISTANCE.
	if _seam_hold_enabled:
		if seam_preload: _seam_retention = true
		elif not seam_keep: _seam_retention = false
	for id in ["harbor","mountain","desert"]:
		for vehicle in support[id]:
			var position: Vector3 = vehicle.position
			var distance := Vector2(position.x-WORLD_CONNECTION.SEAM.x,position.z-WORLD_CONNECTION.SEAM.z).length()
			if distance <= CONNECTION_PRELOAD_DISTANCE and not seam_preload:
				seam_anchor = position
				seam_preload = true
			if distance <= CONNECTION_RELEASE_DISTANCE: seam_keep = true
		if not support[id].is_empty(): _mount_region(id,support[id][0].position)
	if seam_preload:
		_mount_region("harbor",seam_anchor)
		_mount_region("mountain",seam_anchor)
	if seam_preload or north_preload: _mount_connection()
	elif not seam_keep and not north_keep:
		for id in ["harbor","mountain","desert"]:
			if id != physical_region and support[id].is_empty(): _queue_unmount(id)
		if is_instance_valid(connection):
			if _connection_park_enabled and not is_instance_valid(_parked_connection):
				# Estacionada (22/10): a mesma conexão volta na próxima aproximação da ponte, sem remontar.
				world.remove_child(connection)
				_parked_connection = connection
			else:
				# Conexão da ponte (dezenas de malhas e colisões) sai pela fila de vídeo, aos poucos (16/10).
				GPU_RELEASE.retire(connection)
			connection = null
	var dispatch_support := _active_dispatch_support()
	for id in regions:
		var mounted: Node3D = regions[id]
		if not is_instance_valid(mounted): continue
		mounted.set_vehicle_support(support[id]+dispatch_support[id])
		var seam_side: bool = _seam_retention and (id == "harbor" or id == "mountain")
		mounted.set_retention_radius(2 if id == physical_region or seam_side else 1)
		var region_focus := point
		if id != physical_region and seam_distance > CONNECTION_PRELOAD_DISTANCE:
			if not support[id].is_empty(): region_focus = support[id][0].position
			elif seam_preload: region_focus = seam_anchor
		mounted.set_focus(region_focus)

## Conexão da ponte estacionada fora da árvore entre aproximações (22/10): era montada de novo a cada
## entrada na faixa de 240 m (world_connection 3 ms) no mesmo quadro em que o porto voltava (13 ms).
## GETECO_CONNECTION_PARK=0 volta a montar e liberar.
static var _connection_park_enabled := OS.get_environment("GETECO_CONNECTION_PARK") != "0"
var _parked_connection: Node3D

func _mount_connection() -> void:
	if is_instance_valid(connection): return
	var traced := Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	if is_instance_valid(_parked_connection):
		connection = _parked_connection
		_parked_connection = null
	else:
		connection = WORLD_CONNECTION.new()
	world.add_child(connection)
	_trace_cost("world_connection",traced)

## Desde a ponte unificada (6079bffd, 16/10) o piso do corredor é só da conexão: as regiões recortam a
## pegada dela. O ponto de partida da serra (spawn_position) fica nesse tabuleiro. Viagem e resgate
## conferem o chão antes de _update_physical_residency chegar lá, então montam a conexão aqui; sem
## isso a viagem padrão para a serra dava "sem solo" e o resgate na serra longe da emenda ficava
## preso em "Local de resgate ocupado" (sonda de 18/10). É o mesmo custo de logo depois do teleporte.
func prepare_connection_at(point: Vector3) -> void:
	var seam_distance := Vector2(point.x-WORLD_CONNECTION.SEAM.x,point.z-WORLD_CONNECTION.SEAM.z).length()
	var north_distance := Vector2(point.x-NORTH_CONNECTION_ANCHOR.x,point.z-NORTH_CONNECTION_ANCHOR.z).length()
	if seam_distance <= CONNECTION_PRELOAD_DISTANCE or north_distance < NORTH_CONNECTION_PRELOAD: _mount_connection()

## Folga da divisa porto/serra. Sem ela, parado na ponte em cima da linha (x≈456), o jogador trocou de
## região 7 vezes em 11 s mexendo menos de 1 m (release de 2026-10-13), e cada troca refaz rotas,
## tráfego, clima e áudio.
const LOGICAL_REGION_HYSTERESIS := 4.0

func _update_logical_region(point: Vector3) -> void:
	if not state.place_id.is_empty(): return
	var next_region := WORLD_CONNECTION.logical_region(point)
	if next_region == state.region_id or not regions.has(next_region): return
	if _inside_logical_hysteresis(point, next_region): return
	_commit_logical_region(next_region)

## Entre porto e serra a troca só vale quando o ponto continua do outro lado mesmo recuado pela folga.
func _inside_logical_hysteresis(point: Vector3, next_region: String) -> bool:
	var pair := [state.region_id, next_region]
	if not ("harbor" in pair and "mountain" in pair): return false
	var back := Vector3(-LOGICAL_REGION_HYSTERESIS, 0.0, LOGICAL_REGION_HYSTERESIS) if next_region == "mountain" else Vector3(LOGICAL_REGION_HYSTERESIS, 0.0, -LOGICAL_REGION_HYSTERESIS)
	return WORLD_CONNECTION.logical_region(point + back) != next_region

func _commit_logical_region(next_region: String) -> void:
	if next_region == state.region_id or not regions.has(next_region): return
	var previous: String = state.region_id
	state.set_location(next_region)
	region = regions[next_region]
	world.street = region
	# Veículos do jogador e com passageiro mantêm as mesmas instâncias,
	# velocidade, ocupantes e acessórios; só o contexto lógico de rota muda.
	if world.driving.occupied and is_instance_valid(world.driving.car): world.driving.car.set_meta("region_id",next_region)
	if session != null and is_instance_valid(session.passenger_transport) and session.passenger_transport.riding and is_instance_valid(session.passenger_transport.car):
		session.passenger_transport.car.set_meta("region_id",next_region)
	_repath_ambient_traffic()
	_refresh_route_consumers()
	if is_instance_valid(urban_transit): urban_transit.on_region_changed()
	if session != null:
		session.sync_dispatch_location()
		session.refresh_routine_context()
		if is_instance_valid(session.weather): session.weather._update()
	if is_instance_valid(world_audio) and world_audio.has_method("on_region_changed"):
		world_audio.on_region_changed(previous,next_region)
	logical_region_changed.emit(previous,next_region)

func _update_mobile_region_metadata() -> void:
	for car in vehicles:
		if not is_instance_valid(car) or not car.is_visible_in_tree(): continue
		car.set_meta("region_id",WORLD_CONNECTION.logical_region(car.global_position))

func _update_chairlift_schedule() -> void:
	if session == null or not is_instance_valid(session.weather): return
	var hour := float(session.weather.time_of_day)*24.0
	var operating := hour >= 8.0 and hour < 18.0
	if chairlift_schedule_initialized and operating == chairlift_operating: return
	chairlift_schedule_initialized = true
	chairlift_operating = operating
	for mounted in regions.values():
		if is_instance_valid(mounted) and mounted.has_method("set_chairlift_operating"): mounted.set_chairlift_operating(operating)

func starting_vehicle() -> Dictionary:
	var saved: Array = state.world_state.get("vehicles",[])
	if saved.is_empty(): return {}
	var record: Dictionary=saved[0]
	if record.get("region","")=="desert":
		var point:=Vector3(record.position[0],record.position[1],record.position[2])
		var restored:=preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").restore_point(point,state.world_state)
		if restored!=point:
			record=record.duplicate(true)
			record.position=[restored.x,.12,restored.z]
			record.yaw=0.0
	return record

func _restore_player_vehicle() -> void:
	var saved := starting_vehicle()
	if saved.is_empty(): return
	var car: CharacterBody3D = world.driving.car
	var point := Vector3(saved.position[0],saved.position[1],saved.position[2])
	if car.has_method("restore_fleet_extras"): car.restore_fleet_extras(saved)
	car.equipment_state = saved.get("equipment",{}).duplicate(true)
	if saved.has("paint"): car.paint_color = Color.html(saved.paint)
	if saved.has("vehicle_id"): car.vehicle_id = str(saved.vehicle_id)
	if car.archetype == "taxi_yellow":
		car.set_meta("taxi_stolen",true)
		preload("res://runtime/TaxiService.gd").light(car,false)
	car.set_meta("region_id",saved.region)
	if float(saved.get("heavy_crush_ratio",1.0)) < 1.0:
		preload("res://gameplay/street_physics/HeavyVehicleCrush.gd").apply_saved(car,float(saved.heavy_crush_ratio))
		if float(saved.health) <= 0: car.set_meta("heavy_crush_exploded",true)
	if saved.region != state.region_id or (point.distance_to(world.player.position)>75 and not saved.get("was_driven",false)):
		car.place(point,float(saved.yaw))
		car.set_meta("awaiting_ground",true)
		car.set_physics_process(false)
		car.visible = saved.region == state.region_id
	elif vehicle_position_clear(car,point,float(saved.yaw)):
		car.place(point,float(saved.yaw))
	else:
		# A pose inicial na rua mais próxima pode ser a mesma pose salva obstruída.
		# Admite o corpo antes do primeiro passo de física; nunca deixa a recuperação empurrar
		# um carro carregado através de um sólido ou para baixo da rua.
		var admitted := false
		for distance in [6.0,12.0,24.0,48.0]:
			for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
				var candidate := nearest_road(point+direction*distance)+Vector3.UP*.12
				var yaw := road_yaw(candidate)
				if not vehicle_position_clear(car,candidate,yaw): continue
				car.place(candidate,yaw)
				admitted = true
				break
			if admitted: break
		if not admitted:
			car.place(point,float(saved.yaw))
			car.set_meta("awaiting_ground",true)
			car.set_physics_process(false)
	car.restore_health(float(saved.health))
	car.restore_body_dents(saved.get("body_dents",[]),saved.get("breakaway_parts",{}),saved.get("broken_glass",[]))
	car.restore_blood_stains(int(saved.get("blood_stains",0)))
	if int(saved.get("punctured_tires",0)) > 0:
		preload("res://gameplay/police_response/ground/TirePuncture.gd").puncture(car,int(saved.punctured_tires),false)

func capture_player_vehicle() -> void:
	# A missing selection must not erase another valid stored vehicle or cast a
	# freed reference. Explicit removals retire their own snapshot separately.
	if not is_instance_valid(world.driving.car): return
	var car: CharacterBody3D = world.driving.car
	if car.vehicle_id in ["story_tow_vehicle","neco_tow_truck"] or car.get_meta("residence_vehicle",false) or car.get_meta("garage_reward",false): return
	if car.vehicle_id == "jessica_jetta_gli": return
	state.world_state.vehicles = [preload("res://runtime/FleetState.gd").capture(car,state.region_id)]
	state.world_state.vehicles[0].was_driven = world.driving.occupied

func release_player_vehicle() -> void:
	if not is_instance_valid(world.driving.car): return
	var car: CharacterBody3D = world.driving.car
	# queue_free durante o jogo é remoção deliberada, não um carro em streaming/salvo.
	# Mantém snapshots sem relação de garagem/história e evita reviver este corpo ao carregar.
	if car.is_queued_for_deletion() and not world.is_queued_for_deletion():
		if starting_vehicle().get("vehicle_id", "") == car.vehicle_id:
			state.world_state.vehicles = []
		return
	capture_player_vehicle()

func nearest_road(point: Vector3) -> Vector3:
	var closest := point
	var distance := INF
	for road in _resident_roads():
		for i in range(road.points.size()-1):
			var candidate := Geometry3D.get_closest_point_to_segment(point,road.points[i],road.points[i+1])
			var offset: Vector3 = (road.points[i+1]-road.points[i]).normalized().cross(Vector3.UP)*road.width*.25
			candidate += offset
			if point.distance_squared_to(candidate) < distance:
				distance = point.distance_squared_to(candidate)
				closest = candidate
	return closest

func set_population(count: int) -> void:
	requested_population = clampi(count,0,VC_MAX_POPULATION if population_vc_enabled else MAX_POPULATION)
	if not ready_for_play: return
	while world.people.size() > requested_population:
		var actor = world.people.pop_back()
		if is_instance_valid(actor): actor.queue_free()
	world.population = world.people.size()

const _SYS_SPAN := preload("res://runtime/StallWorkTrace.gd")
## Span do sistema inteiro (22/10): quadros de 30–60 ms com o tempo em _process sem nenhum span.
func _process(delta: float) -> void:
	var span := _SYS_SPAN.begin()
	_process_traced(delta)
	_SYS_SPAN.finish_slow("sys.production.process", span, 3000)

func _process_traced(delta: float) -> void:
	if not ready_for_play: return
	# Refazer rotas (3–5 ms) também pede o quadro: se o chão do deserto já o levou, fica para o próximo.
	if _route_refresh_pending and HEAVY_FRAME.claim("routes.refresh"):
		_route_refresh_pending = false
		var refresh_span := STALL_WORK.begin()
		_refresh_route_consumers()
		STALL_WORK.finish_slow("routes.deferred_refresh", refresh_span, 2000)
		# Um quadro só para isto: a residência física (montagem/desmontagem) volta no próximo.
		return
	_drain_pending_unmount()
	_update_chairlift_schedule()
	if travel_busy: return
	# As rotinas de admissão são donas do foco enquanto esperam a sincronia de colisão.
	# Seguir a posição antiga do jogador aqui descarregaria o destino dele.
	if session == null or not session.ready_for_play or session.has_position_transition(): return
	if not _p1_count_started and "--p1-count" in OS.get_cmdline_user_args():
		_p1_count_started = true
		_count_p1_population()
	if not _release_benchmark_started and RELEASE_BENCHMARK.requested():
		_release_benchmark_started = true
		var benchmark := RELEASE_BENCHMARK.new()
		benchmark.name = "ReleaseBenchmark"
		benchmark.world = world
		add_child(benchmark)
	var street_live: bool = state.place_id.is_empty() or (session.building_entrance != null and session.building_entrance.in_building()) or (session.service_roofs != null and session.service_roofs.is_active())
	if street_live:
		var focus := _physical_focus()
		_update_physical_residency(focus)
		_update_logical_region(focus)
	if street_live: _service_population_job()
	else: _population_jobs.clear()
	if street_live and population_vc_enabled: _review_pedestrians(delta)
	population_clock += delta
	if population_clock < .25 or not street_live: return
	population_clock = 0
	_update_density()
	_update_mobile_region_metadata()
	for index in range(world.people.size()-1,-1,-1) if not population_vc_enabled else []:
		var actor = world.people[index]
		if not is_instance_valid(actor): world.people.remove_at(index)
		elif PORT_POLICY.contains_private_area(actor.global_position):
			world.people.remove_at(index)
			actor.queue_free()
		elif actor.position.distance_to(world.player.position) > POPULATION_DESPAWN and not _on_screen(actor.global_position,1.0):
			world.people.remove_at(index)
			actor.queue_free()
	# Reposição e criação de equipamento se acumulavam neste mesmo
	# tick de quarto de segundo. Cada uma pode instanciar malhas/materiais; admite um trabalho
	# por quadro seguinte, preservando as metas de população e todo equipamento de veículo.
	_trim_density()
	if _population_jobs.is_empty(): _population_jobs.assign(["citizen","traffic","equipment","equipment"])
	footbridge_crossers.update(world, world.player.position, state.region_id, population_cap())
	ambient_journeys.update(self)
	for index in range(vehicles.size()-1,-1,-1):
		var car = vehicles[index]
		if not is_instance_valid(car): vehicles.remove_at(index)
		elif _is_ambient_traffic(car) and car.traffic and car != world.driving.car and PORT_POLICY.contains_private_area(car.global_position):
			vehicles.remove_at(index)
			STALL_WORK.finish("marker.vehicle_despawn", STALL_WORK.begin())
			car.queue_free()
		elif _is_ambient_traffic(car) and car.health <= 0.0 and car != world.driving.car and _wreck_expired(car) and car.global_position.distance_to(world.player.global_position) > 20.0 and not _on_screen(car.global_position,3.0):
			# Carcaça de trânsito (traffic=false ao ser destruída) nunca saía de cena e
			# travava cruzamentos. Some fora do quadro, depois de alguns segundos.
			vehicles.remove_at(index)
			STALL_WORK.finish("marker.vehicle_despawn", STALL_WORK.begin())
			car.queue_free()
		elif _is_ambient_traffic(car) and car.traffic and car != world.driving.car and car.stuck_time > STUCK_DESPAWN_SECONDS and car.global_position.distance_to(world.player.global_position) > STUCK_DESPAWN_DISTANCE and not _on_screen(car.global_position,3.0):
			# Travado sem saída (desvio impossível, impasse): some fora do quadro e o
			# spawner repõe outro em ponto livre. Antes a fila ficava parada para sempre.
			vehicles.remove_at(index)
			STALL_WORK.finish("marker.vehicle_despawn", STALL_WORK.begin())
			car.queue_free()
		elif not traffic_holds.is_empty() and _is_ambient_traffic(car) and car.traffic and car != world.driving.car and in_traffic_hold(car.global_position) and not _on_screen(car.global_position,3.0):
			# Trecho reservado (set_traffic_hold): o carro sai antes de chegar à vista.
			traffic_hold_removed += 1
			vehicles.remove_at(index)
			STALL_WORK.finish("marker.vehicle_despawn", STALL_WORK.begin())
			car.queue_free()
		elif _is_ambient_traffic(car) and car.traffic and car.global_position.distance_to(world.player.global_position) > POPULATION_DESPAWN and not _on_screen(car.global_position,3.0):
			# Trânsito ambiente sai de cena só longe e fora do quadro, como entra.
			vehicles.remove_at(index)
			STALL_WORK.finish("marker.vehicle_despawn", STALL_WORK.begin())
			car.queue_free()
		elif car.get_meta("region_id",state.region_id) != state.region_id: continue
		elif car.has_meta("awaiting_ground"):
			# Rampa do túnel do canal: o carro suspenso durante o streaming afundava
			# até ~1 m no piso inclinado e nenhum raio achava chão. Volta à superfície.
			if CANAL_TUNNEL.in_roadway(car.position): car.position.y = CANAL_TUNNEL.floor_y(car.position.x) + .05
			if vehicle_position_clear(car,car.position,car.rotation.y):
				car.remove_meta("awaiting_ground")
				car.set_physics_process(true)
		elif not car.traffic and car != world.driving.car and car.vehicle_id not in ["story_tow_vehicle","neco_tow_truck"] and not car.get_meta("residence_vehicle",false) and not car.get_meta("garage_reward",false) and not car.get_meta("port_work_vehicle",false) and not car.get_meta("secret_discovery_vehicle",false) and not car.get_meta("race_owned",false) and not car.get_meta("armored_transport",false) and car.position.distance_to(world.player.position) > 145:
			vehicles.remove_at(index)
			# Donos de um snapshot estacionado conseguem distinguir a limpeza do streaming de
			# uma remoção explícita sem manter vivo um corpo físico distante.
			car.set_meta("distance_despawn", true)
			STALL_WORK.finish("marker.vehicle_despawn", STALL_WORK.begin())
			car.queue_free()
	_rescue_fallen_vehicles()
	world.population = world.people.size()

func _review_pedestrians(delta: float) -> void: _population._review_pedestrians(delta)

func _count_p1_population() -> void: await _population._count_p1_population()

static func density_target(dispatch_units: int, stars: int) -> float: return POPULATION.density_target(dispatch_units, stars)

static func area_density_target(region_id: String, point: Vector3) -> Vector2: return POPULATION.area_density_target(region_id, point)

func _update_density() -> void: _population._update_density()

func population_cap() -> int:
	var target := mini(requested_population,VC_MAX_POPULATION) if population_vc_enabled else requested_population
	return ceili(float(target)*minf(density_scale,area_density_scale.x)-.00001)
func _population_cap() -> int: return population_cap()

func traffic_cap() -> int:
	# Os componentes de Vector2 são float32; ignora o erro de arredondamento abaixo de uma entidade nos
	# tetos inteiros escritos (por exemplo, 40 * .8 precisa continuar 32, não 33).
	return ceili(float(VC_TRAFFIC_TARGET if population_vc_enabled else TRAFFIC_TARGET)*minf(density_scale,area_density_scale.y)-.00001)
func _traffic_cap() -> int: return traffic_cap()

func _trim_density() -> void: _population._trim_density()

func _service_population_job() -> void: _population._service_population_job()

func vehicle_position_clear(car: CharacterBody3D, point: Vector3, yaw: float) -> bool: return _traffic.vehicle_position_clear(car, point, yaw)

func spawn_vehicle(id: String, point: Vector3, yaw: float = 0.0, crush_ratio: float = 1.0) -> CharacterBody3D: return _traffic.spawn_vehicle(id, point, yaw, crush_ratio)

func _ambient_traffic_count() -> int: return _traffic._ambient_traffic_count()

func _is_ambient_traffic(car: Variant) -> bool: return _traffic._is_ambient_traffic(car)

func _repath_ambient_traffic() -> void: _traffic._repath_ambient_traffic()

## Ponto dentro do quadro da câmera (com folga de `radius` metros e 10% da tela).
func _on_screen(point: Vector3, radius: float = 1.0) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return false
	var rect := get_viewport().get_visible_rect().grow(get_viewport().get_visible_rect().size.x*.1)
	for offset in [Vector3.ZERO,Vector3.UP*2.0,Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
		var sample: Vector3 = point+offset
		if not camera.is_position_behind(sample) and rect.has_point(camera.unproject_position(sample)): return true
	return false

func _carriageway_cells() -> Dictionary: return _traffic._carriageway_cells()

func _on_carriageway(point: Vector3) -> bool: return _traffic._on_carriageway(point)

static func carriageway_grid(roads: Array) -> Dictionary: return TRAFFIC.carriageway_grid(roads)

static func grid_on_carriageway(grid: Dictionary, point: Vector3) -> bool: return TRAFFIC.grid_on_carriageway(grid, point)

func _wreck_expired(car: Node) -> bool: return _traffic._wreck_expired(car)

## Anel de entrada/saída: longe o bastante e fora do quadro.
## Trechos onde o trânsito ambiente não nasce e, fora do quadro, sai de cena (29/10). A Descida da Meia
## Noite marca o grampo dos portões 7–9 enquanto a prova corre: um carro do trânsito descendo ali a 4–6 m/s
## enfileirava os rivais, sem reta para ultrapassar (docs/downhill-20261028.md). id -> [pontos, raio].
var traffic_holds: Dictionary = {}
var traffic_hold_removed := 0

func set_traffic_hold(id: StringName, points: PackedVector3Array, radius: float) -> void:
	traffic_holds[id] = [points, radius]

func clear_traffic_hold(id: StringName) -> void:
	traffic_holds.erase(id)

func clear_ambient_traffic_near(points: PackedVector3Array, radius: float) -> int: return _traffic.clear_ambient_traffic_near(points, radius)

func in_traffic_hold(point: Vector3) -> bool: return _traffic.in_traffic_hold(point)

func _spawn_point_allowed(point: Vector3, radius: float, minimum := POPULATION_SPAWN_MIN) -> bool: return _traffic._spawn_point_allowed(point, radius, minimum)

func road_yaw(point: Vector3) -> float: return _traffic.road_yaw(point)

func _spawn_citizen() -> void: _population._spawn_citizen()

func _prewarm_route_jit() -> void: _prewarm._prewarm_route_jit()

func _await_lanes(pending: Array[int]) -> bool: return await _prewarm._await_lanes(pending)

func _prewarm_lane(steps: Array, pending: Array[int], curtain: CanvasLayer) -> void: await _prewarm._prewarm_lane(steps, pending, curtain)

func _draw_prewarm_step(step: String, curtain: CanvasLayer) -> void: await _prewarm._draw_prewarm_step(step, curtain)

func _prewarm_mark(label: String, began: int) -> int: return _prewarm._prewarm_mark(label, began)

func _trace_cost(label: String, began: int) -> void:
	if began == 0: return
	SESSION_OPS.completed(self, "world", label, began, {"region":state.region_id})
	if not world.get_meta("benchmark_trace",false): return
	var elapsed := Time.get_ticks_usec()-began
	if elapsed < 2000: return
	var costs: Array = world.get_meta("perf_costs",[])
	if costs.size()<512: costs.append({"label":label,"start_usec":began,"duration_usec":elapsed})
	world.set_meta("perf_costs",costs)

func _create_citizen() -> void: _population._create_citizen()

func _clip_citizen_route(point: Vector3, start: Vector3, finish: Vector3) -> PackedVector3Array: return _population._clip_citizen_route(point, start, finish)

func _create_desert_citizen() -> void: _population._create_desert_citizen()

func desert_social_route_clear(route: PackedVector3Array) -> bool: return _population.desert_social_route_clear(route)

func _pedestrian_route_sweep_clear(route: PackedVector3Array) -> bool: return _population._pedestrian_route_sweep_clear(route)

func _spawn_vehicle() -> void: _traffic._spawn_vehicle()

func _create_traffic_vehicle() -> void: _traffic._create_traffic_vehicle()

## `destination_override` leva a um ponto exato (ex.: saída do forte no esqui) em vez
## do ponto de partida padrão da região.
func travel(region_id: String,destination_override := Vector3.INF) -> bool:
	if session != null and session.desert != null and session.desert.busy(): return false
	if region_id == "desert" and not preload("res://world/north_gateway/NorthGatewayPolicy.gd").campaign_completed(state.campaign.snapshot()): return false
	if travel_busy or not session.ready_for_play or session.is_transition_blocked(): return false
	if region_id not in ["harbor","mountain","desert"] or region_id == state.region_id or world.driving.occupied or not state.place_id.is_empty(): return false
	if session.passenger_transport.riding or world.gameplay.health <= 0: return false
	travel_busy = true
	_travel_checked(region_id,destination_override)
	return true # Pedido admitido; a conclusão é dona do save depois da admissão física.

func _travel_checked(region_id: String,destination_override := Vector3.INF) -> void:
	var was_paused := get_tree().paused
	var was_locked: bool = world.player.input_locked
	session.ready_for_play = false
	world.player.input_locked = true
	get_tree().paused = true
	var was_resident := regions.has(region_id) and is_instance_valid(regions[region_id])
	var next_region: Node3D = _mount_region(region_id,destination_override)
	var destination: Vector3 = (destination_override if destination_override.is_finite() else next_region.spawn_position)+Vector3.UP*.12
	# A viagem rápida pausa o streaming normal; termina a célula de destino sob a transição.
	next_region.set_focus(destination,true)
	prepare_connection_at(destination)
	# Mantém a região de origem intacta até o destino ter sincronizado a colisão.
	for i in 3: await get_tree().physics_frame
	if not session.position_clear(destination):
		if not was_resident: _unmount_region(region_id)
		travel_busy = false
		session.ready_for_play = true
		world.player.input_locked = was_locked
		get_tree().paused = was_paused
		session.show_message("Destino ocupado ou sem solo. Viagem não realizada.")
		return
	# Quem para na viagem fica no registro da sessão (FullSession.CANCEL_STEPS, etapa "travel").
	session.cancel_for(&"travel")
	world.gameplay.on_region_changed()
	world.gameplay.emergency.reset_region()
	# A viagem rápida descarrega a população. Travessias lógicas de costura cidade/montanha
	# não chamam isto, então uma reação ativa sobrevive a uma troca comum de region_id.
	if is_instance_valid(civilian_reactions): civilian_reactions.reset_population()
	if is_instance_valid(roadside_parking): roadside_parking.reset()
	for citizen in world.people:
		if is_instance_valid(citizen): citizen.queue_free()
	world.people.clear()
	for vehicle in vehicles:
		if not is_instance_valid(vehicle): continue
		if vehicle == world.driving.car or vehicle.vehicle_id in ["neco_tow_truck","story_tow_vehicle"] or vehicle.get_meta("residence_vehicle",false) or vehicle.get_meta("garage_reward",false):
			if not vehicle.has_meta("region_id"): vehicle.set_meta("region_id",state.region_id)
			vehicle.set_physics_process(false)
			vehicle.hide()
		else: vehicle.queue_free()
	vehicles = vehicles.filter(func(vehicle): return is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion())
	state.world_state.erase("pedestrian")
	world.player.teleport(destination)
	_commit_logical_region(region_id)
	region.set_focus(destination if destination_override.is_finite() else region.spawn_position)
	_update_physical_residency(destination)
	for vehicle in vehicles:
		vehicle.visible = vehicle.get_meta("region_id","") == region_id and not vehicle.has_meta("tow_pending")
		if vehicle.visible and vehicle.collision_layer != 0: vehicle.set_meta("awaiting_ground",true)
	world.camera.initialized = false
	session.garage_rewards.on_location_changed()
	session.sync_dispatch_location()
	if is_instance_valid(urban_transit): urban_transit.on_region_changed()
	travel_busy = false
	session.ready_for_play = true
	world.player.input_locked = was_locked
	get_tree().paused = was_paused
	session.save_game()

func _request_remaining_fleet_scenes(already: Array[String]) -> void: await _prewarm._request_remaining_fleet_scenes(already)
