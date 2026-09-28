extends Control
## Interface isolada para a pasta fisica de Vicente.
##
## `configure()` aceita SecretNetworkProgression ou um Dictionary de snapshot.
## O runtime hospedeiro continua dono do modal, save e reproducao dos audios.

signal closed
signal audio_toggled(id: String, playing: bool)
signal route_selected(id: String)

const CANVAS := preload("res://ui/SecretFileCanvas.gd")
const STYLE := preload("res://ui/GameStyle.gd")
const FONT_REGULAR := preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const FONT_SEMIBOLD := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")

const TEXT := Color("eee4ce")
const MUTED := Color("a99c82")
const PAPER_TEXT := Color("403a30")
const ACCENT := Color("c04b42")
const GOLD := Color("d0a45f")

const EVIDENCE_ORDER := [
	"keypad_invoice",
	"keypad_house_plaque",
	"keypad_radio_frequency",
	"keypad_service_stamp",
	"audio_vicente_field",
	"audio_maintenance_shift",
	"audio_blackout",
	"audio_sealed_sector",
	"lab_access_badge",
	"lab_power_report",
	"lab_incident_photo",
]
const ROUTE_ORDER := [
	"route_village_house",
	"route_harbor_sewer",
	"route_south_port_drain",
	"route_mountain_outfall",
]

var progression: Variant
var snapshot: Dictionary = {}
var summary: Dictionary = {}
var current_tab := 0
var selected_id := ""
var map_zoom := 1.0
var playing_audio_id := ""

var canvas: Control
var title_label: Label
var tab_buttons: Array[Button] = []
var close_button: Button
var item_list: VBoxContainer
var item_scroll: ScrollContainer
var detail_label: Label
var audio_button: Button
var route_button: Button
var zoom_row: HBoxContainer


func _ready() -> void:
	name = "SecretFilePanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = CANVAS.new()
	add_child(canvas)
	_build_controls()
	resized.connect(_layout)
	hide()
	_layout()


func configure(source: Variant) -> void:
	progression = source
	refresh()


func open(source: Variant = null) -> bool:
	if source != null:
		progression = source
	refresh()
	if not bool(snapshot.get("dossier_received", false)):
		return false
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_focus.call_deferred()
	return true


func close() -> void:
	if not visible:
		return
	_stop_audio()
	hide()
	closed.emit()


func refresh(source: Variant = null) -> void:
	if source != null:
		progression = source
	_read_source()
	if current_tab == 2 and not bool(summary.get("headquarters_discovered", false)):
		current_tab = 0
	_update_tabs()
	_rebuild_items()
	_update_detail()
	_sync_canvas()
	_layout.call_deferred()


func set_audio_playing(id: String, playing: bool) -> void:
	playing_audio_id = id if playing else ""
	_update_audio_button()


func select_tab(index: int) -> void:
	index = clampi(index, 0, 2)
	if index == 2 and not bool(summary.get("headquarters_discovered", false)):
		return
	if current_tab == index:
		return
	_stop_audio()
	current_tab = index
	selected_id = ""
	_update_tabs()
	_rebuild_items()
	_update_detail()
	_sync_canvas()
	_refresh_focus.call_deferred()


