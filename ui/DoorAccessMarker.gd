extends Node2D
## Shared, text-free doorway indicator. Cached drawing; no per-frame animation.
const ORANGE := Color("f39a38")
var _style: StyleBoxFlat

func _ready() -> void:
	z_index = 5 # abaixo do Player (z_index=10): marcador não pode cobrir o personagem ao passar na frente
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(ORANGE.r, ORANGE.g, ORANGE.b, .14)
	_style.border_color = ORANGE
	_style.set_corner_radius_all(4)
	_style.set_border_width_all(1)

func _draw() -> void:
	if _style != null:
		draw_style_box(_style, Rect2(-13, -7, 26, 14))
