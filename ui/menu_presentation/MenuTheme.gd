extends RefCounted

const STYLE := preload("res://ui/GameStyle.gd")
const INK := STYLE.INK
const SURFACE := STYLE.SURFACE
const TEXT := STYLE.TEXT
const MUTED := STYLE.MUTED
const ACCENT := STYLE.ACCENT

static func box(fill: Color, border: Color, width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

static func create() -> Theme:
	var result := STYLE.create_theme(20)
	result.default_font_size = 20
	result.set_color("font_color", "Label", TEXT)
	result.set_type_variation("MenuTitle", "Label")
	result.set_font_size("font_size", "MenuTitle", 30)
	result.set_stylebox("panel", "PanelContainer", box(INK, STYLE.LINE))
	result.set_constant("separation", "VBoxContainer", 10)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill := STYLE.SURFACE.lightened(.04) if state == "hover" else SURFACE
		if state == "pressed": fill = STYLE.SURFACE.lightened(.08)
		if state == "disabled": fill = INK
		result.set_stylebox(state, "Button", box(fill, STYLE.LINE))
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_hover_color", "Button", TEXT)
	result.set_color("font_pressed_color", "Button", TEXT)
	result.set_color("font_focus_color", "Button", TEXT)
	result.set_color("font_disabled_color", "Button", MUTED)
	var focus := box(Color.TRANSPARENT, ACCENT, 3)
	focus.draw_center = false
	result.set_stylebox("focus", "Button", focus)
	result.set_stylebox("focus", "HSlider", focus)
	var track := box(STYLE.LINE, STYLE.LINE, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	result.set_stylebox("slider", "HSlider", track)
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = ACCENT
	result.set_stylebox("grabber_area", "HSlider", filled)
	result.set_stylebox("grabber_area_highlight", "HSlider", filled)
	return result
