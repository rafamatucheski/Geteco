extends Control
## Shared world interaction key. Geometry is cached by CanvasItem until changed.
const INK := Color("f4eddf")
static var _face: StyleBoxFlat
static var _base: StyleBoxFlat
var _label: Label
var _key := ""
var _font_size := 0
var _original: Dictionary = {}

static func sync(label: Label, active: bool) -> void:
	var cap := label.get_node_or_null("InteractionKeycap")
	if not active:
		if cap != null: cap.restore()
		return
	if cap == null:
		cap = load("res://ui/InteractionKeycap.gd").new()
		cap.name = "InteractionKeycap"
		label.add_child(cap)
	cap.refresh()

func _ready() -> void:
	_label = get_parent() as Label
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	if _face == null:
		_face = StyleBoxFlat.new()
		_face.bg_color = Color("202930")
		_face.border_color = Color("b4b8af")
		_face.set_border_width_all(1)
		_face.set_corner_radius_all(5)
		_base = StyleBoxFlat.new()
		_base.bg_color = Color("080e14")
		_base.set_corner_radius_all(5)
		_base.shadow_color = Color(0, 0, 0, 0.42)
		_base.shadow_size = 3
		_base.shadow_offset = Vector2(0, 2)

func refresh() -> void:
	if _original.is_empty():
		_original = {"alignment": _label.vertical_alignment}
		for token in ["font_color", "font_shadow_color"]:
			_original[token] = _label.get_theme_color(token) if _label.has_theme_color_override(token) else null
		_original["font_size"] = _label.get_theme_font_size("font_size") if _label.has_theme_font_size_override("font_size") else null
		_label.add_theme_color_override("font_color", INK)
		_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		_label.add_theme_font_size_override("font_size", maxi(16, _label.get_theme_font_size("font_size")))
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	visible = true
	var font_size := _label.get_theme_font_size("font_size")
	if _key != _label.text or _font_size != font_size:
		_key = _label.text
		_font_size = font_size
		queue_redraw()

func restore() -> void:
	visible = false
	if _original.is_empty(): return
	for token in ["font_color", "font_shadow_color"]:
		if _original[token] == null: _label.remove_theme_color_override(token)
		else: _label.add_theme_color_override(token, _original[token])
	if _original.font_size == null: _label.remove_theme_font_size_override("font_size")
	else: _label.add_theme_font_size_override("font_size", _original.font_size)
	_label.vertical_alignment = _original.alignment
	_original.clear()

func _draw() -> void:
	if _label == null or _font_size == 0: return
	var font := _label.get_theme_font("font")
	var glyph_width := font.get_string_size(_key, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
	var height := maxf(28, _font_size + 12)
	var width := maxf(height, glyph_width + 18)
	var center_x := size.x * 0.5
	if _label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT: center_x = glyph_width * 0.5
	elif _label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT: center_x = size.x - glyph_width * 0.5
	var rect := Rect2(Vector2(center_x-width*0.5, (size.y-height)*0.5), Vector2(width, height))
	draw_style_box(_base, Rect2(rect.position + Vector2(0, 3), rect.size))
	draw_style_box(_face, rect)
	# Amber notch is the consistent interaction accent, including controller glyphs.
	draw_line(rect.position + Vector2(8, 1), rect.position + Vector2(width-8, 1), Color("e8b77d"), 2.0, true)
