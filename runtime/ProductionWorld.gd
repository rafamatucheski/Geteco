extends Node
const SESSION_OPS := preload("res://runtime/SessionOperations.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const HEAVY_FRAME := preload("res://runtime/HeavyFrameClaim.gd")
const GPU_RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const ACTOR := preload("res://scripts/Actor.gd")
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
const DENSITY_PER_UNIT := 0.07
const DENSITY_MIN := 0.4
const DENSITY_STARS := 4
const DENSITY_STARS_SCALE := 0.6
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

## Prepara o jogo residente e os dados de rota sob a cortina. Mundos nativos
## distantes não montam mais geometria descartável; o I/O de recurso entra na fila depois de jogável.
func _prewarm_regions(curtain: CanvasLayer = null) -> void:
	var incremental := true
	var phase_traced := Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	if curtain != null:
		curtain.set_stage(.36, "Carregando veículos…")
		await get_tree().process_frame
	PIPELINE_PROBE.stage("world_build")
	await _hold_fleet_scenes_incremental()
	_trace_cost("startup:fleet_hold",phase_traced)
	PIPELINE_PROBE.stage("fleet_hold")
	if "--no-prewarm" in OS.get_cmdline_user_args() or world.get_meta("skip_prewarm",false): return
	var began := Time.get_ticks_msec()
	# Caixa e cilindros unitários lidos da GPU uma vez, sob a cortina: daí em diante toda fusão de
	# G.box/G.cylinder escala na CPU (MeshArrayCache, GETECO_PRIMITIVE_CPU_ARRAYS).
	preload("res://world/chunk_bake/MeshArrayCache.gd").prewarm_unit_shapes()
	# Recursos da preparação em segundo plano (quase todos shaders) pedidos já, em thread, junto com o
	# resto da carga; recolhidos antes de a cortina sair (BackgroundRegionPreparation.prefetch_collect).
	preload("res://runtime/BackgroundRegionPreparation.gd").prefetch_start()

	if curtain != null:
		curtain.set_stage(.40, "Compilando shaders do tráfego…")
		await get_tree().process_frame
	phase_traced = Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	await _prewarm_fleet_shaders(incremental, curtain)
	_trace_cost("startup:fleet_shaders",phase_traced)
	# Pintura suja/molhada/gasta × formatos reais de carro e porta, escondida: compila nos trabalhadores
	# do motor durante o resto da carga (VehicleMaterialVariantPrewarm.start_hidden; sai antes da cortina).
	preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd").start_hidden(world)
	phase_traced = Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	PIPELINE_PROBE.stage("fleet_shaders")
	var stage_traced := phase_traced
	# As texturas carbonizadas existentes custam ~4.5 ms no primeiro uso. Monta o
	# cache compartilhado delas sob a cortina de carregamento, sem criar fogos nem destroços.
	preload("res://gameplay/vehicle_effects/VehicleDamage.gd")._char(false)
	# O primeiro tiro que muda o desgaste também precisa destes recursos.
	preload("res://gameplay/vehicle_effects/VehicleDamage.gd")._scratches(0)
	preload("res://gameplay/vehicle_effects/VehicleDamage.gd")._dents()
	preload("res://gameplay/vehicle_effects/VehicleTireEffects.gd").prewarm_skid_audio()
	# Variante de shader das marcas de pneu (alfa, sem luz, cor de vértice): compilada sob a cortina e
	# mantida viva pelo material estático, em vez de na primeira derrapagem (163-290 ms no release).
	var mark_primer := MeshInstance3D.new()
	mark_primer.name = "TireMarkPrimer"
	mark_primer.mesh = QuadMesh.new()
	mark_primer.material_override = preload("res://gameplay/vehicle_effects/VehicleTireEffects.gd").mark_material()
	mark_primer.position = Vector3(0, -500, 0)
	world.add_child(mark_primer)
	await get_tree().process_frame
	if is_instance_valid(mark_primer): mark_primer.queue_free()
	if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return
	stage_traced = _prewarm_mark("damage_marks", stage_traced)
	# Os takes de explosão e a apresentação imutável de fogo eram montados na detonação.
	# Mantém esses recursos limitados prontos, sem criar um incidente vivo.
	if curtain != null:
		curtain.set_stage(.44,"Carregando áudio…")
		await get_tree().process_frame
	# Capô aberto do Gol da oficina do Digo, sem ler a GPU quando a oficina entra no streaming do deserto.
	preload("res://world/desert/drag_meet/DesertDigoWorkshop.gd").prewarm_hoods()
	# Fonte e nomes do quadro da arrancada (etapa 15 do chão do deserto: 54 ms no estresse de 21/10).
	preload("res://activities/desert_drag/DesertDragBoardProp.gd").prewarm()
	# Antes das filas: a preparação do deserto (fila resident_regions) monta a oficina com estes prontos.
	stage_traced = _prewarm_mark("desert_props", stage_traced)
	# Filas da carga (27/10): áudio, modelos das armas e a preparação das regiões residentes esperavam quadros
	# em série (`combat_resources` ~5 s e `resident_prewarm` ~4,9 s a quente, §7.4), enquanto as filas de
	# desenho passam a maior parte do tempo esperando a GPU com o thread principal parado. Agora correm como
	# filas junto com elas. GETECO_LOAD_LANES=0 volta à série. Só com GETECO_PREWARM_PARALLEL ligado.
	_prewarm_incremental = incremental
	var load_lanes := OS.get_environment("GETECO_LOAD_LANES") != "0" and OS.get_environment("GETECO_PREWARM_PARALLEL") != "0"
	if not load_lanes:
		await _prewarm_audio_banks()
		stage_traced = _prewarm_mark("audio", stage_traced)
	# Pré-aquecimentos de desenho (22/10, 3ª rodada): em série, com o cache frio, cada um esperava sozinho as
	# próprias compilações (combat_resources 31 s no frio, 5 s a quente; a sonda viu 2-8 s por etapa com 3-70
	# pipelines cada). Juntos, todos põem as peças diante da câmera nos mesmos quadros e as compilações correm ao
	# mesmo tempo nos trabalhadores do motor. A Cobra/polícia do tiroteio continua depois dos corpos do Meshy
	# (usa os GLBs já carregados). LIGADO por padrão desde 24/10 (=0 volta à série): na 3ª rodada não houve
	# medição limpa; na 5ª (PC livre, sem Godot externo) o frio ficou 3–5 s mais curto nas 8 rodadas de
	# oeste, serra e deserto e a quente ficou igual em 6 rotas (docs/perf-playthrough-20261021.md §10).
	if OS.get_environment("GETECO_PREWARM_PARALLEL") != "0":
		var lanes: Array = [["local_light_shadow"], ["fire"], ["police_visual"], ["vehicle_variants"], ["bridge_look"],
			["desert_ground_cover"], ["family_variants"], ["painted_facades"], ["wildlife"], ["forge"], ["skate"],
			["meshy_bodies", "spawn_visuals"]]
		if not preload("res://runtime/RainPrewarm.gd").late: lanes.append(["rain"])
		if load_lanes: lanes.append_array([["audio_banks"], ["weapon_templates"], ["resident_regions"]])
		var pending: Array[int] = [lanes.size()]
		for lane in lanes: _prewarm_lane(lane, pending, curtain)
		if not await _await_lanes(pending): return
		stage_traced = _prewarm_mark("parallel_draws", stage_traced)
	else:
		var serial: Array[String] = ["fire", "rain", "police_visual", "vehicle_variants", "bridge_look", "local_light_shadow",
			"desert_ground_cover", "family_variants", "painted_facades", "wildlife", "forge", "skate", "meshy_bodies", "spawn_visuals"]
		if preload("res://runtime/RainPrewarm.gd").late: serial.erase("rain")
		for step in serial:
			await _draw_prewarm_step(step, curtain)
			if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return
			stage_traced = _prewarm_mark(step, stage_traced)
	if not load_lanes:
		await _prewarm_weapon_templates()
		if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return
	stage_traced = _prewarm_mark("weapon_templates", stage_traced)
	_trace_cost("startup:combat_resources",phase_traced)
	# Um quadro entre as etapas pesadas deixa a tela de carregamento andar; o mundo
	# já está montado e o 'ready_for_play' ainda é falso nesse trecho.
	if curtain != null:
		curtain.set_stage(.46, "Preparando texturas e prédios…")
		await get_tree().process_frame
	phase_traced = Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	if not load_lanes: await _prewarm_resident_regions()
	if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return
	_trace_cost("startup:resident_prewarm",phase_traced)
	PIPELINE_PROBE.stage("resident_prewarm")
	background_preparation = preload("res://runtime/BackgroundRegionPreparation.gd").new()
	background_preparation.controller = self
	add_child(background_preparation)
	background_preparation.set_process(false)
	if not _eager_preparation_for_benchmark(): background_preparation.enqueue(state.region_id)
	for id in ["harbor","mountain","desert"]:
		if regions.has(id): continue
		if curtain != null:
			curtain.set_stage(.6 if id == "mountain" else .66, "Preparando " + ("a serra" if id == "mountain" else "o deserto" if id == "desert" else "o porto") + "…")
			await get_tree().process_frame
		var detached: Node3D = _build_region(id)
		if detached == null: continue
		if not await _prepare_geography(detached): return
		# Aquecer dados/conteudo sem montar uma vizinhanca do spawn que sera descartada.
		detached.initial_prewarm_only = true
		phase_traced = Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
		world.add_child(detached)
		_trace_cost("startup:distant_prepare:"+id,phase_traced)
		phase_traced = Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
		# O pré-aquecimento do deserto prepara só dados compartilhados de terreno/material. Os mundos
		# nativos montavam/descartavam todas as células aqui. Esses montadores procedurais
		# continuam no streaming por proximidade, nunca na fila de recursos em segundo plano.
		if id == "desert" or _eager_preparation_for_benchmark():
			if incremental: await detached.prewarm_incremental()
			else: detached.prewarm()
		else:
			await preload("res://runtime/RetainedRegionPreparation.gd").run(detached)
		_trace_cost("startup:distant_prewarm:"+id,phase_traced)
		PIPELINE_PROBE.stage("distant_prewarm:" + id)
		detached.initial_prewarm_only = false
		detached.release_chunks()
		world.remove_child(detached)
		_region_cache[id] = detached
		if not _eager_preparation_for_benchmark(): background_preparation.enqueue(id)
	# Grafos de rota das três combinações residentes, sob a cortina.
	if curtain != null:
		curtain.set_stage(.76, "Traçando rotas do trânsito…")
		await get_tree().process_frame
	var live := regions.duplicate()
	var all := live.duplicate()
	for id in _region_cache: all[id] = _region_cache[id]
	phase_traced = Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	# Serra + deserto (carro deixado na serra, jogador no deserto) faltava: a desmontagem do porto caía nela
	# e refazia o grafo no jogo (routes.configure 40 ms, estresse do deserto de 22/10).
	# GETECO_ROUTE_COMBO_MD=0 volta à lista antiga (A/B).
	var combos: Array = [["harbor"],["mountain"],["desert"],["harbor","mountain"],["harbor","desert"],["mountain","desert"],["harbor","mountain","desert"]]
	if OS.get_environment("GETECO_ROUTE_COMBO_MD") == "0": combos.erase(["mountain","desert"])
	for combo in combos:
		regions = {}
		for id in combo:
			if all.has(id): regions[id] = all[id]
		if regions.size() == combo.size(): _configure_routes()
		if incremental: await get_tree().process_frame
	regions = live
	_configure_routes()
	population_layout.configure(ambient_roads_cache)
	_trace_cost("startup:route_graphs",phase_traced)
	PIPELINE_PROBE.stage("route_graphs")
	print("Pré-aquecimento das regiões: ", Time.get_ticks_msec()-began, " ms")

var _prewarm_incremental := false

func _prewarm_audio_banks() -> void:
	var combat_audio = preload("res://gameplay/CombatAudio.gd")
	await combat_audio.prewarm_reload_banks(get_tree())
	await combat_audio.prewarm_gameplay_banks(get_tree())
	await preload("res://audio/VehicleCrashAudio.gd").prewarm(get_tree())

## Modelos das armas na mão, prontos antes da primeira troca (Gameplay._weapon_template).
func _prewarm_weapon_templates() -> void:
	if OS.get_environment("GETECO_WEAPON_TEMPLATE") == "0": return
	await preload("res://gameplay/ArsenalWeapon3D.gd").warm_templates(get_tree(), preload("res://gameplay/WeaponCatalog.gd").WEAPONS.keys())

func _prewarm_resident_regions() -> void:
	if is_instance_valid(region) and (state.region_id == "desert" or _eager_preparation_for_benchmark()):
		if _prewarm_incremental: await region.prewarm_incremental()
		else: region.prewarm()
	elif is_instance_valid(region):
		await preload("res://runtime/RetainedRegionPreparation.gd").run(region)
	# Vizinhas já montadas (começar na serra monta o porto junto) não passam pelo laço das distantes
	# abaixo: sem isto o porto nunca era preparado e a carga do navio, os prédios e o túnel pesavam
	# ao vivo (release de 2026-10-13, começo na serra).
	for neighbour_id in regions.keys():
		var neighbour: Variant = regions[neighbour_id]
		if neighbour == region or not is_instance_valid(neighbour) or neighbour_id == "desert" or _eager_preparation_for_benchmark(): continue
		await preload("res://runtime/RetainedRegionPreparation.gd").run(neighbour)
		if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return

func _apply_player_settings() -> void:
	if is_instance_valid(environment): V2Settings.apply_environment(environment.environment)
	if is_instance_valid(sun) and sun_shadow_near_enabled:
		sun.directional_shadow_max_distance = V2Settings.shadow_distance_metres()

func _eager_preparation_for_benchmark() -> bool:
	return OS.is_debug_build() and world.get_meta("background_loading_baseline",false)

func _hold_fleet_scenes() -> void:
	if not _fleet_scenes.is_empty(): return
	preload("res://gameplay/icecream/IceCreamVan.gd").prewarm()
	# Trânsito e as viaturas do despacho (DispatchRules.ARCHETYPES): nascem e somem igual.
	for id in TRAFFIC_CAR_TYPES+TRAFFIC_MOTORCYCLE_TYPES+["police_cruiser","medic_box","rescue_pumper","station_wagon"]:
		var definition: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(id)
		if definition.has("scene"):
			var scene := load(definition.scene)
			if scene != null: _fleet_scenes.append(scene)

## Preenche os planos de fusão por modelo existentes antes do primeiro despacho.
## O aquecimento de shader de PackedScene cru não roda os decoradores do FleetCatalog.
func _prewarm_dispatch_models() -> void:
	var fleet := preload("res://runtime/FleetCatalog.gd")
	var rules := preload("res://gameplay/dispatch/DispatchRules.gd")
	var traced := Time.get_ticks_usec() if is_instance_valid(world) and (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	for id in rules.ARCHETYPES.values():
		var model_traced := Time.get_ticks_usec() if traced else 0
		var model: Node3D = fleet.create(str(id))
		if model != null:
			# Materiais que a porta recortada leva para formatos de vértice novos (FormatPrewarm, desenhados
			# junto com as variantes de pintura). GETECO_FORMAT_PREWARM=0 desliga.
			if preload("res://runtime/FormatPrewarm.gd").enabled():
				var door_materials: Array[Material] = preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd").door_materials
				# A viatura do jogo usa o casco de peças soltas (VehiclePanelCatalog): a porta sai dele.
				var sources: Array[Node3D] = [model]
				var panels := preload("res://gameplay/vehicle_effects/VehiclePanelCatalog.gd")
				if panels.supports(str(id)) and OS.get_environment("GETECO_BREAKAWAY_PREWARM") != "0":
					var panel_model := panels.create(str(id))
					if panel_model != null: sources.append(panel_model)
				for source in sources:
					for part in preload("res://gameplay/VehicleDoorBuilder.gd")._parts(source):
						for surface in part.mesh.get_surface_count():
							var material := part.get_active_material(surface)
							if material != null and not material in door_materials: door_materials.append(material)
				for source in sources:
					if source != model: source.free()
			# Arrays da lataria na cópia da CPU (MeshArrayCache), sob a cortina: o preparo da porta da
			# viatura que chega (VehicleDoorBuilder) não lê mais a malha de volta da GPU no jogo.
			if OS.get_environment("GETECO_DOOR_ARRAY_CACHE") != "0":
				for part in preload("res://gameplay/VehicleDoorBuilder.gd")._parts(model):
					for surface in part.mesh.get_surface_count():
						preload("res://world/chunk_bake/MeshArrayCache.gd").arrays_of(part.mesh, surface)
				# A primeira batida de cada viatura lia também as arrays em repouso do amassado (mesma
				# regra de VehicleBodyDents._prepare: sem rodas, interior e corpos com esqueleto).
				for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
					var path := str(model.get_path_to(part)).to_lower()
					if part.mesh == null or part.skeleton != NodePath("") or "wheel" in path or "interior" in path or "rider" in path: continue
					preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd")._rest_arrays(part.mesh)
			model.free()
		_trace_cost("prewarm_dispatch_model:"+str(id),model_traced)
		await get_tree().process_frame
	await _collect_traffic_door_materials()
	_trace_cost("startup:dispatch_models",traced)

## Portas dos carros comuns da frota redesenhada (27/10): a folha da porta animada (DriverDoorPresentation)
## leva o material da lataria para o formato da porta e compilava 7 pipelines `surface` num quadro de
## 25–37 ms no oeste e nos sobrados (atlas_crew_pickup, ranch_single, ranch_pickup; sonda de 24–25/10).
## Só as viaturas do despacho entravam em `door_materials`. Um material por assinatura de shader basta:
## o pipeline é por shader × formato, não por instância. GETECO_DOOR_TRAFFIC_PREWARM=0 desliga.
func _collect_traffic_door_materials() -> void:
	if not preload("res://runtime/FormatPrewarm.gd").enabled() or OS.get_environment("GETECO_DOOR_TRAFFIC_PREWARM") == "0": return
	var fleet := preload("res://runtime/FleetCatalog.gd")
	var variants := preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd")
	var door_materials: Array[Material] = variants.door_materials
	var seen := {}
	for material in door_materials: seen[variants.shader_signature(material)] = true
	for id in TRAFFIC_CAR_TYPES:
		if not preload("res://runtime/RedesignedFleet.gd").contains(id): continue
		var began := STALL_WORK.begin()
		var model: Node3D = fleet.create(id)
		if model == null: continue
		for part in preload("res://gameplay/VehicleDoorBuilder.gd")._parts(model):
			for surface in part.mesh.get_surface_count():
				var material := part.get_active_material(surface)
				if material == null: continue
				var signature: String = variants.shader_signature(material)
				if seen.has(signature): continue
				seen[signature] = true
				door_materials.append(material)
		model.free()
		STALL_WORK.finish_slow("startup.traffic_door_materials", began, 4000)
		await get_tree().process_frame

func _prewarm_fleet_shaders(_incremental: bool, curtain: CanvasLayer = null) -> void:
	await _prewarm_dispatch_models()
	var fleet := preload("res://runtime/FleetCatalog.gd")
	var effects := preload("res://gameplay/emergency/EffectsPrewarm.gd")
	# Aquece os modelos de produção decorados e também as cenas-fonte retidas.
	# Uma câmera reserva, não atual, na origem nunca exercitava as passadas de GPU deles.
	# Sob a cortina (runtime/LoadingTurbo.gd) vão 4 modelos por vez, numa grade 2x2 bem dentro do
	# quadro (10 e 13 m à frente, ±2,2 m de lado): as mesmas duas passagens de desenho para cada um,
	# um quarto dos quadros. Era 2,9 s de "Compilando shaders do tráfego" no release de 21/10, um
	# modelo por vez. GETECO_LOADING_TURBO=0 volta a um por vez.
	var batch_size := 4 if preload("res://runtime/LoadingTurbo.gd").active() else 1
	var ids: Array = fleet.all().keys()
	# Cupê, Monaliza, Metro e viatura rodam no jogo com o casco de peças soltas (VehiclePanelCatalog,
	# Vehicle._ready): outra cena, outros materiais de pintura. Sem eles aqui, a pintura suja/molhada desses
	# quatro compilava no jogo (sonda de pipelines, 22/10). GETECO_BREAKAWAY_PREWARM=0 desliga.
	if OS.get_environment("GETECO_BREAKAWAY_PREWARM") != "0":
		for panel_id in preload("res://gameplay/vehicle_effects/VehiclePanelCatalog.gd").IDS: ids.append("breakaway:" + str(panel_id))
	if await _compile_fleet_hidden(ids, curtain):
		print("startup: dents_rest_prewarm vertices=", preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd").fleet_rest_vertices)
		return
	var next := 0
	while next < ids.size():
		var batch: Array[Dictionary] = []
		while batch.size() < batch_size and next < ids.size():
			var id := str(ids[next])
			next += 1
			var created: Node3D = null
			if id.begins_with("breakaway:"):
				id = id.trim_prefix("breakaway:")
				created = preload("res://gameplay/vehicle_effects/VehiclePanelCatalog.gd").create(id)
			else: created = fleet.create(id)
			if created != null: batch.append({"id": id, "model": created})
		if batch.is_empty(): continue
		var camera := world.camera as Camera3D
		if DisplayServer.get_name() != "headless" and effects._covered_loading(world, curtain) and effects._current_camera(world, camera):
			for slot in batch.size():
				var model: Node3D = batch[slot].model
				model.process_mode = Node.PROCESS_MODE_DISABLED
				world.add_child(model)
				var row := float(slot / 2)
				var side := 0.0 if batch.size() == 1 else (-2.2 if slot % 2 == 0 else 2.2)
				model.global_position = camera.global_position - camera.global_basis.z * (9.0 + row * 4.0) + camera.global_basis.x * side
			# Lentes apagadas (22/10): VehicleEquipment liga e desliga `emission_enabled` das lentes, outra
			# variante de shader por material de lente; no jogo o equipamento do carro novo compilava duas
			# pipelines no sync do RenderingServer (13–15 ms entre o _process e o desenho, estresse no porto e
			# nos sobrados). Uma cópia de cada modelo com as lentes emissivas apagadas entra no mesmo lote, duas
			# fileiras mais atrás, e passa pelos mesmos dois desenhos; os materiais apagados ficam retidos.
			var dim_copies: Array[Node3D] = []
			if OS.get_environment("GETECO_LENS_VARIANT_PREWARM") != "0":
				for slot in batch.size():
					var copy := (batch[slot].model as Node3D).duplicate(0) as Node3D
					if copy == null: continue
					if _dim_emissive_lenses(copy) == 0:
						copy.free()
						continue
					copy.process_mode = Node.PROCESS_MODE_DISABLED
					world.add_child(copy)
					var row := float(slot / 2) + 2.0
					var side := 0.0 if batch.size() == 1 else (-2.2 if slot % 2 == 0 else 2.2)
					copy.global_position = camera.global_position - camera.global_basis.z * (9.0 + row * 4.0) + camera.global_basis.x * side
					dim_copies.append(copy)
			# Dois desenhos reais, com espera finita quando a janela está minimizada.
			var draws: Array[int] = [0]
			var count_draw := func() -> void: draws[0] += 1
			RenderingServer.frame_post_draw.connect(count_draw)
			for frame in 12:
				await get_tree().process_frame
				if not effects._covered_loading(world, curtain): break
				if draws[0] >= 2: break
			RenderingServer.frame_post_draw.disconnect(count_draw)
			for copy in dim_copies:
				if is_instance_valid(copy): copy.free()
		for entry in batch:
			var model: Node3D = entry.model
			# Bases de pintura para as variantes de uso/desgaste (desenhadas depois).
			preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd").collect(model, str(entry.id))
			# Vidros na CPU para medir a cabine em jogo sem ler a malha da GPU (VehicleInterior.spec).
			preload("res://gameplay/VehicleInterior.gd").cache_glass(model)
			# Lataria em repouso de cada modelo para o 1º amassado (VehicleBodyDents.prewarm_rest).
			preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd").prewarm_rest(model)
			model.free()
		await get_tree().process_frame
	print("startup: dents_rest_prewarm vertices=", preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd").fleet_rest_vertices)

## A frota inteira (e as cópias de lentes apagadas) escondida de uma vez antes dos lotes desenhados
## (22/10, 3ª rodada): com o cache frio cada lote de 4 compilava seus shaders na thread principal, um depois
## do outro (fleet_shaders 7,2 s frio × 2,3 s quente). Escondidas, as pipelines compilam em paralelo nos
## trabalhadores (runtime/HiddenCompile.gd). Com GETECO_FLEET_HIDDEN_ONLY (padrão) os lotes desenhados diante
## da câmera nem acontecem: a pipeline que trava (a "ubershader" da superfície) já ficou pronta escondida, e a
## especialização de cada carro é feita em segundo plano no jogo, sem quadro esperando. Devolve true quando
## fez tudo o que os lotes faziam (bases de pintura, vidros, lataria em repouso). Só com GETECO_HIDDEN_COMPILE=1.
func _compile_fleet_hidden(ids: Array, curtain: CanvasLayer) -> bool:
	if not preload("res://runtime/HiddenCompile.gd").enabled() or DisplayServer.get_name() == "headless": return false
	if not preload("res://gameplay/emergency/EffectsPrewarm.gd")._covered_loading(world, curtain): return false
	var hidden_only := OS.get_environment("GETECO_FLEET_HIDDEN_ONLY") != "0"
	var primaries: Array[Dictionary] = []
	var holder := Node3D.new()
	holder.name = "FleetHiddenCompile"
	holder.visible = false
	world.add_child(holder)
	var lens_dim := OS.get_environment("GETECO_LENS_VARIANT_PREWARM") != "0"
	var fade_copies := OS.get_environment("GETECO_WRECK_FADE_PREWARM") == "1"
	for raw_id in ids:
		var id := str(raw_id)
		var model: Node3D = null
		if id.begins_with("breakaway:"): model = preload("res://gameplay/vehicle_effects/VehiclePanelCatalog.gd").create(id.trim_prefix("breakaway:"))
		else: model = preload("res://runtime/FleetCatalog.gd").create(id)
		if model == null: continue
		model.process_mode = Node.PROCESS_MODE_DISABLED
		holder.add_child(model)
		primaries.append({"id": id.trim_prefix("breakaway:"), "model": model})
		if lens_dim:
			var copy := model.duplicate(0) as Node3D
			if copy != null:
				if _dim_emissive_lenses(copy) == 0: copy.free()
				else:
					copy.process_mode = Node.PROCESS_MODE_DISABLED
					holder.add_child(copy)
		# Carcaça sumindo (Vehicle._tick_wreck põe `transparency` em todas as malhas): os materiais do carro
		# no passe alfa. No estresse com cache frio o 1º sumiço compilou 5 pipelines `draw` num quadro de
		# 3,0 s (export D, 22/10). Desligado por padrão (GETECO_WRECK_FADE_PREWARM=1): ganho não medido limpo.
		if fade_copies:
			var faded := model.duplicate(0) as Node3D
			if faded != null:
				for found in faded.find_children("*", "GeometryInstance3D", true, false): (found as GeometryInstance3D).transparency = .5
				faded.process_mode = Node.PROCESS_MODE_DISABLED
				holder.add_child(faded)
	# Insígnia dos carros da Cobra (CobraAppearance.livery/race_livery), posta no carro ao nascer.
	holder.add_child(preload("res://gameplay/urban_v1/CobraAppearance.gd").insignia(1.0))
	await preload("res://runtime/HiddenCompile.gd").settle(get_tree())
	if hidden_only:
		for entry in primaries:
			var model: Node3D = entry.model
			if not is_instance_valid(model): continue
			# O mesmo que os lotes desenhados fazem com cada modelo antes de liberá-lo.
			preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd").collect(model, str(entry.id))
			preload("res://gameplay/VehicleInterior.gd").cache_glass(model)
			preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd").prewarm_rest(model)
	if is_instance_valid(holder): holder.free()
	return hidden_only

## Cópia apagada (sem emissão) de cada material emissivo do modelo, retida por chave de variante.
static var _retained_lens_variants: Dictionary = {}
func _dim_emissive_lenses(model: Node3D) -> int:
	var count := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null: continue
		var surfaces: int = 1 if part.material_override != null else part.mesh.get_surface_count()
		for surface in surfaces:
			var original := part.get_active_material(surface) as StandardMaterial3D
			if original == null or not original.emission_enabled: continue
			var dark := original.duplicate() as StandardMaterial3D
			dark.emission_enabled = false
			dark.emission_energy_multiplier = 0.0
			if part.material_override != null: part.material_override = dark
			else: part.set_surface_override_material(surface, dark)
			var key := str(original.get_instance_id())
			if not _retained_lens_variants.has(key): _retained_lens_variants[key] = dark
			count += 1
	return count

func _hold_fleet_scenes_incremental() -> void:
	if not _fleet_scenes.is_empty(): return
	# Só _hold_fleet_scenes (sem chamadores) pré-aquecia o carro de sorvete: a primeira van no
	# trânsito montava palhaços (26 ms), pintura do teto (11 ms) e teto (3 ms) num quadro
	# (serra, EXE perfinv6 de 17/10); a segunda custava 0,3 ms.
	preload("res://gameplay/icecream/IceCreamVan.gd").prewarm()
	preload("res://runtime/VehicleUsage.gd").prewarm()
	# A 1ª morte fazia load() síncrono da biblioteca Mixamo (auditoria de 19/10, §5).
	preload("res://gameplay/MixamoDeath.gd").prewarm()
	# Mesma regra para o levantar do chão (atropelado, tirado do carro): nada de load() no 1º tombo.
	preload("res://gameplay/street_physics/BodyGetUp3D.gd").prewarm()
	var ids: Array = TRAFFIC_CAR_TYPES + TRAFFIC_MOTORCYCLE_TYPES + ["police_cruiser", "medic_box", "rescue_pumper", "station_wagon"]
	ids.append(str(starting_vehicle().get("archetype", "sport_coupe")))
	for record in state.world_state.get("garage_rewards", {}).get("vehicles", {}).values():
		ids.append(str(record.get("archetype", "")))
	var paths: Array[String] = []
	for id in ids:
		var definition: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(id)
		var path := str(definition.get("scene", ""))
		if path.is_empty() or path in paths: continue
		paths.append(path)
	await _retain_fleet_paths(paths, _fleet_scenes)
	await _request_remaining_fleet_scenes(paths)

## Cenas da frota pedidas em thread logo no começo da carga (22/10): "Carregando veículos…" esperava
## 2 cenas por vez, com um quadro entre os pares (2,0 s no oeste a 3440x1440), depois de "Montando o
## porto" (5,7 s de trabalho no thread principal). Pedidas no início, a leitura e a montagem dos recursos
## correm nos trabalhadores durante a montagem do porto; a etapa só recolhe. GETECO_FLEET_EARLY=0 desliga.
var _early_fleet_paths: Dictionary = {}
func _request_fleet_scenes_early() -> void:
	if OS.get_environment("GETECO_FLEET_EARLY") == "0" or DisplayServer.get_name() == "headless": return
	var fleet := preload("res://runtime/FleetCatalog.gd")
	for id in fleet.all().keys():
		var path := str(fleet.spec(str(id)).get("scene", ""))
		if path.is_empty() or _early_fleet_paths.has(path) or ResourceLoader.has_cached(path): continue
		if ResourceLoader.load_threaded_request(path) == OK: _early_fleet_paths[path] = true

func _retain_fleet_paths(paths: Array[String], retained: Array[Resource]) -> void:
	# O renderizador dummy headless não consegue alocar esses RIDs de malha em paralelo.
	# Ele ainda carrega/retém os recursos reais, em sequência, para os testes de contrato.
	if DisplayServer.get_name() == "headless":
		for path in paths:
			var resource := load(path)
			if resource != null: retained.append(resource)
			await get_tree().process_frame
		return
	# Limita a pressão de alocação/envio de recursos em vez de inundar o pool de
	# workers com todos os veículos de uma vez. Mantém um quadro entre pedidos concluídos.
	var requested: Array[String] = []
	for path in paths:
		requested.append(path)
		if requested.size() < 2 and path != paths.back(): continue
		var early_pair := true
		for pending_path in requested:
			# Já pedida no começo (_request_fleet_scenes_early): só recolhe, sem segundo pedido.
			if _early_fleet_paths.has(pending_path): continue
			early_pair = false
			ResourceLoader.load_threaded_request(pending_path)
		for pending_path in requested:
			while ResourceLoader.load_threaded_get_status(pending_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await get_tree().process_frame
			if ResourceLoader.load_threaded_get_status(pending_path) == ResourceLoader.THREAD_LOAD_LOADED:
				retained.append(ResourceLoader.load_threaded_get(pending_path))
			_early_fleet_paths.erase(pending_path)
		requested.clear()
		# Pedidas no começo já carregaram com o porto: sem o quadro de folga entre pares.
		if early_pair: continue
		await get_tree().process_frame

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

func _resident_roads() -> Array:
	var result: Array = []
	for id in ["harbor","mountain","desert"]:
		if not regions.has(id) or not is_instance_valid(regions[id]): continue
		for road in regions[id].roads:
			if road.get("traffic",true): result.append(road)
	if regions.has("harbor") and regions.has("mountain"):
		result.append_array(WORLD_CONNECTION.traffic_connectors())
	# Túnel do canal: rua virtual só no grafo, com a altura do piso (ver CanalTunnel3D).
	if regions.has("harbor") and is_instance_valid(regions.harbor):
		result.append_array(preload("res://world/urban_detail/CanalTunnel3D.gd").traffic_roads(regions.harbor.roads))
	return result

## Grafos de rota por conjunto de regiões residentes. configure() cruza todos os
## trechos entre si (~55 + 65 ms com Harbor e Mountain); na costura isso se repetia a
## cada montagem/desmontagem de Mountain. Cópias rasas: configure() esvazia no lugar.
var _route_cache: Dictionary = {}

func _route_key() -> String:
	var ids: Array = []
	for id in ["harbor","mountain","desert"]:
		if regions.has(id) and is_instance_valid(regions[id]): ids.append(id)
	return ",".join(ids)

static func _graph_snapshot(graph) -> Array:
	return [graph.segments.duplicate(),graph.vertices.duplicate(),graph.edges.duplicate(),graph._vertex_ids.duplicate()]

static func _graph_restore(graph, snapshot: Array) -> void:
	graph.segments = snapshot[0].duplicate()
	graph.vertices = snapshot[1].duplicate()
	graph.edges = snapshot[2].duplicate()
	graph._vertex_ids = snapshot[3].duplicate()

func _configure_routes() -> void:
	_carriageway_grid = {}
	var key := _route_key()
	var cached: Dictionary = _route_cache.get(key,{})
	if not cached.is_empty():
		_graph_restore(traffic_routes,cached.traffic)
		_graph_restore(ambient_traffic_routes,cached.ambient)
		ambient_roads_cache = cached.ambient_roads.duplicate()
		return
	var roads := _resident_roads()
	traffic_routes.configure(roads)
	ambient_roads_cache = PORT_POLICY.ambient_roads(roads)
	ambient_traffic_routes.configure(ambient_roads_cache)
	_route_cache[key] = {"traffic":_graph_snapshot(traffic_routes),"ambient":_graph_snapshot(ambient_traffic_routes),"ambient_roads":ambient_roads_cache.duplicate()}

func _refresh_route_consumers() -> void:
	if traffic_routes == null: return
	var traced := Time.get_ticks_usec() if is_instance_valid(world) and (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	# Spans por etapa (22/10): a desmontagem do porto custava 46 ms no deserto e só 6 eram remove_child.
	var stage := STALL_WORK.begin()
	_configure_routes()
	STALL_WORK.finish_slow("routes.configure", stage, 2000)
	stage = STALL_WORK.begin()
	population_layout.configure(ambient_roads_cache)
	STALL_WORK.finish_slow("routes.population_layout", stage, 2000)
	var layouts: Array = []
	if regions.has("harbor") and regions.harbor.harbor_road_geometry != null:
		layouts = regions.harbor.harbor_road_geometry.crossing_layout
	stage = STALL_WORK.begin()
	preload("res://gameplay/traffic_junctions/TrafficJunctions.gd").configure(ambient_traffic_routes,layouts)
	STALL_WORK.finish_slow("routes.junctions", stage, 2000)
	_trace_cost("route_graphs",traced)
	stage = STALL_WORK.begin()
	if is_instance_valid(world) and is_instance_valid(world.dispatch): world.dispatch.refresh_roads()
	STALL_WORK.finish_slow("routes.dispatch", stage, 2000)
	stage = STALL_WORK.begin()
	if is_instance_valid(world) and is_instance_valid(world.traffic_yield): world.traffic_yield.refresh_roads(traffic_routes)
	STALL_WORK.finish_slow("routes.traffic_yield", stage, 2000)

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
		if world.driving.occupied and car == world.driving.car: continue
		car.place(anchor, car.rotation.y)
		car.set_meta("awaiting_ground", true)
		car.set_physics_process(false)
		push_warning("Veículo %s caiu abaixo do mundo; devolvido a %s até o chão carregar." % [car.vehicle_id, anchor])

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
		session._refresh_routine_context()
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
	footbridge_crossers.update(world, world.player.position, state.region_id, _population_cap())
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

## Mantém quatro revisões por segundo distribuídas, com no máximo um oitavo por quadro.
## O cursor permanece no sucessor quando uma remoção desloca os índices.
func _review_pedestrians(delta: float) -> void:
	_pedestrian_review_credit = minf(_pedestrian_review_credit + delta * world.people.size() * 4.0,world.people.size())
	var budget := mini(int(_pedestrian_review_credit),maxi(1,ceili(float(world.people.size()) / 8.0)))
	_pedestrian_review_credit -= budget
	for step in budget:
		if world.people.is_empty():
			_pedestrian_review_cursor = 0
			break
		_pedestrian_review_cursor %= world.people.size()
		var actor = world.people[_pedestrian_review_cursor]
		var retire := not is_instance_valid(actor)
		if not retire:
			var distance: float = actor.global_position.distance_to(world.player.global_position)
			retire = PORT_POLICY.contains_private_area(actor.global_position)
			# Rotinas autoradas e travessias preservam a permanência e a recuperação antigas.
			if actor.has_meta("desert_routine") or actor.has_meta("desert_social_slot") or actor.get_meta("footbridge_crosser",false):
				retire = retire or (distance > POPULATION_DESPAWN and not _on_screen(actor.global_position,1.0))
			elif not retire and distance > VC_PEDESTRIAN_HIDDEN_DISTANCE:
				retire = distance > VC_PEDESTRIAN_VISIBLE_DISTANCE or not _on_screen(actor.global_position,1.0)
		if retire:
			world.people.remove_at(_pedestrian_review_cursor)
			if is_instance_valid(actor): actor.queue_free()
		else:
			_pedestrian_review_cursor += 1

## Diagnóstico explícito da P1: conta a cena real após 30 s, sem amostrar FPS/tempo de quadro.
## Fica no arquivo dono da tarefa para não criar um runner em arquivos de outra sessão.
func _count_p1_population() -> void:
	if not no_save:
		push_error("P1: contagem exige --no-save para preservar o save do usuário.")
		get_tree().quit(1)
		return
	# Headless nasce com viewport 64x64; a câmera precisa do enquadramento de gameplay.
	get_tree().root.size = Vector2i(1280,720)
	await get_tree().create_timer(30.0).timeout
	var people := 0
	var authored_people := 0
	var farthest_visible := 0.0
	var farthest_hidden := 0.0
	var farthest_common_visible := 0.0
	var farthest_common_hidden := 0.0
	var farthest_traffic := 0.0
	var parked := 0
	var persistent := 0
	for actor in world.people:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion(): continue
		people += 1
		var distance: float = actor.global_position.distance_to(world.player.global_position)
		var authored: bool = actor.has_meta("desert_routine") or actor.has_meta("desert_social_slot") or actor.get_meta("footbridge_crosser",false)
		if authored: authored_people += 1
		if _on_screen(actor.global_position,1.0):
			farthest_visible = maxf(farthest_visible,distance)
			if not authored: farthest_common_visible = maxf(farthest_common_visible,distance)
		else:
			farthest_hidden = maxf(farthest_hidden,distance)
			if not authored: farthest_common_hidden = maxf(farthest_common_hidden,distance)
	for car in vehicles:
		if not is_instance_valid(car) or car.is_queued_for_deletion(): continue
		if _is_persistent_vehicle(car): persistent += 1
		elif not car.traffic: parked += 1
		elif _is_ambient_traffic(car) and car.health > 0.0:
			farthest_traffic = maxf(farthest_traffic,car.global_position.distance_to(world.player.global_position))
	var report := {"population_vc":population_vc_enabled,"sun_shadow_near":sun_shadow_near_enabled,
		"region":state.region_id,"focus":str(world.player.global_position),"pedestrians":people,
		"pedestrian_cap":_population_cap(),"ambient_traffic":_ambient_traffic_count(),"traffic_cap":_traffic_cap(),
		"farthest_visible_m":farthest_visible,"farthest_hidden_m":farthest_hidden,"farthest_traffic_m":farthest_traffic,
		"authored_pedestrians":authored_people,"common_farthest_visible_m":farthest_common_visible,
		"common_farthest_hidden_m":farthest_common_hidden,"viewport":str(get_viewport().get_visible_rect().size),
		"parked":parked,"persistent":persistent,"sun_shadow_distance_m":sun.directional_shadow_max_distance,
		"native_dispatch_router":is_instance_valid(world.dispatch) and world.dispatch.router._native != null}
	print("P1_CONTAGEM ",JSON.stringify(report))
	get_tree().quit(0 if not population_vc_enabled or (people <= VC_MAX_POPULATION and _ambient_traffic_count() <= VC_TRAFFIC_TARGET) else 1)

## Alvo da densidade: cada unidade de despacho em cena tira `DENSITY_PER_UNIT`, e de
## `DENSITY_STARS` estrelas para cima o teto não passa de `DENSITY_STARS_SCALE`.
static func density_target(dispatch_units: int, stars: int) -> float:
	var target := clampf(1.0-float(dispatch_units)*DENSITY_PER_UNIT,DENSITY_MIN,1.0)
	if stars >= DENSITY_STARS: target = minf(target,DENSITY_STARS_SCALE)
	return target

## Public market/terminal streets favour foot traffic; industrial and rural areas
## carry fewer pedestrians. Coordinates follow the authored harbor street layout
## (market/terminal x60..165,z0..100; industrial waterfront south of z156).
## Twenty-metre shoulders avoid a hard population boundary between streets.
static func area_density_target(region_id: String, point: Vector3) -> Vector2:
	if region_id == "mountain": return Vector2(.6,.7)
	if region_id == "desert": return Vector2(.7,.8)
	if region_id != "harbor": return Vector2.ONE
	var target := Vector2(1.0,.9)
	var market_edge := maxf(maxf(60.0-point.x,point.x-165.0),maxf(-point.z,point.z-100.0))
	var market_weight := 1.0-smoothstep(0.0,20.0,market_edge)
	target = target.lerp(Vector2(.9,.7),market_weight)
	return target.lerp(Vector2(.7,.8),smoothstep(156.0,176.0,point.z))

func _update_density() -> void:
	var units := 0
	if is_instance_valid(world.dispatch): units = world.dispatch.units.size()
	var stars := 0
	if is_instance_valid(world.gameplay): stars = int(world.gameplay.stars)
	var target := density_target(units,stars)
	var area_target := area_density_target(state.region_id,world.player.global_position)
	# Interruptor para comparar com/sem a densidade dinâmica em medições.
	if "--no-density" in OS.get_cmdline_user_args():
		target = 1.0
		area_target = Vector2.ONE
	# Chamado a cada 0,25 s: 1,0 -> 0,4 em ~1,5 s; volta em ~7,5 s (sem pisca-pisca com
	# viaturas entrando e saindo).
	density_scale = move_toward(density_scale,target,.1 if target < density_scale else .02)
	# Mudanças de área também assentam aos poucos; a remoção ainda exige distância e estar
	# fora da câmera, então o trânsito visível existente nunca some numa fronteira.
	area_density_scale.x = move_toward(area_density_scale.x,area_target.x,.02)
	area_density_scale.y = move_toward(area_density_scale.y,area_target.y,.02)

func _population_cap() -> int:
	var target := mini(requested_population,VC_MAX_POPULATION) if population_vc_enabled else requested_population
	return ceili(float(target)*minf(density_scale,area_density_scale.x)-.00001)

func _traffic_cap() -> int:
	# Os componentes de Vector2 são float32; ignora o erro de arredondamento abaixo de uma entidade nos
	# tetos inteiros escritos (por exemplo, 40 * .8 precisa continuar 32, não 33).
	return ceili(float(VC_TRAFFIC_TARGET if population_vc_enabled else TRAFFIC_TARGET)*minf(density_scale,area_density_scale.y)-.00001)

## Tira no máximo um pedestre e um carro civil por chamada, o mais longe do jogador e fora
## do quadro, enquanto houver mais que o teto atual.
func _trim_density() -> void:
	var origin: Vector3 = world.player.position
	if world.people.size() > _population_cap():
		var worst := -1
		var farthest := DENSITY_TRIM_MIN_DISTANCE
		for index in world.people.size():
			var actor = world.people[index]
			if not is_instance_valid(actor): continue
			var distance: float = actor.position.distance_to(origin)
			if distance > farthest and not _on_screen(actor.global_position,1.0):
				farthest = distance
				worst = index
		if worst >= 0:
			var removed = world.people[worst]
			world.people.remove_at(worst)
			removed.queue_free()
	if _ambient_traffic_count() > _traffic_cap():
		var worst_car := -1
		var farthest_car := DENSITY_TRIM_MIN_DISTANCE
		for index in vehicles.size():
			var car = vehicles[index]
			if not _is_ambient_traffic(car) or not car.traffic or car.health <= 0.0 or car == world.driving.car: continue
			var distance: float = car.global_position.distance_to(origin)
			if distance > farthest_car and not _on_screen(car.global_position,3.0):
				farthest_car = distance
				worst_car = index
		if worst_car >= 0:
			var removed_car = vehicles[worst_car]
			vehicles.remove_at(worst_car)
			removed_car.queue_free()

func _service_population_job() -> void:
	if _population_jobs.is_empty(): return
	var job: String = _population_jobs.pop_front()
	var began := Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	match job:
		"citizen":
			if world.people.size() < _population_cap(): _spawn_citizen()
		"traffic":
			if _ambient_traffic_count() < _traffic_cap() and not "--no-traffic" in OS.get_cmdline_user_args(): _spawn_vehicle()
		"equipment":
			for car in vehicles:
				if not is_instance_valid(car) or car.is_queued_for_deletion() or is_instance_valid(car.equipment): continue
				if car.traffic or (car.controlled and car.external_input):
					car.ensure_equipment(world)
					break
	_trace_cost("population_job:"+job,began)

func vehicle_position_clear(car: CharacterBody3D, point: Vector3, yaw: float) -> bool:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	if car.has_method("placement_poses"):
		var poses: Array[Transform3D] = car.placement_poses(point,yaw)
		for index in poses.size():
			if session!=null and session.cold!=null and not session.cold.prepare_collision_at(poses[index].origin): return false
			for x in [-1.0,1.0]:
				for z in [-float(car.LENGTHS[index])*.4,float(car.LENGTHS[index])*.4]:
					var support: Vector3 = poses[index]*Vector3(x,0,z)
					if space.intersect_ray(PhysicsRayQueryParameters3D.create(support+Vector3.UP*.6,support-Vector3.UP*.5,1)).is_empty(): return false
		return car.admits(poses,false)
	var basis := Basis(Vector3.UP,yaw)
	# Carros salvos distantes esperam o terreno antes de pedir objetos em streaming.
	for x in [-car.half_width*.8,car.half_width*.8]:
		for z in [-car.half_length*.8,car.half_length*.8]:
			var support: Vector3 = point+basis*Vector3(x,0,z)
			# Começa a 0,6 m: numa rampa (túnel do canal) a quina da frente fica até
			# ~0,3 m abaixo do piso e o raio de 0,3 m nascia dentro dele.
			var ray := PhysicsRayQueryParameters3D.create(support+Vector3.UP*.6,support-Vector3.UP*.5,1)
			if space.intersect_ray(ray).is_empty(): return false
	if session != null and session.cold != null and not session.cold.prepare_collision_at(point): return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = car.shape.shape
	query.transform = Transform3D(basis,point+basis*car.shape.position)
	query.collision_mask = 7
	query.exclude = [car.get_rid()]
	# Caixa horizontal numa rampa (túnel do canal) entra ~28 cm no piso: sem esta
	# exceção o carro suspenso ali nunca era liberado.
	for hit in space.intersect_shape(query,4):
		if is_instance_valid(hit.collider) and hit.collider.has_meta("vehicle_ramp_structure"): continue
		return false
	return true

func spawn_vehicle(id: String, point: Vector3, yaw: float = 0.0, crush_ratio: float = 1.0) -> CharacterBody3D:
	if preload("res://runtime/FleetCatalog.gd").spec(id).is_empty(): return null
	var car = VEHICLE.new()
	if id=="biarticulated_510":
		car.free()
		car=preload("res://runtime/transit/BiarticulatedBus.gd").new()
		car.stolen=true
	car.archetype = id
	car.vehicle_id = "vehicle_"+str(Time.get_ticks_usec())
	car.position = point
	car.set_meta("region_id",state.region_id)
	car.rotation.y = yaw
	var traced := Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	world.add_child(car)
	PIPELINE_PROBE.note("spawn_vehicle", car)
	if id=="biarticulated_510":
		car.place(point,yaw)
		if is_instance_valid(urban_transit) and is_instance_valid(urban_transit.urban_service) and not urban_transit.urban_service.fleet.has(car): urban_transit.urban_service.fleet.append(car)
	_trace_cost("spawn_vehicle_add_child:"+id,traced)
	if is_finite(crush_ratio) and crush_ratio >= .18 and crush_ratio <= .55:
		preload("res://gameplay/street_physics/HeavyVehicleCrush.gd").apply_saved(car,crush_ratio)
	traced = Time.get_ticks_usec() if traced != 0 else 0
	var clear := vehicle_position_clear(car,point,yaw)
	_trace_cost("spawn_vehicle_position_clear",traced)
	if not clear:
		if point.distance_to(world.player.position) < 75:
			car.queue_free()
			return null
		car.set_meta("awaiting_ground",true)
		car.set_physics_process(false)
	car.destroyed.connect(func():
		if is_instance_valid(world.gameplay):
			world.gameplay.explode(car.global_position+Vector3.UP*.4,5.0,35.0,car,false)
			if is_instance_valid(world.gameplay.emergency):
				world.gameplay.emergency.ignite(car.global_position,car))
	vehicles.append(car)
	return car

func _ambient_traffic_count() -> int:
	var count := 0
	for car in vehicles:
		if is_instance_valid(car) and _is_ambient_traffic(car) and car.traffic and car.health > 0.0: count += 1
	return count

func _is_ambient_traffic(car: Variant) -> bool:
	if not is_instance_valid(car) or not car is Node or car.get_meta("ambient_traffic",false) != true: return false
	# O carro tomado pelo jogador e os persistentes não entram no orçamento civil.
	if population_vc_enabled and (car.is_queued_for_deletion() or _is_persistent_vehicle(car)): return false
	return true

func _repath_ambient_traffic() -> void:
	for car in vehicles:
		if not _is_ambient_traffic(car) or not car.traffic or car.health <= 0.0: continue
		if car.has_meta("ambient_next_route"): car.remove_meta("ambient_next_route")
		var route: Curve3D = ambient_traffic_routes.route_near(car.global_position,int(car.route.get_meta("lane_index",0)) if car.route!=null else 0,-car.global_basis.z)
		if route == null or route.get_baked_length() < 12.0 or not PORT_POLICY.route_is_ambient_safe(route):
			car.queue_free()
			continue
		car.route = route
		car.route_distance = route.get_closest_offset(car.global_position)

func _near_segment() -> Dictionary:
	var options := []
	for road in ambient_roads_cache:
		for i in range(road.points.size()-1):
			var a: Vector3 = road.points[i]
			var b: Vector3 = road.points[i+1]
			var point := Geometry3D.get_closest_point_to_segment(world.player.position,a,b)
			if point.distance_to(world.player.position) < POPULATION_SPAWN_MAX and a.distance_to(b) > 4:
				options.append({"a":a,"b":b,"width":road.width})
	return options.pick_random() if not options.is_empty() else {}

## Ponto dentro do quadro da câmera (com folga de `radius` metros e 10% da tela).
func _on_screen(point: Vector3, radius: float = 1.0) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return false
	var rect := get_viewport().get_visible_rect().grow(get_viewport().get_visible_rect().size.x*.1)
	for offset in [Vector3.ZERO,Vector3.UP*2.0,Vector3(radius,0,0),Vector3(-radius,0,0),Vector3(0,0,radius),Vector3(0,0,-radius)]:
		var sample: Vector3 = point+offset
		if not camera.is_position_behind(sample) and rect.has_point(camera.unproject_position(sample)): return true
	return false

## Grade de trechos de pista para _on_carriageway. A admissão de um pedestre testa ~20-40
## pontos da calçada e cada um varria todos os trechos de todas as ruas residentes (e
## remontava _resident_roads, com conectores e túnel): é o grosso de population_spawn
## (p99 4,2 ms no porto, release 13-15/10). Mesmo teste exato, só nos trechos da célula.
## Refeita quando o conjunto residente muda (_configure_routes), como os grafos de rota.
const CARRIAGEWAY_CELL := 16.0
var _carriageway_grid: Dictionary = {}
var _carriageway_key := ""

func _carriageway_cells() -> Dictionary:
	var key := _route_key()
	if key == _carriageway_key and not _carriageway_grid.is_empty(): return _carriageway_grid
	_carriageway_key = key
	_carriageway_grid = carriageway_grid(_resident_roads())
	return _carriageway_grid

func _on_carriageway(point: Vector3) -> bool:
	var bridge = preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
	if bridge.owns_east_point(Vector2(point.x,point.z)) and Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),bridge.east_asphalt_footprint()):
		return true
	return grid_on_carriageway(_carriageway_cells(), point)

static func carriageway_grid(roads: Array) -> Dictionary:
	var grid := {}
	for road in roads:
		var points: PackedVector3Array = road.points
		var half := float(road.width)*.5+.3
		for i in range(points.size()-1):
			var a := Vector2(points[i].x,points[i].z)
			var b := Vector2(points[i+1].x,points[i+1].z)
			var bounds := Rect2(a,Vector2.ZERO).expand(b).grow(half)
			for x in range(floori(bounds.position.x/CARRIAGEWAY_CELL),floori(bounds.end.x/CARRIAGEWAY_CELL)+1):
				for z in range(floori(bounds.position.y/CARRIAGEWAY_CELL),floori(bounds.end.y/CARRIAGEWAY_CELL)+1):
					var cell := Vector2i(x,z)
					if not grid.has(cell): grid[cell] = []
					grid[cell].append([a,b,half])
	return grid

static func grid_on_carriageway(grid: Dictionary, point: Vector3) -> bool:
	var flat := Vector2(point.x,point.z)
	var cell := Vector2i(floori(flat.x/CARRIAGEWAY_CELL),floori(flat.y/CARRIAGEWAY_CELL))
	for segment in grid.get(cell,[]):
		var nearest := Geometry2D.get_closest_point_to_segment(flat,segment[0],segment[1])
		if flat.distance_to(nearest) < segment[2]: return true
	return false

const WRECK_LINGER_MSEC := 6000

func _wreck_expired(car: Node) -> bool:
	if not car.has_meta("wrecked_msec"): car.set_meta("wrecked_msec",Time.get_ticks_msec())
	return Time.get_ticks_msec()-int(car.get_meta("wrecked_msec")) > WRECK_LINGER_MSEC

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

## Tira o trânsito ambiente de perto destes pontos já, mesmo à vista: só para quem chama sob a cortina
## (largada da descida), onde o jogador não vê o carro sumir. Devolve quantos saíram.
func clear_ambient_traffic_near(points: PackedVector3Array, radius: float) -> int:
	var removed := 0
	for index in range(vehicles.size()-1,-1,-1):
		var car = vehicles[index]
		if not _is_ambient_traffic(car) or not car.traffic or car == world.driving.car: continue
		for p: Vector3 in points:
			if car.global_position.distance_to(p) > radius: continue
			vehicles.remove_at(index)
			# Sem colisão já: a vaga é consultada neste mesmo quadro, antes do queue_free valer.
			car.collision_layer = 0
			car.queue_free()
			removed += 1
			break
	return removed

func in_traffic_hold(point: Vector3) -> bool:
	for hold: Array in traffic_holds.values():
		var limit: float = hold[1]*hold[1]
		for p: Vector3 in hold[0]:
			if Vector2(point.x-p.x,point.z-p.z).length_squared() <= limit: return true
	return false

func _spawn_point_allowed(point: Vector3, radius: float, minimum := POPULATION_SPAWN_MIN) -> bool:
	var distance := Vector2(point.x-world.player.global_position.x,point.z-world.player.global_position.z).length()
	# Pedestres comuns usam raio 1; carros mantêm o anel original de admissão.
	var maximum := VC_PEDESTRIAN_SPAWN_MAX if population_vc_enabled and radius <= 1.0 else POPULATION_SPAWN_MAX
	return distance >= minimum and distance <= maximum and not _on_screen(point,radius)

func road_yaw(point: Vector3) -> float:
	var best := INF
	var yaw := 0.0
	for road in _resident_roads():
		for index in range(road.points.size()-1):
			var a: Vector3 = road.points[index]
			var b: Vector3 = road.points[index+1]
			var distance := Geometry3D.get_closest_point_to_segment(point,a,b).distance_squared_to(point)
			if distance < best:
				best = distance
				var direction := b-a
				yaw = atan2(-direction.x,-direction.z)
	return yaw

func _spawn_citizen() -> void:
	var began := Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	_create_citizen()
	_trace_cost("population_spawn",began)

## O primeiro uso do espelho C# (RoadGraphSearch.cs) paga ~22 ms de JIT de Build/NearestEdge/
## Plan/BuildPath (medido em 05/10, docs/reviews/dispatch-plan-stall-20261005.md). Perto do
## terminal, prepare_startup_route já paga isso sob a cortina; longe dele o custo caía no
## primeiro despacho/ônibus/PortHaul em pleno jogo. Um roteador descartável compila os mesmos
## métodos sem tocar no estado dos roteadores reais (bloqueios, relógio, espelho) nem no RNG.
## HARBOR_ROUTER_JIT_PREWARM=0 desliga, para A/B.
func _prewarm_route_jit() -> void:
	if OS.get_environment("HARBOR_ROUTER_JIT_PREWARM") == "0": return
	if traffic_routes == null or traffic_routes.vertices.size() < 2: return
	var began := Time.get_ticks_usec()
	var router: RefCounted = preload("res://gameplay/dispatch/DispatchRoadRouter.gd").new()
	router.configure(traffic_routes)
	var count: int = traffic_routes.vertices.size()
	var planned := false
	# Alguns pares podem não ter caminho (mão única); só um plano completo exercita BuildPath.
	for step in [2, 3, 5, 7]:
		var result: Dictionary = router.plan(traffic_routes.vertices[0], traffic_routes.vertices[count / step])
		if result.get("ok", false):
			planned = true
			break
	var elapsed := Time.get_ticks_usec() - began
	print("startup: route_jit_prewarm native=%s planned=%s ms=%.3f" % [router._native != null, planned, elapsed / 1000.0])
	if world.get_meta("benchmark_trace", false): _trace_cost("startup:route_jit_prewarm", began)

## Espera as filas paralelas. Uma etapa que pare com erro de script nunca devolveria a vez e a cortina ficaria
## presa: depois de LANE_DEADLINE_MSEC a carga segue com aviso (o pré-aquecimento que faltou compila no jogo).
## Devolve false se o mundo saiu da árvore no meio.
const LANE_DEADLINE_MSEC := 180000
func _await_lanes(pending: Array[int]) -> bool:
	var deadline := Time.get_ticks_msec() + LANE_DEADLINE_MSEC
	while pending[0] > 0:
		await get_tree().process_frame
		if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): return false
		if Time.get_ticks_msec() > deadline:
			push_warning("Pré-aquecimento em paralelo: %d fila(s) não terminaram em %d s; a carga segue." % [pending[0], int(LANE_DEADLINE_MSEC / 1000.0)])
			break
	return true

## Uma fila de pré-aquecimentos de desenho em série; várias filas correm juntas (GETECO_PREWARM_PARALLEL).
## Chamada sem await: cada etapa espera os próprios quadros e `pending` cai quando a fila acaba.
func _prewarm_lane(steps: Array, pending: Array[int], curtain: CanvasLayer) -> void:
	for step in steps:
		if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree(): break
		var traced := Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
		await _draw_prewarm_step(str(step), curtain)
		_trace_cost("startup:prewarm:" + str(step), traced)
	pending[0] -= 1

func _draw_prewarm_step(step: String, curtain: CanvasLayer) -> void:
	match step:
		"fire":
			preload("res://gameplay/emergency/Fire.gd").prewarm_visuals()
			await preload("res://gameplay/emergency/EffectsPrewarm.gd").run(world, curtain)
		"rain": await preload("res://runtime/RainPrewarm.gd").run(world, curtain)
		"police_visual": await preload("res://gameplay/emergency/PoliceVisualPrewarm.gd").run(world, curtain)
		"vehicle_variants": await preload("res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd").run(world, curtain)
		"bridge_look": await preload("res://runtime/BridgeLookPrewarm.gd").run(world, curtain)
		# Omni (cubo e paraboloide) e spot com sombra + chão natural opaco e de borda: a feature de
		# pipeline de sombra local passa a existir antes do jogo (túnel da ponte, lanterna, faróis).
		"local_light_shadow": await preload("res://runtime/LocalLightShadowPrewarm.gd").run(world, curtain)
		"desert_ground_cover": await preload("res://world/desert/DesertGroundCover.gd").prewarm_draw(world, curtain)
		"family_variants": await preload("res://runtime/FamilyVariantPrewarm.gd").run(world, curtain)
		"painted_facades": await preload("res://runtime/PaintedFacadePrewarm.gd").run(world, curtain)
		"wildlife": await preload("res://runtime/WildlifePrewarm.gd").run(world, curtain)
		"forge": await preload("res://runtime/ForgePrewarm.gd").run(world, curtain)
		"skate": await preload("res://activities/skate/SkateModel.gd").prewarm_colors(world)
		"meshy_bodies": await preload("res://assets/civilians/MeshyBodyPrewarm.gd").run(world, curtain)
		# Primeira aparição da Cobra e da polícia no tiroteio (sumiço do morto, itens largados, giroflex):
		# quadros de 588-646 ms no desenho no release de 17/10. Depois dos GLBs do Meshy, já carregados acima.
		"spawn_visuals": await preload("res://gameplay/emergency/SpawnVisualPrewarm.gd").run(world, curtain)
		"street_fx": await preload("res://gameplay/street_physics/StreetEffectsPrewarm.gd").run(world, curtain)
		# Aquece depois que o CityLook liga o framebuffer Mobile final (incluindo glow).
		"reaction_visuals": await preload("res://gameplay/emergency/ReactionVisualPrewarm.gd").run(world, curtain)
		"vehicle_interior": await preload("res://gameplay/VehicleInteriorMaterialPrewarm.gd").run(world, curtain)
		# Tiros, impactos, explosão e armas na mão desenhados diante da câmera (cache de pipeline frio).
		"combat_effects": await preload("res://gameplay/CombatEffectsPrewarm.gd").run(world, curtain)
		# Filas de carga sem desenho (GETECO_LOAD_LANES): correm junto com as de desenho.
		"audio_banks": await _prewarm_audio_banks()
		"weapon_templates": await _prewarm_weapon_templates()
		"resident_regions": await _prewarm_resident_regions()
		# Silhueta de oclusão nos formatos de carro e no jogador, mobília dos prédios do porto (sonda de 22–25/10).
		"late_surfaces": await preload("res://runtime/LateSurfacePrewarm.gd").run(world, curtain)

## Etapas do pré-aquecimento com nome (22/10, 3ª rodada): no cache frio `startup:combat_resources` levava
## 31 s (5 s a quente) e só o total ia ao registro. Cada etapa vai ao registro da sessão
## (`startup:prewarm:<nome>`) e fecha a etapa na sonda de pipelines (GETECO_PIPELINE_PROBE=1).
func _prewarm_mark(label: String, began: int) -> int:
	_trace_cost("startup:prewarm:" + label, began)
	PIPELINE_PROBE.stage(label)
	return Time.get_ticks_usec() if began != 0 else 0

func _trace_cost(label: String, began: int) -> void:
	if began == 0: return
	SESSION_OPS.completed(self, "world", label, began, {"region":state.region_id})
	if not world.get_meta("benchmark_trace",false): return
	var elapsed := Time.get_ticks_usec()-began
	if elapsed < 2000: return
	var costs: Array = world.get_meta("perf_costs",[])
	if costs.size()<512: costs.append({"label":label,"start_usec":began,"duration_usec":elapsed})
	world.set_meta("perf_costs",costs)

func _create_citizen() -> void:
	if state.region_id == "desert":
		_create_desert_citizen()
		return
	var segment := population_layout.select(self)
	if segment.is_empty(): return
	var along: Vector3 = segment.a.direction_to(segment.b)
	var point: Vector3 = segment.point
	var margin := minf(20.0,segment.a.distance_to(segment.b)*.4)
	var center: Vector3 = Geometry3D.get_closest_point_to_segment(point,segment.a,segment.b)
	var offset: Vector3 = point-center
	var start: Vector3 = center-along*minf(margin,center.distance_to(segment.a)*.8)+offset
	var finish: Vector3 = center+along*minf(margin,center.distance_to(segment.b)*.8)+offset
	# As calçadas ficam acima da linha central da rua; admite no piso real delas,
	# em vez de recusar uma calçada livre como cápsula dentro do calçamento.
	var grounded: Array[Vector3] = []
	for candidate in [point,start,finish]:
		var ground: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*1.0,candidate-Vector3.UP*1.0,1))
		if ground.is_empty() or absf(ground.position.y-candidate.y)>.4: return
		grounded.append(Vector3(candidate.x,ground.position.y+.08,candidate.z))
	point = grounded[0]
	start = grounded[1]
	finish = grounded[2]
	var pedestrian_route := _clip_citizen_route(point,start,finish)
	if pedestrian_route.is_empty(): return
	var actor = ACTOR.new()
	actor.identity = randi_range(0,10000)
	actor.position = point+Vector3.UP*.08
	actor.speed = randf_range(1.15,1.75)
	actor.route = pedestrian_route
	actor.set_meta("ambient_road_id",str(segment.road.id))
	actor.set_meta("region_id",state.region_id)
	world.add_child(actor)
	world.people.append(actor)

## Mantém a caminhada original onde está livre. Num cruzamento ou obstrução,
## usa a parte apoiada em volta do spawn em vez de recusar a calçada
## inteira. As mesmas amostras de admissão de <=2 m e a cápsula inteira da faixa continuam valendo.
func _clip_citizen_route(point: Vector3, start: Vector3, finish: Vector3) -> PackedVector3Array:
	if _on_carriageway(point) or CANAL_TUNNEL.reserves(Vector2(point.x,point.z),.5) or PORT_POLICY.contains_private_area(point): return PackedVector3Array()
	if not session.position_clear(point+Vector3.UP*.06): return PackedVector3Array()
	var route := PackedVector3Array()
	for target in [start,finish]:
		var last := point
		var steps := maxi(1,ceili(point.distance_to(target)/2.0))
		for i in range(1,steps+1):
			var candidate := point.lerp(target,float(i)/steps)
			if _on_carriageway(candidate) or CANAL_TUNNEL.reserves(Vector2(candidate.x,candidate.z),.5) or PORT_POLICY.contains_private_area(candidate): break
			if not session.position_clear(candidate+Vector3.UP*.08): break
			last = candidate
		route.append(last)
	if route[0].distance_to(route[1]) < 4.0: return PackedVector3Array()
	if PORT_POLICY.segment_enters_private_area(route[0],route[1]): return PackedVector3Array()
	return route if _pedestrian_route_sweep_clear(route) else PackedVector3Array()

func _create_desert_citizen() -> void:
	var occupied := {}
	for actor in world.people:
		if is_instance_valid(actor) and actor.has_meta("desert_social_slot"):
			occupied[int(actor.get_meta("desert_social_slot"))] = true
	var start := randi_range(0,_desert_social_slots.size()-1)
	for index in _desert_social_slots.size():
		var slot_id := (start+index)%_desert_social_slots.size()
		if occupied.has(slot_id): continue
		var slot: Dictionary = _desert_social_slots[slot_id]
		var point: Vector3 = slot.point
		var distance := point.distance_to(world.player.global_position)
		# Espaços sociais pequenos cabem dentro do anel de exclusão de 45 m da cidade. Admite
		# os moradores deles mais perto, ainda fora da câmera e nunca em cima de nós.
		if distance < 12.0 or distance > POPULATION_SPAWN_MAX or _on_screen(point,1.0): continue
		if not desert_social_route_clear(slot.route): continue
		var actor = DESERT_SOCIAL_ACTOR.new()
		actor.identity = 6100+slot_id
		actor.position = point+Vector3.UP*.08
		actor.speed = 1.2
		actor.route = slot.route
		actor.social_activity = slot.activity
		actor.social_facing = slot.facing
		actor.set_meta("region_id","desert")
		actor.set_meta("desert_social_slot",slot_id)
		world.add_child(actor)
		world.people.append(actor)
		return

func desert_social_route_clear(route: PackedVector3Array) -> bool:
	# A autoria pode mover prédios: recusa a rota inteira, nunca só o spawn.
	var a := route[0]
	var b := route[-1]
	var steps := maxi(1,ceili(a.distance_to(b)/2.0))
	for i in range(steps+1):
		var point := a.lerp(b,float(i)/steps)
		if _on_carriageway(point) or not session.position_clear(point+Vector3.UP*.08): return false
	return _pedestrian_route_sweep_clear(route)

func _pedestrian_route_sweep_clear(route: PackedVector3Array) -> bool:
	var a := route[0]
	var b := route[-1]
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	# Inclui o pequeno desvio de faixa de caminhada do Actor na folga varrida.
	capsule.radius = .72 if a.distance_squared_to(b) > .01 else .32
	capsule.height = 1.7
	query.shape = capsule
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY,a+Vector3.UP*.98)
	query.motion = b-a
	if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	var result: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
	return result[0] >= 1.0

