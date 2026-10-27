extends Control
## Compatibility glyphs share the current HUD's filtered vector masters.
const GLYPHS := preload("res://ui/hud/VectorGlyphs.gd")
var armor := false
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(12, 12)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
func _draw() -> void:
	var ink := Color("eee9e2")
	var extent := Vector2.ONE * minf(size.x, size.y)
	draw_texture_rect(GLYPHS.texture("shield_outline" if armor else "health_cross"), Rect2((size - extent) * .5, extent), false, ink)
