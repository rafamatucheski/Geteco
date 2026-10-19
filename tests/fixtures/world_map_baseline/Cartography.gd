extends RefCounted
const STYLE := preload("res://ui/GameStyle.gd")
## Cartographic texture, deliberately unlabeled: not surveyed elevation data.
## World anchored contours, capped at 28 x 38 samples, shared by both maps.
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
	canvas.draw_colored_polygon(PackedVector2Array([point+Vector2(0,-radius),point+Vector2(radius,0),point+Vector2(0,radius),point+Vector2(-radius,0)]),color)
static func player(canvas: Control, point: Vector2, heading: float) -> void:
	var shape := PackedVector2Array()
	for p in [Vector2(10,0),Vector2(-6,-6),Vector2(-3,0),Vector2(-6,6)]: shape.append(point+p.rotated(heading))
	canvas.draw_colored_polygon(shape,STYLE.COLD)
