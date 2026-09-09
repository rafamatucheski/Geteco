class_name CarChalkboard
extends Node2D

## A Lousa de Carros Encomendados (Gone in 60 Seconds + NFS Most Wanted Blacklist)
## Gerencia os 5 contratos de roubo de veículos da Zona 1 e o duelo contra o Don Hector (#5 da Blacklist).

signal vehicle_delivered(car_id: String, reward: int)
signal boss_duel_unlocked()
signal dialogue_opened()
signal dialogue_closed()
signal mission_selected(mission_id: String)

@export var use_legacy_position: bool = true
var interaction_enabled: bool = true
var campaign_mode: bool = false
var campaign_missions: Array[Dictionary] = []

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
var orders_scroll: ScrollContainer
var orders_vbox: VBoxContainer
var status_label: Label
var nav_hint_label: Label
var duel_btn: Button
var board_title: Label
var audio_player: AudioStreamPlayer2D
var _close_btn: Button
var _locked_message_key: String = ""
var _locked_prompt: Label

func _ready() -> void:
	add_to_group("car_chalkboard")
	z_index = 5
	if use_legacy_position:
		position = Vector2(160, 780)
	
	orders = ZONE_1_ORDERS.duplicate(true)
	_build_world_prop()
	_build_ui()
	var settings := get_node_or_null("/root/SettingsManager")
	if settings and not settings.language_changed.is_connected(_on_language_changed):
		settings.language_changed.connect(_on_language_changed)

func _update_localized_texts() -> void:
	var is_en := TranslationServer.get_locale().begins_with("en")
	if is_instance_valid(nav_hint_label):
		nav_hint_label.text = "[ 🠅 🠇 / Mouse ] Choose    [ Enter / Click ] Accept    [ ESC ] Close" if is_en else "[ 🠅 🠇 / Mouse ] Escolher    [ Enter / Clique ] Aceitar    [ ESC ] Fechar"
	if is_instance_valid(_close_btn):
		_close_btn.text = tr("BOARD_CLOSE")
	if is_instance_valid(board_title):
		board_title.text = tr("BOARD_TITLE_MACIOTA") if campaign_mode else "📋 LOUSA DE ENCOMENDAS (60 SEGUNDOS) - ZONA 1"
	if is_instance_valid(status_label) and campaign_mode:
		status_label.text = tr("BOARD_STATUS_MACIOTA")

func _on_language_changed(_locale: String) -> void:
	_update_localized_texts()
	if is_ui_open:
		_refresh_orders_list()
		_focus_first_selectable()

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

	# Separate label so the legacy Zone1 prompt above is never mutated: the
	# locked-reason hint only ever appears when a caller opts in via
	# set_locked_message_key() (Harbor's board, before Maciota's contact ends).
	_locked_prompt = Label.new()
	_locked_prompt.name = "LockedPrompt"
	_locked_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locked_prompt.position = Vector2(-80, -28)
	_locked_prompt.add_theme_font_size_override("font_size", 9)
	_locked_prompt.add_theme_color_override("font_color", Color("#e57373"))
	_locked_prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	_locked_prompt.visible = false
	add_child(_locked_prompt)

	audio_player = AudioStreamPlayer2D.new()
	add_child(audio_player)

