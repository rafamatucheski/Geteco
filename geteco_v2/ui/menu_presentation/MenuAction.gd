extends Button
## Native Button behavior with a wrapping caption. Configure once per instance.

var caption := Label.new()

func _init() -> void:
	custom_minimum_size.y = 52
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.offset_left = 18
	caption.offset_right = -18
	caption.offset_top = 12
	caption.offset_bottom = -12
	resized.connect(_fit_caption)
	theme_changed.connect(_fit_caption)

func configure(label_text: String, action: Callable, unavailable := false) -> void:
	caption.text = label_text
	tooltip_text = label_text
	disabled = unavailable or not action.is_valid()
	caption.modulate = Color("b9c7d2") if disabled else Color.WHITE
	if not disabled: pressed.connect(action)
	_fit_caption.call_deferred()

func _fit_caption() -> void:
	if not is_inside_tree(): return
	var font := caption.get_theme_font("font")
	var font_size := caption.get_theme_font_size("font_size")
	var measured := font.get_multiline_string_size(
		caption.text, HORIZONTAL_ALIGNMENT_LEFT, maxf(1, size.x - 36), font_size,
		-1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var lines := maxi(1, ceili(measured.y / maxf(1, font.get_height(font_size))))
	var spacing := maxi(0, caption.get_theme_constant("line_spacing")) * (lines - 1)
	custom_minimum_size.y = maxf(52, ceilf(measured.y) + spacing + 24)
