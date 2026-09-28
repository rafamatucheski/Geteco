extends Control
## Tiny vector health/armor glyphs; no texture loading or continuous redraw.
var armor := false
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(12, 12)
func _draw() -> void:
	var ink := Color("eee9e2")
	if armor:
		draw_polyline(PackedVector2Array([Vector2(6,1),Vector2(11,3),Vector2(10,8),Vector2(6,11),Vector2(2,8),Vector2(1,3),Vector2(6,1)]), ink, 1.4, true)
	else:
		draw_rect(Rect2(4,1,4,10), ink)
		draw_rect(Rect2(1,4,10,4), ink)
