class_name ClothingStore
extends CanvasLayer

signal store_closed

var shopper: Node = null
var is_active: bool = false
var selected_outfit_id: String = "dante_classic"
var current_filter: String = "Todos"

var preview_3d: CharacterPreview3D
var outfit_list_vbox: VBoxContainer
var name_label: Label
var district_label: Label
var desc_label: Label
var price_label: Label
var action_button: Button
var wallet_label: Label
var notice_label: Label
var filter_buttons: Dictionary = {}

func _ready() -> void:
	layer = 65
	_build_ui()
	hide()

func open_store(player: Node) -> void:
	shopper = player
	is_active = true
	show()
	if shopper:
		selected_outfit_id = String(shopper.get("current_outfit_id"))
		if selected_outfit_id.is_empty():
			selected_outfit_id = "dante_classic"
	_select_outfit(selected_outfit_id)
	_refresh_wallet()
	_populate_outfit_list()
	_show_notice("BEM-VINDO À BOUTIQUE! EXPERIMENTE OS TRAJES DOS 5 DISTRITOS.")

func close_store() -> void:
	is_active = false
	hide()
	store_closed.emit()

func _input(event: InputEvent) -> void:
	if not is_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			close_store()
			get_viewport().set_input_as_handled()

func _select_outfit(outfit_id: String) -> void:
	selected_outfit_id = outfit_id
	var data := OutfitCatalog.get_outfit(outfit_id)
	if preview_3d:
		preview_3d.set_outfit(outfit_id)
	
	if name_label:
		name_label.text = data.get("name", "")
	if district_label:
		district_label.text = "📍 DISTRITO: " + data.get("district", "")
	if desc_label:
		desc_label.text = data.get("description", "") + "\n\nPROTEÇÃO CONTRA O FRIO: %d%%\nReduz a perda de temperatura. Não recupera calor." % roundi(OutfitCatalog.cold_protection(outfit_id)*100)
	
	var price: int = int(data.get("price", 0))
	var is_owned: bool = _is_outfit_owned(outfit_id)
	var is_equipped: bool = _is_outfit_equipped(outfit_id)

	if price_label:
		if is_equipped:
			price_label.text = "STATUS: [EQUIPADO]"
			price_label.add_theme_color_override("font_color", Color("2ed573"))
		elif is_owned:
			price_label.text = "STATUS: [ADQUIRIDO NO GUARDA-ROUPA]"
			price_label.add_theme_color_override("font_color", Color("70a1ff"))
		else:
			price_label.text = "VALOR: $ %d" % price
			price_label.add_theme_color_override("font_color", Color("ffa502"))

	if action_button:
		if is_equipped:
			action_button.text = "EQUIPADO ATUALMENTE"
			action_button.disabled = true
		elif is_owned:
			action_button.text = "EQUIPAR ESTE TRAJE"
			action_button.disabled = false
		else:
			action_button.text = "COMPRAR POR $ %d" % price
			action_button.disabled = false

func _on_action_pressed() -> void:
	if not shopper or not is_instance_valid(shopper):
		return
	var data := OutfitCatalog.get_outfit(selected_outfit_id)
	var price: int = int(data.get("price", 0))
	var is_owned: bool = _is_outfit_owned(selected_outfit_id)

	if is_owned:
		if shopper.has_method("apply_outfit"):
			shopper.apply_outfit(selected_outfit_id)
		_show_notice("TRAJE '" + String(data.get("name", "")) + "' EQUIPADO COM SUCESSO!")
		_play_click_audio()
	else:
		var current_money: int = int(shopper.get("money"))
		if current_money < price:
			_show_notice("DINHEIRO INSUFICIENTE! VOCÊ PRECISA DE $ " + str(price))
			_play_error_audio()
			return
		
		# Efetua a compra
		shopper.set("money", current_money - price)
		var owned_dict: Dictionary = shopper.get("owned_outfits")
		owned_dict[selected_outfit_id] = true
		shopper.set("owned_outfits", owned_dict)
		if shopper.has_method("apply_outfit"):
			shopper.apply_outfit(selected_outfit_id)
		
		_show_notice("COMPROU E EQUIPOU: " + String(data.get("name", "")) + "!")
		_play_cash_audio()

	_refresh_wallet()
	_select_outfit(selected_outfit_id)
	_populate_outfit_list()

func _is_outfit_owned(outfit_id: String) -> bool:
	if outfit_id == "dante_classic":
		return true
	if shopper:
		var owned: Dictionary = shopper.get("owned_outfits")
		return owned.get(outfit_id, false) == true
	return false

func _is_outfit_equipped(outfit_id: String) -> bool:
	if shopper:
		return String(shopper.get("current_outfit_id")) == outfit_id
	return false

func _refresh_wallet() -> void:
	if wallet_label and shopper:
		wallet_label.text = "$ %08d" % int(shopper.get("money"))

func _show_notice(text: String) -> void:
	if notice_label:
		notice_label.text = text

func _populate_outfit_list() -> void:
	if not outfit_list_vbox:
		return
	for child in outfit_list_vbox.get_children():
		child.queue_free()

	var all_outfits := OutfitCatalog.get_all_outfits()
	for data in all_outfits:
		var district: String = data.get("district", "")
		if current_filter != "Todos" and district != current_filter:
			continue
		
		var id: String = data.get("id", "")
		var is_selected: bool = id == selected_outfit_id
		var is_owned: bool = _is_outfit_owned(id)
		var is_equipped: bool = _is_outfit_equipped(id)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 52)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		var prefix := " [✓] " if is_equipped else (" [★] " if is_owned else " [$] ")
		var price_str := "GRÁTIS" if int(data.get("price", 0)) == 0 else ("$ " + str(data.get("price", 0)))
		btn.text = prefix + String(data.get("name", "")) + " (" + price_str + ")\n   " + district
		
		if is_selected:
			btn.add_theme_color_override("font_color", Color("f39c12"))
		elif is_equipped:
			btn.add_theme_color_override("font_color", Color("2ed573"))
		elif is_owned:
			btn.add_theme_color_override("font_color", Color("70a1ff"))

		btn.pressed.connect(func():
			_select_outfit(id)
			_populate_outfit_list()
			_play_click_audio()
		)
		outfit_list_vbox.add_child(btn)

