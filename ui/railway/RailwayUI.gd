extends CanvasLayer
## Presentation only. RailwayTransit owns admission, campaign gates and player locks.

const STYLE := preload("res://ui/GameStyle.gd")
const NETWORK := preload("res://world/railway/RailwayNetwork.gd")
const RAIL_BLUE := Color("86bfce")

signal station_closed

var transit: Node
var origin_id := ""
var selected_id := ""
var destinations: Array = []
var station_buttons: Dictionary = {}
var _connections: Array[Dictionary] = []
var _root: Control
var _shade: ColorRect
var _station_panel: PanelContainer
var _station_title: Label
var _station_list: VBoxContainer
var _selection: Label
var _status: Label
var _board: Button
var _fast: Button
var _close: Button
var _journey_panel: PanelContainer
var _journey_title: Label
var _journey_time: Label
var _progress: ProgressBar
var _inside: Button
var _outside: Button
var _skip: Button
var _journey_actions: BoxContainer
var _station_actions: BoxContainer
var _journey_active := false


func _ready() -> void:
	name = "RailwayUI"
	layer = 35
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_root = Control.new()
	_root.name = "RailwayScreen"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = STYLE.create_theme(17)
	add_child(_root)
	_build_station_menu()
	_build_journey_hud()
	_root.resized.connect(_layout)
	_layout()
	close_station()
	hide_journey()


func configure(next_transit: Node) -> void:
	for connection in _connections:
		if is_instance_valid(transit) and transit.is_connected(connection.signal_name, connection.callback):
			transit.disconnect(connection.signal_name, connection.callback)
	_connections.clear()
	transit = next_transit
	if not is_instance_valid(transit): return
	_bind("station_requested", open_station)
	_bind("trip_started", show_journey)
	_bind("trip_updated", update_journey)
	_bind("trip_finished", _on_arrival)
	_bind("notice", show_notice)
	if transit.has_signal("station_menu_closed"):
		_bind("station_menu_closed", close_station)


func _bind(signal_name: StringName, callback: Callable) -> void:
	transit.connect(signal_name, callback)
	_connections.append({"signal_name": signal_name, "callback": callback})


