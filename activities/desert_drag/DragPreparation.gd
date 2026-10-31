extends Control
## Um percurso frio termina de carregar antes de revelar a câmera da contagem.
const FONT=preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
var progress := 0.0:
	set(value):
		progress=clampf(value,0.0,1.0)
		queue_redraw()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("11171e"))
	var center := size*.5
	draw_string(FONT,center+Vector2(-250,-24),tr("Preparando a pista…"),HORIZONTAL_ALIGNMENT_CENTER,500,28,Color("f0f3f5"))
	draw_rect(Rect2(center+Vector2(-180,0),Vector2(360,4)),Color("34414e"))
	draw_rect(Rect2(center+Vector2(-180,0),Vector2(360*progress,4)),Color("ffbc55"))
	draw_string(FONT,center+Vector2(-250,48),"Q / B · "+tr("ABANDONAR"),HORIZONTAL_ALIGNMENT_CENTER,500,16,Color("8f9ba7"))
