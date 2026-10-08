extends Control
## Presentation only. The caller owns unlocks, wallet mutations and persistence.
signal style_requested(id: String)
signal close_requested
const STYLES := preload("res://activities/desert_drag/DragInstrumentStyles.gd")
const HUD := preload("res://activities/desert_drag/DesertDragHUD.gd")
const FACE := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const BODY := preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const PAPER := Color("f4f3ef")
const MUTED := Color("98a4af")
const CORAL := Color("ff633b")
const CYAN := Color("58d7ec")
var rows: Array[Button] = []
var action_button: Button
var back_button: Button
var preview: Control
var selected := "classic"
var equipped := "classic"
var owned: Array = ["classic", "bar"]
var victories := 0
var money := 0
var message := ""
var _confirming := ""
var _definitions: Array[Dictionary] = []

func _ready() -> void:
	custom_minimum_size = Vector2(900, 640)
	size = custom_minimum_size
	_definitions = STYLES.definitions()
	for index in _definitions.size():
		var row := Button.new()
		row.name = str(_definitions[index].id)
		row.tooltip_text = str(_definitions[index].name)
		row.position = Vector2(30, 136 + index * 81)
		row.size = Vector2(299, 73)
		row.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		row.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, .045)))
		row.add_theme_stylebox_override("pressed", _box(Color(1, 1, 1, .08)))
		row.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, CYAN))
		row.pressed.connect(select_style.bind(str(_definitions[index].id)))
		row.focus_entered.connect(select_style.bind(str(_definitions[index].id)))
		add_child(row)
		rows.append(row)
	var window := Control.new()
	window.name = "InstrumentPreview"
	window.position = Vector2(356, 139)
	window.size = Vector2(512, 252)
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(window)
	preview = HUD.new()
	preview.name = "LiveInstrumentStyle"
	preview.set("preview_mode", true)
	window.add_child(preview)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.set_process(false)
	preview.set_process_input(false)
	preview.set("rpm", 5780.0)
	preview.set("speed", 168.0)
	preview.set("gear", 4)
	preview.set("nitro", .68)
	preview.set("racing", true)
	preview.set("input_gamepad", false)
	action_button = Button.new()
	action_button.position = Vector2(356, 510)
	action_button.size = Vector2(512, 54)
	_button_style(action_button, true)
	action_button.pressed.connect(_activate)
	add_child(action_button)
	back_button = Button.new()
	back_button.text = "VOLTAR"
	back_button.position = Vector2(733, 32)
	back_button.size = Vector2(135, 41)
	_button_style(back_button, false)
	back_button.pressed.connect(func(): close_requested.emit())
	add_child(back_button)
	for row in rows: row.focus_neighbor_right = row.get_path_to(action_button)
	_refresh()

func show_styles(state: Dictionary, wins: int, available_money: int) -> void:
	owned = state.get("owned", ["classic", "bar"]).duplicate()
	equipped = str(state.get("selected", "classic"))
	selected = equipped if STYLES.IDS.has(equipped) else "classic"
	victories = maxi(0, wins)
	money = maxi(0, available_money)
	_confirming = ""
	message = ""
	_refresh()
	if not rows.is_empty(): rows[STYLES.IDS.find(selected)].grab_focus()

func select_style(id: String) -> void:
	if not STYLES.IDS.has(id): return
	if id != selected:
		_confirming = ""
		message = ""
	selected = id
	_refresh()

func set_message(text: String) -> void:
	message = text
	_confirming = ""
	_refresh()

func _activate() -> void:
	if action_button.disabled: return
	var definition: Dictionary = STYLES.CATALOG[selected]
	if selected not in owned and int(definition.price) > 0 and _confirming != selected:
		_confirming = selected
		message = ""
		_refresh()
		return
	_confirming = ""
	_refresh()
	style_requested.emit(selected)

func _input(event: InputEvent) -> void:
	# Handle Back before the session's generic modal shortcut closes both screens.
	if is_visible_in_tree() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game")):
		close_requested.emit()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	if action_button == null: return
	var definition: Dictionary = STYLES.CATALOG[selected]
	var bought := selected in owned
	var locked := not bought and victories < int(definition.wins)
	var short_of_cash := not bought and money < int(definition.price)
	action_button.disabled = selected == equipped or locked or short_of_cash
	if selected == equipped: action_button.text = "EQUIPADO"
	elif bought or int(definition.price) == 0: action_button.text = "EQUIPAR  →"
	elif locked: action_button.text = "LIBERA COM " + _wins_label(int(definition.wins))
	elif short_of_cash: action_button.text = "FALTAM " + _cash(int(definition.price) - money)
	elif _confirming == selected: action_button.text = "CONFIRMAR COMPRA · " + _cash(int(definition.price))
	else: action_button.text = "COMPRAR · " + _cash(int(definition.price))
	preview.call("set_style", selected)
	preview.queue_redraw()
	var row := rows[STYLES.IDS.find(selected)]
	action_button.focus_neighbor_left = action_button.get_path_to(row)
	queue_redraw()