func _build_controls() -> void:
	title_label = _label(_text("ARQUIVO DE VICENTE", "VICENTE'S FILE"), 22, TEXT, FONT_SEMIBOLD)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_label)

	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 5)
	add_child(tabs)
	for index in 3:
		var button := Button.new()
		button.text = [_text("MAPA", "MAP"), _text("EVIDÊNCIAS", "EVIDENCE"), _text("REDE", "NETWORK")][index]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_override("font", FONT_SEMIBOLD)
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(select_tab.bind(index))
		tabs.add_child(button)
		tab_buttons.append(button)

	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = "×"
	close_button.tooltip_text = _text("Fechar · J / Esc", "Close · J / Esc")
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.add_theme_font_override("font", FONT_SEMIBOLD)
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(close)
	add_child(close_button)

	item_scroll = ScrollContainer.new()
	item_scroll.name = "Records"
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	item_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(item_scroll)
	item_list = VBoxContainer.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.add_theme_constant_override("separation", 6)
	item_scroll.add_child(item_list)

	detail_label = _label("", 14, PAPER_TEXT, FONT_REGULAR)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(detail_label)

	audio_button = Button.new()
	audio_button.name = "AudioToggle"
	audio_button.focus_mode = Control.FOCUS_ALL
	audio_button.add_theme_font_override("font", FONT_SEMIBOLD)
	audio_button.pressed.connect(_toggle_audio)
	add_child(audio_button)

	route_button = Button.new()
	route_button.name = "RouteSelect"
	route_button.text = _text("SELECIONAR", "SELECT")
	route_button.focus_mode = Control.FOCUS_ALL
	route_button.add_theme_font_override("font", FONT_SEMIBOLD)
	route_button.pressed.connect(func():
		if not selected_id.is_empty(): route_selected.emit(selected_id))
	add_child(route_button)

	zoom_row = HBoxContainer.new()
	zoom_row.name = "MapZoom"
	zoom_row.add_theme_constant_override("separation", 5)
	add_child(zoom_row)
	var zoom_out := _small_button("−", _change_zoom.bind(-0.1))
	zoom_out.tooltip_text = _text("Afastar mapa", "Zoom out")
	zoom_row.add_child(zoom_out)
	var zoom_reset := _small_button("1:1", func(): map_zoom = 1.0; _sync_canvas())
	zoom_reset.tooltip_text = _text("Restaurar zoom", "Reset zoom")
	zoom_row.add_child(zoom_reset)
	var zoom_in := _small_button("+", _change_zoom.bind(0.1))
	zoom_in.tooltip_text = _text("Aproximar mapa", "Zoom in")
	zoom_row.add_child(zoom_in)

	_style_controls()


func _style_controls() -> void:
	for button in tab_buttons + [close_button, audio_button, route_button]:
		_style_button(button)
	for child in zoom_row.get_children():
		_style_button(child)


func _style_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.085, 0.06, 0.90)
	normal.border_color = Color(0.48, 0.40, 0.28, 0.75)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.24, 0.16, 0.10, 0.94)
	hover.border_color = GOLD
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.border_color = ACCENT
	pressed.border_width_bottom = 3
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_color_override("font_focus_color", GOLD)
	button.add_theme_color_override("font_disabled_color", Color("6e6555"))


func _read_source() -> void:
	snapshot = {}
	summary = {}
	if progression is Dictionary:
		var dictionary: Dictionary = progression
		if dictionary.get("snapshot") is Dictionary:
			snapshot = dictionary.snapshot.duplicate(true)
			summary = dictionary.get("summary", {}).duplicate(true) if dictionary.get("summary") is Dictionary else {}
		else:
			snapshot = dictionary.duplicate(true)
	elif is_instance_valid(progression):
		if progression.has_method("snapshot"):
			var next_snapshot: Variant = progression.call("snapshot")
			if next_snapshot is Dictionary:
				snapshot = next_snapshot.duplicate(true)
		if progression.has_method("progress_summary"):
			var next_summary: Variant = progression.call("progress_summary")
			if next_summary is Dictionary:
				summary = next_summary.duplicate(true)
		elif progression.has_method("summary"):
			var next_summary: Variant = progression.call("summary")
			if next_summary is Dictionary:
				summary = next_summary.duplicate(true)
	if summary.is_empty():
		summary = _derive_summary(snapshot)


