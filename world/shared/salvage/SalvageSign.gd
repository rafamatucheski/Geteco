extends Node2D
## Canvas boards stay crisp at the gameplay zoom and cannot sink into a roof.
var kind := "gate"

static func icon(canvas: CanvasItem, center: Vector2, unit: float, color: Color) -> void:
	# A car beneath a descending press, shared by the entrance and map marker.
	canvas.draw_line(center+Vector2(-9,-10)*unit,center+Vector2(9,-10)*unit,color,2*unit,true)
	canvas.draw_line(center+Vector2(0,-10)*unit,center+Vector2(0,-5)*unit,color,2*unit,true)
	canvas.draw_line(center+Vector2(-7,-4)*unit,center+Vector2(7,-4)*unit,color,2*unit,true)
	canvas.draw_style_box(_car_style(color),Rect2(center+Vector2(-8,1)*unit,Vector2(16,6)*unit))
	canvas.draw_polyline(PackedVector2Array([center+Vector2(-5,1)*unit,center+Vector2(-3,-2)*unit,center+Vector2(3,-2)*unit,center+Vector2(5,1)*unit]),color,1.5*unit,true)
	for x in [-5,5]: canvas.draw_circle(center+Vector2(x,8)*unit,1.8*unit,color)

static func _car_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color=color
	style.set_corner_radius_all(2)
	return style

func _ready() -> void:
	z_index=9
	queue_redraw()

func _draw() -> void:
	var width := 86.0 if kind=="gate" else 116.0
	var height := 62.0 if kind=="gate" else 32.0
	if kind=="gate":
		draw_line(Vector2(-28,0),Vector2(-28,-36),Color("807962"),5)
		draw_line(Vector2(28,0),Vector2(28,-36),Color("807962"),5)
	var board := Rect2(-width*.5,-height-24,width,height)
	var style := StyleBoxFlat.new()
	style.bg_color=Color("172c2a")
	style.border_color=Color("edc778")
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	draw_style_box(style,board)
	if kind=="gate":
		icon(self,board.get_center(),2.0,Color("ffe1a1"))
	else:
		var title := "NECO" if kind=="office" else "ENTREGA" if kind=="delivery" else "PRENSA"
		var font := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
		var size := 22 if kind=="office" else 19
		var length := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
		draw_string(font,Vector2(-length*.5,board.position.y+23),title,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color("fff0cf"))