func _build_station_menu() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0.01, 0.018, 0.026, 0.54)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_shade)
	_station_panel = PanelContainer.new()
	_station_panel.name = "StationMenu"
	_station_panel.add_theme_stylebox_override("panel", _panel_style(true))
	_root.add_child(_station_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_station_panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	_station_title = STYLE.label("", 28)
	_station_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_station_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(_station_title)
	_close = _button("Voltar", "CloseStation")
	_close.pressed.connect(_request_close)
	heading.add_child(_close)
	var line := HSeparator.new()
	column.add_child(line)
	var scroll := ScrollContainer.new()
	scroll.name = "DestinationScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	_station_list = VBoxContainer.new()
	_station_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_station_list.add_theme_constant_override("separation", 7)
	scroll.add_child(_station_list)
	_selection = STYLE.label("", 20, RAIL_BLUE)
	_selection.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_selection)
	_status = STYLE.label("", 15, STYLE.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 36
	column.add_child(_status)
	_station_actions = BoxContainer.new()
	_station_actions.add_theme_constant_override("separation", 10)
	column.add_child(_station_actions)
	_board = _button("Embarcar", "BoardTrain", true)
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.pressed.connect(_request_travel.bind(false))
	_station_actions.add_child(_board)
	_fast = _button("Viagem rápida", "FastTravel")
	_fast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fast.pressed.connect(_request_travel.bind(true))
	_station_actions.add_child(_fast)


func _build_journey_hud() -> void:
	_journey_panel = PanelContainer.new()
	_journey_panel.name = "JourneyHUD"
	_journey_panel.add_theme_stylebox_override("panel", _panel_style(false))
	_root.add_child(_journey_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	_journey_panel.add_child(column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 16)
	column.add_child(heading)
	_journey_title = STYLE.label("", 20)
	_journey_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journey_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(_journey_title)
	_journey_time = STYLE.label("", 16, RAIL_BLUE)
	_journey_time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(_journey_time)
	_progress = ProgressBar.new()
	_progress.name = "TripProgress"
	_progress.custom_minimum_size.y = 4
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color("35434c")
	track.set_corner_radius_all(2)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = RAIL_BLUE
	_progress.add_theme_stylebox_override("background", track)
	_progress.add_theme_stylebox_override("fill", fill)
	column.add_child(_progress)
	_journey_actions = BoxContainer.new()
	_journey_actions.add_theme_constant_override("separation", 8)
	column.add_child(_journey_actions)
	_inside = _button("Vista interna", "InteriorView")
	_inside.toggle_mode = true
	_inside.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inside.pressed.connect(_request_camera.bind(0))
	_journey_actions.add_child(_inside)
	_outside = _button("Vista externa", "ExteriorView")
	_outside.toggle_mode = true
	_outside.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outside.pressed.connect(_request_camera.bind(1))
	_journey_actions.add_child(_outside)
	_skip = _button("Pular viagem", "SkipTrip")
	_skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skip.pressed.connect(_request_skip)
	_journey_actions.add_child(_skip)


func _panel_style(menu: bool) -> StyleBoxFlat:
	var skin := STYLE.panel()
	skin.bg_color = Color(0.055, 0.08, 0.1, 0.98 if menu else 0.94)
	skin.border_color = Color("475a67")
	skin.border_width_top = 2
	skin.content_margin_left = 22 if menu else 16
	skin.content_margin_right = 22 if menu else 16
	skin.content_margin_top = 18 if menu else 12
	skin.content_margin_bottom = 18 if menu else 12
	return skin


func _button(text: String, node_name: String, primary := false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size.y = 42
	button.add_theme_font_size_override("font_size", 17)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var skin := STYLE.compact(primary or state in ["hover", "pressed"], 6, Vector2(12, 9))
		skin.bg_color = Color("213a46") if primary else Color("1c2932")
		if state in ["hover", "pressed"]: skin.bg_color = skin.bg_color.lightened(0.12)
		if state == "disabled": skin.bg_color = Color("192229")
		skin.border_color = RAIL_BLUE if primary or state in ["hover", "pressed"] else Color("40535f")
		skin.shadow_size = 0
		button.add_theme_stylebox_override(state, skin)
	var focus := STYLE.compact(true, 6)
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = RAIL_BLUE
	focus.set_border_width_all(2)
	focus.shadow_size = 0
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_focus_color", RAIL_BLUE)
	return button


func open_station(station_id: String, stations: Array) -> void:
	origin_id = station_id
	destinations = stations.duplicate(true)
	selected_id = ""
	station_buttons.clear()
	for child in _station_list.get_children():
		_station_list.remove_child(child)
		child.queue_free()
	_station_title.text = _station_name(origin_id)
	for destination in destinations:
		var id := str(destination.get("id", ""))
		if id.is_empty() or id == origin_id: continue
		var available := bool(destination.get("available", false))
		var title := str(destination.get("name", id))
		var button := _button(title, "Destination_" + id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 54
		button.toggle_mode = true
		button.clip_text = true
		# Locked destinations remain focusable so their reason is readable on a pad.
		button.add_theme_color_override("font_color", STYLE.TEXT if available else STYLE.MUTED)
		button.tooltip_text = title if available else str(destination.get("locked_reason", "Estação indisponível"))
		button.pressed.connect(select_destination.bind(id))
		button.focus_entered.connect(select_destination.bind(id))
		_station_list.add_child(button)
		station_buttons[id] = button
		if selected_id.is_empty() and available: selected_id = id
	if selected_id.is_empty() and not station_buttons.is_empty(): selected_id = str(station_buttons.keys()[0])
	_shade.show()
	_station_panel.show()
	_layout()
	select_destination(selected_id)
	_wire_station_focus()
	if station_buttons.has(selected_id): _focus_when_visible.call_deferred(weakref(station_buttons[selected_id]))
	else: _focus_when_visible.call_deferred(weakref(_close))


func select_destination(station_id: String) -> void:
	selected_id = station_id
	var selected := _destination(station_id)
	var available := not selected.is_empty() and station_id != origin_id and bool(selected.get("available", false))
	_board.disabled = not available
	_fast.disabled = not available
	for id in station_buttons:
		station_buttons[id].set_pressed_no_signal(id == selected_id)
	_selection.text = str(selected.get("name", "Nenhum destino disponível"))
	if selected.is_empty():
		_status.text = "Nenhum destino disponível"
	elif not available:
		_status.text = str(selected.get("locked_reason", "Estação indisponível"))
	else:
		var seconds := ceili(float(selected.get("duration_seconds", 0.0)))
		_status.text = String(TranslationServer.translate("Viagem · %s")) % _duration(seconds) if seconds > 0 else ""
	_status.add_theme_color_override("font_color", STYLE.MUTED if available else STYLE.MONEY)
	_wire_station_focus()


func close_station() -> void:
	if not is_instance_valid(_station_panel): return
	_station_panel.hide()
	_shade.hide()


func is_station_open() -> bool:
	return is_instance_valid(_station_panel) and _station_panel.visible


func show_journey(state: Dictionary) -> void:
	close_station()
	_journey_active = true
	_journey_panel.show()
	_skip.disabled = false
	update_journey(state)
	_layout()
	_wire_focus([_inside, _outside, _skip], true)
	_focus_when_visible.call_deferred(weakref(_inside))


func update_journey(state: Dictionary) -> void:
	if not _journey_active: return
	var departure := str(state.get("origin_name", _station_name(str(state.get("origin_id", "")))))
	var arrival := str(state.get("destination_name", _station_name(str(state.get("destination_id", "")))))
	_journey_title.text = "%s  →  %s" % [departure, arrival]
	_progress.value = clampf(float(state.get("progress", 0.0)), 0.0, 1.0)
	_journey_time.text = _duration(ceili(maxf(0.0, float(state.get("remaining_seconds", 0.0)))))
	var camera_mode := int(state.get("camera_mode", 0))
	_inside.set_pressed_no_signal(camera_mode == 0)
	_outside.set_pressed_no_signal(camera_mode == 1)


func hide_journey() -> void:
	_journey_active = false
	if is_instance_valid(_journey_panel): _journey_panel.hide()


func show_notice(message: String) -> void:
	if not is_station_open(): return
	_status.text = message
	_status.add_theme_color_override("font_color", STYLE.MONEY)


func _on_arrival(_station_id: String) -> void:
	hide_journey()


func _request_close() -> void:
	if not is_station_open(): return
	close_station()
	if is_instance_valid(transit) and transit.has_method("close_station_menu"):
		transit.close_station_menu()
	station_closed.emit()


func _request_travel(instant: bool) -> void:
	var destination := _destination(selected_id)
	if not is_station_open() or not bool(destination.get("available", false)) or selected_id == origin_id: return
	if is_instance_valid(transit): transit.travel_to(selected_id, instant)


func _request_camera(mode: int) -> void:
	if not _journey_active or not is_instance_valid(transit): return
	transit.set_camera_mode(mode)
	_inside.set_pressed_no_signal(mode == 0)
	_outside.set_pressed_no_signal(mode == 1)


func _request_skip() -> void:
	if not _journey_active or not is_instance_valid(transit): return
	transit.skip_trip()


func _destination(id: String) -> Dictionary:
	for destination in destinations:
		if str(destination.get("id", "")) == id: return destination
	return {}


func _station_name(id: String) -> String:
	if is_instance_valid(transit) and transit.has_method("station_name"): return transit.station_name(id)
	return str(_destination(id).get("name", NETWORK.get_station(id).get("name", id)))


func _duration(seconds: int) -> String:
	return "%d:%02d" % [floori(float(seconds) / 60.0), seconds % 60]


func _layout() -> void:
	if not is_instance_valid(_station_panel): return
	var extent := _root.get_viewport_rect().size
	var margin := 14.0 if extent.x < 700.0 else 28.0
	var width := minf(580.0, maxf(240.0, extent.x - margin * 2.0))
	var height := minf(622.0, maxf(280.0, extent.y - margin * 2.0))
	_station_panel.position = Vector2((extent.x - width) * 0.5, (extent.y - height) * 0.5).round()
	_station_panel.size = Vector2(width, height)
	_station_actions.vertical = width < 360.0
	var journey_width := minf(700.0, maxf(240.0, extent.x - margin * 2.0))
	_journey_actions.vertical = journey_width < 470.0
	_journey_panel.size = Vector2(journey_width, 0)
	var journey_height := _journey_panel.get_combined_minimum_size().y
	_journey_panel.position = Vector2((extent.x - journey_width) * 0.5, extent.y - journey_height - margin).round()


func _wire_station_focus() -> void:
	var controls: Array[Control] = []
	for button in station_buttons.values(): controls.append(button)
	if not _board.disabled: controls.append(_board)
	if not _fast.disabled: controls.append(_fast)
	controls.append(_close)
	_wire_focus(controls, false)
	if not _board.disabled:
		_board.focus_neighbor_right = _board.get_path_to(_fast)
		_fast.focus_neighbor_left = _fast.get_path_to(_board)


func _wire_focus(controls: Array[Control], horizontal: bool) -> void:
	for index in controls.size():
		var current := controls[index]
		var previous := controls[(index + controls.size() - 1) % controls.size()]
		var next := controls[(index + 1) % controls.size()]
		current.focus_previous = current.get_path_to(previous)
		current.focus_next = current.get_path_to(next)
		current.focus_neighbor_top = current.get_path_to(previous if not horizontal else current)
		current.focus_neighbor_bottom = current.get_path_to(next if not horizontal else current)
		current.focus_neighbor_left = current.get_path_to(previous if horizontal else current)
		current.focus_neighbor_right = current.get_path_to(next if horizontal else current)


func _focus_when_visible(reference: WeakRef) -> void:
	var control := reference.get_ref() as Control
	if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree() and not control.is_queued_for_deletion():
		control.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if is_station_open() and event.is_action_pressed("ui_cancel"):
		_request_close()
		get_viewport().set_input_as_handled()
