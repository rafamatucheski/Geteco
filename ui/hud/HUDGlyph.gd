extends Control
## Cached vector pictograms stay clean across UI scales without live viewports.
const STYLE := preload("res://ui/GameStyle.gd")
const GLYPHS := preload("res://ui/hud/VectorGlyphs.gd")
var kind := "heart"
var ink := STYLE.TEXT
func _init(symbol := "heart", color := STYLE.TEXT) -> void:
	kind = symbol
	ink = color
	custom_minimum_size = Vector2(18,18)
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
func _draw() -> void:
	var symbol := GLYPHS.texture(kind)
	if symbol == null: return
	var extent := Vector2.ONE * minf(size.x, size.y)
	draw_texture_rect(symbol, Rect2((size - extent) * .5, extent), false, ink)
