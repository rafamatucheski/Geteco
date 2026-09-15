extends "res://world/harbor/HarborPreview.gd"
## Production entry point; the authored preview remains independently available.
var campaign_controller: Node
var loaded_from_save := false
var gameplay_ready := false
var _interior_check_elapsed := 0.0
var _last_room: Node2D
var restaurant_life: Node2D

func _enter_tree() -> void:
	review_mode = false
	var saves := get_node_or_null("/root/SaveManager")
	loaded_from_save = (saves != null and saves.has_pending_save()) or get_node("/root/RegionTravel").is_arriving()

func _ready() -> void:
	preload("res://world/harbor/urban_transit/UrbanTransit.gd").reserve_platform_spawns(self)
	super._ready()
	var hud := preload("res://HUD.tscn").instantiate()
	add_child(hud)
	# Review buttons can operate a parked vehicle remotely; not a campaign action.
	hud.get_node("RootMargin/VehicleTestPanel").hide()
	add_child(preload("res://ui/PauseMenu.tscn").instantiate())
	call_deferred("_start_gameplay")

func _start_gameplay() -> void:
	# Player's deferred save restore and the inherited world setup run first.
	# Um dia dura 24 minutos; refeições acompanham o relógio e a pausa do jogo.
	weather.day_length_seconds = 1440.0
	weather.is_dynamic_time = true
	weather.process_mode = Node.PROCESS_MODE_PAUSABLE
	var state := get_node("/root/CampaignState")
	state.set_campaign_flag(&"harbor_campaign_active", true)
	if not loaded_from_save:
		$Player.global_position = $ArrivalSpawn.global_position
		$Player.velocity = Vector2.ZERO
	_walk()
	$Player/Camera.reset_smoothing()
	$Player._refresh_weapon_ui()
	var wanted := get_node_or_null("/root/WantedManager")
	var hud := get_tree().get_first_node_in_group("hud")
	if wanted != null and hud != null:
		wanted.stars_changed.connect(hud.update_stars)
		if "current_stars" in wanted:
			hud.update_stars(wanted.current_stars)
	_restore_room_presentation()
	var soundscape := preload("res://world/harbor/HarborSoundscape.gd").new()
	soundscape.name = "HarborSoundscape"
	add_child(soundscape)
	$ArrivalStop.prepare_player($Player)
	campaign_controller = load("res://world/harbor/campaign/HarborArrivalMission.gd").new()
	campaign_controller.name = "ArrivalMission"
	add_child(campaign_controller)
	campaign_controller.configure(self)
	campaign_controller.start_or_resume()
	var city_audio := get_node_or_null("/root/CityAudioManager")
	if is_instance_valid(city_audio) and city_audio.has_method("set_active"):
		# Inicia só quando a campanha indica que a cena de chegada já terminou.
		city_audio.set_active(state.has_campaign_flag(&"harbor_arrival_seen"))
	var tutorials := preload("res://ui/tutorial_preview/GameplayTutorials.gd").new()
	tutorials.name = "GameplayTutorials"
	add_child(tutorials)
	var cobra_campaign := preload("res://world/harbor/campaign/CobraCampaignBridge.gd").new()
	cobra_campaign.name = "CobraCampaign"
	add_child(cobra_campaign)
	cobra_campaign.configure(self)
	var boss_reward := preload("res://world/harbor/campaign/CobraBossReward.gd").new()
	boss_reward.name = "CobraBossReward"
	add_child(boss_reward)
	boss_reward.configure(self, cobra_campaign.ledger)
	var aftermath := preload("res://world/harbor/campaign/CobraAftermath.gd").new()
	aftermath.name = "CobraAftermath"
	add_child(aftermath)
	aftermath.configure(self, cobra_campaign.ledger)
	$Interiors/InteriorSpaces.add_child(preload("res://world/harbor/PortBossGarage.gd").new())
	_spawn_world_extras()
	_spawn_police_manhole_sewer()
	_spawn_motorsport_weather()
	gameplay_ready = true
	add_child(preload("res://ui/ZoneEntryHUD.gd").new())
	var personal_car := preload("res://world/harbor/monaliza/PersonalCarManager.gd").new()
	personal_car.name = "PersonalCarManager"
	add_child(personal_car)
	var residences := preload("res://world/harbor/residences/ResidenceManager.gd").new()
	residences.name = "ResidencePrototype"
	add_child(residences)
	var stream := preload("res://world/harbor/ContinuousWorld.gd").new()
	stream.name = "ContinuousWorld"
	add_child(stream)
	var regional_coach := preload("res://world/shared/transit/HarborMountainCoachService.gd").new()
	regional_coach.name = "HarborMountainCoachService"
	add_child(regional_coach)
	regional_coach.configure(self, stream)
	var auto_service := preload("res://world/harbor/HarborAutoService.gd").new()
	auto_service.name = "PayNSpray"
	add_child(auto_service)
	var cemetery := preload("res://world/harbor/HarborCemetery.gd").new()
	cemetery.name = "Cemetery"
	cemetery.global_position = Vector2(-650, 1740)
	add_child(cemetery)
	var living_events := preload("res://world/harbor/events/HarborWorldEvents.gd").new()
	living_events.name = "WorldEvents"
	add_child(living_events)
	restaurant_life = preload("res://world/harbor/restaurants/HarborRestaurantLife.gd").new()
	add_child(restaurant_life)
	var robberies := preload("res://world/harbor/HarborRobberies.gd").new()
	robberies.name="Robberies"
	add_child(robberies)
	var clothing_shops := preload("res://world/harbor/HarborClothingShops.gd").new()
	clothing_shops.name="ClothingShops"
	add_child(clothing_shops)
	var urban_transit := preload("res://world/harbor/urban_transit/UrbanTransit.gd").new()
	urban_transit.name = "UrbanTransit"
	add_child(urban_transit)
	var minimap := preload("res://ui/HarborMinimap.gd").new()
	minimap.name = "Minimap"
	add_child(minimap)
	get_node("/root/RegionTravel").finish_arrival(self)
	var presentation := preload("res://ui/GameplayPresentation.gd").new()
	presentation.name = "GameplayPresentation"
	add_child(presentation)

