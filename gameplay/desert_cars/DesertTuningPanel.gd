extends CanvasLayer
## The panel emits intent only; session commits money + parts atomically, then
## calls show_vehicle with the authoritative state. No second wallet lives here.
## Passar o mouse (ou o foco) numa peça mostra nas barras como o carro ficaria.
signal purchase_requested(part_id: String)
signal remove_requested(slot: String)
signal closed
signal loadout_requested(parts: Dictionary)
signal preview_requested(parts: Dictionary)
signal preview_closed
signal view_requested(slot: String)
signal camera_action(action: String, value: float)
signal orbit_requested(delta: Vector2)
const STYLE := preload("res://ui/GameStyle.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const PERF := preload("res://data/catalogs/VehiclePerformance.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const RACE_WINS := preload("res://systems/campaign/RaceWins.gd")
const SHOWROOM := preload("res://gameplay/desert_cars/TuningShowroom.gd")
const GOLD := Color("d8b45f")
const MUTED := Color("8b949c")
const GOOD := Color("5fcf86")
const BAD := Color("e0614f")
const CLASS_COLORS := {"S":Color("e3b341"),"A":Color("e0573b"),"B":Color("a068e0"),"C":Color("4a90d9"),"D":Color("7d858c")}
const STATS := [["rate_accel","Aceleração"],["rate_speed","Velocidade final"],["rate_handling","Curva"],["rate_braking","Frenagem"]]
var _root: PanelContainer
var _dim: ColorRect
var _showroom: SubViewportContainer
var _title: Label
var _subtitle: Label
var _badge: PanelContainer
var _badge_letter: Label
var _wallet: Label
var _numbers: Label
var _message: Label
var _tabs: HFlowContainer
var _cards: VBoxContainer
var _scroll: ScrollContainer
var _bars: Array = []
var _root_control: Control
var _car_id := "desert_faisca"
var _model_id := "desert_faisca"
var _parts: Dictionary = {}
var _owned: Array = []
var _wins := 0
var _money := 0
var _slot := ""
var _pending := ""
var _base: Dictionary = {}
var _stats_panel: Control
var _view_controls: HBoxContainer
var _rotation_button: Button
## Quem prepara o carro: o Digo no deserto, o mecânico na Maciota.
var mechanic_name := "Digo"
var owned_only := false
const GROUPS := {"Visual":["paint","finish","sunroof","taillights","neon"],"Carroceria":["spoiler","skirts","front_lip","diffuser"],"Rodas":["wheel_model","wheel_size","wheels"],"Desempenho":["ecu","engine","turbo","nitro","gearbox","suspension","tires","weight","exhaust"]}
var _group := "Visual"
var _menu_level := 0
var _draft_parts: Dictionary = {}
var _groups: HBoxContainer
var _total: Label
var _apply: Button
var _compare: Button
var _exit_prompt: PanelContainer
var _footer: PanelContainer
var _live_car: CharacterBody3D
var _live_surface: Control
var _live_dragging := false
var _comparison := false
var _exit_after_apply := false
var _thumbnailer: Node

func set_live_vehicle(car: CharacterBody3D) -> void:
	_live_car = car
	if is_instance_valid(_showroom):
		_showroom.visible = not is_instance_valid(car)
		if is_instance_valid(car): _showroom.hide_showroom()
	if is_instance_valid(_dim): _dim.visible = not is_instance_valid(car)
	if is_instance_valid(_live_surface): _live_surface.visible = is_instance_valid(car)

func _ready() -> void:
	add_to_group("vehicle_tuning_panels")
	layer = 36
	_root_control = Control.new()
	_root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_control.theme = STYLE.create_theme(15)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var button_style := STYLE.button(false)
		button_style.set_corner_radius_all(3)
		button_style.content_margin_top = 6
		button_style.content_margin_bottom = 6
		button_style.border_color = GOLD if state in ["hover", "focus", "pressed"] else STYLE.LINE
		_root_control.theme.set_stylebox(state, "Button", button_style)
	add_child(_root_control)
	_dim = ColorRect.new()
	_dim.color = Color("101719")
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root_control.add_child(_dim)
	# Carro à direita, lista à esquerda e desempenho embaixo, como nas oficinas de GTA.
	_showroom = SHOWROOM.new()
	_showroom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_showroom.anchor_left = .28
	_showroom.offset_left = 0
	_root_control.add_child(_showroom)
	_live_surface = Control.new()
	_live_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_live_surface.anchor_left = .28
	_live_surface.hide()
	_live_surface.gui_input.connect(_live_input)
	_root_control.add_child(_live_surface)
	_root = PanelContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.anchor_right = .28
	_root.offset_right = 0
	_root.add_theme_stylebox_override("panel",_box(Color("11191df5"),Color("394043"),0,0,20))
	_root_control.add_child(_root)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	_root.add_child(column)
	column.add_child(_build_header())
	_groups = HBoxContainer.new()
	_groups.add_theme_constant_override("separation",3)
	column.add_child(_groups)
	var parts := _build_parts()
	parts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(parts)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color",GOLD)
	column.add_child(_message)
	_stats_panel = _build_stats()
	_stats_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_stats_panel.anchor_left = .28
	_stats_panel.offset_left = 16.0
	_stats_panel.offset_right = -20.0
	_stats_panel.offset_top = -226.0
	_stats_panel.offset_bottom = -105.0
	_root_control.add_child(_stats_panel)
	_view_controls = _build_view_controls()
	_view_controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_view_controls.offset_left = -355.0
	_view_controls.offset_right = -20.0
	_view_controls.offset_top = 20.0
	_view_controls.offset_bottom = 56.0
	_root_control.add_child(_view_controls)
	_footer = _build_footer()
	_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.anchor_left = .28
	_footer.offset_left = 16
	_footer.offset_right = -16
	_footer.offset_top = -88
	_footer.offset_bottom = -16
	_root_control.add_child(_footer)
	_exit_prompt = _build_exit_prompt()
	_root_control.add_child(_exit_prompt)
	_thumbnailer = preload("res://gameplay/desert_cars/TuningWheelThumbnails.gd").new()
	add_child(_thumbnailer)
	_thumbnailer.texture_ready.connect(_refresh_wheel_thumbnail)
	visibility_changed.connect(func():
		if not visible:
			_showroom.hide_showroom()
			_live_dragging = false
			preview_closed.emit())
	hide()

func _box(fill: Color, border: Color, width: int, radius: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(mini(radius,3))
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin*.8
	style.content_margin_bottom = margin*.8
	return style

func _build_header() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",7)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation",10)
	box.add_child(top)
	var shop := Label.new()
	shop.name = "Mechanic"
	shop.text = mechanic_name
	shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop.add_theme_font_size_override("font_size",32)
	top.add_child(shop)
	_wallet = Label.new()
	_wallet.add_theme_font_size_override("font_size",17)
	_wallet.add_theme_color_override("font_color",GOLD)
	top.add_child(_wallet)
	box.add_child(HSeparator.new())
	var names := HBoxContainer.new()
	box.add_child(names)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size",21)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_color_override("font_color",MUTED)
	_subtitle.add_theme_font_size_override("font_size",14)
	names.add_child(_subtitle)
	_badge = PanelContainer.new()
	_badge.hide()
	_badge_letter = Label.new()
	_badge.add_child(_badge_letter)
	names.add_child(_badge)
	return box

func _build_stats() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_box(Color("14181cee"),Color("2c343c"),1,10,16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	panel.add_child(row)
	var bars := VBoxContainer.new()
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.add_theme_constant_override("separation",9)
	row.add_child(bars)
	for stat in STATS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation",12)
		var name_label := Label.new()
		name_label.text = str(stat[1])
		name_label.custom_minimum_size = Vector2(138,0)
		line.add_child(name_label)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(0,14)
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var under := _bar(Color("2e353c"))
		var over := _bar(Color(0,0,0,0))
		holder.add_child(under)
		holder.add_child(over)
		line.add_child(holder)
		var value := Label.new()
		value.custom_minimum_size = Vector2(84,0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		bars.add_child(line)
		_bars.append({"key":str(stat[0]),"value":value,"under":under,"over":over})
	_numbers = Label.new()
	_numbers.custom_minimum_size = Vector2(168,0)
	_numbers.add_theme_color_override("font_color",MUTED)
	_numbers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_numbers)
	return panel

func _build_view_controls() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",6)
	for entry in [["−",-.1],["+",.1]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(36,36)
		button.pressed.connect(func():
			if is_instance_valid(_live_car): camera_action.emit("zoom",float(entry[1]))
			else: _showroom.zoom_by(float(entry[1])))
		row.add_child(button)
	_rotation_button = Button.new()
	_rotation_button.text = "Girar"
	_rotation_button.toggle_mode = true
	_rotation_button.button_pressed = true
	_rotation_button.toggled.connect(func(enabled):
		if is_instance_valid(_live_car): camera_action.emit("rotate",1.0 if enabled else 0.0)
		else: _showroom.set_auto_rotate(enabled))
	row.add_child(_rotation_button)
	var reset := Button.new()
	reset.text = "Recentrar"
	reset.pressed.connect(func():
		if is_instance_valid(_live_car): camera_action.emit("reset",0.0)
		else: _showroom.reset_view()
		_rotation_button.set_pressed_no_signal(not is_instance_valid(_live_car)))
	row.add_child(reset)
	return row

func _build_footer() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_box(Color("11191df5"),Color("41494c"),1,3,12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	panel.add_child(row)
	_compare = Button.new()
	_compare.text = "Original"
	_compare.toggle_mode = true
	_compare.tooltip_text = "Comparar com o carro antes das mudanças"
	_compare.toggled.connect(_compare_original)
	row.add_child(_compare)
	_total = Label.new()
	_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_total.add_theme_font_size_override("font_size",22)
	_total.add_theme_color_override("font_color",GOLD)
	row.add_child(_total)
	_apply = Button.new()
	_apply.text = "Aplicar mudanças"
	_apply.custom_minimum_size = Vector2(166,42)
	_apply.add_theme_stylebox_override("normal",_box(GOLD,Color("f1cf81"),1,3,12))
	_apply.add_theme_color_override("font_color",Color("161b1e"))
	_apply.pressed.connect(_apply_draft)
	row.add_child(_apply)
	var exit := Button.new()
	exit.text = "Sair da oficina"
	exit.pressed.connect(close_panel)
	row.add_child(exit)
	return panel

func _build_exit_prompt() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -80
	panel.offset_bottom = 80
	panel.add_theme_stylebox_override("panel",_box(Color("11191d"),GOLD,1,3,20))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	panel.add_child(column)
	var title := Label.new()
	title.text = "Há mudanças sem aplicar"
	column.add_child(title)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	for label in ["Continuar","Aplicar e sair","Descartar e sair"]:
		var button := Button.new()
		button.text = label
		buttons.add_child(button)
		if label == "Descartar e sair": button.pressed.connect(discard_and_close)
		elif label == "Aplicar e sair": button.pressed.connect(func():
			if _draft_cost() <= _money: _apply_draft(true))
		else: button.pressed.connect(_continue_preparing)
	panel.hide()
	return panel

func _live_input(event: InputEvent) -> void:
	if not is_instance_valid(_live_car): return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: _live_dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera_action.emit("zoom",.08 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -.08)
	elif event is InputEventMouseMotion and _live_dragging:
		_rotation_button.set_pressed_no_signal(false)
		orbit_requested.emit(event.relative / _live_surface.size.max(Vector2.ONE))

func _bar(background: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.add_theme_stylebox_override("background",_box(background,Color(0,0,0,0),0,4,0))
	bar.add_theme_stylebox_override("fill",_box(GOLD,Color(0,0,0,0),0,4,0))
	return bar

func _build_parts() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",10)
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation",6)
	_tabs.add_theme_constant_override("v_separation",6)
	box.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation",8)
	_scroll.add_child(_cards)
	box.add_child(_scroll)
	return box

func show_vehicle(car_id: String, parts: Dictionary, owned: Array, wins: int, money: int, appearance: Dictionary = {}) -> void:
	if not visible:
		_group = "Visual"
		_menu_level = 0
	if car_id != _car_id or str(appearance.get("archetype",car_id)) != _model_id or _slot.is_empty():
		_group = "Visual"
		_slot = "paint"
		_menu_level = 0
	_car_id = car_id
	_model_id = str(appearance.get("archetype",car_id))
	_parts = TUNING.clean_parts(parts)
	_draft_parts = _parts.duplicate(true)
	_comparison = false
	_compare.set_pressed_no_signal(false)
	_exit_prompt.hide()
	_owned = owned.duplicate()
	_wins = maxi(0,wins)
	_money = maxi(0,money)
	_pending = ""
	_base = PERF.measure(_car_id,_parts)
	var label := str(FLEET.spec(_model_id).get("label",_model_id))
	_title.text = label
	_wallet.text = "R$ %s" % _money_text(_money)
	var shop := _root.find_child("Mechanic",true,false) as Label
	if shop != null: shop.text = mechanic_name
	_message.text = ""
	_rebuild_groups()
	_rebuild_tabs()
	_rebuild_cards()
	_preview({})
	show()
	var shown_model := str(appearance.get("archetype",car_id))
	if not is_instance_valid(_live_car):
		_showroom.show_car(shown_model,appearance.get("paint",FLEET.default_paint(shown_model,Color.WHITE)),_parts)
	else: preview_requested.emit(_parts.duplicate(true))
	set_live_vehicle(_live_car)
	if is_instance_valid(_live_car): camera_action.emit("rotate",0.0)
	_rotation_button.set_pressed_no_signal(false if is_instance_valid(_live_car) else _showroom._auto_rotate)
	_update_total()
	_focus_first()
	if _exit_after_apply:
		_exit_after_apply = false
		discard_and_close.call_deferred()

func set_message(message: String) -> void:
	_exit_after_apply = false
	_message.text = message

func confirm_application() -> void:
	preload("res://gameplay/desert_cars/TuningConfirmationAudio.gd").play(self)

func close_panel() -> void:
	if not visible: return
	if _draft_parts != _parts:
		_exit_prompt.show()
		var button := _exit_prompt.find_children("*","Button",true,false)[0] as Button
		button.grab_focus()
		return
	discard_and_close()

func discard_and_close() -> void:
	_exit_after_apply = false
	_draft_parts = _parts.duplicate(true)
	_exit_prompt.hide()
	hide()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("ui_cancel"):
		request_cancel()
		get_viewport().set_input_as_handled()

func request_cancel() -> void:
	if _exit_prompt.visible: _continue_preparing()
	elif _menu_level > 0: _go_back()
	else: close_panel()

func _continue_preparing() -> void:
	_exit_after_apply = false
	_exit_prompt.hide()
	_compare.grab_focus()

func _money_text(value: int) -> String:
	var digits := str(value)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length()-i) % 3 == 0: out += "."
		out += digits[i]
	return out

func _rebuild_tabs() -> void:
	_tabs.hide()

func _slot_title(slot: String) -> String:
	return str({"sunroof":"Teto","wheel_model":"Modelo","wheel_size":"Aro","wheels":"Cor"}.get(slot,TUNING.SLOT_LABELS.get(slot,slot)))

func _slot_available(slot: String) -> bool:
	for id in TUNING.PARTS:
		if str(TUNING.PARTS[id].slot) == slot and _compatible(str(id)): return true
	return false

func _select_slot(slot: String) -> void:
	for group in GROUPS:
		if slot in GROUPS[group]: _group = group
	_menu_level = 2
	_slot = slot
	_pending = ""
	_rebuild_groups()
	_rebuild_tabs()
	_rebuild_cards()
	_preview({})
	_update_total()
	view_requested.emit(slot)

func _open_slot(slot: String) -> void:
	_select_slot(slot)
	_focus_first()

func _open_category(group: String, focus_item: String = "") -> void:
	_group = group
	_menu_level = 1
	_rebuild_groups()
	_rebuild_cards()
	_preview({})
	_focus_menu_item(focus_item)

func show_visual_menu(focus_item: String = "") -> void:
	_group = "Visual"
	_menu_level = 0
	_rebuild_groups()
	_rebuild_cards()
	_preview({})
	_focus_menu_item(focus_item)

func _go_back() -> void:
	if _menu_level == 2 and _group != "Visual": _open_category(_group,_slot)
	else: show_visual_menu(_slot if _menu_level == 2 else _group)

func _rebuild_groups() -> void:
	for old in _groups.get_children():
		_groups.remove_child(old)
		old.queue_free()
	if _menu_level > 0:
		var back := Button.new()
		back.name = "MenuBack"
		back.text = "Voltar"
		back.pressed.connect(_go_back)
		_groups.add_child(back)
	var title := Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size",19)
	title.text = "Visuais" if _menu_level == 0 else ("Visuais / "+_group if _menu_level == 1 else ("Visuais" if _group == "Visual" else _group)+" / "+_slot_title(_slot))
	_groups.add_child(title)

func _menu_button(label: String, action: Callable, key: String) -> void:
	var button := Button.new()
	button.text = label+"  ›"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 46
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("menu_key",key)
	button.pressed.connect(action)
	_cards.add_child(button)

func _rebuild_cards() -> void:
	for old in _cards.get_children():
		_cards.remove_child(old)
		old.queue_free()
	if _menu_level < 2:
		var menu_slots: Array = GROUPS["Visual"] if _menu_level == 0 else GROUPS[_group]
		for slot in menu_slots:
			if not _slot_available(str(slot)): continue
			_menu_button(_slot_title(str(slot)),_open_slot.bind(str(slot)),str(slot))
		if _menu_level == 0:
			if GROUPS["Carroceria"].any(func(slot): return _slot_available(str(slot))): _menu_button("Carroceria",_open_category.bind("Carroceria"),"Carroceria")
			_menu_button("Rodas",_open_category.bind("Rodas"),"Rodas")
			_menu_button("Desempenho",_open_category.bind("Desempenho"),"Desempenho")
		return
	var ids: Array = []
	for id in TUNING.PARTS:
		if str(TUNING.PARTS[id].slot) == _slot and _compatible(str(id)): ids.append(str(id))
	ids.sort_custom(func(a,b): return int(TUNING.PARTS[a].wins) < int(TUNING.PARTS[b].wins) or (int(TUNING.PARTS[a].wins) == int(TUNING.PARTS[b].wins) and int(TUNING.PARTS[a].cost) < int(TUNING.PARTS[b].cost)))
	_original_card(_slot,_cards,false)
	for id in ids: _cards.add_child(_card(str(id)))

func _compatible(id: String) -> bool:
	return TUNING.compatible(id,_model_id)

func _original_card(slot: String, holder: Container, compact: bool) -> void:
	var row: HBoxContainer
	if not compact:
		row = HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
	if slot == "wheel_model" and not compact:
		var thumbnail := TextureRect.new()
		thumbnail.custom_minimum_size = Vector2(58,50)
		thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var design := "stock:"+_model_id
		thumbnail.set_meta("wheel_design",design)
		thumbnail.texture = _thumbnailer.texture_for(design)
		row.add_child(thumbnail)
	var button := Button.new()
	button.text = "Original" if compact else "Original · R$ 0"
	button.set_meta("original_slot",slot)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.button_pressed = not _draft_parts.has(slot)
	button.custom_minimum_size.y = 34 if compact else 46
	button.pressed.connect(_choose_part.bind(slot,""))
	button.focus_entered.connect(func(): _slot = slot; _preview({"slot":slot,"id":""}))
	button.focus_exited.connect(_preview.bind({}))
	if compact:
		_compact_button(button)
		holder.add_child(button)
	else:
		var panel := PanelContainer.new()
		var selected := not _draft_parts.has(slot)
		panel.add_theme_stylebox_override("panel",_box(Color("22282bcc") if selected else Color("151d20cc"),GOLD if selected else Color("343d40"),2 if selected else 1,3,9))
		button.flat = true
		row.add_child(button)
		panel.add_child(row)
		holder.add_child(panel)

## Acesso estável para testes e atalhos: abre o espaço da peça e devolve o botão do cartão.
func button_for_part(id: String) -> Button:
	if not TUNING.PARTS.has(id): return null
	if str(TUNING.PARTS[id].slot) != _slot or _menu_level != 2: _select_slot(str(TUNING.PARTS[id].slot))
	for card in _cards.find_children("*","PanelContainer",true,false):
		if str(card.get_meta("part_id","")) == id: return card.get_meta("action_button") as Button
	return null

func _card(id: String, compact: bool = false) -> Control:
	var part: Dictionary = TUNING.PARTS[id]
	var slot := str(part.slot)
	var selected := str(_draft_parts.get(slot,"")) == id
	var installed := str(_parts.get(slot,"")) == id
	var rival := str(part.get("rival_reward",""))
	var locked: bool = id not in _owned and (_wins < int(part.wins) or not rival.is_empty() or owned_only)
	var panel := PanelContainer.new()
	panel.set_meta("part_id",id)
	panel.add_theme_stylebox_override("panel",_box(Color("22282bcc") if selected else Color("151d20cc"),GOLD if selected else Color("343d40"),2 if selected else 1,3,5 if compact else 9))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	panel.add_child(row)
	if slot == "wheel_model":
		var image := TextureRect.new()
		image.custom_minimum_size = Vector2(58,50)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var design := str(part.get("wheel_design","five_spoke"))
		image.texture = _thumbnailer.texture_for(design)
		image.set_meta("wheel_design",design)
		row.add_child(image)
	var button := Button.new()
	button.text = str(part.label).trim_prefix("Aro ").capitalize() if compact and slot == "wheel_size" else str(part.label)
	if compact: _compact_button(button)
	if compact and slot == "wheels": button.text = ""
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 30 if compact else 42
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.flat = true
	button.disabled = locked
	button.tooltip_text = "Instalada" if installed else ("Selecionada na prévia" if selected else "Experimentar no carro")
	if compact: button.tooltip_text = "%s · %s" % [str(part.label),"Comprada" if id in _owned else "R$ "+_money_text(int(part.cost))]
	if _group == "Desempenho": button.tooltip_text = str(part.effect)
	if owned_only and id not in _owned: button.tooltip_text = "Adquira esta peça na oficina"
	button.add_theme_color_override("font_color",GOLD if selected else Color("e3e6e5"))
	button.add_theme_stylebox_override("focus",_box(Color("293438"),GOLD,2,2,6))
	if slot in ["paint","wheels","neon","taillights"]:
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(20,20)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = Color(str(part.get("body_color",part.get("wheel_color",part.get("neon",part.get("tail_color","ffffff"))))))
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
	row.add_child(button)
	panel.set_meta("action_button",button)
	if not compact:
		var cost := Label.new()
		cost.text = "Instalada" if installed else ("Comprada" if id in _owned else "R$ %s" % _money_text(int(part.cost)))
		if selected: cost.text += "  ✓"
		if locked: cost.text = "Na oficina" if owned_only and id not in _owned else (String(TranslationServer.translate("%d vitórias")) % int(part.wins) if rival.is_empty() else "Desafio")
		cost.add_theme_color_override("font_color",GOLD if selected else MUTED)
		row.add_child(cost)
	button.pressed.connect(_choose_part.bind(slot,id))
	var change := {"slot":slot,"id":id}
	button.focus_entered.connect(func(): _slot = slot; view_requested.emit(slot); _preview(change))
	button.focus_exited.connect(_preview.bind({}))
	panel.mouse_entered.connect(_preview.bind(change))
	panel.mouse_exited.connect(_preview.bind({}))
	return panel

func _compact_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size",14)
	for state in ["normal","hover","pressed","disabled"]:
		button.add_theme_stylebox_override(state,_box(Color(0,0,0,0),Color(0,0,0,0),0,0,2))

func _refresh_wheel_thumbnail(design: String) -> void:
	for thumbnail in _cards.find_children("*","TextureRect",true,false):
		if str(thumbnail.get_meta("wheel_design","")) == design:
			thumbnail.texture = _thumbnailer.texture_for(design)

func _choose_part(slot: String, id: String) -> void:
	if not id.is_empty() and (not TUNING.PARTS.has(id) or not _compatible(id)): return
	if not id.is_empty():
		var part: Dictionary = TUNING.PARTS[id]
		if str(part.slot) != slot or (id not in _owned and _wins < int(part.wins)): return
		if part.has("rival_reward") and id not in _owned: return
		if owned_only and id not in _owned: return
	_slot = slot
	_menu_level = 2
	for group in GROUPS:
		if slot in GROUPS[group]: _group = group
	if id.is_empty(): _draft_parts.erase(slot)
	else: _draft_parts[slot] = id
	_comparison = false
	_compare.set_pressed_no_signal(false)
	_rebuild_groups()
	_rebuild_cards()
	_preview({})
	_update_total()
	if not id.is_empty(): _focus_later(button_for_part(id))
	else: _focus_first()

func _draft_cost() -> int:
	var total := 0
	for slot in _draft_parts:
		var id := str(_draft_parts[slot])
		if str(_parts.get(slot,"")) != id and id not in _owned: total += int(TUNING.PARTS[id].cost)
	return total

func _update_total() -> void:
	var cost := _draft_cost()
	_total.text = "Total  R$ %s" % _money_text(cost)
	_apply.disabled = _draft_parts == _parts or cost > _money
	_message.text = "Falta R$ %s" % _money_text(cost-_money) if cost > _money else ("Prévia" if _draft_parts != _parts else "")

func _apply_draft(exit_after: bool = false) -> void:
	_exit_after_apply = false
	if _draft_parts == _parts or _draft_cost() > _money: return
	_exit_after_apply = exit_after
	loadout_requested.emit(_draft_parts.duplicate(true))

func _compare_original(enabled: bool) -> void:
	_comparison = enabled
	_compare.text = "Ver prévia" if enabled else "Original"
	_preview({})

## `change` é {slot,id}: como o carro ficaria com essa peça (id vazio = sem a peça).
func _preview(change: Dictionary) -> void:
	var shown: Dictionary = _base
	var candidate := _parts.duplicate() if _comparison else _draft_parts.duplicate()
	if not change.is_empty() and not _comparison:
		if str(change.id).is_empty(): candidate.erase(change.slot)
		else: candidate[change.slot] = change.id
		shown = PERF.measure(_car_id,candidate)
	var changed := candidate != _parts
	# Cosmetic slots keep the vehicle visible without irrelevant mechanical bars.
	_stats_panel.visible = _menu_level == 2 and _group == "Desempenho"
	shown = PERF.measure(_car_id,candidate)
	if is_instance_valid(_live_car): preview_requested.emit(candidate.duplicate(true))
	elif is_instance_valid(_showroom): _showroom.apply_parts(candidate)
	for bar in _bars:
		var current := float(_base[bar.key])
		var next := float(shown[bar.key])
		bar.under.value = maxf(current,next)
		bar.over.value = minf(current,next)
		var tint := GOLD if not changed or is_equal_approx(current,next) else (GOOD if next > current else BAD)
		bar.under.add_theme_stylebox_override("fill",_box(tint,Color(0,0,0,0),0,4,0))
		bar.over.add_theme_stylebox_override("fill",_box(GOLD,Color(0,0,0,0),0,4,0))
		bar.value.text = "%d" % roundi(current) if not changed or is_equal_approx(current,next) else "%d → %d" % [roundi(current),roundi(next)]
		bar.value.add_theme_color_override("font_color",Color.WHITE if not changed or is_equal_approx(current,next) else tint)
	var letter := str(shown["class"])
	_badge_letter.text = letter
	_badge.add_theme_stylebox_override("panel",_box(CLASS_COLORS[letter],Color(0,0,0,0),0,10,4))
	_subtitle.visible = _menu_level == 2 and _group == "Desempenho"
	_subtitle.text = "Classe "+letter
	_subtitle.tooltip_text = String(TranslationServer.translate("%d / %d vitórias")) % [_wins,RACE_WINS.maximum()]
	_numbers.text = "0–100 km/h: %s\n400 m: %s\nFinal: %d km/h" % [_seconds(shown.zero_to_100),_seconds(shown.quarter),roundi(float(shown.top_kmh))]

func _seconds(value: Variant) -> String:
	return "—" if float(value) == INF else "%.2f s" % float(value)

## Os cartões são refeitos a cada mudança; o foco só vale se o botão ainda estiver na tela.
func _focus_later(button: Button) -> void:
	if button == null: return
	# A weak reference survives replacing cards before the deferred callback.
	var reference: WeakRef = weakref(button)
	var grab := func():
		var target: Button = reference.get_ref()
		if target != null and target.is_inside_tree() and target.is_visible_in_tree(): target.grab_focus()
	grab.call_deferred()

func _focus_first() -> void:
	if _menu_level == 2:
		var selected_id := str(_draft_parts.get(_slot,""))
		if not selected_id.is_empty():
			var selected := button_for_part(selected_id)
			if selected != null and not selected.disabled:
				_focus_later(selected)
				return
		for option in _cards.find_children("*","Button",true,false):
			if str(option.get_meta("original_slot","")) == _slot:
				_focus_later(option as Button)
				return
		return
	for child in _cards.get_children():
		if child is Button and not child.disabled:
			_focus_later(child)
			return

func _focus_menu_item(key: String) -> void:
	for child in _cards.get_children():
		if child is Button and str(child.get_meta("menu_key","")) == key:
			_focus_later(child)
			return
	_focus_first()