## Recomputes the panel's fixed rect (PRESET_CENTER + explicit offsets encode a
## fixed size) and pivot so scale-based open/close animation stays centered.
func _apply_panel_size(size: Vector2) -> void:
	panel.custom_minimum_size = size
	panel.offset_left = -size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_bottom = size.y * 0.5
	panel.pivot_offset = size * 0.5

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 25
	add_child(ui_layer)

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_panel_size(Vector2(640, 480))

	# Estilo lousa de ardósia com moldura de madeira, na mesma paleta do
	# prop físico do quadro no mundo (frame/slate acima) para textura coerente.
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#182026")
	style.border_color = Color("#5d4037")
	style.border_width_left = 10
	style.border_width_right = 10
	style.border_width_top = 10
	style.border_width_bottom = 10
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_color = Color(0, 0, 0, 0.65)
	style.shadow_size = 14
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)

	var title = Label.new()
	board_title = title
	title.text = "📋 LOUSA DE ENCOMENDAS (60 SEGUNDOS) - ZONA 1"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#f5f6fa"))
	main_vbox.add_child(title)

	var sep = HSeparator.new()
	main_vbox.add_child(sep)

	orders_scroll = ScrollContainer.new()
	orders_scroll.custom_minimum_size = Vector2(0, 260)
	orders_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	orders_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	orders_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	orders_scroll.follow_focus = true

	orders_vbox = VBoxContainer.new()
	orders_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orders_vbox.add_theme_constant_override("separation", 8)
	orders_scroll.add_child(orders_vbox)
	main_vbox.add_child(orders_scroll)

	var sep2 = HSeparator.new()
	main_vbox.add_child(sep2)

	# Seção Blacklist #5
	var bl_box = HBoxContainer.new()
	bl_box.alignment = BoxContainer.ALIGNMENT_CENTER

	status_label = Label.new()
	status_label.text = "★ BLACKLIST #5: DON HECTOR 'CASCAVEL' [BLOQUEADO: ENTREGUE 3 CARROS] ★"
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#e74c3c"))
	bl_box.add_child(status_label)
	main_vbox.add_child(bl_box)

	nav_hint_label = Label.new()
	nav_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav_hint_label.add_theme_font_size_override("font_size", 12)
	nav_hint_label.add_theme_color_override("font_color", Color("#95a5a6"))
	main_vbox.add_child(nav_hint_label)

	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 20)

	duel_btn = Button.new()
	duel_btn.text = "DESAFIAR DON HECTOR"
	duel_btn.disabled = true
	duel_btn.add_theme_font_size_override("font_size", 14)
	duel_btn.pressed.connect(_on_duel_pressed)
	btn_box.add_child(duel_btn)

	var close_btn = Button.new()
	close_btn.text = tr("BOARD_CLOSE")
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.custom_minimum_size = Vector2(160, 36)
	close_btn.pressed.connect(close_chalkboard)
	btn_box.add_child(close_btn)
	_close_btn = close_btn

	_update_localized_texts()

	main_vbox.add_child(btn_box)
	panel.add_child(main_vbox)
	ui_layer.add_child(panel)

## Called by the owning interior once, right after creating the board, to
## name the reason shown (both languages, live) while interaction_enabled is
## still false. Never unlocks anything by itself — purely informational.
func set_locked_message_key(key: String) -> void:
	_locked_message_key = key

func _process(_delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player): return

	var dist = global_position.distance_to(player.global_position)
	var prompt = get_node_or_null("Prompt")
	if interaction_enabled and dist < 45.0 and not is_ui_open:
		if prompt: prompt.visible = true
		if _locked_prompt: _locked_prompt.visible = false
	elif not interaction_enabled and dist < 45.0 and not is_ui_open and not _locked_message_key.is_empty():
		if prompt: prompt.visible = false
		if _locked_prompt:
			_locked_prompt.text = "🔒 " + tr(_locked_message_key)
			_locked_prompt.visible = true
	else:
		if prompt: prompt.visible = false
		if _locked_prompt: _locked_prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if is_ui_open and event.is_action_pressed("ui_cancel"):
		close_chalkboard()
		get_viewport().set_input_as_handled()
	elif interaction_enabled and not is_ui_open and event.is_action_pressed("interact") and not event.is_echo():
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if is_instance_valid(player) and global_position.distance_to(player.global_position) < 45.0:
			open_chalkboard()
			get_viewport().set_input_as_handled()

func open_chalkboard() -> void:
	if not interaction_enabled or is_ui_open:
		return
	is_ui_open = true
	panel.visible = true
	_refresh_orders_list()
	# Animação curta de abertura: a lousa "surge" em vez de simplesmente aparecer.
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.86, 0.86)
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.16)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18)
	_focus_first_selectable()
	dialogue_opened.emit()

func close_chalkboard() -> void:
	if not is_ui_open:
		return
	is_ui_open = false
	# Controle/foco do jogador voltam imediatamente; o fade é só cosmético.
	get_viewport().gui_release_focus()
	dialogue_closed.emit()
	var tw := create_tween().set_ease(Tween.EASE_IN)
	tw.tween_property(panel, "modulate:a", 0.0, 0.1)
	tw.tween_callback(func() -> void: panel.visible = false)

