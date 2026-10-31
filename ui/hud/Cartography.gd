extends RefCounted
const STYLE := preload("res://ui/GameStyle.gd")
const GLYPHS := preload("res://ui/hud/VectorGlyphs.gd")
## Textura cartográfica, de propósito sem rótulos: não são dados de elevação medidos.
## Curvas ancoradas no mundo, limitadas a 28 x 38 amostras, compartilhadas pelos dois mapas.
static func contours(canvas: Control, extent: Vector2, center: Vector2, zoom: float) -> void:
	var step := maxf(18.0,extent.y/24.0)
	var phase := fposmod(center.y*zoom,step)
	for row in mini(28,ceili(extent.y/step)+4):
		var points := PackedVector2Array()
		for col in 38:
			var x := extent.x*col/37.0
			var world_x := x+center.x*zoom
			var y := (row-2)*step-phase + sin(world_x*.025+row*.23)*13 + sin(world_x*.053+row*.13)*5
			points.append(Vector2(x,y))
		canvas.draw_polyline(points,STYLE.MAP_CONTOUR,1,true)
static func diamond(canvas: Control, point: Vector2, radius := 6.0, color := STYLE.WAYPOINT) -> void:
	canvas.draw_texture_rect(GLYPHS.texture("diamond"),Rect2(point-Vector2.ONE*radius*1.2,Vector2.ONE*radius*2.4),false,color)
static func player(canvas: Control, point: Vector2, heading: float) -> void:
	GLYPHS.draw_rotated(canvas,"player",point,24.0,heading,STYLE.COLD)
