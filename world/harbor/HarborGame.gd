extends "res://world/harbor/HarborPreview.gd"
## Production entry point; the authored preview remains independently available.
var campaign_controller: Node
var loaded_from_save := false
var gameplay_ready := false
var _interior_check_elapsed := 0.0
var _last_room: Node2D

func _enter_tree() -> void:
	review_mode = false
	var saves := get_node_or_null("/root/SaveManager")
	loaded_from_save = (saves != null and saves.has_pending_save()) or get_node("/root/RegionTravel").is_arriving()

func _ready() -> void:
	super._ready()
	var hud := preload("res://HUD.tscn").instantiate()
	add_child(hud)
	# Review buttons can operate a parked vehicle remotely; not a campaign action.
	hud.get_node("RootMargin/VehicleTestPanel").hide()
	add_child(preload("res://ui/PauseMenu.tscn").instantiate())
	call_deferred("_start_gameplay")

func _start_gameplay() -> void:
	# Player's deferred save restore and the inherited world setup run first.
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
	_spawn_world_extras()
	gameplay_ready = true
	var personal_car := preload("res://world/harbor/monaliza/PersonalCarManager.gd").new()
	personal_car.name = "PersonalCarManager"
	add_child(personal_car)
	var stream := preload("res://world/harbor/ContinuousWorld.gd").new()
	stream.name = "ContinuousWorld"
	add_child(stream)
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
	var robberies := preload("res://world/harbor/HarborRobberies.gd").new()
	robberies.name="Robberies"
	add_child(robberies)
	var clothing_shops := preload("res://world/harbor/HarborClothingShops.gd").new()
	clothing_shops.name="ClothingShops"
	add_child(clothing_shops)
	var minimap := preload("res://ui/HarborMinimap.gd").new()
	minimap.name = "Minimap"
	add_child(minimap)
	get_node("/root/RegionTravel").finish_arrival(self)

## Desmanche, colecionáveis e zonas de drift — esta é a árvore que "Novo
## Jogo" realmente carrega (Main.tscn é legado, só usado por saves antigos).
## Coordenadas ancoradas em constantes reais do próprio código do harbor:
## HarborDistrict.LAND_BOUNDS (-100,-100,3300,2580), HarborWaterfront.SHIP_BOUNDS
## (3350,650,440,1500) + GANGWAY_BOUNDS (3130,1742,288,40), e
## CobraNeighborhood.CENTER/LAND (7700,1700) / (6510,960,2010,1450).
func _spawn_world_extras() -> void:
	const CHOP_SHOP_SCRIPT := preload("res://ChopShopZone.gd")
	const COLLECTIBLE_SCRIPT := preload("res://Collectible.gd")
	const DRIFT_ZONE_SCRIPT := preload("res://DriftChallengeZone.gd")

	var chop_shop: Node2D = CHOP_SHOP_SCRIPT.new()
	chop_shop.name = "ChopShopZone"
	# Logo a sudeste da "CobraWorkshop" (oficina em Rect2(8230,1390,220,255)),
	# perto do cruzamento (8000,1700) da malha viária local.
	chop_shop.position = Vector2(8150, 1780)
	add_child(chop_shop)

	# Prefixo "harbor_" pra nunca colidir com os IDs equivalentes plantados em
	# Main.tscn/CityDemo.gd (a árvore legada) — mesmo Player.collectibles_found
	# sendo uma lista só, sem essa separação os dois mundos podiam achar que um
	# achado já tinha sido pego no outro.
	var collectibles := [
		{"id": "harbor_col_navio_01", "pos": Vector2(3450, 1760), "label": "PISTA — CONVÉS DO CARGUEIRO"},
		{"id": "harbor_col_cobras_01", "pos": Vector2(7550, 1550), "label": "PISTA — COVIL DOS COBRAS"},
		{"id": "harbor_col_oeste_01", "pos": Vector2(-60, 1200), "label": "ACHADO — LIMITE OESTE"},
		{"id": "harbor_col_leste_01", "pos": Vector2(8480, 1700), "label": "ACHADO — LIMITE LESTE"},
		{"id": "harbor_col_norte_01", "pos": Vector2(1500, -60), "label": "ACHADO — LIMITE NORTE"},
		{"id": "harbor_col_sul_01", "pos": Vector2(1500, 2450), "label": "ACHADO — LIMITE SUL"},
	]
	for entry in collectibles:
		var item: Area2D = COLLECTIBLE_SCRIPT.new()
		item.collectible_id = entry["id"]
		item.flavor_label = entry["label"]
		item.position = entry["pos"]
		add_child(item)

	var drift_zones := [
		{"name": "PÁTIO DA CHEGADA", "pos": Vector2(770, 1600), "radius": 95.0, "reward_per_1000": 150},
		{"name": "CURVA DA PONTE", "pos": Vector2(6280, -4430), "radius": 95.0, "reward_per_1000": 170},
		{"name": "RUA DOS COBRAS", "pos": Vector2(7700, 1550), "radius": 90.0, "reward_per_1000": 200},
	]
	for zone_def in drift_zones:
		var zone: Node2D = DRIFT_ZONE_SCRIPT.new()
		zone.name = "DriftZone_%s" % String(zone_def["name"]).replace(" ", "_")
		zone.setup(zone_def)
		zone.position = zone_def["pos"]
		add_child(zone)

func _process(delta: float) -> void:
	# Seven room bounds, only five times a second: restore presentation on load
	# and clear interior camera/weather after a hospital respawn.
	if not gameplay_ready:
		return
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