func _exit_tree() -> void:
	if is_ui_open:
		close_chalkboard()

func _focus_first_selectable() -> void:
	for child in orders_vbox.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			return

func configure_missions(missions: Array[Dictionary]) -> void:
	var first_activation := not campaign_mode
	campaign_mode = true
	campaign_missions = missions.duplicate(true)
	if is_instance_valid(board_title):
		board_title.text = tr("BOARD_TITLE_MACIOTA")
	if first_activation:
		_apply_panel_size(Vector2(680, 520))
	if is_ui_open:
		_refresh_orders_list()
		_focus_first_selectable()

## Concluída: título e descrição riscados (BBCode [s]), com um visto verde.
func _build_completed_row(title: String, desc: String) -> Control:
	var row := HBoxContainer.new()
	row.set_meta("board_row_state", "completed")
	var check := Label.new()
	check.text = " ✔ "
	check.add_theme_font_size_override("font_size", 14)
	check.add_theme_color_override("font_color", Color("#2ecc71"))
	row.add_child(check)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = "[s]%s[/s]\n[s][font_size=13]%s[/font_size][/s]" % [title, desc]
	text.add_theme_color_override("default_color", Color(0.6, 0.6, 0.6, 0.85))
	row.add_child(text)
	return row

## Bloqueada: título esmaecido com um cadeado e o motivo do bloqueio, sem
## permitir seleção (nem por mouse nem por teclado) até o requisito ser cumprido.
func _build_locked_row(title: String, desc: String, requirement: String) -> Control:
	var row := HBoxContainer.new()
	row.set_meta("board_row_state", "locked")
	var lock := Label.new()
	lock.text = " 🔒 "
	lock.add_theme_font_size_override("font_size", 14)
	lock.add_theme_color_override("font_color", Color("#7f8c8d"))
	row.add_child(lock)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color("#7f8c8d"))
	vbox.add_child(title_lbl)
	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))
	vbox.add_child(desc_lbl)
	if not requirement.is_empty():
		var req_lbl := Label.new()
		req_lbl.text = requirement
		req_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		req_lbl.add_theme_font_size_override("font_size", 13)
		req_lbl.add_theme_color_override("font_color", Color("#e8b44f"))
		vbox.add_child(req_lbl)
	row.add_child(vbox)
	return row

func _select_mission(mission_id: String) -> void:
	close_chalkboard()
	mission_selected.emit(mission_id)

func _refresh_orders_list() -> void:
	_update_localized_texts()
	for child in orders_vbox.get_children():
		orders_vbox.remove_child(child)
		child.queue_free()
	if campaign_mode:
		duel_btn.visible = false
		status_label.text = tr("BOARD_STATUS_MACIOTA")
		status_label.add_theme_color_override("font_color", Color("#e8b44f"))
		# Lista fixa e autorada (sem contratos gerados): cada missão aparece em um
		# de três estados — disponível (botão clicável), concluída (riscada) ou
		# bloqueada (mostra o motivo). Nunca inventa conteúdo para preencher a lista.
		for mission in campaign_missions:
			var title := String(mission.get("title", "Serviço"))
			var desc := String(mission.get("description", ""))
			var completed := bool(mission.get("completed", false))
			var enabled := bool(mission.get("enabled", false))
			var requirement := String(mission.get("requirement", ""))
			if completed:
				orders_vbox.add_child(_build_completed_row(title, desc))
			elif enabled:
				var button := Button.new()
				button.text = "%s\n%s" % [title, desc]
				button.focus_mode = Control.FOCUS_ALL
				button.add_theme_font_size_override("font_size", 15)
				button.custom_minimum_size = Vector2(0, 56)
				button.pressed.connect(_select_mission.bind(String(mission.get("id", ""))))
				orders_vbox.add_child(button)
			else:
				orders_vbox.add_child(_build_locked_row(title, desc, requirement))
		if campaign_missions.is_empty():
			var notice := Label.new()
			notice.text = tr("BOARD_NO_SERVICES")
			orders_vbox.add_child(notice)
		return

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
