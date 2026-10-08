extends Control
var tint:=Color("7c213b")
func _ready() -> void: mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	var center:=size.x*0.5
	draw_style_box(_shape(Color("172922"),6),Rect2(center-18,39,36,73))
	draw_rect(Rect2(center-7,14,14,31),Color("172922"))
	draw_rect(Rect2(center-8,12,16,11),Color("b99b5b"))
	draw_rect(Rect2(center-14,61,28,33),Color("eadfca"))
	draw_rect(Rect2(center-11,70,22,14),tint)
	draw_line(Vector2(center-11,47),Vector2(center-11,58),Color(0.7,0.9,0.8,0.25),2)
func _shape(color: Color, radius: int) -> StyleBoxFlat:
	var result:=StyleBoxFlat.new(); result.bg_color=color; result.set_corner_radius_all(radius); return result
