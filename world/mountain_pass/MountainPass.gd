class_name MountainPass
extends Node2D

## MountainPass: Região 2 - Montanha, Floresta & Cume Congelado
## Entrada oficial pela segunda ponte no entroncamento norte do Harbor. Inclui:
## - A ponte estaiada original (HarborBridge) para teste contínuo
## - O 3D Summit SUV 4x4 (veículo dos Lobos de Gelo) estacionado pronto para pilotar
## - Túnel jogável com mecânica cutaway
## - Madeireira, lago e ponte pênsil pedestre que bloqueia carros
## - Caverna secreta com cache de armas raras
## - Subida de serra com hairpins e mirante para a cidade minúscula (Parallax)
## - Pista de gelo liso (Black Ice)
## - Clima de tempestade de gelo (granizo/nevasca) e medidor de frio/hipotermia
## - Bunker militar de radar no cume

const MountainAltitudeParallaxScript = preload("res://world/mountain_pass/MountainAltitudeParallax.gd")
const MountainPassRoadScript = preload("res://world/mountain_pass/MountainPassRoad.gd")
const MountainTunnelScript = preload("res://world/mountain_pass/MountainTunnel.gd")
const IceStormManagerScript = preload("res://world/mountain_pass/IceStormManager.gd")
const ColdSurvivalControllerScript = preload("res://world/mountain_pass/ColdSurvivalController.gd")
const ColdStatusHUDScript = preload("res://world/mountain_pass/ColdStatusHUD.gd")
const HARBOR_BRIDGE_SCRIPT = preload("res://world/harbor/HarborBridge.gd")
const MOUNTAIN_SUV_SCRIPT = preload("res://world/mountain_pass/MountainSUV.gd")
const PLAYER_SCRIPT := preload("res://Player.gd")
const MOUNTAIN_SCENERY_BUILDER := preload("res://world/mountain_pass/MountainSceneryBuilder.gd")
const MOUNTAIN_INTERIOR_MGR_SCRIPT := preload("res://world/mountain_pass/MountainInteriorManager.gd")

@export var connect_to_harbor: bool = true
@export var spawn_player_on_ready: bool = true
@export var spawn_suv_on_ready: bool = true
var streamed_region := false
var region_ready := false
var region_selected := true

var parallax: Node2D
var road: Node2D
var tunnel: Node2D
var bridge: Node2D
var storm_manager: Node2D
var cold_controller: Node
var cold_hud: CanvasLayer
var interior_manager: Node2D

var player_instance: Node2D
var suv_instance: Node2D
var main_camera: Camera2D

func _ready() -> void:
	if not streamed_region:
		var combat_effects := preload("res://world/shared/combat/WeaponEffects.gd").new()
		combat_effects.name = "WeaponEffects"
		add_child(combat_effects)
	var travel := get_node("/root/RegionTravel")
	if travel.is_arriving() or get_node("/root/SaveManager").has_pending_save():
		spawn_suv_on_ready = false
	await _setup_environment()
	if streamed_region: await get_tree().process_frame
	_setup_bridge()
	_setup_setpieces()
	if not streamed_region:
		# Na cena avulsa usamos o mesmo circuito em coordenadas da serra.
		# No mundo contínuo a ferrovia já pertence ao porto: não criar outro trem.
		var rail := preload("res://world/harbor/HarborRailLine.gd").new()
		rail.name = "RegionalFreightRail"
		rail.position = -preload("res://world/shared/rail/HarborMountainRailRoute.gd").MOUNTAIN_OFFSET
		add_child(rail)
	if streamed_region:
		await MOUNTAIN_SCENERY_BUILDER.build_streamed_scenery(self)
	else:
		await MOUNTAIN_SCENERY_BUILDER.build_full_scenery(self)
	_setup_weather_and_cold()
	cold_controller.cold_zone_y_threshold += global_position.y
	if streamed_region:
		cold_controller.set_player(player_instance)
		storm_manager.follow_target = player_instance
		await get_tree().process_frame
	if spawn_player_on_ready:
		_spawn_player_and_suv()
	var expedition := preload("res://world/mountain_pass/MountainExpedition.gd").new()
	expedition.name = "MountainExpedition"
	add_child(expedition)
	if streamed_region:
		while not expedition.region_ready: await get_tree().process_frame
	var settlement := preload("res://world/mountain_pass/MountainSettlement.gd").new()
	settlement.name = "MountainSettlement"
	add_child(settlement)
	if streamed_region:
		while not settlement.region_ready: await get_tree().process_frame
	var traffic := preload("res://world/mountain_pass/MountainTraffic.gd").new()
	traffic.name = "MountainTraffic"
	add_child(traffic)
	if streamed_region:
		while not traffic.region_ready: await get_tree().process_frame
	if spawn_player_on_ready:
		var hud := preload("res://HUD.tscn").instantiate()
		add_child(hud)
		hud.get_node("RootMargin/VehicleTestPanel").hide()
		add_child(preload("res://ui/PauseMenu.tscn").instantiate())
		call_deferred("_finish_region_arrival")
	region_ready = true

