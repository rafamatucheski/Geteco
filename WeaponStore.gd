class_name WeaponStore
extends Area2D

var player: Node = null
var is_open := false
var prompt: Label
var panel: PanelContainer
var wallet_label: Label
var status_label: Label
var items_container: VBoxContainer
var canvas_layer: CanvasLayer

# Portas de correr
var door_left: Polygon2D
var door_right: Polygon2D
var is_door_open := false
var interior: AmmuNationInterior
const DOOR_INTERACTION_RADIUS := 118.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_storefront_visual()
	_build_ui()
	interior = AmmuNationInterior.new()
	add_child(interior)
	interior.exit_requested.connect(_close)

func _process(_delta: float) -> void:
	# Fallback intencional: a fachada pode cobrir parcialmente o Area2D.
	# A entrada continua funcionando pelo ponto central da porta.
	if player == null or not is_instance_valid(player):
		var candidate := get_tree().get_first_node_in_group("player")
		if candidate and candidate.global_position.distance_to(global_position) <= DOOR_INTERACTION_RADIUS:
			player = candidate
	if player == null or not is_instance_valid(player):
		if prompt: prompt.hide()
		if is_door_open:
			_set_doors_open(false)
		return
		
	# Verifica se o jogador está a pé
	var is_on_foot = not player.get_tree().get_nodes_in_group("vehicle").any(func(v): return v.get("is_driven_by_player") == true)
	
	if not is_on_foot:
		if prompt:
			prompt.text = "🛑 DESÇA DO VEÍCULO PARA ENTRAR"
			prompt.modulate = Color("ff7777")
			prompt.show()
		if is_door_open:
			_set_doors_open(false)
		return
	else:
		if prompt:
			prompt.text = "🔫 [E / F] AMMU-NATION"
			prompt.modulate = Color("ffe36b")
			prompt.visible = not is_open
		if not is_door_open:
			_set_doors_open(true)
		
	if not is_open and (Input.is_action_just_pressed("interact") or Input.is_key_pressed(KEY_F) or Input.is_key_pressed(KEY_ENTER)):
		_open()
	elif is_open:
		# Não teste E continuamente aqui: a mesma tecla que abre não pode fechar
		# a cena no frame seguinte enquanto o usuário ainda a mantém pressionada.
		if Input.is_action_just_pressed("interact") or Input.is_key_pressed(KEY_ESCAPE):
			_close()

func _set_doors_open(open_state: bool) -> void:
	is_door_open = open_state
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if door_left and door_right:
		# Porta de enrolar sobe para dentro da fachada; não são duas portas de vidro.
		var target_y = -30.0 if open_state else 0.0
		tween.tween_property(door_left, "position:y", target_y, 0.38)
		tween.tween_property(door_right, "position:y", target_y, 0.38)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player = body

func _on_body_exited(body: Node2D) -> void:
	if body == player:
		_close()
		player = null
		_set_doors_open(false)

func _open() -> void:
	if player == null:
		return
	is_open = true
	add_to_group("weapon_store_open")
	canvas_layer.show()
	panel.hide()
	interior.open_store(player)

func _close() -> void:
	is_open = false
	remove_from_group("weapon_store_open")
	if canvas_layer:
		canvas_layer.hide()
	if panel:
		panel.hide()
	if interior and interior.active:
		interior.close_store()

func _play_cash_audio() -> void:
	var p = AudioStreamPlayer.new()
	p.stream = ProceduralAudio.get_cash_register_stream()
	p.volume_db = -10.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _buy_weapon(id: String) -> void:
	if player != null and player.has_method("buy_weapon"):
		var msg: String = player.buy_weapon(id)
		if msg == "COMPRA REALIZADA":
			_play_cash_audio()
		_refresh(msg)

func _equip_weapon(id: String) -> void:
	if player != null and player.has_method("equip_weapon"):
		player.equip_weapon(id)
		_refresh("EQUIPADO")

func _buy_ammo(id: String, rounds: int, price: int) -> void:
	if player != null and player.has_method("buy_ammo_amount"):
		var msg: String = player.buy_ammo_amount(id, rounds, price)
		if msg == "MUNIÇÃO COMPRADA":
			_play_cash_audio()
		_refresh(msg)

