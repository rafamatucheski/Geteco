extends Node2D
## A soft parking outline on the ground, below cars and pedestrians.
var ready_for_delivery := false
var _clock := 0.0

func _ready() -> void:
	z_index=3
	var unshaded:=CanvasItemMaterial.new()
	unshaded.light_mode=CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material=unshaded

func _process(delta: float) -> void:
	if not visible: return
	_clock+=delta
	queue_redraw()

func _draw() -> void:
	var pulse:=.65+.15*sin(_clock*2.3)
	var color:=Color("8fe0bb") if ready_for_delivery else Color("f3cf7b")
	var bay:=Rect2(-33,-44,66,88)
	for radius in [9.0,6.0,3.0]:
		draw_rect(bay.grow(radius),Color(color,.045*pulse),false,radius*2,true)
	draw_rect(bay,Color(color,.055*pulse))
	for side in [-1,1]:
		for end in [-1,1]:
			var corner:=Vector2(side*33,end*44)
			draw_polyline(PackedVector2Array([corner-Vector2(side*15,0),corner,corner-Vector2(0,end*18)]),Color(color,pulse),2.5,true)