func _derive_summary(state: Dictionary) -> Dictionary:
	return {
		"dossier_received":bool(state.get("dossier_received", false)),
		"fragments_found":state.get("fragments", []).size(),
		"fragments_total":6,
		"keypad_clues_found":state.get("keypad_clues", []).size(),
		"keypad_clues_total":4,
		"house_discovered":bool(state.get("house_discovered", false)),
		"keypad_unlocked":bool(state.get("keypad_unlocked", false)),
		"headquarters_discovered":bool(state.get("headquarters_discovered", false)),
		"routes_active":state.get("routes", []).size(),
		"routes_total":4,
		"audio_logs_found":state.get("audio_logs", []).size(),
		"audio_logs_total":4,
		"lab_clues_found":state.get("lab_clues", []).size(),
		"lab_clues_total":3,
		"sealed_sector_discovered":bool(state.get("sealed_sector_discovered", false)),
		"final_door_unlocked":bool(state.get("final_door_unlocked", false)),
	}


func _update_tabs() -> void:
	for index in tab_buttons.size():
		tab_buttons[index].button_pressed = current_tab == index
	tab_buttons[2].disabled = not bool(summary.get("headquarters_discovered", false))
	tab_buttons[2].tooltip_text = _text("Descubra o QG", "Discover the HQ") if tab_buttons[2].disabled else ""
	zoom_row.visible = current_tab == 0
	item_scroll.visible = current_tab in [1, 2]
	audio_button.visible = current_tab == 1 and selected_id.begins_with("audio_")
	route_button.visible = current_tab == 2 and not selected_id.is_empty()


func _rebuild_items() -> void:
	for child in item_list.get_children():
		item_list.remove_child(child)
		child.queue_free()
	var ids: Array = []
	if current_tab == 1:
		var known: Array = []
		known.append_array(snapshot.get("keypad_clues", []))
		known.append_array(snapshot.get("audio_logs", []))
		known.append_array(snapshot.get("lab_clues", []))
		for id in EVIDENCE_ORDER:
			if known.has(id): ids.append(id)
	elif current_tab == 2:
		for id in ROUTE_ORDER:
			if snapshot.get("routes", []).has(id): ids.append(id)
	if not ids.has(selected_id):
		selected_id = str(ids[0]) if not ids.is_empty() else ""
	for id_variant in ids:
		var id := str(id_variant)
		var button := Button.new()
		button.text = _item_label(id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = id == selected_id
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_override("font", FONT_REGULAR)
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_select_item.bind(id))
		item_list.add_child(button)
		_style_button(button)
	_update_tabs()


func _select_item(id: String) -> void:
	if selected_id == id:
		return
	_stop_audio()
	selected_id = id
	for child in item_list.get_children():
		if child is Button:
			child.button_pressed = child.text == _item_label(id)
	_update_detail()
	_sync_canvas()


func _update_detail() -> void:
	if selected_id.is_empty():
		detail_label.text = _text("Nenhum registro", "No record") if current_tab == 1 else ""
	else:
		detail_label.text = _item_label(selected_id)
	_update_audio_button()
	route_button.visible = current_tab == 2 and not selected_id.is_empty()


func _toggle_audio() -> void:
	if not selected_id.begins_with("audio_"):
		return
	var next_playing := playing_audio_id != selected_id
	if not playing_audio_id.is_empty() and playing_audio_id != selected_id:
		audio_toggled.emit(playing_audio_id, false)
	playing_audio_id = selected_id if next_playing else ""
	audio_toggled.emit(selected_id, next_playing)
	_update_audio_button()


func _stop_audio() -> void:
	if playing_audio_id.is_empty():
		return
	var previous := playing_audio_id
	playing_audio_id = ""
	audio_toggled.emit(previous, false)
	_update_audio_button()


func _update_audio_button() -> void:
	audio_button.visible = current_tab == 1 and selected_id.begins_with("audio_")
	audio_button.text = _text("PARAR", "STOP") if playing_audio_id == selected_id else _text("REPRODUZIR", "PLAY")


func _change_zoom(amount: float) -> void:
	map_zoom = clampf(snappedf(map_zoom + amount, 0.1), 0.8, 1.4)
	_sync_canvas()


func _sync_canvas() -> void:
	if is_instance_valid(canvas):
		canvas.set_context(current_tab, snapshot, summary, selected_id, map_zoom)