func _buy_armor(amount: int, price: int) -> void:
	if player != null and player.has_method("buy_armor_amount"):
		var msg: String = player.buy_armor_amount(amount, price)
		if "EQUIPADO" in msg:
			_play_cash_audio()
		_refresh(msg)

func _refresh(notice: String = "") -> void:
	if player == null or wallet_label == null:
		return
		
	var money: int = int(player.get("money"))
	wallet_label.text = "💰 SEU SALDO:  $ %08d" % money
	
	if status_label:
		status_label.text = notice
		status_label.modulate = Color("ffe36b") if "COMPRA" in notice or "COLETE" in notice or "MUNIÇÃO" in notice or "EQUIPADO" in notice else Color("ff7777")
		
	for child in items_container.get_children():
		child.queue_free()
		
	var inventory: Dictionary = player.get("weapon_inventory") if player.get("weapon_inventory") else {}
	var ammo_dict: Dictionary = player.get("weapon_ammo") if player.get("weapon_ammo") else {}
	
	# Item 1: SMG
	var smg_owned: bool = (inventory.get("smg", false) == true)
	var smg_ammo: Dictionary = ammo_dict.get("smg", {})
	_create_weapon_card(
		"🔴 SUBMETRALHADORA SMG 9MM",
		"Arma Automática • Cadência Rápida • 30 Balas/Pente",
		smg_owned,
		int(smg_ammo.get("clip", 0)), int(smg_ammo.get("reserve", 0)),
		1200,
		"smg",
		60, 80,   # Parcial: 60 balas por $80
		240, 260  # Completa: 240 balas por $260
	)
	
	# Item 2: ESCOPETA 12G
	var rifle_ammo: Dictionary = ammo_dict.get("hunting_rifle", {})
	_create_weapon_card("PRESA DO INVERNO", "Rifle de caça encontrado na cabana", inventory.get("hunting_rifle", false) == true,
		int(rifle_ammo.get("clip", 0)), int(rifle_ammo.get("reserve", 0)), int(WeaponCatalog.get_weapon("hunting_rifle").price),
		"hunting_rifle", 10, 160, 35, 480)

	# Item 2: ESCOPETA 12G
	var shot_owned: bool = (inventory.get("shotgun", false) == true)
	var shot_ammo: Dictionary = ammo_dict.get("shotgun", {})
	_create_weapon_card(
		"🟠 ESCOPETA CALIBRE 12G",
		"Espalha 6 Balotes de Chumbo • Dano Letal de Perto",
		shot_owned,
		int(shot_ammo.get("clip", 0)), int(shot_ammo.get("reserve", 0)),
		1800,
		"shotgun",
		12, 120,  # Parcial: 12 cartuchos por $120
		48, 360   # Completa: 48 cartuchos por $360
	)
	
	# Item 3: PISTOLA 9MM
	var pist_ammo: Dictionary = ammo_dict.get("pistol", {})
	_create_weapon_card(
		"🟡 PISTOLA 9MM GLOCK",
		"Padrão • Precisa e Confiável • 12 Balas/Pente",
		true,
		int(pist_ammo.get("clip", 0)), int(pist_ammo.get("reserve", 0)),
		0,
		"pistol",
		24, 40,   # Parcial: 24 balas por $40
		120, 150  # Completa: 120 balas por $150
	)
	
	# Item 3.5: FACA DE COMBATE (corpo a corpo, sem municao pra comprar depois)
	var knife_owned: bool = (inventory.get("knife", false) == true)
	_create_melee_card(
		"🔪 FACA DE COMBATE",
		"Corpo a Corpo • Silenciosa • Sem Necessidade de Munição",
		knife_owned,
		350,
		"knife"
	)

	# Item 4: COLETE BALÍSTICO
	var cur_armor: int = int(player.get("armor"))
	_create_armor_card(cur_armor)

