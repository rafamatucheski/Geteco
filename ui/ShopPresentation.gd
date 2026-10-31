extends RefCounted
## Apresentação local para os menus antigos de comerciante; sem estado de economia ou de jogo.
const STYLE=preload("res://ui/GameStyle.gd")
static func apply(root: Control, primary: Button=null) -> void:
	for node in root.find_children("*","Button",true,false):
		var button:=node as Button
		var main:=button==primary
		button.add_theme_font_override("font",STYLE.FONT)
		button.add_theme_font_size_override("font_size",15)
		button.custom_minimum_size.y=52 if "\n" in button.text else 34
		for state in ["normal","hover","pressed","hover_pressed","disabled"]:
			var skin:=StyleBoxFlat.new()
			skin.bg_color=STYLE.SURFACE if state=="normal" else Color("2b3037")
			skin.border_color=Color("41464d")
			skin.border_width_bottom=1
			skin.set_corner_radius_all(2)
			skin.content_margin_left=10; skin.content_margin_right=10
			skin.content_margin_top=5; skin.content_margin_bottom=5
			if main and state!="disabled":
				skin.bg_color=Color("d5ad63") if state=="normal" else Color("e1bc78")
			button.add_theme_stylebox_override(state,skin)
		var focus:=StyleBoxFlat.new(); focus.bg_color=Color.TRANSPARENT
		focus.border_color=STYLE.TEXT; focus.set_border_width_all(2); focus.set_corner_radius_all(2)
		button.add_theme_stylebox_override("focus",focus)
		button.add_theme_color_override("font_color",STYLE.INK if main else STYLE.TEXT)
		for state in ["font_hover_color","font_focus_color","font_pressed_color","font_hover_pressed_color"]: button.add_theme_color_override(state,STYLE.INK if main else STYLE.TEXT)
		button.add_theme_color_override("font_disabled_color",STYLE.MUTED)
