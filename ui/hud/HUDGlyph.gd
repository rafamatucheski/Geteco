extends Control
## Small vector symbols; no fonts, emoji fallbacks or live SubViewports.
const STYLE := preload("res://ui/GameStyle.gd")
var kind := "heart"
var ink := STYLE.TEXT
func _init(symbol := "heart", color := STYLE.TEXT) -> void:
	kind = symbol
	ink = color
	custom_minimum_size = Vector2(18,18)
	mouse_filter = MOUSE_FILTER_IGNORE
func _draw() -> void:
	var s := minf(size.x,size.y)/24.0
	draw_set_transform((size-Vector2.ONE*24*s)*.5,0,Vector2.ONE*s)
	match kind:
		"heart":
			draw_circle(Vector2(7,8),5,ink); draw_circle(Vector2(17,8),5,ink)
			draw_colored_polygon(PackedVector2Array([Vector2(2,9),Vector2(22,9),Vector2(12,22)]),ink)
		"shield":
			draw_colored_polygon(PackedVector2Array([Vector2(3,4),Vector2(12,1),Vector2(21,4),Vector2(19,15),Vector2(12,22),Vector2(5,15)]),ink)
		"cold":
			for i in 6:
				var d := Vector2.UP.rotated(i*PI/3)
				draw_line(Vector2(12,12),Vector2(12,12)+d*10,ink,1.5,true)
				for side in [-1,1]: draw_line(Vector2(12,12)+d*6,Vector2(12,12)+d*4+d.rotated(side*PI/2)*3,ink,1.3,true)
		"bag":
			draw_arc(Vector2(12,7),4,PI,TAU,12,ink,1.6,true)
			var box := STYLE.compact(false,4,Vector2.ZERO); box.bg_color=Color.TRANSPARENT; box.border_color=ink
			draw_style_box(box,Rect2(4,6,16,16)); draw_style_box(box,Rect2(7,13,10,7))
			draw_line(Vector2(8,7),Vector2(8,11),ink,1.4); draw_line(Vector2(16,7),Vector2(16,11),ink,1.4)
		"money":
			draw_set_transform(Vector2(2,6)*s,-.18,Vector2.ONE*s)
			draw_rect(Rect2(0,0,20,13),ink,false,1.5); draw_circle(Vector2(10,6.5),3,ink,false,1.5,true)
		"shirt":
			draw_colored_polygon(PackedVector2Array([Vector2(7,3),Vector2(10,5),Vector2(14,5),Vector2(17,3),Vector2(23,8),Vector2(19,12),Vector2(17,10),Vector2(17,22),Vector2(7,22),Vector2(7,10),Vector2(5,12),Vector2(1,8)]),ink)
