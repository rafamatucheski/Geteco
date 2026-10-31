extends PanelContainer
## Apresentação compartilhada e por evento para legendas faladas e cartões de conversa.
## Os produtores cuidam de tempo, áudio e entrada; esta superfície só mostra a fala deles.
const STYLE := preload("res://ui/GameStyle.gd")
const VOICE_ACCENT := Color("dfa96a")

var speaker_label: Label
var message: Label
var content: VBoxContainer
var max_width := 640.0
var bottom_margin := 28.0
var text: String:
	get: return _text
	set(value):
		var split := value.find("\n")
		set_line(value.left(split) if split >= 0 else "", value.substr(split+1) if split >= 0 else value)

var _text := ""
var _speaker := ""
var _message := ""
var _layout_queued := false
var _scale := -1.0
var _surface: StyleBoxFlat

func _init() -> void:
	name = "DialogueCaption"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_meta("preserve_panel_style", true)
	theme = STYLE.create_theme(23)
	_surface = STYLE.panel()
	_surface.bg_color = Color(0.066, 0.078, 0.095, 0.90)
	_surface.border_color = Color("42484e")
	_surface.set_corner_radius_all(9)
	_surface.shadow_color = Color(0, 0, 0, 0.3)
	_surface.shadow_size = 3
	add_theme_stylebox_override("panel", _surface)
	content = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	add_child(content)
	var identity := HBoxContainer.new()
	identity.name = "Identity"
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_theme_constant_override("separation", 12)
	content.add_child(identity)
	speaker_label = STYLE.label("", 13, VOICE_ACCENT)
	speaker_label.name = "Speaker"
	speaker_label.add_theme_font_override("font", STYLE.STRONG)
	identity.add_child(speaker_label)
	var rule := HSeparator.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line := StyleBoxLine.new()
	line.color = Color(VOICE_ACCENT, 0.22)
	line.thickness = 1
	rule.add_theme_stylebox_override("separator", line)
	identity.add_child(rule)
	message = Label.new()
	message.name = "Message"
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message.add_theme_font_override("font", STYLE.FONT)
	message.add_theme_color_override("font_color", STYLE.TEXT)
	message.add_theme_constant_override("line_spacing", 4)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(message)
	hide()

func _ready() -> void:
	get_viewport().size_changed.connect(_queue_layout)
	minimum_size_changed.connect(_queue_layout)
	_queue_layout()

func set_line(speaker: String, spoken_text: String) -> void:
	if speaker == _speaker and spoken_text == _message:
		visible = not spoken_text.is_empty()
		return
	_speaker = speaker
	_message = spoken_text
	_text = speaker+"\n"+spoken_text if not speaker.is_empty() and not spoken_text.is_empty() else spoken_text
	speaker_label.text = speaker
	speaker_label.get_parent().visible = not speaker.is_empty()
	message.text = spoken_text
	visible = not spoken_text.is_empty()
	_queue_layout()

func layout_for_viewport(extent: Vector2) -> void:
	if extent.x <= 0 or extent.y <= 0: return
	var next_scale := clampf(extent.y/720.0, 0.85, 1.25)
	if not is_equal_approx(_scale, next_scale):
		_scale = next_scale
		_apply_scale(_scale)
	var margin := maxf(18.0, 28.0*_scale)
	var width := minf(max_width*_scale, extent.x-margin*2.0)
	custom_minimum_size.x = width
	size = Vector2(width, get_combined_minimum_size().y)
	position = Vector2((extent.x-size.x)*0.5, maxf(margin, extent.y-size.y-bottom_margin*_scale)).round()

func _apply_scale(value: float) -> void:
	speaker_label.add_theme_font_size_override("font_size", roundi(13.0*value))
	message.add_theme_font_size_override("font_size", roundi(18.0*value))
	content.add_theme_constant_override("separation", roundi(6.0*value))
	_surface.content_margin_left = roundf(16.0*value)
	_surface.content_margin_right = roundf(16.0*value)
	_surface.content_margin_top = roundf(10.0*value)
	_surface.content_margin_bottom = roundf(10.0*value)

func _queue_layout() -> void:
	if _layout_queued or not is_inside_tree(): return
	_layout_queued = true
	_layout.call_deferred()

func _layout() -> void:
	_layout_queued = false
	if is_inside_tree(): layout_for_viewport(get_viewport_rect().size)
