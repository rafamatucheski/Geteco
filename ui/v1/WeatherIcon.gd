extends Control
## A autoridade do clima escolhe o estado; a apresentação usa arte vetorial em cache.
const GLYPHS := preload("res://ui/hud/VectorGlyphs.gd")
var state := "sun"

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _draw() -> void:
	var symbol := GLYPHS.texture("weather_" + state)
	if symbol == null: return
	var extent := Vector2.ONE * minf(size.x, size.y)
	draw_texture_rect(symbol, Rect2((size - extent) * .5, extent), false)
