extends Control
## The host owns the world, modal locks, mouse mode and rewards. This panel only
## times three throws and reports their results; it does no work while closed.

signal throw_released(strength: float, hit: bool)
signal finished(hits: int)

const STYLE := preload("res://ui/GameStyle.gd")
const THROWS := 3
const TARGET_MIN := 0.62
const TARGET_MAX := 0.78
const THROW_SECONDS := 1.15
const SWEEP_SPEED := 0.82

var active := false
var attempts := 0
var hits := 0
var strength := 0.0
var cooldown := 0.0
var _phase := 0.0
var _awaiting_release := true
var _panel: PanelContainer
var _attempt_label: Label
var _score_label: Label
var _instruction: Label
var _meter: Control
var _throw_button: Button
var _cancel_button: Button


static func is_hit(value: float) -> bool:
	return is_finite(value) and value >= TARGET_MIN and value <= TARGET_MAX


func _ready() -> void:
	name = "TruckersVillageHorseshoes"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = STYLE.create_theme(16)
	_build_panel()
	resized.connect(_layout)
	_panel.minimum_size_changed.connect(_layout)
	var controls := get_node_or_null("/root/GameInput")
	if controls != null:
		controls.bindings_changed.connect(_refresh_controls)
		controls.device_changed.connect(_refresh_controls)
	_refresh_controls()
	_layout()
	hide()
	set_process(false)
	set_process_input(false)


func open_game() -> bool:
	if active or not is_node_ready():
		return false
	active = true
	attempts = 0
	hits = 0
	strength = 0.0
	cooldown = 0.0
	_phase = 0.0
	# Always require a released frame, including when opened from an input
	# callback before Godot has finished dispatching that same input event.
	_awaiting_release = true
	show()
	_cancel_button.release_focus()
	set_process(true)
	set_process_input(true)
	_instruction.text = "Solte a ação para começar"
	_refresh()
	_layout()
	return true


func cancel_game() -> void:
	_finish(-1)


func _finish(result: int) -> void:
	if not active:
		return
	active = false
	cooldown = 0.0
	set_process(false)
	set_process_input(false)
	hide()
	finished.emit(result)


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if not active or not is_finite(delta) or delta <= 0.0:
		return
	if _awaiting_release and not _launch_is_held():
		_awaiting_release = false
		if cooldown <= 0.0:
			_instruction.text = "Lance na faixa dourada"
		_refresh()
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)
		if cooldown > 0.0:
			return
		if attempts >= THROWS:
			_finish(hits)
			return
		_phase = 0.0
		strength = 0.0
		_instruction.text = "Lance na faixa dourada"
		_refresh()
		return
	if _awaiting_release:
		return
	_phase = fposmod(_phase + delta * SWEEP_SPEED, 2.0)
	strength = 1.0 - absf(_phase - 1.0)
	_meter.queue_redraw()


func try_throw() -> bool:
	if not active or _awaiting_release or cooldown > 0.0 or attempts >= THROWS:
		return false
	var hit := is_hit(strength)
	attempts += 1
	if hit:
		hits += 1
	cooldown = THROW_SECONDS
	_awaiting_release = true
	_instruction.text = "Acertou!" if hit else ("Ficou curto" if strength < TARGET_MIN else "Passou do alvo")
	_refresh()
	throw_released.emit(strength, hit)
	return true


func _launch_is_held() -> bool:
	return Input.is_action_pressed("interact") or Input.is_action_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
		get_viewport().set_input_as_handled()
		if not event.is_echo():
			cancel_game()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if event.is_echo():
			return
		if event.is_action_pressed("ui_accept") and _cancel_button.has_focus():
			cancel_game()
		else:
			try_throw()


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "ThrowPanel"
	_panel.add_theme_stylebox_override("panel", STYLE.compact(true, 10, Vector2(18, 12)))
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := STYLE.label("Ferraduras", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_attempt_label = STYLE.label("", 16, STYLE.MUTED)
	heading.add_child(_attempt_label)
	_score_label = STYLE.label("", 16, STYLE.ACCENT)
	column.add_child(_score_label)
	_meter = Control.new()
	_meter.name = "StrengthMeter"
	_meter.custom_minimum_size = Vector2(0, 32)
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.draw.connect(_draw_meter)
	column.add_child(_meter)
	_instruction = STYLE.label("", 16, STYLE.MUTED)
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_instruction)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	_throw_button = Button.new()
	_throw_button.name = "Throw"
	_throw_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_throw_button.add_theme_stylebox_override("normal", STYLE.button(true))
	_throw_button.pressed.connect(try_throw)
	buttons.add_child(_throw_button)
	_cancel_button = Button.new()
	_cancel_button.name = "Cancel"
	_cancel_button.text = "Sair"
	_cancel_button.pressed.connect(cancel_game)
	buttons.add_child(_cancel_button)
	_throw_button.focus_neighbor_right = _throw_button.get_path_to(_cancel_button)
	_throw_button.focus_next = _throw_button.focus_neighbor_right
	_throw_button.focus_previous = _throw_button.focus_neighbor_right
	_cancel_button.focus_neighbor_left = _cancel_button.get_path_to(_throw_button)
	_cancel_button.focus_next = _cancel_button.focus_neighbor_left
	_cancel_button.focus_previous = _cancel_button.focus_neighbor_left


func _refresh_controls() -> void:
	if _throw_button == null:
		return
	var controls := get_node_or_null("/root/GameInput")
	var key: String = controls.hint("interact") if controls != null else "E"
	_throw_button.text = "Lançar · %s" % key


func _refresh() -> void:
	var shown_attempt := attempts if cooldown > 0.0 else mini(attempts + 1, THROWS)
	_attempt_label.text = "%d / %d" % [shown_attempt, THROWS]
	_score_label.text = "Acertos: %d" % hits
	_throw_button.disabled = not active or _awaiting_release or cooldown > 0.0
	if not _throw_button.disabled and not _cancel_button.has_focus():
		_throw_button.grab_focus()
	_meter.queue_redraw()


func _layout() -> void:
	if _panel == null:
		return
	var width := minf(520.0, maxf(0.0, size.x - 32.0))
	_panel.size.x = width
	_panel.size.y = _panel.get_combined_minimum_size().y
	_panel.position = Vector2((size.x - width) * 0.5, maxf(8.0, size.y - _panel.size.y - 24.0))


func _draw_meter() -> void:
	var track := Rect2(5, 8, maxf(0.0, _meter.size.x - 10), 16)
	_meter.draw_rect(track, STYLE.INK)
	var target := Rect2(track.position + Vector2(track.size.x * TARGET_MIN, 0), Vector2(track.size.x * (TARGET_MAX - TARGET_MIN), track.size.y))
	_meter.draw_rect(target, STYLE.ACCENT)
	_meter.draw_rect(track, STYLE.LINE, false, 1.0)
	var x := track.position.x + track.size.x * strength
	_meter.draw_line(Vector2(x, 3), Vector2(x, 29), STYLE.TEXT, 3.0, true)
	_meter.draw_circle(Vector2(x, 4), 3.0, STYLE.TEXT)