func _create_weapon_card(title: String, desc: String, owned: bool, clip: int, reserve: int, weapon_price: int, weapon_id: String, p_rounds: int, p_price: int, f_rounds: int, f_price: int) -> void:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.13, 0.94)
	style.border_color = Color(0.25, 0.30, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	row.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	row.add_child(vbox)
	
	var top_hbox := HBoxContainer.new()
	vbox.add_child(top_hbox)
	
	var lbl_title := Label.new()
	lbl_title.text = title
	lbl_title.add_theme_font_size_override("font_size", 16)
	lbl_title.add_theme_color_override("font_color", Color("ffe36b"))
	lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(lbl_title)
	
	var lbl_status := Label.new()
	lbl_status.text = "EQUIPADA: %d/%d" % [clip, reserve] if owned else "BLOQUEADA"
	lbl_status.add_theme_font_size_override("font_size", 13)
	lbl_status.add_theme_color_override("font_color", Color("78dcff") if owned else Color("ff7777"))
	top_hbox.add_child(lbl_status)
	
	var lbl_desc := Label.new()
	lbl_desc.text = desc
	lbl_desc.add_theme_font_size_override("font_size", 12)
	lbl_desc.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	vbox.add_child(lbl_desc)
	
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_hbox)
	
	if not owned:
		var btn_buy := Button.new()
		btn_buy.text = "🛒 COMPRAR ARMA  ($ %d)" % weapon_price
		if not player.is_weapon_shop_unlocked(weapon_id):
			btn_buy.disabled = true
			btn_buy.text = String(WeaponCatalog.get_weapon(weapon_id).get("discovery_hint", "BLOQUEADA"))
		btn_buy.custom_minimum_size = Vector2(200, 34)
		btn_buy.pressed.connect(func(): _buy_weapon(weapon_id))
		btn_hbox.add_child(btn_buy)
	else:
		var btn_partial := Button.new()
		btn_partial.text = "📦 MUNIÇÃO PARCIAL (+%d) $ %d" % [p_rounds, p_price]
		btn_partial.custom_minimum_size = Vector2(210, 32)
		btn_partial.pressed.connect(func(): _buy_ammo(weapon_id, p_rounds, p_price))
		btn_hbox.add_child(btn_partial)
		
		var btn_full := Button.new()
		btn_full.text = "⚡ MUNIÇÃO COMPLETA (+%d) $ %d" % [f_rounds, f_price]
		btn_full.custom_minimum_size = Vector2(230, 32)
		btn_full.pressed.connect(func(): _buy_ammo(weapon_id, f_rounds, f_price))
		btn_hbox.add_child(btn_full)
		
	items_container.add_child(row)

func _create_melee_card(title: String, desc: String, owned: bool, price: int, weapon_id: String) -> void:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.13, 0.94)
	style.border_color = Color(0.25, 0.30, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	row.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	row.add_child(vbox)

	var top_hbox := HBoxContainer.new()
	vbox.add_child(top_hbox)

	var lbl_title := Label.new()
	lbl_title.text = title
	lbl_title.add_theme_font_size_override("font_size", 16)
	lbl_title.add_theme_color_override("font_color", Color("ffe36b"))
	lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(lbl_title)

	var lbl_status := Label.new()
	lbl_status.text = "EQUIPADA" if owned else "BLOQUEADA"
	lbl_status.add_theme_font_size_override("font_size", 13)
	lbl_status.add_theme_color_override("font_color", Color("78dcff") if owned else Color("ff7777"))
	top_hbox.add_child(lbl_status)

	var lbl_desc := Label.new()
	lbl_desc.text = desc
	lbl_desc.add_theme_font_size_override("font_size", 12)
	lbl_desc.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	vbox.add_child(lbl_desc)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_hbox)

	if not owned:
		var btn_buy := Button.new()
		btn_buy.text = "🛒 COMPRAR  ($ %d)" % price
		btn_buy.custom_minimum_size = Vector2(200, 34)
		btn_buy.pressed.connect(func(): _buy_weapon(weapon_id))
		btn_hbox.add_child(btn_buy)
	else:
		var btn_equip := Button.new()
		btn_equip.text = "🔪 EQUIPAR"
		btn_equip.custom_minimum_size = Vector2(140, 34)
		btn_equip.pressed.connect(func(): _equip_weapon(weapon_id))
		btn_hbox.add_child(btn_equip)

	items_container.add_child(row)