## Desmanche, colecionáveis e zonas de drift — esta é a árvore que "Novo
## Jogo" realmente carrega (Main.tscn é legado, só usado por saves antigos).
## Coordenadas ancoradas em constantes reais do próprio código do harbor:
## HarborDistrict.LAND_BOUNDS (-100,-100,3300,2580), HarborWaterfront.SHIP_BOUNDS
## (3350,650,440,1500) + GANGWAY_BOUNDS (3130,1742,288,40), e
## CobraNeighborhood.CENTER/LAND (7700,1700) / (6510,960,2010,1450).
func _spawn_world_extras() -> void:
	const CHOP_SHOP_SCRIPT := preload("res://cars/ChopShopZone.gd")
	const COLLECTIBLE_SCRIPT := preload("res://economy/Collectible.gd")
	const DRIFT_ZONE_SCRIPT := preload("res://cars/DriftChallengeZone.gd")

	var chop_shop: Node2D = CHOP_SHOP_SCRIPT.new()
	chop_shop.name = "ChopShopZone"
	# Dedicated rural yard with its own gravel access off Memorial North.
	chop_shop.position = preload("res://cars/salvage/SalvageLocation.gd").HARBOR_CENTER
	add_child(chop_shop)

	# Prefixo "harbor_" pra nunca colidir com os IDs equivalentes plantados em
	# Main.tscn/CityDemo.gd (a árvore legada) — mesmo Player.collectibles_found
	# sendo uma lista só, sem essa separação os dois mundos podiam achar que um
	# achado já tinha sido pego no outro.
	# Esconderijos acessíveis: corredor de carga, fundos das casas e dos
	# prédios. Fora das vias, entradas e limites fechados; IDs preservam saves.
	var collectibles := [
		{"id": "harbor_col_navio_01", "pos": Vector2(3515, 1545), "label": "PISTA — CONVÉS DO CARGUEIRO"},
		{"id": "harbor_col_cobras_01", "pos": Vector2(7440, 1035), "label": "PISTA — COVIL DOS COBRAS"},
		{"id": "harbor_col_oeste_01", "pos": Vector2(555, 932), "label": "ACHADO — LIMITE OESTE"},
		{"id": "harbor_col_leste_01", "pos": Vector2(8480, 1440), "label": "ACHADO — LIMITE LESTE"},
		{"id": "harbor_col_norte_01", "pos": Vector2(1455, 22), "label": "ACHADO — LIMITE NORTE"},
		{"id": "harbor_col_sul_01", "pos": Vector2(2705, 1768), "label": "ACHADO — LIMITE SUL"},
	]
	for entry in collectibles:
		var item: Area2D = COLLECTIBLE_SCRIPT.new()
		item.collectible_id = entry["id"]
		item.flavor_label = entry["label"]
		item.position = entry["pos"]
		add_child(item)

	var drift_zones := [
		{"id": "harbor_westgate", "name": "PÁTIO WESTGATE", "pos": Vector2(750, 1900), "radius": 120.0, "reward_per_1000": 150},
		{"id": "harbor_cold_storage", "name": "PÁTIO DOS ARMAZÉNS", "pos": Vector2(2600, 1050), "radius": 130.0, "reward_per_1000": 200},
	]
	for zone_def in drift_zones:
		var zone: Node2D = DRIFT_ZONE_SCRIPT.new()
		zone.name = "DriftZone_%s" % String(zone_def["name"]).replace(" ", "_")
		zone.setup(zone_def)
		zone.position = zone_def["pos"]
		add_child(zone)

