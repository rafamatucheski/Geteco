extends Node2D
## Same compact doorway indicator used by the original game, drawn in HUD pixels.
var style: StyleBoxFlat
var update_position: Callable
func _ready() -> void:
	process_priority = 1100 # After the camera and the rest of the HUD.
	style = StyleBoxFlat.new()
	style.bg_color = Color(0.953,.604,.22,.14)
	style.border_color = Color("f39a38")
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
func _process(_delta: float) -> void:
	if update_position.is_valid(): update_position.call()
func _draw() -> void:
	if style: draw_style_box(style,Rect2(-13,-7,26,14))