func _cash(amount: int) -> String:
	var digits := str(amount)
	var formatted := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0: formatted += "."
		formatted += digits[index]
	return "R$ " + formatted

func _wins_label(count: int) -> String:
	return "%d %s" % [count, "RIVAL VENCIDO" if count == 1 else "RIVAIS VENCIDOS"]

func _box(color: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	return style

func _button_style(button: Button, primary: bool) -> void:
	button.add_theme_font_override("font", FACE)
	button.add_theme_font_size_override("font_size", 21 if primary else 17)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(key, Color("11161c") if primary else PAPER)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _box(CORAL if primary else Color("26313c")))
	button.add_theme_stylebox_override("hover", _box(Color("ff845d") if primary else Color("394959")))
	button.add_theme_stylebox_override("pressed", _box(Color("dc4d2b") if primary else Color("425366")))
	button.add_theme_stylebox_override("disabled", _box(Color("252e38")))
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, CYAN))

func _text(at: Vector2, text: String, points: int, color := PAPER, strong := false, width := -1.0, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(FACE if strong else BODY, at, text, alignment, width, points, color)

func _draw() -> void:
	if _definitions.is_empty(): return
	draw_style_box(_box(Color(0, 0, 0, .3)), Rect2(7, 9, 900, 640))
	draw_style_box(_box(Color("11171e"), Color("34414e")), Rect2(0, 0, 900, 640))
	draw_rect(Rect2(0, 0, 900, 4), CORAL)
	_text(Vector2(30, 32), "ARRANCADA", 14, MUTED, true)
	_text(Vector2(30, 79), "PAINÉIS", 43, PAPER, true)
	_text(Vector2(454, 35), "SALDO", 12, MUTED, true, 246, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(454, 69), _cash(money), 28, PAPER, true, 246, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_line(Vector2(30, 95), Vector2(868, 95), Color("34414e"), 1)
	_text(Vector2(41, 121), "MODELO", 14, MUTED, true)
	_text(Vector2(356, 121), "PRÉVIA", 14, MUTED, true)
	for index in _definitions.size():
		var definition := _definitions[index]
		var id := str(definition.id)
		var at := Vector2(30, 136 + index * 81)
		var locked := id not in owned and victories < int(definition.wins)
		var chosen := id == selected
		draw_style_box(_box(Color("293642") if chosen else Color("1b2530")), Rect2(at, Vector2(299, 73)))
		if chosen: draw_rect(Rect2(at, Vector2(3, 73)), CORAL)
		_text(at + Vector2(15, 31), str(definition.name).to_upper(), 25, MUTED if locked else PAPER, true)
		var status := "EQUIPADO" if id == equipped else ("ADQUIRIDO" if id in owned else (_wins_label(int(definition.wins)) if locked else _cash(int(definition.price))))
		_text(at + Vector2(16, 56), status, 14, CYAN if id in owned else (MUTED if locked else CORAL), true)
		if locked:
			var needed := int(definition.wins)
			_text(at + Vector2(224, 44), "%d / %d" % [mini(victories, needed), needed], 19, MUTED, true)
		elif id == equipped:
			draw_line(at + Vector2(260, 35), at + Vector2(267, 42), CYAN, 2)
			draw_line(at + Vector2(267, 42), at + Vector2(280, 27), CYAN, 2)
	draw_style_box(_box(Color("0b1016"), Color("26343f")), Rect2(356, 136, 512, 258))
	var selected_definition: Dictionary = STYLES.CATALOG[selected]
	_text(Vector2(356, 435), str(selected_definition.name).to_upper(), 31, PAPER, true)
	var detail := "ADQUIRIDO" if selected in owned else ("LIBERA COM " + _wins_label(int(selected_definition.wins)) if victories < int(selected_definition.wins) else _cash(int(selected_definition.price)))
	if _confirming == selected: detail = "CONFIRMAR COMPRA?"
	_text(Vector2(356, 469), detail, 18, CORAL if _confirming == selected else MUTED, true)
	draw_line(Vector2(30, 582), Vector2(868, 582), Color("34414e"), 1)
	if not message.is_empty():
		draw_multiline_string(BODY, Vector2(32, 605), message, HORIZONTAL_ALIGNMENT_LEFT, 835, 17, 2, CORAL)
	else:
		_text(Vector2(32, 612), "↑ ↓  SELECIONAR", 15, MUTED)
		_text(Vector2(227, 612), "→  AÇÃO  /  ENTER  CONFIRMAR", 15, MUTED)
		_text(Vector2(725, 612), "ESC / B  VOLTAR", 15, MUTED)
