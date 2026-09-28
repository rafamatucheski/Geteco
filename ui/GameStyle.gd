extends RefCounted
## Linguagem visual compartilhada, sem trocar as cores funcionais do HUD.
const INK := Color("171a1f")
const SURFACE := Color("20242a")
const GLASS := Color(19.0/255, 22.0/255, 27.0/255, .88)
const LINE := Color("4a4f55")
const TEXT := Color("f1eee7")
const MUTED := Color("a8adb3")
const ACCENT := Color("c9a35f")
const HEALTH := Color("ea6262")
const ARMOR := Color("69b8dc")
const COLD := Color("8cdceb")
const MONEY := Color("d9b35f")
const WAYPOINT := Color("e6a84b")
const DISABLED := Color("62676d")
const MAP_ROAD := Color("999a94")
const MAP_CONTOUR := Color("303e40")
const FONT := preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const STRONG := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const FADE := .18
const SAFE_MARGIN := 24.0

static func compact(accent := false, radius := 10, padding := Vector2(12,8)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = GLASS
	s.border_color = ACCENT if accent else LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = padding.x
	s.content_margin_right = padding.x
	s.content_margin_top = padding.y
	s.content_margin_bottom = padding.y
	s.shadow_color = Color(0,0,0,.22)
	s.shadow_size = 4
	return s

static func create_theme(font_size := 16) -> Theme:
	var result := Theme.new()
	result.default_font = FONT
	result.default_font_size = font_size
	for type in ["Label", "Button", "OptionButton", "CheckButton", "RichTextLabel"]:
		result.set_color("font_color", type, TEXT)
		result.set_color("font_disabled_color", type, DISABLED)
		result.set_color("font_hover_color", type, TEXT)
		result.set_color("font_focus_color", type, ACCENT)
		result.set_color("default_color", type, TEXT)
	result.set_stylebox("panel", "PanelContainer", panel())
	for state in ["normal", "hover", "pressed", "disabled"]:
		result.set_stylebox(state, "Button", button(state in ["hover", "pressed"]))
	var focus := compact(true,8)
	focus.bg_color = Color.TRANSPARENT
	focus.shadow_color = Color(ACCENT,.12)
	result.set_stylebox("focus", "Button", focus)
	for type in ["VScrollBar","HScrollBar"]:
		var track := compact(false,3,Vector2(3,3)); track.shadow_size=0; track.set_border_width_all(0); track.bg_color=SURFACE
		var grabber := track.duplicate(); grabber.bg_color=LINE
		var active := grabber.duplicate(); active.bg_color=ACCENT
		result.set_stylebox("scroll",type,track)
		result.set_stylebox("grabber",type,grabber)
		result.set_stylebox("grabber_highlight",type,active)
		result.set_stylebox("grabber_pressed",type,active)
	return result

static func label(text := "", font_size := 16, color := TEXT) -> Label:
	var result := Label.new()
	result.text = text
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_override("font", STRONG)
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",color)
	return result

static func amount(value: int) -> String:
	var digits := str(absi(value))
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length()-i)%3 == 0: result += "."
		result += digits[i]
	return ("−" if value < 0 else "") + result

static func objective_strip() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = GLASS
	s.border_color = ACCENT
	s.border_width_left = 2
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

static func panel(accent := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = GLASS
	s.border_color = ACCENT if accent else LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(12)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	s.shadow_color = Color(0,0,0,0.28)
	s.shadow_size = 8
	return s

static func button(primary := false) -> StyleBoxFlat:
	var s := panel(primary)
	s.bg_color = SURFACE.lightened(.04) if primary else SURFACE
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.content_margin_left = 16
	s.content_margin_right = 16
	return s

static func apply(node: Node, text_scale := 1.0, root := true) -> void:
	if node is Control:
		if root: node.theme = create_theme()
		if node is PanelContainer and not node.get_meta("preserve_panel_style", false):
			node.add_theme_stylebox_override("panel", panel())
		if node is BaseButton:
			var primary := bool(node.get_meta("primary_action", false))
			node.add_theme_stylebox_override("normal", button(primary))
			node.add_theme_stylebox_override("hover", button(true))
			node.add_theme_stylebox_override("pressed", button(true))
			var focus := panel(true)
			focus.bg_color = Color.TRANSPARENT
			focus.set_border_width_all(2)
			node.add_theme_stylebox_override("focus", focus)
			node.add_theme_color_override("font_color", TEXT)
			node.add_theme_color_override("font_hover_color", ACCENT)
			node.add_theme_color_override("font_focus_color", ACCENT)
			node.add_theme_color_override("font_disabled_color", MUTED.darkened(0.2))
		if node is Label or node is Button or node is RichTextLabel:
			var property := "normal_font_size" if node is RichTextLabel else "font_size"
			if not node.has_meta("ui_base_font"):
				node.set_meta("ui_base_font", maxi(14, node.get_theme_font_size(property)))
			node.add_theme_font_size_override(property, roundi(float(node.get_meta("ui_base_font"))*text_scale))
			# The family supplies its own weight; thick outlines bury its counters.
			node.add_theme_constant_override("outline_size", node.get_theme_constant("outline_size") if node.get_meta("preserve_hud_ink", false) else mini(1,node.get_theme_constant("outline_size")))
			node.add_theme_constant_override("shadow_offset_x", 0)
			node.add_theme_constant_override("shadow_offset_y", 1)
			var color: Color = node.get_theme_color("font_color") if not node is RichTextLabel else TEXT
			if color.r > 0.6 and color.g > 0.45 and color.b < 0.45 and not node.get_meta("preserve_hud_ink", false):
				node.add_theme_color_override("font_color", ACCENT)
		if node is HSlider:
			var track := StyleBoxFlat.new()
			track.bg_color = LINE
			track.content_margin_top = 3
			track.content_margin_bottom = 3
			track.set_corner_radius_all(3)
			node.add_theme_stylebox_override("slider", track)
	for child in node.get_children(): apply(child, text_scale, false)

static func trap_focus(container: Control, grab := true) -> void:
	var controls: Array[Control] = []
	_collect_focus(container, controls)
	if controls.is_empty(): return
	for i in controls.size():
		controls[i].focus_next = controls[i].get_path_to(controls[(i+1)%controls.size()])
		controls[i].focus_previous = controls[i].get_path_to(controls[(i-1+controls.size())%controls.size()])
		controls[i].focus_neighbor_bottom = controls[i].focus_next
		controls[i].focus_neighbor_top = controls[i].focus_previous
	if grab: controls[0].grab_focus()

static func _collect_focus(node: Node, controls: Array[Control]) -> void:
	if node is Control and node.is_visible_in_tree() and node.focus_mode == Control.FOCUS_ALL:
		if not (node is BaseButton and node.disabled): controls.append(node)
	for child in node.get_children(): _collect_focus(child, controls)