func _build_ui() -> void:
	# Fundo Escurecido Translúcido
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.88)
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)
	margin.add_child(main_vbox)

	# --- CABEÇALHO ---
	var header_hbox := HBoxContainer.new()
	main_vbox.add_child(header_hbox)

	var title_vbox := VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_vbox)

	var title := Label.new()
	title.text = "👔 ALFAIATARIA & BOUTIQUE DANTE"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("f39c12"))
	title_vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Personalize o estilo do Dante com os trajes temáticos dos 5 bairros da cidade"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("bdc3c7"))
	title_vbox.add_child(subtitle)

	wallet_label = Label.new()
	wallet_label.text = "$ 00000000"
	wallet_label.add_theme_font_size_override("font_size", 30)
	wallet_label.add_theme_color_override("font_color", Color("2ed573"))
	header_hbox.add_child(wallet_label)

	# --- CORPO PRINCIPAL (2 COLUNAS: LISTA À ESQUERDA, PREVIEW 3D À DIREITA) ---
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 24)
	main_vbox.add_child(body_hbox)

	# COLUNA ESQUERDA: Filtros por Bairro & Lista de Trajes
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_stretch_ratio = 1.15
	left_vbox.add_theme_constant_override("separation", 10)
	body_hbox.add_child(left_vbox)

	var filter_scroll := ScrollContainer.new()
	filter_scroll.custom_minimum_size = Vector2(0, 42)
	filter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	filter_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_vbox.add_child(filter_scroll)

	var filter_hbox := HBoxContainer.new()
	filter_hbox.add_theme_constant_override("separation", 6)
	filter_scroll.add_child(filter_hbox)

	for dist in OutfitCatalog.get_districts():
		var fbtn := Button.new()
		fbtn.text = dist
		fbtn.pressed.connect(func():
			current_filter = dist
			_populate_outfit_list()
			_play_click_audio()
		)
		filter_hbox.add_child(fbtn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(scroll)

	outfit_list_vbox = VBoxContainer.new()
	outfit_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outfit_list_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(outfit_list_vbox)

	# COLUNA DIREITA: Preview 3D com Pedestal Giratório e Detalhes
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_stretch_ratio = 1.0
	right_vbox.add_theme_constant_override("separation", 10)
	body_hbox.add_child(right_vbox)

	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	sb.set_corner_radius_all(8)
	sb.border_color = Color(0.25, 0.30, 0.40)
	sb.set_border_width_all(2)
	preview_panel.add_theme_stylebox_override("panel", sb)
	right_vbox.add_child(preview_panel)

	var preview_inner := VBoxContainer.new()
	preview_panel.add_child(preview_inner)

	preview_3d = CharacterPreview3D.new()
	preview_3d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_inner.add_child(preview_3d)

	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 4)
	preview_inner.add_child(info_box)

	name_label = Label.new()
	name_label.text = "STREETWEAR URBANO"
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color("f39c12"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_box.add_child(name_label)

	district_label = Label.new()
	district_label.text = "📍 DISTRITO: Centro Urbano"
	district_label.add_theme_font_size_override("font_size", 13)
	district_label.add_theme_color_override("font_color", Color("74b9ff"))
	district_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_box.add_child(district_label)

	desc_label = Label.new()
	desc_label.text = "Descrição do traje..."
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color("dfe6e9"))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_box.add_child(desc_label)

	price_label = Label.new()
	price_label.text = "VALOR: $ 0"
	price_label.add_theme_font_size_override("font_size", 16)
	price_label.add_theme_color_override("font_color", Color("ffa502"))
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_box.add_child(price_label)

	# --- RODAPÉ: AÇÕES & AVISOS ---
	var footer_hbox := HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(footer_hbox)

	notice_label = Label.new()
	notice_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice_label.text = "Aviso da loja..."
	notice_label.add_theme_font_size_override("font_size", 14)
	notice_label.add_theme_color_override("font_color", Color("2ed573"))
	footer_hbox.add_child(notice_label)

	action_button = Button.new()
	action_button.text = "EQUIPAR TRAJE"
	action_button.custom_minimum_size = Vector2(210, 48)
	action_button.add_theme_font_size_override("font_size", 16)
	action_button.pressed.connect(_on_action_pressed)
	footer_hbox.add_child(action_button)

	var close_button = Button.new()
	close_button.text = "[E / ESC] FECHAR LOJA"
	close_button.custom_minimum_size = Vector2(180, 48)
	close_button.add_theme_font_size_override("font_size", 14)
	close_button.pressed.connect(close_store)
	footer_hbox.add_child(close_button)

func _play_click_audio() -> void:
	var audio := AudioStreamPlayer.new()
	audio.stream = ProceduralAudio.get_ui_click_stream()
	audio.volume_db = -4.0
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)

func _play_cash_audio() -> void:
	var audio := AudioStreamPlayer.new()
	audio.stream = ProceduralAudio.get_cash_register_stream()
	audio.volume_db = 0.0
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)

func _play_error_audio() -> void:
	var audio := AudioStreamPlayer.new()
	audio.stream = ProceduralAudio.get_bullet_metal_hit_stream()
	audio.volume_db = -2.0
	audio.pitch_scale = 0.6
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)
