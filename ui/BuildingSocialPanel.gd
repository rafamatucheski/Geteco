extends Control
## Functional conversation controls; the session owns input and the live world.
signal action_requested(action_id: String)
signal close_requested
const STYLE := preload("res://ui/GameStyle.gd")
var card: PanelContainer
var name_label: Label
var mood_label: Label
var reply_label: Label
var close_button: Button
var buttons: Dictionary = {}
var _column: VBoxContainer
var _dock_left := false

func _init() -> void:
	name = "BuildingSocialPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = STYLE.create_theme(18)
	card = PanelContainer.new()
	card.set_meta("preserve_panel_style", true)
	card.add_theme_stylebox_override("panel", STYLE.panel())
	add_child(card)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 8)
	card.add_child(_column)
	name_label = STYLE.label("", 24, STYLE.ACCENT)
	_column.add_child(name_label)
	mood_label = STYLE.label("", 16, STYLE.MUTED)
	_column.add_child(mood_label)
	reply_label = Label.new()
	reply_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reply_label.custom_minimum_size.y = 52
	reply_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(reply_label)
	for row in [["greet", "Cumprimentar"], ["chat", "Conversar"], ["joke", "Brincar"], ["reassure", "Acalmar"], ["intimidate", "Intimidar"]]:
		var button := Button.new()
		var action_id: String = row[0]
		button.name = action_id
		button.text = row[1]
		button.custom_minimum_size.y = 36
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(func(): action_requested.emit(action_id))
		_column.add_child(button)
		buttons[action_id] = button
	close_button = Button.new()
	close_button.name = "LeaveConversation"
	close_button.text = "Encerrar conversa"
	close_button.custom_minimum_size.y = 36
	close_button.pressed.connect(func(): close_requested.emit())
	_column.add_child(close_button)
	hide()

func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	card.minimum_size_changed.connect(_queue_layout)
	_layout()

func present(snapshot: Dictionary, options: Array, line := "") -> void:
	name_label.text = str(snapshot.get("name", "Morador"))
	mood_label.text = str(snapshot.get("mood_label", "Tranquilo"))
	var state: String = str(snapshot.get("state", "neutral"))
	mood_label.add_theme_color_override("font_color", STYLE.HEALTH if state in ["scared", "annoyed", "calling_police"] else STYLE.MONEY if state == "happy" else STYLE.MUTED)
	if not line.is_empty(): reply_label.text = line
	var focused := get_viewport().gui_get_focus_owner()
	var available: Dictionary = {}
	for option: Dictionary in options:
		var id := str(option.get("id", ""))
		if not buttons.has(id): continue
		var button: Button = buttons[id]
		button.text = str(option.get("label", button.text))
		available[id] = bool(option.get("enabled", true))
	for id: String in buttons:
		buttons[id].disabled = not bool(available.get(id, false))
	show()
	STYLE.trap_focus(card, false)
	if focused is Button and card.is_ancestor_of(focused) and focused.disabled: close_button.grab_focus()
	_queue_layout()

func focus_first() -> void:
	if not is_visible_in_tree(): return
	STYLE.trap_focus(card)

func activate_focused() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is Button and card.is_ancestor_of(focused) and not focused.disabled: focused.pressed.emit()

func set_conversation_anchor(screen_point: Vector2) -> void:
	# Keep both people visible while they gesture and respond. The viewport owns
	# projection; this surface only selects the free side of the conversation.
	var dock_left := screen_point.x >= get_viewport_rect().size.x * .5
	if _dock_left == dock_left: return
	_dock_left = dock_left
	_layout()

func _queue_layout() -> void:
	_layout.call_deferred()

func _layout() -> void:
	if not is_inside_tree(): return
	var extent := get_viewport_rect().size
	var width := minf(390.0, maxf(220.0, extent.x - 32.0))
	card.custom_minimum_size.x = width
	card.size = Vector2(width, card.get_combined_minimum_size().y)
	var horizontal := 24.0 if _dock_left else maxf(16.0, extent.x - width - 24.0)
	card.position = Vector2(horizontal, maxf(16.0, (extent.y - card.size.y) * .5)).round()
