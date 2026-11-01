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
## Residência das regiões (montar/desmontar, apoio dos veículos, conexão da ponte, região lógica) separada
## em 01/11 (Onda 3): o estado e o sinal logical_region_changed ficam aqui; cada função antiga delega.
const RESIDENCY := preload("res://runtime/ProductionResidency.gd")
var _residency: RESIDENCY = RESIDENCY.new(self)
## Carga do mundo (corpo de build() em etapas, início e --play-at) separada em 01/11 (Onda 3): o estado
## fica aqui; build() e cada função antiga delegam em uma linha, com `await` onde esperam quadro.
const BUILD := preload("res://runtime/ProductionBuild.gd")
var _build: BUILD = BUILD.new(self)
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

func build() -> void: await _build.run()

func _prewarm_regions(curtain: CanvasLayer = null) -> void: await _prewarm._prewarm_regions(curtain)

func _prewarm_audio_banks() -> void: await _prewarm._prewarm_audio_banks()

func _prewarm_weapon_templates() -> void: await _prewarm._prewarm_weapon_templates()

func _prewarm_resident_regions() -> void: await _prewarm._prewarm_resident_regions()

func _apply_player_settings() -> void:
	if is_instance_valid(environment): get_node("/root/V2Settings").apply_environment(environment.environment)
	if is_instance_valid(sun) and sun_shadow_near_enabled:
		sun.directional_shadow_max_distance = get_node("/root/V2Settings").shadow_distance_metres()

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

func _startup_driver_pending() -> bool: return _build._startup_driver_pending()

func _settle_startup() -> bool: return await _build._settle_startup()

func _prepare_geography(candidate: Node3D) -> bool: return await _build._prepare_geography(candidate)

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

func _install_world_edits() -> void: _build._install_world_edits()

## `--play-at=região,x,z` (só com --no-save). Devolve {} se ausente ou inválido.
var play_at_request: Dictionary = {}
static func _play_at_argument() -> Dictionary: return BUILD._play_at_argument()

func _resolve_play_at() -> void: _build._resolve_play_at()

func _place_at_request() -> void: await _build._place_at_request()

func _startup_focus_hint() -> Vector3: return _build._startup_focus_hint()

func _startup_position() -> Vector3: return _build._startup_position()

func _audio() -> Node:
	var audio = preload("res://audio/WorldAudio.gd").new()
	audio.world = world
	return audio

func _physical_focus() -> Vector3: return _residency._physical_focus()

func _mount_region(id: String, requested_focus: Vector3 = Vector3.INF) -> Node3D: return _residency._mount_region(id, requested_focus)

func _build_region(id: String, first_focus := Vector3.INF) -> Node3D: return _residency._build_region(id, first_focus)

func _mount_region_now(id: String, requested_focus: Vector3) -> Node3D: return _residency._mount_region_now(id, requested_focus)

## Rotas refeitas no quadro seguinte à montagem/desmontagem, já jogando (22/10): remontar o porto na serra
## somava montagem (8 ms), foco, conexão da ponte e os consumidores de rota (dispatch, cruzamentos,
## população, 3–5 ms) num quadro de 35–38 ms. Montagem e desmontagem no mesmo quadro refazem uma vez só.
## Sob a cortina e em teste continua no ato. GETECO_ROUTE_REFRESH_DEFER=0 volta ao ato sempre.
var _route_refresh_pending := false
func _request_route_refresh() -> void: _residency._request_route_refresh()

func _mount_census(mounted: Node) -> void: _residency._mount_census(mounted)

## Desmontagem pela residência física, já jogando, espera um quadro sem outro trabalho pesado
## (HeavyFrameClaim): aos 3 s no deserto ela caía junto da etapa de estradas do chão (27/10).
## Sob a cortina, em teste e com GETECO_UNMOUNT_DEFER=0, desmonta no ato.
var _pending_unmounts: Dictionary = {}
func _queue_unmount(id: String) -> void: _residency._queue_unmount(id)

func _drain_pending_unmount() -> void: _residency._drain_pending_unmount()

func _unmount_region(id: String) -> void: _residency._unmount_region(id)

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

func _persistent_vehicle_support() -> Dictionary: return _residency._persistent_vehicle_support()

func _is_persistent_vehicle(car: Node) -> bool: return _residency._is_persistent_vehicle(car)

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

func _active_dispatch_support() -> Dictionary: return _residency._active_dispatch_support()

func _update_physical_residency(point: Vector3) -> void: _residency._update_physical_residency(point)

## Conexão da ponte estacionada fora da árvore entre aproximações (22/10): era montada de novo a cada
## entrada na faixa de 240 m (world_connection 3 ms) no mesmo quadro em que o porto voltava (13 ms).
## GETECO_CONNECTION_PARK=0 volta a montar e liberar.
static var _connection_park_enabled := OS.get_environment("GETECO_CONNECTION_PARK") != "0"
var _parked_connection: Node3D

func _mount_connection() -> void: _residency._mount_connection()

func prepare_connection_at(point: Vector3) -> void: _residency.prepare_connection_at(point)

## Folga da divisa porto/serra. Sem ela, parado na ponte em cima da linha (x≈456), o jogador trocou de
## região 7 vezes em 11 s mexendo menos de 1 m (release de 2026-10-13), e cada troca refaz rotas,
## tráfego, clima e áudio.
const LOGICAL_REGION_HYSTERESIS := 4.0

func _update_logical_region(point: Vector3) -> void: _residency._update_logical_region(point)

func _inside_logical_hysteresis(point: Vector3, next_region: String) -> bool: return _residency._inside_logical_hysteresis(point, next_region)

func _commit_logical_region(next_region: String) -> void: _residency._commit_logical_region(next_region)

func _update_mobile_region_metadata() -> void: _residency._update_mobile_region_metadata()

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
