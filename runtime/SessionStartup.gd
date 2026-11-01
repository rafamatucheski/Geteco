extends RefCounted
## Carregamento da FullSession: o corpo do _ready (~54 sistemas criados, cada um com _timed_add e
## await _startup_frame()). Separado em 01/11 (Onda 3 de docs/plano-divisao-arquivos-grandes-20261101.md)
## em etapas nomeadas, na MESMA ordem de antes: nenhum await, add_child, connect ou emit mudou de lugar.
## O _ready continua declarado na sessão e só faz `await _startup.run()`: TestSession
## (test_session_cleanup_registry) e DialogueSession (test_maciota_voice) o sobrescrevem numa subclasse.
## Todo campo atribuído continua sendo da sessão (g.x = ...); startup_finished é sinal dela.
## _timed_add, _startup_frame e _label ficam na sessão e são chamados por `g.`, para o span
## session.ready.* e a fatia de tempo do carregamento incremental continuarem os mesmos.
## `g` fica como Node, e não como o script da FullSession, para não criar preload cíclico.

const SESSION_OPS := preload("res://runtime/SessionOperations.gd")
const DOOR_TRANSITION := preload("res://runtime/DoorTransition.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

func run() -> void:
	_prepare()
	await _install_entrances()
	await _install_hud()
	_connect_gameplay_signals()
	await _install_activities()
	await _install_city_systems()
	await _install_story_systems()
	await _install_voices()
	g._connect_voice_settings()
	await _install_street_systems()
	await _install_optional_systems()
	await _install_transit()
	_finish()

## Antes de tudo: a sessão não processa entrada nem quadro enquanto está pela metade.
func _prepare() -> void:
	g.process_mode = Node.PROCESS_MODE_ALWAYS
	# Input and session updates cannot observe a half-constructed session.
	g.set_process(false)
	g.set_process_input(false)
	g._startup_slice_usec = Time.get_ticks_usec()
	g.state = g.controller.state

## Portas, entradas de lugares, telhados, mirante e parque (filhos da própria sessão).
func _install_entrances() -> void:
	g.door_transition = DOOR_TRANSITION.new()
	await g._startup_frame()
	g._timed_add(g, g.door_transition, "door_transition")
	g.weapon_shop_entrance = preload("res://runtime/WeaponShopEntrance.gd").new()
	g.weapon_shop_entrance.session = g
	await g._startup_frame()
	g._timed_add(g, g.weapon_shop_entrance, "weapon_shop_entrance")
	g.special_place_entrance = preload("res://runtime/SpecialPlaceEntrance.gd").new()
	g.special_place_entrance.session = g
	await g._startup_frame()
	g._timed_add(g, g.special_place_entrance, "special_place_entrance")
	g.building_entrance = preload("res://runtime/HarborBuildingRuntime.gd").new()
	g.building_entrance.session = g
	await g._startup_frame()
	g._timed_add(g, g.building_entrance, "building_entrance")
	g.building_social = preload("res://runtime/BuildingSocialInteraction.gd").new()
	g.building_social.session = g
	await g._startup_frame()
	g._timed_add(g, g.building_social, "building_social")
	g.door_lockpick = preload("res://runtime/DoorLockpick.gd").new()
	g.door_lockpick.session = g
	g._timed_add(g, g.door_lockpick, "door_lockpick")
	g.service_roofs = preload("res://runtime/HarborServiceRoofRuntime.gd").new()
	g.service_roofs.session = g
	await g._startup_frame()
	g._timed_add(g, g.service_roofs, "service_roofs")
	if not Engine.get_meta("coastal_lookout_baseline",false):
		g.coastal_lookout = preload("res://runtime/coastal_lookout/CoastalLookoutRuntime.gd").new()
		g.coastal_lookout.configure(g.world)
		await g._startup_frame()
		g._timed_add(g, g.coastal_lookout, "coastal_lookout")
	if not Engine.get_meta("amusement_park_baseline",false):
		var diagnostic_amusement_park := SESSION_OPS.begin(g, "amusement_park", "create_and_configure")
		g.amusement_park = preload("res://runtime/amusement_park/AmusementParkRuntime.gd").new()
		g.amusement_park.configure(g)
		SESSION_OPS.finish(diagnostic_amusement_park)
		await g._startup_frame()
		g._timed_add(g, g.amusement_park, "amusement_park")

## Âncora no mundo, rótulos antigos (origem dos textos do HUD), marcador de porta e painel de menu.
func _install_hud() -> void:
	g.anchor = Node3D.new()
	await g._startup_frame()
	g._timed_add(g.world, g.anchor, "anchor")
	g.objective = g._label(Vector2(530,24),20)
	g.objective.custom_minimum_size.x = 700
	g.objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g.stats = g._label(Vector2(26,64),18)
	g.thermal_status = g._label(Vector2(26,120),18)
	g.thermal_status.add_theme_color_override("font_outline_color",Color(0.02,0.04,0.06))
	g.thermal_status.add_theme_constant_override("outline_size",4)
	g.thermal_status.hide()
	g.prompt = g._label(Vector2(26,590),20)
	g.notice = g._label(Vector2(26,550),18)
	# Só a origem da mensagem; o ContextualHUDManager cuida da notificação visível.
	g.notice.hide()
	g.marker = preload("res://ui/DoorAccessMarker.gd").new()
	await g._startup_frame()
	g._timed_add(g.world.hud, g.marker, "marker")
	g.arrow = g._label(Vector2.ZERO,30)
	g.arrow.text = "▲"
	g.arrow.modulate = Color("f39a38")
	g.arrow.pivot_offset = Vector2(12,20)
	# O HUD ancorado no mundo precisa seguir a câmera final em todo quadro renderizado,
	# não a atualização de texto de 10 Hz (que fazia o marcador laranja pular).
	g.marker.update_position = g.update_world_indicator
	g.panel = PanelContainer.new()
	g.panel.position = Vector2(330,110)
	g.panel.custom_minimum_size = Vector2(620,440)
	await g._startup_frame()
	g._timed_add(g.world.hud, g.panel, "panel")
	var margin := MarginContainer.new()
	for side in ["top","left","right","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	g.panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580,400)
	margin.add_child(scroll)
	g.column = VBoxContainer.new()
	g.column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.column.add_theme_constant_override("separation",10)
	scroll.add_child(g.column)
	g.panel.hide()

## Mensagem, morte, prisão e aviso da polícia do Gameplay.
func _connect_gameplay_signals() -> void:
	g.world.gameplay.message.connect(g.show_message)
	g.world.gameplay.player_died.connect(g.on_death)
	g.world.gameplay.player_arrested.connect(g.on_arrest)
	g.world.gameplay.police_warning_issued.connect(g._police_voice_warning)

## Missões, atividades, motocross, skate, residência, gatos e serra.
func _install_activities() -> void:
	g.mission_world = preload("res://runtime/MissionWorld.gd").new()
	g.mission_world.session = g
	await g._startup_frame()
	g._timed_add(g.world, g.mission_world, "mission_world")
	var diagnostic_activities := SESSION_OPS.begin(g, "activities", "create_and_configure")
	g.activities = preload("res://activities/Activities.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.activities, "activities")
	g.activities.configure(g)
	SESSION_OPS.finish(diagnostic_activities)
	var diagnostic_motocross := SESSION_OPS.begin(g, "motocross", "create_and_configure")
	g.motocross = preload("res://activities/motocross/Motocross.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.motocross, "motocross")
	g.motocross.configure(g)
	SESSION_OPS.finish(diagnostic_motocross)
	var diagnostic_skate := SESSION_OPS.begin(g, "skate", "create_and_configure")
	g.skate = preload("res://activities/skate/Skate.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.skate, "skate")
	g.skate.configure(g)
	SESSION_OPS.finish(diagnostic_skate)
	var diagnostic_residence_services := SESSION_OPS.begin(g, "residence_services", "create_and_configure")
	g.residence_services = preload("res://runtime/ResidenceServices.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.residence_services, "residence_services")
	g.residence_services.configure(g)
	SESSION_OPS.finish(diagnostic_residence_services)
	if not Engine.get_meta("cats_baseline",false):
		var diagnostic_cats := SESSION_OPS.begin(g, "cats", "create_and_configure")
		g.cats = preload("res://runtime/cats/CatRuntime.gd").new()
		await g._startup_frame()
		g._timed_add(g.world, g.cats, "cats")
		g.cats.configure(g)
		SESSION_OPS.finish(diagnostic_cats)
	var diagnostic_mountain_progression := SESSION_OPS.begin(g, "mountain_progression", "create_and_configure")
	g.mountain_progression = preload("res://activities/MountainProgression.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.mountain_progression, "mountain_progression")
	g.mountain_progression.configure(g)
	SESSION_OPS.finish(diagnostic_mountain_progression)
	g.world.player.ski_controller = g.mountain_progression
	var diagnostic_mountain_activities := SESSION_OPS.begin(g, "mountain_activities", "create_and_configure")
	g.mountain_activities = preload("res://runtime/MountainActivities.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.mountain_activities, "mountain_activities")
	g.mountain_activities.configure(g)
	SESSION_OPS.finish(diagnostic_mountain_activities)

## Serviços, lojas, vinho, mundo invertido, fliperama, assaltos, chegada, garagem, frota da polícia e carro pessoal.
func _install_city_systems() -> void:
	var diagnostic_services := SESSION_OPS.begin(g, "services", "create_and_configure")
	g.services = preload("res://runtime/Services.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.services, "services")
	g.services.configure(g)
	SESSION_OPS.finish(diagnostic_services)
	if g.state.world_state.has("services") and not g.services.restore_snapshot(g.state.world_state.services): g.controller.block_saving("serviços não restauraram")
	var diagnostic_storefronts := SESSION_OPS.begin(g, "storefronts", "create_and_configure")
	g.storefronts = preload("res://runtime/HarborStorefronts.gd").new()
	await g._startup_frame()
	g._timed_add(g.world.hud, g.storefronts, "storefronts")
	g.storefronts.configure(g)
	SESSION_OPS.finish(diagnostic_storefronts)
	if not Engine.get_meta("curitiba_cellar_baseline",false):
		var diagnostic_wine := SESSION_OPS.begin(g, "wine", "create_and_configure")
		g.wine = preload("res://gameplay/wine/WineRuntime.gd").new()
		await g._startup_frame()
		g._timed_add(g.world, g.wine, "wine")
		g.wine.configure(g)
		SESSION_OPS.finish(diagnostic_wine)
	if not Engine.get_meta("upside_world_baseline",false):
		var diagnostic_upside_world := SESSION_OPS.begin(g, "upside_world", "create_and_configure")
		g.upside_world = preload("res://runtime/upside_world/UpsideWorldRuntime.gd").new()
		g.upside_world.configure(g)
		SESSION_OPS.finish(diagnostic_upside_world)
		await g._startup_frame()
		g._timed_add(g, g.upside_world, "upside_world")
	if not Engine.get_meta("arcade_baseline",false):
		var diagnostic_arcade := SESSION_OPS.begin(g, "arcade", "create_and_configure")
		g.arcade = preload("res://activities/arcade/ArcadeRuntime.gd").new()
		await g._startup_frame()
		g._timed_add(g.world, g.arcade, "arcade")
		g.arcade.configure(g)
		SESSION_OPS.finish(diagnostic_arcade)
	var diagnostic_robberies := SESSION_OPS.begin(g, "robberies", "create_and_configure")
	g.robberies = preload("res://runtime/Robberies.gd").new()
	if g.state.world_state.has("robberies") and not g.robberies.restore_snapshot(g.state.world_state.robberies): g.controller.block_saving("assaltos não restauraram")
	await g._startup_frame()
	g._timed_add(g.world, g.robberies, "robberies")
	g.robberies.configure(g)
	SESSION_OPS.finish(diagnostic_robberies)
	var diagnostic_arrival := SESSION_OPS.begin(g, "arrival", "create_and_configure")
	g.arrival = preload("res://runtime/Arrival.gd").new()
	g.arrival.configure(g)
	SESSION_OPS.finish(diagnostic_arrival)
	if g.state.world_state.has("arrival") and not g.arrival.restore_state(g.state.world_state.arrival): g.controller.block_saving("chegada não restaurou")
	await g._startup_frame()
	g._timed_add(g.world, g.arrival, "arrival")
	g.arrival.changed.connect(g.save_game)
	var diagnostic_garage_rewards := SESSION_OPS.begin(g, "garage_rewards", "create_and_configure")
	g.garage_rewards = preload("res://runtime/GarageRewards.gd").new()
	if g.state.world_state.has("garage_rewards") and not g.garage_rewards.restore_snapshot(g.state.world_state.garage_rewards): g.controller.block_saving("prêmios da garagem não restauraram")
	await g._startup_frame()
	g._timed_add(g.world, g.garage_rewards, "garage_rewards")
	g.garage_rewards.configure(g)
	SESSION_OPS.finish(diagnostic_garage_rewards)
	var diagnostic_police_motor_pool := SESSION_OPS.begin(g, "police_motor_pool", "create_and_configure")
	g.police_motor_pool = preload("res://runtime/PoliceMotorPool.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.police_motor_pool, "police_motor_pool")
	g.police_motor_pool.configure(g)
	SESSION_OPS.finish(diagnostic_police_motor_pool)
	var diagnostic_personal_car := SESSION_OPS.begin(g, "personal_car", "create_and_configure")
	g.personal_car = preload("res://runtime/PersonalCar.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.personal_car, "personal_car")
	g.personal_car.configure(g)
	SESSION_OPS.finish(diagnostic_personal_car)

## Jessica, Ato 1 da Helena, deserto, oficina do Maciota e mineração.
func _install_story_systems() -> void:
	var diagnostic_jessica := SESSION_OPS.begin(g, "jessica", "create_and_configure")
	g.jessica = preload("res://runtime/JessicaRuntime.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.jessica, "jessica")
	g.jessica.configure(g)
	SESSION_OPS.finish(diagnostic_jessica)
	var diagnostic_helena_act1 := SESSION_OPS.begin(g, "helena_act1", "create_and_configure")
	g.helena_act1 = preload("res://runtime/harbor_act1/HelenaAct1.gd").new()
	g._timed_add(g.world, g.helena_act1, "helena_act1")
	g.helena_act1.configure(g)
	SESSION_OPS.finish(diagnostic_helena_act1)
	var diagnostic_desert := SESSION_OPS.begin(g, "desert", "create_and_configure")
	g.desert = preload("res://runtime/desert/DesertRuntime.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.desert, "desert")
	g.desert.configure(g)
	SESSION_OPS.finish(diagnostic_desert)
	var diagnostic_maciota_workshop := SESSION_OPS.begin(g, "maciota_workshop", "create_and_configure")
	g.maciota_workshop = preload("res://runtime/MaciotaWorkshop.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.maciota_workshop, "maciota_workshop")
	g.maciota_workshop.configure(g)
	SESSION_OPS.finish(diagnostic_maciota_workshop)
	var diagnostic_mining := SESSION_OPS.begin(g, "mining", "create_and_configure")
	g.mining = preload("res://runtime/MiningRuntime.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.mining, "mining")
	g.mining.configure(g)
	SESSION_OPS.finish(diagnostic_mining)

## Vozes de diálogo e de fala; a ligação com V2Settings fica na sessão (ver _connect_voice_settings).
func _install_voices() -> void:
	g.dialogue_voice = AudioStreamPlayer.new()
	g.dialogue_voice.process_mode = Node.PROCESS_MODE_PAUSABLE
	g.dialogue_voice.bus = &"Dialogue" if AudioServer.get_bus_index("Dialogue") >= 0 else &"Master"
	await g._startup_frame()
	g._timed_add(g, g.dialogue_voice, "dialogue_voice")
	g.speech_voice = AudioStreamPlayer.new()
	g.speech_voice.process_mode = Node.PROCESS_MODE_PAUSABLE
	g.speech_voice.bus = g.dialogue_voice.bus
	await g._startup_frame()
	g._timed_add(g, g.speech_voice, "speech_voice")

## Transporte de passageiros, porto e cemitério, contêineres, carro-forte, inventário e roda de equipamento.
func _install_street_systems() -> void:
	var diagnostic_passenger_transport := SESSION_OPS.begin(g, "passenger_transport", "create_and_configure")
	g.passenger_transport = preload("res://runtime/PassengerTransport.gd").new()
	g.passenger_transport.configure(g)
	SESSION_OPS.finish(diagnostic_passenger_transport)
	await g._startup_frame()
	g._timed_add(g.world, g.passenger_transport, "passenger_transport")
	var diagnostic_urban_operations := SESSION_OPS.begin(g, "urban_operations", "create_and_configure")
	g.urban_operations = preload("res://gameplay/urban_v1/UrbanOperations.gd").new()
	g.urban_operations.configure(g)
	SESSION_OPS.finish(diagnostic_urban_operations)
	await g._startup_frame()
	g._timed_add(g.world, g.urban_operations, "urban_operations")
	if g.state.world_state.has("urban_operations") and not g.urban_operations.restore_snapshot(g.state.world_state.urban_operations): g.controller.block_saving("porto e cemitério não restauraram")
	var diagnostic_port_container_loot := SESSION_OPS.begin(g, "port_container_loot", "create_and_configure")
	g.port_container_loot = preload("res://gameplay/urban_v1/PortContainerLoot.gd").new()
	g.port_container_loot.configure(g)
	SESSION_OPS.finish(diagnostic_port_container_loot)
	await g._startup_frame()
	g._timed_add(g.world, g.port_container_loot, "port_container_loot")
	var diagnostic_armored_transport := SESSION_OPS.begin(g, "armored_transport", "create_and_configure")
	g.armored_transport = preload("res://gameplay/armored/ArmoredTransport.gd").new()
	g.armored_transport.configure(g)
	SESSION_OPS.finish(diagnostic_armored_transport)
	await g._startup_frame()
	g._timed_add(g.world, g.armored_transport, "armored_transport")
	var diagnostic_field_inventory := SESSION_OPS.begin(g, "field_inventory", "create_and_configure")
	g.field_inventory = preload("res://systems/inventory/FieldInventoryRuntime.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, g.field_inventory, "field_inventory")
	g.field_inventory.configure(g)
	SESSION_OPS.finish(diagnostic_field_inventory)
	g.equipment_wheel = preload("res://runtime/EquipmentWheel.gd").new()
	g.world.add_child(g.equipment_wheel)
	g.equipment_wheel.configure(g)

## Pesca e frio da serra (cada um com seu interruptor de linha de base).
func _install_optional_systems() -> void:
	if not Engine.get_meta("fishing_baseline",false):
		var diagnostic_fishing := SESSION_OPS.begin(g, "fishing", "create_and_configure")
		g.fishing = preload("res://activities/fishing/Fishing.gd").new()
		await g._startup_frame()
		g._timed_add(g.world, g.fishing, "fishing")
		g.fishing.configure(g)
		SESSION_OPS.finish(diagnostic_fishing)
		g.fishing_runtime = preload("res://runtime/FishingRuntime.gd").new()
		g.fishing_runtime.session = g
		await g._startup_frame()
		g._timed_add(g, g.fishing_runtime, "fishing_runtime")
	if not g.world.get_meta("skip_cold",false):
		var diagnostic_cold := SESSION_OPS.begin(g, "cold", "create_and_configure")
		g.cold = preload("res://runtime/ColdSurvival.gd").new()
		g.cold.configure(g)
		SESSION_OPS.finish(diagnostic_cold)
		if g.state.world_state.has("cold") and not g.cold.restore(g.state.world_state.cold): g.controller.block_saving("frio da serra não restaurou")
		await g._startup_frame()
		g._timed_add(g.world, g.cold, "cold")

## Ferrovia e ônibus regional com as interfaces.
func _install_transit() -> void:
	if "--railway-baseline" not in OS.get_cmdline_user_args():
		g.railway_world = preload("res://world/railway/RailwayWorld.gd").new()
		g.railway_world.configure(g.controller)
		await g._startup_frame()
		g._timed_add(g.world, g.railway_world, "railway_world")
		var diagnostic_railway := SESSION_OPS.begin(g, "railway", "create_and_configure")
		g.railway = preload("res://runtime/railway/RailwayTransit.gd").new()
		g.railway.name = "RailwayTransit"
		g.railway.configure(g)
		SESSION_OPS.finish(diagnostic_railway)
		await g._startup_frame()
		g._timed_add(g.world, g.railway, "railway")
		var railway_ui := preload("res://ui/railway/RailwayUI.gd").new()
		await g._startup_frame()
		g._timed_add(g.world, railway_ui, "railway_ui")
		railway_ui.configure(g.railway)
	var diagnostic_regional_coach := SESSION_OPS.begin(g, "regional_coach", "create_and_configure")
	g.regional_coach = preload("res://runtime/regional/RegionalCoachTransit.gd").new()
	g.regional_coach.name = "RegionalCoachTransit"
	g.regional_coach.configure(g)
	SESSION_OPS.finish(diagnostic_regional_coach)
	await g._startup_frame()
	g._timed_add(g.world, g.regional_coach, "regional_coach")
	var coach_ui := preload("res://ui/railway/RailwayUI.gd").new()
	await g._startup_frame()
	g._timed_add(g.world, coach_ui, "coach_ui")
	coach_ui.name = "RegionalCoachUI"
	coach_ui.configure(g.regional_coach)

## Sessão pronta: volta a processar e avisa quem espera (ProductionWorld aguarda startup_finished).
func _finish() -> void:
	g.startup_complete = true
	g.set_process(true)
	g.set_process_input(true)
	g.startup_finished.emit()
