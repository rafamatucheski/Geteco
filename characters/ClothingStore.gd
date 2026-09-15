class_name ClothingStore
extends CanvasLayer

signal store_closed
const STYLE := preload("res://ui/GameStyle.gd")
var shopper: Node
var is_active := false
var selected_outfit_id := "dante_classic"
var current_filter := "Todos"
var winter_stock := false
var store_title := "UNION / ROUPAS"
var preview_3d: CharacterPreview3D
var outfit_list_vbox: VBoxContainer
var name_label: Label
var desc_label: Label
var action_button: Button
var wallet_label: Label
var notice_label: Label
var filter_buttons: Dictionary = {}
var _panel: PanelContainer
var _close_button: Button

func _ready() -> void:
	layer = 65
	_build_ui()
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()
	hide()

func open_store(player: Node) -> void:
	shopper = player
	is_active = true
	show()
	preview_3d.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	current_filter = "Distrito do Gelo" if winter_stock else "Todos"
	selected_outfit_id = String(shopper.get("current_outfit_id")) if shopper else "dante_classic"
	if selected_outfit_id.is_empty(): selected_outfit_id = "dante_classic"
	if winter_stock and OutfitCatalog.cold_protection(selected_outfit_id) < .6:
		selected_outfit_id = "dante_arctic"
	_select_outfit(selected_outfit_id)
	_refresh_wallet()
	_populate_outfit_list()
	_show_notice("")
	if not action_button.disabled: action_button.grab_focus()
	else: _close_button.grab_focus()

func close_store() -> void:
	is_active = false
	hide()
	preview_3d.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	store_closed.emit()

func _input(event: InputEvent) -> void:
	if not is_active: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE,KEY_E]:
		close_store()
		get_viewport().set_input_as_handled()

func _select_outfit(outfit_id: String) -> void:
	selected_outfit_id = outfit_id
	preview_3d.set_outfit(outfit_id)
	name_label.text = _outfit_name(outfit_id)
	var protection := roundi(OutfitCatalog.cold_protection(outfit_id)*100)
	desc_label.text = "%d%% menos perda de calor\nAbrigos recuperam a temperatura." % protection if protection > 0 else "Sem proteção contra o frio."
	var owned := _is_outfit_owned(outfit_id)
	var equipped := _is_outfit_equipped(outfit_id)
	action_button.disabled = equipped
	action_button.text = "Equipado" if equipped else ("Vestir" if owned else "Comprar e vestir · $ %d" % int(OutfitCatalog.get_outfit(outfit_id).price))
	_show_notice("")

func _on_action_pressed() -> void:
	if not is_instance_valid(shopper) or _is_outfit_equipped(selected_outfit_id): return
	var price := int(OutfitCatalog.get_outfit(selected_outfit_id).price)
	var owned := _is_outfit_owned(selected_outfit_id)
	if not owned:
		var money := int(shopper.get("money"))
		if money < price:
			_show_notice("Faltam $ %d." % (price-money))
			return
		shopper.set("money",money-price)
		var wardrobe: Dictionary = shopper.get("owned_outfits")
		wardrobe[selected_outfit_id] = true
		shopper.set("owned_outfits",wardrobe)
	shopper.apply_outfit(selected_outfit_id)
	_select_outfit(selected_outfit_id)
	_refresh_wallet()
	_populate_outfit_list()
	_show_notice("Roupa equipada." if owned else "Compra concluída. Roupa equipada.")
	_play_audio(ProceduralAudio.get_ui_click_stream() if owned else ProceduralAudio.get_cash_register_stream())

func _is_outfit_owned(outfit_id: String) -> bool:
	if outfit_id == "dante_classic": return true
	if not is_instance_valid(shopper): return false
	var wardrobe: Dictionary = shopper.get("owned_outfits")
	return wardrobe.get(outfit_id,false) == true

func _is_outfit_equipped(outfit_id: String) -> bool:
	return is_instance_valid(shopper) and String(shopper.get("current_outfit_id")) == outfit_id

func _refresh_wallet() -> void:
	if is_instance_valid(shopper): wallet_label.text = "Saldo  $ %d" % int(shopper.get("money"))

func _show_notice(message: String) -> void:
	notice_label.text = message

