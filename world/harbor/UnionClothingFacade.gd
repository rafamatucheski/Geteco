extends Node2D
## Storefront fitted to NorthFrontage3; keeps its original solid and doorway.

func _ready() -> void:
	z_index = 6
	var sign := Label.new()
	sign.text = "U N I O N"
	sign.position = Vector2(-87, 7)
	sign.size = Vector2(174, 26)
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign.add_theme_font_size_override("font_size", 19)
	sign.add_theme_color_override("font_color", Color("f2dfb6"))
	add_child(sign)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-108, 5, 216, 85), Color("273d3c"))
	draw_rect(Rect2(-102, 8, 204, 25), Color("203331"))
	draw_line(Vector2(-100, 34), Vector2(100, 34), Color("bca275"), 2)
	for side in [-1, 1]:
		var x: float = side * 69.0
		draw_rect(Rect2(x-28, 41, 56, 43), Color("bda77f"))
		draw_rect(Rect2(x-25, 44, 50, 36), Color("435d61"))
		_draw_dressed_mannequin(x, side > 0)
		draw_line(Vector2(x-22,46),Vector2(x-5,46),Color("ddd6b9"),1)
		draw_rect(Rect2(x-25,82,50,4),Color("263530"))
	# Door stays exposed in the central opening, with a small woven welcome mat.
	draw_rect(Rect2(-30,37,60,53),Color("172a2b"))
	draw_rect(Rect2(-30,108,60,12),Color("74644a"))
	for i in 6:
		draw_line(Vector2(-27+i*10,109),Vector2(-27+i*10,118),Color("8d7b5e"),1)

func _draw_dressed_mannequin(x: float, long_coat: bool) -> void:
	# A complete 29-unit figure fits inside the glass with breathing room.
	var ivory := Color("e3d8c3")
	var coat := Color("c09868") if long_coat else Color("6595a5")
	var trousers := Color("343a42") if long_coat else Color("243745")
	draw_ellipse_base(Vector2(x, 78))
	draw_line(Vector2(x, 74), Vector2(x, 78), Color("9c9989"), 0.8)
	# Separate legs and shoes make the silhouette human at street scale.
	draw_line(Vector2(x-2, 64), Vector2(x-2.5, 74), trousers, 2.8)
	draw_line(Vector2(x+2, 64), Vector2(x+3, 74), trousers, 2.8)
	draw_line(Vector2(x-4, 75), Vector2(x-1, 75), Color("172329"), 1.8)
	draw_line(Vector2(x+2, 75), Vector2(x+5, 75), Color("172329"), 1.8)
	draw_line(Vector2(x, 53), Vector2(x, 56), ivory, 1.8)
	draw_circle(Vector2(x, 51), 2.2, ivory)
	var hem := 68.0 if long_coat else 64.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(x-3.5,55), Vector2(x+3.5,55),
		Vector2(x+3,61), Vector2(x+4,hem),
		Vector2(x-4,hem), Vector2(x-3,61)]), coat)
	for arm in [-1.0, 1.0]:
		draw_polyline(PackedVector2Array([
			Vector2(x+arm*3,56), Vector2(x+arm*5,60),
			Vector2(x+arm*5.5,64)]), coat.darkened(0.1), 2.2, true)
		draw_circle(Vector2(x+arm*5.5,65), 1.0, ivory)
	draw_line(Vector2(x,57), Vector2(x,hem-0.5), coat.darkened(0.35), 0.6)
	draw_polyline(PackedVector2Array([
		Vector2(x-2,55), Vector2(x,58), Vector2(x+2,55)]), ivory, 0.9, true)

func draw_ellipse_base(at: Vector2) -> void:
	draw_set_transform(at, 0, Vector2(1, 0.25))
	draw_circle(Vector2.ZERO, 8, Color("263b3d"))
	draw_set_transform(Vector2.ZERO)