func _setup_environment() -> void:
	# 0. Gerenciador de Interiores da Montanha
	interior_manager = MOUNTAIN_INTERIOR_MGR_SCRIPT.new()
	interior_manager.name = "MountainInteriorManager"
	add_child(interior_manager)
	if streamed_region:
		while not interior_manager.region_ready: await get_tree().process_frame

	# 1. Parallax da Cidade Minúscula ao Fundo
	parallax = MountainAltitudeParallaxScript.new()
	parallax.name = "MountainAltitudeParallax"
	add_child(parallax)

	# 2. A Estrada Sinuosa da Serra (Spline Curve2D)
	road = MountainPassRoadScript.new()
	road.name = "MountainPassRoad"
	add_child(road)

	# 3. O Túnel Jogável com Cutaway
	tunnel = MountainTunnelScript.new()
	tunnel.name = "MountainTunnel"
	tunnel.position = Vector2(4950, 400)
	tunnel.set("tunnel_length", 850.0)
	tunnel.set("tunnel_width", 150.0)
	add_child(tunnel)

func _setup_bridge() -> void:
	# Instancia a ponte do Porto para continuidade direta (sem gatilho de ida para montanha)
	bridge = HARBOR_BRIDGE_SCRIPT.new()
	bridge.name = "HarborBridgeCrossing"
	bridge.set("is_in_mountain_pass", true)
	add_child(bridge)
	if connect_to_harbor:
		_build_harbor_return_trigger()

func _build_harbor_return_trigger() -> void:
	var return_crossing := Area2D.new()
	return_crossing.name = "HarborReturnCrossing"
	return_crossing.collision_layer = 0
	return_crossing.collision_mask = 1 | 2 | 4 | 8
	return_crossing.position = Vector2(2950.0, 400.0)
	
	var col := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(60.0, 220.0)
	col.shape = box
	return_crossing.add_child(col)
	
	return_crossing.body_entered.connect(_on_harbor_crossing_entered)
	add_child(return_crossing)

func _finish_region_arrival() -> void:
	get_node("/root/RegionTravel").finish_arrival(self)
	player_instance._refresh_weapon_ui()

func _on_harbor_crossing_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.velocity.x < 0:
		get_node("/root/RegionTravel").request("harbor", body)