func _outfit_name(id: String) -> String:
	return String({"dante_classic":"Dante clássico","dante_suit":"Terno","dante_arctic":"Parka ártica","dante_ski":"Conjunto de ski","dante_trench":"Sobretudo de lã","dante_cowboy":"Pistoleiro","dante_madmax":"Sobrevivente","dante_lumberjack":"Lenhador","dante_ghillie":"Camuflado","dante_hawaii":"Havaiana","dante_badboy":"Regata"}.get(id,OutfitCatalog.get_outfit(id).name))

func _populate_outfit_list() -> void:
	for child in outfit_list_vbox.get_children():
		outfit_list_vbox.remove_child(child)
		child.queue_free()
	for data in OutfitCatalog.get_all_outfits():
		if current_filter != "Todos" and data.district != current_filter: continue
		var id: String = data.id
		var button := Button.new()
		button.text = _outfit_name(id) + ("  ·  seu" if _is_outfit_owned(id) else "")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 39
		button.toggle_mode = true
		button.button_pressed = id == selected_outfit_id
		_style_button(button)
		button.pressed.connect(func():
			_select_outfit(id)
			_populate_outfit_list()
			for entry in outfit_list_vbox.get_children():
				if entry.button_pressed: entry.grab_focus()
		)
		outfit_list_vbox.add_child(button)
	for district in filter_buttons:
		filter_buttons[district].set_pressed_no_signal(district == current_filter)

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02,0.03,0.04,.72)
	add_child(backdrop)
	_panel = PanelContainer.new()
	_panel.name = "ClothingPanel"
	_panel.add_theme_stylebox_override("panel",STYLE.panel())
	add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",16)
	_panel.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",20)
	content.add_child(header)
	var title := _label(store_title,22,STYLE.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	wallet_label = _label("",14,STYLE.MUTED)
	header.add_child(wallet_label)
	_close_button = Button.new()
	_close_button.text = "Fechar · Esc"
	_style_button(_close_button)
	_close_button.pressed.connect(close_store)
	header.add_child(_close_button)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",28)
	content.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	body.add_child(left)
	preview_3d = CharacterPreview3D.new()
	preview_3d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(preview_3d)
	name_label = _label("",18,STYLE.TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(name_label)
	var rotate_hint := _label("Arraste para girar",12,STYLE.MUTED)
	rotate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(rotate_hint)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 300
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation",12)
	body.add_child(right)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation",8)
	right.add_child(filters)
	for item in [["Inverno","Distrito do Gelo"],["Todas","Todos"]]:
		var button := Button.new()
		button.text = item[0]
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(button)
		var filter: String = item[1]
		filter_buttons[filter] = button
		button.pressed.connect(func():
			current_filter = filter
			if filter != "Todos" and OutfitCatalog.get_outfit(selected_outfit_id).district != filter:
				_select_outfit("dante_arctic")
			_populate_outfit_list()
		)
		filters.add_child(button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	right.add_child(scroll)
	outfit_list_vbox = VBoxContainer.new()
	outfit_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outfit_list_vbox.add_theme_constant_override("separation",5)
	scroll.add_child(outfit_list_vbox)
	desc_label = _label("",14,STYLE.MUTED)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(desc_label)
	action_button = Button.new()
	action_button.custom_minimum_size.y = 46
	_style_button(action_button,true)
	action_button.pressed.connect(_on_action_pressed)
	right.add_child(action_button)
	notice_label = _label("",13,STYLE.TEXT)
	notice_label.custom_minimum_size.y = 20
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(notice_label)

func _fit_panel() -> void:
	var screen := get_viewport().get_visible_rect().size
	var desired := Vector2(minf(800,screen.x-48),minf(540,screen.y-48))
	_panel.size = desired
	_panel.position = (screen-desired)*.5

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _style_button(button: Button, primary := false) -> void:
	button.add_theme_stylebox_override("normal",STYLE.button(primary))
	button.add_theme_stylebox_override("hover",STYLE.button(true))
	button.add_theme_stylebox_override("pressed",STYLE.button(true))
	var focus := STYLE.button(true)
	focus.bg_color = Color.TRANSPARENT
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus",focus)
	button.add_theme_color_override("font_color",STYLE.TEXT)
	button.add_theme_font_size_override("font_size",14)

func _play_audio(stream: AudioStream) -> void:
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.volume_db = -6
	add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()
