extends RefCounted
## Ground position is the center of the footprint, not the top of the box.
static func draw_crate(canvas: Node2D, ground: Vector2) -> void:
	var a := ground + Vector2(-7,-4)
	var b := ground + Vector2(7,-4)
	var c := ground + Vector2(7,5)
	var d := ground + Vector2(-7,5)
	var height := Vector2(0,-8)
	# Short contact shadow overlaps the footprint instead of floating away.
	canvas.draw_colored_polygon(PackedVector2Array([a,b+Vector2(3,1),c+Vector2(3,2),d+Vector2(0,2)]),Color(0.08,0.1,0.09,0.28))
	canvas.draw_colored_polygon(PackedVector2Array([d+height,c+height,c,d]),Color("89663e"))
	canvas.draw_colored_polygon(PackedVector2Array([b+height,c+height,c,b]),Color("715437"))
	canvas.draw_colored_polygon(PackedVector2Array([a+height,b+height,c+height,d+height]),Color("b59763"))
	for x in [-4,4]:
		canvas.draw_line(ground+Vector2(x,-12),ground+Vector2(x,-3),Color("cbb080"),1.5)
		canvas.draw_line(ground+Vector2(x,-3),ground+Vector2(x,5),Color("ae8b56"),1.5)
	canvas.draw_line(d+height,c+height,Color("d0b17a"),1)
	canvas.draw_line(d,c,Color("59472f"),1)