func _create_armor_card(cur_armor: int) -> void:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.13, 0.94)
	style.border_color = Color(0.25, 0.30, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	row.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	row.add_child(vbox)
	
	var top_hbox := HBoxContainer.new()
	vbox.add_child(top_hbox)
	
	var lbl_title := Label.new()
	lbl_title.text = "🛡️ COLETE BALÍSTICO KEVLAR"
	lbl_title.add_theme_font_size_override("font_size", 16)
	lbl_title.add_theme_color_override("font_color", Color("ffe36b"))
	lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(lbl_title)
	
	var lbl_status := Label.new()
	lbl_status.text = "PROTEÇÃO ATUAL: %d%%" % cur_armor
	lbl_status.add_theme_font_size_override("font_size", 13)
	lbl_status.add_theme_color_override("font_color", Color("78dcff"))
	top_hbox.add_child(lbl_status)
	
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_hbox)
	
	var btn_half := Button.new()
	btn_half.text = "🛡️ COLETE 50% ($ 250)"
	btn_half.custom_minimum_size = Vector2(210, 32)
	btn_half.pressed.connect(func(): _buy_armor(50, 250))
	btn_hbox.add_child(btn_half)
	
	var btn_full := Button.new()
	btn_full.text = "🛡️ COLETE 100% ($ 500)"
	btn_full.custom_minimum_size = Vector2(230, 32)
	btn_full.pressed.connect(func(): _buy_armor(100, 500))
	btn_hbox.add_child(btn_full)
	
	items_container.add_child(row)

func _build_storefront_visual() -> void:
	# Fachada estilosa da Ammu-Nation
	var facade := Polygon2D.new()
	facade.polygon = PackedVector2Array([
		Vector2(-42, -54), Vector2(42, -54),
		Vector2(42, -18), Vector2(-42, -18)
	])
	facade.color = Color(0.12, 0.14, 0.16)
	facade.z_index = 10
	add_child(facade)
	
	# Moldura de Vidro da Entrada
	var door_frame := Polygon2D.new()
	door_frame.polygon = PackedVector2Array([
		Vector2(-20, -18), Vector2(20, -18),
		Vector2(20, 10), Vector2(-20, 10)
	])
	door_frame.color = Color(0.04, 0.05, 0.06, 0.9)
	door_frame.z_index = 10
	add_child(door_frame)
	
	# Duas lâminas de uma porta de enrolar, que sobem juntas.
	door_left = Polygon2D.new()
	door_left.polygon = PackedVector2Array([
		Vector2(-10, -16), Vector2(0, -16),
		Vector2(0, 8), Vector2(-10, 8)
	])
	door_left.color = Color(0.35, 0.45, 0.55, 0.85)
	door_left.z_index = 11
	add_child(door_left)
	
	door_right = Polygon2D.new()
	door_right.polygon = PackedVector2Array([
		Vector2(0, -16), Vector2(10, -16),
		Vector2(10, 8), Vector2(0, 8)
	])
	door_right.color = Color(0.35, 0.45, 0.55, 0.85)
	door_right.z_index = 11
	add_child(door_right)
	
	# Prompt flutuante
	prompt = Label.new()
	prompt.text = "[E] ENTRAR"
	prompt.position = Vector2(-100, -68)
	prompt.size = Vector2(200, 22)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 13)
	prompt.add_theme_color_override("font_color", Color("ffe36b"))
	prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt.add_theme_constant_override("outline_size", 4)
	prompt.z_index = 20
	prompt.hide()
	add_child(prompt)

func _build_ui() -> void:
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 60
	add_child(canvas_layer)
	
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.70)
	canvas_layer.add_child(dim)
	
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(680, 520)
	panel.position = Vector2(300, 100)
	panel.add_theme_stylebox_override("panel", _panel_style())
	canvas_layer.add_child(panel)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	
	var header := Label.new()
	header.text = "🎯 AMMU-NATION — ARMAS & MUNIÇÕES 🎯"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color("ffe36b"))
	header.add_theme_color_override("font_outline_color", Color.BLACK)
	header.add_theme_constant_override("outline_size", 4)
	vbox.add_child(header)
	
	wallet_label = Label.new()
	wallet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wallet_label.add_theme_font_size_override("font_size", 16)
	wallet_label.add_theme_color_override("font_color", Color("78dcff"))
	vbox.add_child(wallet_label)
	
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(status_label)
	
	items_container = VBoxContainer.new()
	items_container.add_theme_constant_override("separation", 8)
	vbox.add_child(items_container)
	
	var btn_close := Button.new()
	btn_close.text = "✖ FECHAR LOJA [ESC / E]"
	btn_close.custom_minimum_size = Vector2(0, 36)
	btn_close.pressed.connect(_close)
	vbox.add_child(btn_close)
	
	canvas_layer.hide()

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.98)
	style.border_color = Color("ffe36b")
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.8)
	style.shadow_size = 14
	return style