func _spawn_police_manhole_sewer() -> void:
	var sewer := preload("res://world/harbor/sewer/HarborManholeSewer.gd").new()
	sewer.name = "PoliceManholeSewer"
	# West sidewalk of Union Avenue, beside Harbor Patrol and outside both the
	# precinct footprint and the vehicle lanes.
	sewer.position = sewer.STREET_POSITION
	$Interiors/InteriorSpaces.add_child(sewer)

func _process(delta: float) -> void:
	# Seven room bounds, only five times a second: restore presentation on load
	# and clear interior camera/weather after a hospital respawn.
	if not gameplay_ready:
		return
	if is_instance_valid(restaurant_life):
		var camera := get_viewport().get_camera_2d()
		var focus: Vector2 = camera.get_screen_center_position() if camera else $Player.global_position
		restaurant_life.update_context(weather.time_of_day * 24.0, weather.get_rain_intensity(), focus, delta)
	_interior_check_elapsed += delta
	if _interior_check_elapsed >= 0.2:
		_interior_check_elapsed = 0.0
		_restore_room_presentation()

func _restore_room_presentation() -> void:
	$Interiors.garage_interior.restore_legacy_visitor($Player)
	var room: Node2D = null
	for candidate in $Interiors/InteriorSpaces.get_children():
		if candidate.has_method("contains_point") and candidate.contains_point($Player.global_position):
			room = candidate
			break
	if room == _last_room:
		return
	if is_instance_valid(_last_room):
		_last_room.set_npc_rendering_active(false)
	_last_room = room
	if room != null:
		room.set_npc_rendering_active(true)
		$Interiors._frame_interior_camera($Player, room.get_camera_rect())
	else:
		$Interiors._reset_exterior_camera($Player)
		if $Player.has_meta("harbor_interior"):
			$Player.remove_meta("harbor_interior")
			$Player.remove_meta("police_exterior_position")
	if weather.has_method("set_interior_mode"):
		weather.set_interior_mode(room != null)

func _spawn_motorsport_weather() -> void:
	add_child(preload("res://world/harbor/HarborRainPuddles.gd").new())
	# Gates lie on the authored street centerlines, clear of building footprints.
	for def in [
		{"id":"harbor_docks", "name":"VOLTA DO PORTO", "length_label":"CURTA", "start":Vector2(1100,2200), "checkpoints":[Vector2(2200,2130),Vector2(2270,1250),Vector2(3000,1320),Vector2(2930,2200)], "reward":400, "best_time_bonus":200},
		{"id":"harbor_foundry", "name":"CIRCUITO FOUNDRY", "length_label":"MÉDIA", "start":Vector2(400,1050), "checkpoints":[Vector2(470,400),Vector2(2200,470),Vector2(2130,1250),Vector2(400,1180)], "reward":650, "best_time_bonus":300}
	]:
		var race := preload("res://cars/NightRaceController.gd").new()
		race.setup(def)
		add_child(race)