func _spawn_vehicle() -> void:
	var began := Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	_create_traffic_vehicle()
	_trace_cost("traffic_spawn",began)

func _create_traffic_vehicle() -> void:
	# Shared spatial admission favours quiet stretches and both legal directions.
	for attempt in 2:
		var slot: Dictionary = population_layout.select(self,true)
		if slot.is_empty(): return
		var point: Vector3 = slot.point
		var route: Curve3D = ambient_traffic_routes.route_near(point,int(slot.lane_index),slot.direction)
		if route == null or route.get_baked_length()<12 or not PORT_POLICY.route_is_ambient_safe(route): continue
		var offset := route.get_closest_offset(point)
		if route.get_meta("traffic_open",false) and route.get_baked_length()-offset<14: continue
		point = route.sample_baked(offset,true)
		if not _spawn_point_allowed(point,3.0) or (not traffic_holds.is_empty() and in_traffic_hold(point)): continue
		var ahead := route.sample_baked(minf(offset+.5,route.get_baked_length()),true)-route.sample_baked(maxf(offset-.5,0),true)
		# A rua admitida é dona do contexto, inclusive quando duas regiões estão residentes.
		var spawn_region := str(slot.road.get("region", WORLD_CONNECTION.logical_region(point)))
		var id: String = TRAFFIC_ROSTER.select(spawn_region, str(slot.road.id))
		if spawn_region != "desert" and randi_range(0,9)==0: id=TRAFFIC_MOTORCYCLE_TYPES.pick_random()
		var cobra := preload("res://gameplay/urban_v1/CobraPatrol.gd").select_car(session,point)
		# Os Cobras rodam com a garagem própria (muscle cars e lowriders), não mais todos no mesmo cupê.
		if cobra: id=preload("res://runtime/MuscleFleet.gd").cobra_pick(randf())
		var car = spawn_vehicle(id,point+Vector3.UP*.12,atan2(-ahead.x,-ahead.z))
		if car==null: continue
		car.vehicle_id="street_"+str(Time.get_ticks_usec())
		if id=="courier_van" and preload("res://gameplay/icecream/IceCreamVan.gd").choose(vehicles):
			# Etapas medidas à parte: a van de sorvete custou 39-43 ms no traffic_spawn da serra
			# (EXE de 17/10) e a altura do teto, pré-aquecida, não era a causa.
			var paint_began := Time.get_ticks_usec() if (world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
			car.paint_color=Color("fff0dd")
			_trace_cost("traffic_spawn_icecream_paint",paint_began)
			paint_began = Time.get_ticks_usec() if paint_began != 0 else 0
			car.vehicle_id=preload("res://gameplay/icecream/IceCreamVan.gd").PREFIX+str(Time.get_ticks_usec())
			_trace_cost("traffic_spawn_icecream_id",paint_began)
		car.route=route
		car.route_distance=offset
		car.set_meta("ambient_traffic",true)
		car.traffic=true
		if cobra: preload("res://gameplay/urban_v1/CobraPatrol.gd").attach(session,car)
		return

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
	session._cancel_for(&"travel")
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

## Os demais modelos da frota (polícia, empilhadeira, viaturas do porto...) eram lidos do disco
## na hora em que nasciam: 650 ms num quadro (medido: `port_forklift`, `PoliceMotorPool`). São
## poucos MB no total; a leitura corre em segundo plano e o carregamento posterior acha em cache.
func _request_remaining_fleet_scenes(already: Array[String]) -> void:
	var extra: Array[String] = []
	for id in preload("res://runtime/FleetCatalog.gd").all():
		var path := str(preload("res://runtime/FleetCatalog.gd").spec(id).get("scene", ""))
		if path.is_empty() or path in already or path in extra: continue
		extra.append(path)
	await _retain_fleet_paths(extra, _fleet_extra)
