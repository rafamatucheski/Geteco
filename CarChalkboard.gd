class_name CarChalkboard
extends Node2D

## A Lousa de Carros Encomendados (Gone in 60 Seconds + NFS Most Wanted Blacklist)
## Gerencia os 5 contratos de roubo de veículos da Zona 1 e o duelo contra o Don Hector (#5 da Blacklist).

signal vehicle_delivered(car_id: String, reward: int)
signal boss_duel_unlocked()

const ZONE_1_ORDERS := [
	{
		"id": "taxi_yellow",
		"name": "Táxi Metropolitano",
		"desc": "Carro de fuga anônimo para o desmanche.",
		"reward": 800,
		"location": "Avenida Central / Trânsito Urbano",
		"delivered": false
	},
	{
		"id": "sedan_classic",
		"name": "Sedan Premier 2.0 (Vinho)",
		"desc": "Carro executivo de fuga discreta.",
		"reward": 1200,
		"location": "Estacionamento do Banco Central",
		"delivered": false
	},
	{
		"id": "sport_coupe",
		"name": "Infernus GT Turbo",
		"desc": "Superesportivo de alta aceleração.",
		"reward": 2000,
		"location": "Frente da Loja de Roupas de Luxo",
		"delivered": false
	},
	{
		"id": "ambulance",
		"name": "Ambulância de Resgate",
		"desc": "Veículo de infiltração médica.",
		"reward": 1500,
		"location": "Pátio do Hospital Metropolitano",
		"delivered": false
	},
	{
		"id": "cobra_v8",
		"name": "Cobra V8 Custom (Don Hector)",
		"desc": "A máquina lendária dos Cobras de Ferro.",
		"reward": 2500,
		"location": "Cul-de-Sac dos Cobras de Ferro",
		"delivered": false
	}
]

var orders: Array = []
var delivered_count: int = 0
var boss_unlocked: bool = false
var is_ui_open: bool = false

var ui_layer: CanvasLayer
var panel: PanelContainer
var orders_vbox: VBoxContainer
var status_label: Label
var duel_btn: Button
var audio_player: AudioStreamPlayer2D

func _ready() -> void:
	add_to_group("car_chalkboard")
	z_index = 5
	position = Vector2(160, 780)
	
	orders = ZONE_1_ORDERS.duplicate(true)
	_build_world_prop()
	_build_ui()

func _build_world_prop() -> void:
	# Moldura de madeira da lousa
	var frame := Polygon2D.new()
	frame.polygon = PackedVector2Array([
		Vector2(-20, -15), Vector2(20, -15), Vector2(20, 15), Vector2(-20, 15)
	])
	frame.color = Color("#5d4037") # Madeira escura
	add_child(frame)
	
	# Lousa de ardósia escura
	var slate := Polygon2D.new()
	slate.polygon = PackedVector2Array([
		Vector2(-17, -12), Vector2(17, -12), Vector2(17, 12), Vector2(-17, 12)
	])
	slate.color = Color("#1e272e") # Ardósia negra
	add_child(slate)
	
	var label = Label.new()
	label.text = "📋 LOUSA"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-28, -8)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color("#ecf0f1"))
	add_child(label)
	
	var prompt = Label.new()
	prompt.name = "Prompt"
	prompt.text = "[E] LOUSA DE CARROS"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.position = Vector2(-50, -28)
	prompt.add_theme_font_size_override("font_size", 9)
	prompt.add_theme_color_override("font_color", Color("#f1c40f"))
	prompt.visible = false
	add_child(prompt)

	audio_player = AudioStreamPlayer2D.new()
	add_child(audio_player)

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 25
	add_child(ui_layer)

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(480, 360)
	panel.offset_left = -240.0
	panel.offset_top = -180.0
	panel.offset_right = 240.0
	panel.offset_bottom = 180.0
	panel.visible = false
	
	# Estilo lousa de giz elegante com borda de madeira
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#181c20")
	style.border_color = Color("#8d6e63")
	style.border_width_left = 6
	style.border_width_right = 6
	style.border_width_top = 6
	style.border_width_bottom = 6
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)

	var title = Label.new()
	title.text = "📋 LOUSA DE ENCOMENDAS (60 SEGUNDOS) - ZONA 1"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#f5f6fa"))
	main_vbox.add_child(title)

	var sep = HSeparator.new()
	main_vbox.add_child(sep)

	orders_vbox = VBoxContainer.new()
	orders_vbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(orders_vbox)

	var sep2 = HSeparator.new()
	main_vbox.add_child(sep2)

	# Seção Blacklist #5
	var bl_box = HBoxContainer.new()
	bl_box.alignment = BoxContainer.ALIGNMENT_CENTER

	status_label = Label.new()
	status_label.text = "★ BLACKLIST #5: DON HECTOR 'CASCAVEL' [BLOQUEADO: ENTREGUE 3 CARROS] ★"
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", Color("#e74c3c"))
	bl_box.add_child(status_label)
	main_vbox.add_child(bl_box)

	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 20)

	duel_btn = Button.new()
	duel_btn.text = "DESAFIAR DON HECTOR"
	duel_btn.disabled = true
	duel_btn.pressed.connect(_on_duel_pressed)
	btn_box.add_child(duel_btn)

	var close_btn = Button.new()
	close_btn.text = "FECHAR [ESC]"
	close_btn.pressed.connect(close_chalkboard)
	btn_box.add_child(close_btn)

	main_vbox.add_child(btn_box)
	panel.add_child(main_vbox)
	ui_layer.add_child(panel)

