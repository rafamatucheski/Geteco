extends RefCounted
## Linguagem visual compartilhada, sem trocar as cores funcionais do HUD.
const INK := Color("101820")
const SURFACE := Color("19242d")
const LINE := Color("34434d")
const TEXT := Color("efe7d8")
const MUTED := Color("a9b4bc")
const ACCENT := Color("ff914d")

static func objective_strip() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.06, 0.08, 0.58)
	s.border_color = Color(0.85, 0.71, 0.45, 0.65)
	s.border_width_left = 2
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

static func panel(accent := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = INK
	s.border_color = ACCENT if accent else LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	s.shadow_color = Color(0,0,0,0.28)
	s.shadow_size = 8
	return s

static func button(primary := false) -> StyleBoxFlat:
	var s := panel(primary)
	s.bg_color = Color("35271f") if primary else SURFACE
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.content_margin_left = 16
	s.content_margin_right = 16
	return s

static func apply(node: Node, text_scale := 1.0) -> void:
	if node is Control:
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
	for child in node.get_children(): apply(child, text_scale)

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