func _setup_setpieces() -> void:
	var setpieces := Node2D.new()
	setpieces.name = "Setpieces"
	setpieces.z_index = 2
	add_child(setpieces)

	# A. Madeireira (Logging Camp) & Fogueira de Calor
	var sawmill := Node2D.new()
	sawmill.name = "LoggingCamp"
	sawmill.position = Vector2(6350, 560)
	setpieces.add_child(sawmill)

	# Fogueira / Ponto de Calor (heat_source)
	var campfire := Area2D.new()
	campfire.name = "CampfireHeatSource"
	campfire.position = Vector2(90, 20)
	campfire.add_to_group("heat_source")
	sawmill.add_child(campfire)

	var fire_col := CollisionShape2D.new()
	var fire_circ := CircleShape2D.new()
	fire_circ.radius = 240.0
	fire_col.shape = fire_circ
	campfire.add_child(fire_col)

	var fire_visual := Polygon2D.new()
	fire_visual.color = Color(1.0, 0.45, 0.1)
	fire_visual.polygon = PackedVector2Array([Vector2(-12, -12), Vector2(12, -12), Vector2(0, 18)])
	campfire.add_child(fire_visual)

	var fire_light := PointLight2D.new()
	fire_light.color = Color(1.0, 0.6, 0.2)
	fire_light.energy = 1.5
	fire_light.texture_scale = 2.2
	var fimg := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for fy in 64:
		for fx in 64:
			var d: float = Vector2(fx - 31.5, fy - 31.5).length()
			var a: float = clampf(1.0 - d / 31.5, 0.0, 1.0)
			fimg.set_pixel(fx, fy, Color(1, 1, 1, a * a))
	fire_light.texture = ImageTexture.create_from_image(fimg)
	campfire.add_child(fire_light)

	# B. Ponte Suspensa Estreita (Gorgeneck - Bloqueia carros, so pedestres)
	var footbridge := StaticBody2D.new()
	footbridge.name = "GorgeneckFootbridge"
	footbridge.position = Vector2(7050, 40)
	footbridge.collision_layer = 1
	footbridge.collision_mask = 0
	setpieces.add_child(footbridge)

	for ppos in [Vector2(-95, 0), Vector2(95, 0)]:
		var pcol := CollisionShape2D.new()
		var pcirc := CircleShape2D.new()
		pcirc.radius = 16.0
		pcol.shape = pcirc
		pcol.position = ppos
		footbridge.add_child(pcol)

	# C. Caverna Secreta com Cache de Armas (Cave Cache)
	var cave := Node2D.new()
	cave.name = "CaveCache"
	cave.position = Vector2(6200, -320)
	setpieces.add_child(cave)

	# D. Mirante da Serra com Vista Panoramica (Scenic Overlook)
	var overlook := Area2D.new()
	overlook.name = "ScenicOverlookArea"
	overlook.position = Vector2(7050, -1350)
	setpieces.add_child(overlook)

	var ocol := CollisionShape2D.new()
	var obox := RectangleShape2D.new()
	obox.size = Vector2(280, 200)
	ocol.shape = obox
	overlook.add_child(ocol)

	overlook.body_entered.connect(func(body: Node2D):
		if body == player_instance or (body.has_method("is_driving") and body.is_driving()):
			_set_camera_zoom(0.75)
	)
	overlook.body_exited.connect(func(_body: Node2D):
		_set_camera_zoom(1.0)
	)

	# E. Posto Militar do Cume (Altitude Outpost / Bunker de Radar)
	var bunker := Node2D.new()
	bunker.name = "AltitudeOutpostBunker"
	bunker.position = Vector2(6500, -2800)
	setpieces.add_child(bunker)

	var summit_fire := Area2D.new()
	summit_fire.name = "SummitCampfire"
	summit_fire.position = Vector2(-130, 20)
	summit_fire.add_to_group("heat_source")
	bunker.add_child(summit_fire)
	var s_col := CollisionShape2D.new()
	var s_circ := CircleShape2D.new()
	s_circ.radius = 240.0
	s_col.shape = s_circ
	summit_fire.add_child(s_col)

func _setup_weather_and_cold() -> void:
	# 1. Sistema Climático de Granizo / Nevasca
	storm_manager = IceStormManagerScript.new()
	storm_manager.name = "IceStormManager"
	storm_manager.set("current_state", 3) # ICE_RAIN_HAIL
	add_child(storm_manager)
	if streamed_region and not region_selected: storm_manager.set_sheltered(true)

	# 2. Controlador de Sobrevivência ao Frio
	cold_controller = ColdSurvivalControllerScript.new()
	cold_controller.name = "ColdSurvivalController"
	cold_controller.set("cold_zone_y_threshold", -1400.0) # Frio inicia na subida para a neve
	add_child(cold_controller)
	if streamed_region and not region_selected: cold_controller.set_process(false)

	# 3. HUD Térmico
	cold_hud = ColdStatusHUDScript.new()
	cold_hud.name = "ColdStatusHUD"
	cold_hud.visible = not streamed_region or region_selected
	add_child(cold_hud)

func _spawn_player_and_suv() -> void:
	# 1. Spawna o 3D Summit SUV 4x4 na ponte
	if spawn_suv_on_ready:
		suv_instance = MOUNTAIN_SUV_SCRIPT.new()
		suv_instance.name = "SummitSUV"
		suv_instance.position = Vector2(3350, 400) # Na ponte do Porto
		suv_instance.rotation = 0.0 # Apontando para o leste (em direção à montanha)
		add_child(suv_instance)

	# 2. Spawna Dante (Jogador)
	if PLAYER_SCRIPT:
		player_instance = CharacterBody2D.new()
		player_instance.name = "Player"
		player_instance.set_script(PLAYER_SCRIPT)
		player_instance.position = Vector2(3260, 400) # Atrás do carro na ponte
		player_instance.z_index = 10
		player_instance.collision_layer = 1 | 4
		player_instance.collision_mask = 7
		player_instance.add_to_group("pedestrian")
		player_instance.add_to_group("player")
		
		var p_col := CollisionShape2D.new()
		p_col.name = "Collision"
		var p_shape := CapsuleShape2D.new()
		p_shape.radius = 5.0
		p_shape.height = 16.0
		p_col.shape = p_shape
		player_instance.add_child(p_col)

		main_camera = Camera2D.new()
		main_camera.name = "Camera"
		main_camera.position_smoothing_enabled = true
		main_camera.position_smoothing_speed = 6.0
		player_instance.add_child(main_camera)
		
		add_child(player_instance)
		player_instance.sprite_3d_display.scale = Vector2.ONE * 0.34
		if cold_controller.has_method("set_player"):
			cold_controller.set_player(player_instance)
		storm_manager.set("follow_target", player_instance)

func _set_camera_zoom(target_zoom: float) -> void:
	var active_cam: Camera2D = get_viewport().get_camera_2d() if get_viewport() else null
	if active_cam == null:
		active_cam = main_camera
	if active_cam and is_instance_valid(active_cam):
		var tw := create_tween()
		tw.tween_property(active_cam, "zoom", Vector2(target_zoom, target_zoom), 0.8)


func _process(delta: float) -> void:
	if not region_ready or not region_selected: return
	if not is_instance_valid(player_instance):
		return
	var indoors := bool(player_instance.get_meta("mountain_interior", false)) or bool(player_instance.get_meta("harbor_interior",false))
	var underground: bool = tunnel.contains_actor(player_instance)
	var covered: bool = indoors or underground or bool(player_instance.get_meta("mountain_shelter", false))
	storm_manager.set_sheltered(covered)
	cold_controller.sheltered = covered
	cold_controller.weather_exposure = clampf(storm_manager.storm_intensity, 0.0, 1.0)
	var camera := get_viewport().get_camera_2d()
	if camera and camera.get_meta("mountain_fixed_framing", false):
		return
	if camera:
		if covered:
			camera.set_meta("mountain_zoom", 1.6 if indoors else 2.5)
		else:
			camera.remove_meta("mountain_zoom")
		if camera.get_script() == null:
			var target: float = float(camera.get_meta("mountain_zoom", 1.8))
			camera.zoom = camera.zoom.lerp(Vector2.ONE * target, 1.0 - exp(-5.0 * delta))

func restore_region_interior(actor: Node2D, data: Dictionary) -> void:
	cold_controller.current_temperature = clampf(float(data.get("temperature",100)),0,100)
	storm_manager.weather_clock = float(data.get("weather_clock",0))
	storm_manager.advance_weather(0)
	var id := StringName(data.get("interior", ""))
	var room: Node2D = interior_manager._interiors.get(id)
	if room == null: return
	var point: Array = data.get("exterior_return", [7350,730])
	interior_manager._actor_returns[actor] = Vector2(point[0],point[1])
	actor.set_meta("police_exterior_position", Vector2(point[0],point[1]))
	actor.set_meta("mountain_interior", true)
	actor.set_meta("mountain_interior_id", id)
	room.set_npc_rendering_active(true)
	if room.get("camera_3d") is Camera3D and room.get("sprite_3d") is Sprite2D:
		var helper := preload("res://world/mountain_pass/MountainInteriorActorScale.gd").new()
		interior_manager.add_child(helper)
		helper.configure(actor,room.camera_3d,room.sprite_3d)
		interior_manager._actor_scale_helpers[actor] = helper