func _process(_delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player): return
	
	var dist = global_position.distance_to(player.global_position)
	var prompt = get_node_or_null("Prompt")
	if dist < 45.0 and not is_ui_open:
		if prompt: prompt.visible = true
		if Input.is_key_pressed(KEY_E):
			open_chalkboard()
	else:
		if prompt: prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if is_ui_open and event.is_action_pressed("ui_cancel"):
		close_chalkboard()

func open_chalkboard() -> void:
	is_ui_open = true
	panel.visible = true
	_refresh_orders_list()

func close_chalkboard() -> void:
	is_ui_open = false
	panel.visible = false

func _refresh_orders_list() -> void:
	for child in orders_vbox.get_children():
		child.queue_free()

	for order in orders:
		var row = HBoxContainer.new()
		var check = Label.new()
		check.text = " [X] " if order["delivered"] else " [ ] "
		check.add_theme_color_override("font_color", Color("#2ecc71") if order["delivered"] else Color("#7f8c8d"))
		check.add_theme_font_size_override("font_size", 11)
		row.add_child(check)

		var name_lbl = Label.new()
		name_lbl.text = "%s - $%d (%s)" % [order["name"], order["reward"], order["location"]]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 11)
		if order["delivered"]:
			name_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.65)) # Riscado/cinza
		else:
			name_lbl.add_theme_color_override("font_color", Color("#ecf0f1"))
		row.add_child(name_lbl)

		orders_vbox.add_child(row)

	# Atualiza status da Blacklist
	if delivered_count >= 3:
		boss_unlocked = true
		status_label.text = "★ BLACKLIST #5: DON HECTOR 'CASCAVEL' [PRONTO PARA O DUELO!] ★"
		status_label.add_theme_color_override("font_color", Color("#2ecc71"))
		duel_btn.disabled = false
	else:
		status_label.text = "★ BLACKLIST #5: DON HECTOR [ENTREGUE %d/3 CARROS PARA DESBLOQUEAR] ★" % delivered_count
		status_label.add_theme_color_override("font_color", Color("#e74c3c"))
		duel_btn.disabled = true

func try_deliver_vehicle(car: Node2D, player: Node2D) -> Dictionary:
	var car_type: String = ""
	var a_id = car.get("active_archetype_id")
	if a_id != null and not String(a_id).is_empty():
		car_type = String(a_id)
	else:
		var v_id = car.get("archetype_id")
		if v_id != null:
			car_type = String(v_id)
	if car_type.is_empty():
		if car.is_in_group("emergency_vehicle") and car.get("type") == 1:
			car_type = "ambulance"
		elif "is_police" in car:
			car_type = "police"
			
	for order in orders:
		if order["id"] == car_type and not order["delivered"]:
			order["delivered"] = true
			delivered_count += 1
			
			# Toca raspagem de giz na lousa
			_play_sfx(ProceduralAudio.get_chalk_scratch_stream(), 0.0)
			
			# Recompensa em dinheiro
			var reward: int = order["reward"]
			if "money" in player:
				player.money += reward
				if player.has_method("_refresh_weapon_ui"):
					player._refresh_weapon_ui()
					
			vehicle_delivered.emit(car_type, reward)
			
			if delivered_count >= 3 and not boss_unlocked:
				boss_unlocked = true
				boss_duel_unlocked.emit()
				
			return {"success": true, "name": order["name"], "reward": reward, "delivered_count": delivered_count}
			
	return {"success": false, "name": "", "reward": 0, "delivered_count": delivered_count}

func _on_duel_pressed() -> void:
	close_chalkboard()
	var mm = get_tree().get_first_node_in_group("mission_manager")
	if mm and mm.has_method("_start_boss_duel"):
		mm._start_boss_duel()

func _play_sfx(stream: AudioStream, volume: float) -> void:
	if not audio_player or not stream: return
	audio_player.stream = stream
	audio_player.volume_db = volume
	audio_player.play()