func _layout() -> void:
	if not is_instance_valid(canvas):
		return
	var folder: Rect2 = canvas.folder_rect()
	var left: Rect2 = canvas.left_page_rect()
	var right: Rect2 = canvas.right_page_rect()
	title_label.position = folder.position + Vector2(28, 18)
	title_label.size = Vector2(260, 42)
	var tabs := tab_buttons[0].get_parent() as Control
	tabs.position = folder.position + Vector2(folder.size.x * .5 - 190, 18)
	tabs.size = Vector2(380, 42)
	close_button.position = folder.end - Vector2(56, folder.size.y - 16)
	close_button.size = Vector2(38, 38)
	item_scroll.position = left.position + Vector2(18, 54)
	item_scroll.size = Vector2(left.size.x - 36, left.size.y - 98)
	detail_label.position = right.position + Vector2(26, 50)
	detail_label.size = Vector2(right.size.x - 52, 32)
	audio_button.position = right.end - Vector2(166, 62)
	audio_button.size = Vector2(138, 36)
	route_button.position = right.end - Vector2(166, 62)
	route_button.size = Vector2(138, 36)
	zoom_row.position = left.end - Vector2(154, 48)
	zoom_row.size = Vector2(136, 34)


func _refresh_focus() -> void:
	if not visible:
		return
	STYLE.trap_focus(self, false)
	if current_tab in [1, 2] and item_list.get_child_count() > 0:
		(item_list.get_child(0) as Button).grab_focus()
	else:
		tab_buttons[current_tab].grab_focus()
	for index in tab_buttons.size():
		var previous := tab_buttons[(index - 1 + tab_buttons.size()) % tab_buttons.size()]
		var next := tab_buttons[(index + 1) % tab_buttons.size()]
		tab_buttons[index].focus_neighbor_left = tab_buttons[index].get_path_to(previous)
		tab_buttons[index].focus_neighbor_right = tab_buttons[index].get_path_to(next)


func _input(event: InputEvent) -> void:
	if not visible or not event.is_pressed():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("journal"):
		get_viewport().set_input_as_handled()
		close()
		return
	if event is InputEventJoypadButton and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		var direction := -1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else 1
		_cycle_tab(direction)
		get_viewport().set_input_as_handled()
	elif current_tab == 0 and event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_change_zoom(0.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1)
		get_viewport().set_input_as_handled()


func _cycle_tab(direction: int) -> void:
	var candidate := current_tab
	for _attempt in 3:
		candidate = posmod(candidate + direction, 3)
		if candidate != 2 or bool(summary.get("headquarters_discovered", false)):
			select_tab(candidate)
			return


func _item_label(id: String) -> String:
	var labels := {
		"keypad_invoice":["Recibo · V.F.", "Invoice · V.F."],
		"keypad_house_plaque":["Placa da casa", "House plaque"],
		"keypad_radio_frequency":["Frequência", "Frequency"],
		"keypad_service_stamp":["Carimbo de serviço", "Service stamp"],
		"audio_vicente_field":["Gravação 01", "Recording 01"],
		"audio_maintenance_shift":["Gravação 02", "Recording 02"],
		"audio_blackout":["Gravação 03", "Recording 03"],
		"audio_sealed_sector":["Gravação 04", "Recording 04"],
		"lab_access_badge":["Crachá · C-01", "Badge · C-01"],
		"lab_power_report":["Diagrama · C-02", "Diagram · C-02"],
		"lab_incident_photo":["Fotografia · C-03", "Photograph · C-03"],
		"route_village_house":["Casa da Vila", "Village house"],
		"route_harbor_sewer":["Esgoto de Harbor", "Harbor sewer"],
		"route_south_port_drain":["Dreno do Porto Sul", "South Port drain"],
		"route_mountain_outfall":["Saída da Serra", "Mountain outfall"],
	}
	var pair: Array = labels.get(id, [id, id])
	return _text(str(pair[0]), str(pair[1]))


func _small_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(40, 30)
	button.add_theme_font_override("font", FONT_SEMIBOLD)
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(action)
	return button


func _label(text: String, font_size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _text(pt: String, en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt
