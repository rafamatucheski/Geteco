class_name MissionManager
extends Node2D

## Gerenciador de Missões e Contratos de Gangue
## Controla o Orelhão de Contato do Mercado Velho, Objetivos HUD, Perseguições e Recompensas.

enum MissionState { INACTIVE, BRIEFING, STEAL_VEHICLE, DELIVER_VEHICLE, COMPLETED, FAILED }

var current_state: MissionState = MissionState.INACTIVE
var active_mission_id: String = ""

# Posições de Missão
var payphone_pos: Vector2 = Vector2(320, 240)
var cobra_hideout_pos: Vector2 = Vector2(610, 195)
var docks_garage_pos: Vector2 = Vector2(268, 880)

# Instâncias Ativas da Missão
var target_car: Node2D = null
var gang_guards: Array[Node2D] = []
var chase_cars: Array[Node2D] = []

# Componentes de UI e Marcadores
var payphone_marker: Node2D = null
var hud_layer: CanvasLayer = null
var banner_panel: PanelContainer = null
var objective_label: Label = null
var subtitle_label: Label = null
var waypoint_marker: Polygon2D = null
var audio_player: AudioStreamPlayer2D = null

func _ready() -> void:
	add_to_group("mission_manager")
	z_index = 20
	_build_hud()
	_create_payphone_prop()
	_create_waypoint_marker()

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 15
	add_child(hud_layer)

	banner_panel = PanelContainer.new()
	banner_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner_panel.offset_top = 18.0
	banner_panel.offset_bottom = 78.0
	banner_panel.offset_left = 220.0
	banner_panel.offset_right = -220.0
	banner_panel.visible = false
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.08, 0.08, 0.10, 0.90)
	style_box.border_color = Color("#800000") # Vermelho Cobras de Ferro
	style_box.border_width_left = 3
	style_box.border_width_right = 3
	style_box.border_width_top = 3
	style_box.border_width_bottom = 3
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	banner_panel.add_theme_stylebox_override("panel", style_box)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	objective_label = Label.new()
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.add_theme_font_size_override("font_size", 16)
	objective_label.add_theme_color_override("font_color", Color("#f1c40f"))
	vbox.add_child(objective_label)

	subtitle_label = Label.new()
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 12)
	subtitle_label.add_theme_color_override("font_color", Color("#d2dae2"))
	vbox.add_child(subtitle_label)

	banner_panel.add_child(vbox)
	hud_layer.add_child(banner_panel)

	audio_player = AudioStreamPlayer2D.new()
	audio_player.max_distance = 800.0
	add_child(audio_player)

func _create_payphone_prop() -> void:
	payphone_marker = Node2D.new()
	payphone_marker.name = "OldMarketPayphone"
	payphone_marker.global_position = payphone_pos
	
	# Base da Cabine Telefônica
	var booth = Polygon2D.new()
	booth.polygon = PackedVector2Array([
		Vector2(-10, -12), Vector2(10, -12), Vector2(10, 12), Vector2(-10, 12)
	])
	booth.color = Color("#e74c3c") # Vermelho clássico
	payphone_marker.add_child(booth)

	var glass = Polygon2D.new()
	glass.polygon = PackedVector2Array([
		Vector2(-7, -9), Vector2(7, -9), Vector2(7, 3), Vector2(-7, 3)
	])
	glass.color = Color(0.2, 0.8, 1.0, 0.75)
	payphone_marker.add_child(glass)

	# Ícone 📞 Flutuante com pulso
	var phone_icon = Label.new()
	phone_icon.text = "📞"
	phone_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phone_icon.position = Vector2(-14, -38)
	payphone_marker.add_child(phone_icon)

	var prompt_label = Label.new()
	prompt_label.name = "Prompt"
	prompt_label.text = "[E] ATENDER"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.position = Vector2(-42, -54)
	prompt_label.add_theme_font_size_override("font_size", 11)
	prompt_label.add_theme_color_override("font_color", Color("#f1c40f"))
	prompt_label.visible = false
	payphone_marker.add_child(prompt_label)

	add_child(payphone_marker)

	# Efeito de brilho pulsante no orelhão
	var tw = create_tween().set_loops()
	tw.tween_property(phone_icon, "position:y", -42.0, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(phone_icon, "position:y", -34.0, 0.7).set_trans(Tween.TRANS_SINE)

func _create_waypoint_marker() -> void:
	waypoint_marker = Polygon2D.new()
	waypoint_marker.name = "MissionWaypoint"
	waypoint_marker.polygon = PackedVector2Array([
		Vector2(-14, -14), Vector2(14, -14), Vector2(0, 18)
	])
	waypoint_marker.color = Color("#f1c40f")
	waypoint_marker.visible = false
	waypoint_marker.z_index = 25
	add_child(waypoint_marker)

	var tw = create_tween().set_loops()
	tw.tween_property(waypoint_marker, "scale", Vector2(1.2, 1.2), 0.5)
	tw.tween_property(waypoint_marker, "scale", Vector2(0.9, 0.9), 0.5)

var _phone_ring_timer: float = 0.0

func _process(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return

	# Lógica do Orelhão / Toque de Telefone no Mercado Velho
	if current_state == MissionState.INACTIVE:
		var dist_phone = player.global_position.distance_to(payphone_pos)
		var prompt = payphone_marker.get_node_or_null("Prompt")
		if dist_phone < 50.0:
			if prompt: prompt.visible = true
			if Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_E):
				_start_cobra_mission(player)
		else:
			if prompt: prompt.visible = false
			
		# Toca o som do orelhão se estiver perto
		if dist_phone < 250.0:
			_phone_ring_timer -= delta
			if _phone_ring_timer <= 0.0:
				_phone_ring_timer = 3.5
				_play_sfx(ProceduralAudio.get_phone_ring_stream(), -6.0)

	elif current_state == MissionState.STEAL_VEHICLE:
		if is_instance_valid(target_car):
			waypoint_marker.visible = true
			waypoint_marker.global_position = target_car.global_position + Vector2(0, -42)
			
			# Detecta se Dante entrou no Cobra V8
			if target_car.get("is_driven_by_player") == true:
				_on_vehicle_stolen()
		else:
			waypoint_marker.visible = false

	elif current_state == MissionState.DELIVER_VEHICLE:
		if is_instance_valid(target_car):
			waypoint_marker.visible = true
			waypoint_marker.global_position = docks_garage_pos + Vector2(0, -32)
			
			# Detecta se o carro chegou na Garagem das Docas
			var dist_garage = target_car.global_position.distance_to(docks_garage_pos)
			if dist_garage < 75.0 and target_car.get("is_driven_by_player") == true:
				_complete_cobra_mission(player)
		else:
			_fail_mission("O COBRA V8 FOI DESTRUÍDO!")

func _start_cobra_mission(player: Node2D) -> void:
	active_mission_id = "steal_cobra_v8"
	current_state = MissionState.STEAL_VEHICLE
	_play_sfx(ProceduralAudio.get_mission_start_stream(), 0.0)

	banner_panel.visible = true
	objective_label.text = "MISSÃO: O DON E O COBRA V8"
	subtitle_label.text = "Invada o pátio do Mercado Velho e roube o Cobra V8 Custom!"

	# 1. Spawna o Cobra V8 Custom no pátio do Mercado Velho
	_spawn_target_car()

	# 2. Spawna 3 Capangas dos Cobras de Ferro guardando o carro
	_spawn_cobra_guards()

func _spawn_target_car() -> void:
	var car_scene = load("res://city_demo/scenes/TrafficVehicle.tscn")
	if car_scene:
		target_car = car_scene.instantiate()
	else:
		push_error("MissionManager: TrafficVehicle.tscn não pôde ser carregado")
		return
		
	target_car.global_position = cobra_hideout_pos
	target_car.rotation = -PI * 0.5 # Apontado para a saída do beco
	target_car.set("archetype_id", "cobra_v8")
	target_car.set("vehicle_color", Color("#1a0505"))
	get_parent().add_child(target_car)

func _spawn_cobra_guards() -> void:
	for i in range(3):
		var guard = IronCobraMember.new()
		var offset = Vector2.RIGHT.rotated(i * (PI * 0.65)) * 48.0
		guard.global_position = cobra_hideout_pos + offset
		guard.guard_center = cobra_hideout_pos
		get_parent().add_child(guard)
		gang_guards.append(guard)

func _on_vehicle_stolen() -> void:
	current_state = MissionState.DELIVER_VEHICLE
	objective_label.text = "FUGA: ENTREGUE O COBRA V8"
	subtitle_label.text = "Despiste os reforços e leve o carro até a Garagem das Docas!"
	
	# Alert de fala dos capangas sobreviventes
	for guard in gang_guards:
		if is_instance_valid(guard) and guard.has_method("_shout_gang_bark"):
			guard._shout_gang_bark()

func _complete_cobra_mission(player: Node2D) -> void:
	current_state = MissionState.COMPLETED
	waypoint_marker.visible = false
	
	_play_sfx(ProceduralAudio.get_mission_passed_stream(), 2.0)
	
	# Recompensa em Dinheiro e Desbloqueio
	if "money" in player:
		player.money += 2500
		if player.has_method("_refresh_weapon_ui"):
			player._refresh_weapon_ui()

	var gm = get_node_or_null("/root/GangManager")
	if gm:
		gm.unlock_gang_car("cobra_v8")
		gm.modify_respect("iron_cobras", -25)
		gm.modify_respect("dock_syndicate", 35)

	# Banner Vitória
	objective_label.text = "★ MISSÃO CUMPRIDA! ★"
	objective_label.add_theme_color_override("font_color", Color("#2ecc71"))
	subtitle_label.text = "+$2.500 | COBRA V8 DESBLOQUEADO NA GARAGEM DAS DOCAS!"
	
	var tw = create_tween()
	tw.tween_interval(6.0)
	tw.tween_callback(func():
		banner_panel.visible = false
		current_state = MissionState.INACTIVE
	)

func _fail_mission(reason: String) -> void:
	current_state = MissionState.FAILED
	waypoint_marker.visible = false
	objective_label.text = "MISSÃO FALHOU"
	objective_label.add_theme_color_override("font_color", Color("#e74c3c"))
	subtitle_label.text = reason
	
	var tw = create_tween()
	tw.tween_interval(4.0)
	tw.tween_callback(func():
		banner_panel.visible = false
		current_state = MissionState.INACTIVE
	)

func _start_boss_duel() -> void:
	active_mission_id = "blacklist_5_don_hector"
	current_state = MissionState.STEAL_VEHICLE
	_play_sfx(ProceduralAudio.get_mission_start_stream(), 2.0)
	
	banner_panel.visible = true
	objective_label.text = "★ DUELO DA BLACKLIST #5: DON HECTOR ★"
	objective_label.add_theme_color_override("font_color", Color("#e74c3c"))
	subtitle_label.text = "Destrua ou capture o Cobra V8 Boss do Don Hector na Avenida Principal!"
	
	# Spawna o Don Hector e seu carro de racha no centro da avenida
	var boss_spawn_pos := Vector2(870, 280)
	var car_scene = load("res://city_demo/scenes/TrafficVehicle.tscn")
	if car_scene:
		target_car = car_scene.instantiate()
		target_car.global_position = boss_spawn_pos
		target_car.rotation = PI * 0.5
		target_car.set("archetype_id", "cobra_v8")
		target_car.set("vehicle_color", Color("#0f0f12"))
		target_car.set("has_nitro", false)
		target_car.set("has_neon", true)
		target_car.set("neon_color", Color("#ff4757"))
		target_car.set("health", 250) # Boss HP elevado
		get_parent().add_child(target_car)
		
	waypoint_marker.visible = true
	waypoint_marker.global_position = boss_spawn_pos

func _complete_boss_duel() -> void:
	current_state = MissionState.COMPLETED
	waypoint_marker.visible = false
	_play_sfx(ProceduralAudio.get_mission_passed_stream(), 3.0)
	
	var player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and "money" in player:
		player.money += 5000
		if player.has_method("_refresh_weapon_ui"):
			player._refresh_weapon_ui()
			
	var vum = get_tree().get_first_node_in_group("vehicle_upgrade_manager")
	if vum:
		vum.unlock_next_zone_upgrades(1)
		
	objective_label.text = "★ BLACKLIST #5 DERROTADO! ★"
	objective_label.add_theme_color_override("font_color", Color("#2ecc71"))
	subtitle_label.text = "+$5.000 | PINK SLIP CONQUISTADO | ZONA 2 DESBLOQUEADA!"
	
	var tw = create_tween()
	tw.tween_interval(7.0)
	tw.tween_callback(func():
		banner_panel.visible = false
		current_state = MissionState.INACTIVE
	)

func _play_sfx(stream: AudioStream, volume: float) -> void:
	if not audio_player or not stream: return
	audio_player.stream = stream
	audio_player.volume_db = volume
	audio_player.play()
