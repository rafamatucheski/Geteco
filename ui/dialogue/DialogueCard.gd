extends "res://ui/dialogue/DialogueCaption.gd"
## A conversation line with a real, focusable advance action. Session owns input.
signal advance_requested

var advance_button: Button
var binding_label: Label
var _controls: Node
var _footer: HBoxContainer

func _init() -> void:
	super()
	name = "DialogueCard"
	max_width = 600.0
	bottom_margin = 30.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_footer = HBoxContainer.new()
	_footer.alignment = BoxContainer.ALIGNMENT_END
	_footer.add_theme_constant_override("separation", 10)
	content.add_child(_footer)
	binding_label = STYLE.label("", 14, STYLE.MUTED)
	binding_label.name = "ContinueBinding"
	binding_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	binding_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var keycap := STYLE.compact(false, 4, Vector2(7, 3))
	keycap.bg_color = Color("252b32")
	keycap.shadow_size = 0
	binding_label.add_theme_stylebox_override("normal", keycap)
	_footer.add_child(binding_label)
	advance_button = Button.new()
	advance_button.name = "Continue"
	advance_button.text = "Continuar"
	advance_button.focus_mode = Control.FOCUS_ALL
	advance_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	advance_button.add_theme_font_override("font", STYLE.STRONG)
	for state in ["normal", "hover", "pressed"]:
		var button_style := STYLE.compact(state != "normal", 6, Vector2(13, 5))
		button_style.bg_color = Color("303038") if state != "normal" else Color("23282f")
		button_style.border_color = VOICE_ACCENT if state != "normal" else Color("4b4d50")
		button_style.shadow_size = 0
		advance_button.add_theme_stylebox_override(state, button_style)
	var focus := STYLE.compact(true, 6, Vector2(13, 5))
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = VOICE_ACCENT
	focus.set_border_width_all(2)
	focus.shadow_size = 0
	advance_button.add_theme_stylebox_override("focus", focus)
	advance_button.add_theme_color_override("font_color", STYLE.TEXT)
	advance_button.add_theme_color_override("font_focus_color", STYLE.TEXT)
	advance_button.add_theme_color_override("font_hover_color", STYLE.TEXT)
	_footer.add_child(advance_button)
	advance_button.pressed.connect(func(): advance_requested.emit())

func configure(speaker: String, spoken_text: String, controls: Node = null, continue_label := "") -> void:
	_set_controls(controls)
	advance_button.text = continue_label if not continue_label.is_empty() else ("Continue" if TranslationServer.get_locale().begins_with("en") else "Continuar")
	set_line(speaker, spoken_text)
	_refresh_binding()

func focus_advance() -> void:
	if is_visible_in_tree(): advance_button.grab_focus()

func _apply_scale(value: float) -> void:
	super._apply_scale(value)
	advance_button.add_theme_font_size_override("font_size", roundi(15.0*value))
	binding_label.add_theme_font_size_override("font_size", roundi(14.0*value))
	advance_button.custom_minimum_size.y = roundf(28.0*value)

func _set_controls(controls: Node) -> void:
	if _controls == controls: return
	if is_instance_valid(_controls):
		for signal_name in ["bindings_changed", "device_changed"]:
			if _controls.has_signal(signal_name) and _controls.is_connected(signal_name, _refresh_binding):
				_controls.disconnect(signal_name, _refresh_binding)
	_controls = controls
	if is_instance_valid(_controls):
		for signal_name in ["bindings_changed", "device_changed"]:
			if _controls.has_signal(signal_name): _controls.connect(signal_name, _refresh_binding)

func _refresh_binding() -> void:
	var binding := str(_controls.prompt("interact")) if is_instance_valid(_controls) and _controls.has_method("prompt") else ""
	binding_label.text = binding
	binding_label.visible = not binding.is_empty() and binding != "—"

func _exit_tree() -> void:
	_set_controls(null)
