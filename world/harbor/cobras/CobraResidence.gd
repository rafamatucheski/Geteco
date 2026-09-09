@tool
extends Node2D

## Low-rise, footprint-bounded coastal worker housing, intentionally not the
## city's repeated tower silhouette. No fake interactive door or text label.
var size := Vector2(220,160)
var variant := 0
var wall_color := Color("72594b")

func _ready() -> void:
	z_index = 5
	var body := StaticBody2D.new()
	body.name = "BuildingSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collider.shape = rectangle
	collider.position = size*0.5
	body.add_child(collider)
	add_child(body)
	add_to_group("cobra_residence")
	queue_redraw()

func _draw() -> void:
	var roof := Rect2(Vector2(6,6),size-Vector2(12,38))
	draw_rect(Rect2(Vector2(4,6),size-Vector2(4,6)),Color("2e302b"))
	draw_rect(Rect2(Vector2(0,size.y-38),Vector2(size.x,38)),wall_color)
	var roof_color: Color = [Color("544d44"),Color("665547"),Color("53605c"),Color("626a64")][variant]
	draw_rect(roof,roof_color)
	draw_rect(roof,Color("323b36"),false,3)
	if variant == 3:
		# Long sawtooth industrial roof, clerestory glazing and two shutter bays.
		for i in 4:
			var y := roof.position.y+float(i)*roof.size.y/4
			draw_line(Vector2(9,y),Vector2(size.x-9,y+13),Color("899085"),4)
			draw_line(Vector2(12,y+5),Vector2(size.x-12,y+18),Color("354a46"),6)
		for i in 2:
			var bay := Rect2(Vector2(16+i*size.x*0.5,size.y-34),Vector2(size.x*0.5-30,31))
			draw_rect(bay,Color("3b4140"))
			for j in 6:
				draw_line(bay.position+Vector2(0,j*5),bay.position+Vector2(bay.size.x,j*5),Color("777d70"),1)
		# Serpent motif as paint, not a floating title.
		draw_arc(Vector2(size.x*0.5,roof.size.y*0.5),18,-PI*0.75,PI*0.75,20,Color("9b7046"),5,true)
		draw_line(Vector2(size.x*0.5+12,roof.size.y*0.5+12),Vector2(size.x*0.5-5,roof.size.y*0.5+29),Color("9b7046"),5,true)
		return
	# Gabled roofs, a duplex party wall, or weathered corrugated metal.
	if variant == 2:
		for x in range(10,int(size.x)-9,9):
			draw_line(Vector2(x,9),Vector2(x,roof.end.y-3),Color("737d71"),1)
	else:
		var ridge := roof.position.y+roof.size.y*0.48
		draw_colored_polygon(PackedVector2Array([roof.position,Vector2(roof.end.x,roof.position.y),Vector2(roof.end.x,ridge),Vector2(roof.position.x,ridge)]),roof_color.lightened(0.13))
		draw_line(Vector2(7,ridge),Vector2(size.x-7,ridge),Color("8c7c62"),4)
		for y in range(15,int(roof.end.y)-2,11):
			draw_line(Vector2(10,y),Vector2(size.x-10,y),Color(0.12,0.11,0.09,0.23),1)
	if variant == 1:
		draw_line(Vector2(size.x/2,6),Vector2(size.x/2,size.y-1),Color("39352e"),5)
	for i in (2 if variant == 1 else 1):
		var door_x := size.x*(0.25+0.5*i) if variant == 1 else size.x*0.63
		draw_rect(Rect2(door_x-10,size.y-32,20,29),Color("302e28"))
		draw_circle(Vector2(door_x+6,size.y-16),1.8,Color("bca474"))
		# Porch and timber supports remain inside the solid footprint.
		draw_rect(Rect2(door_x-25,size.y-8,50,7),Color("a2977b"))
		draw_line(Vector2(door_x-23,size.y-31),Vector2(door_x-23,size.y-2),Color("b8aa8a"),3)
		draw_line(Vector2(door_x+23,size.y-31),Vector2(door_x+23,size.y-2),Color("b8aa8a"),3)
	for x in [size.x*0.12,size.x*0.84]:
		draw_rect(Rect2(x-10,size.y-29,22,17),Color("242d2d"))
		draw_rect(Rect2(x-8,size.y-27,18,13),Color("65766f"))
		draw_line(Vector2(x+1,size.y-27),Vector2(x+1,size.y-14),Color("a4997e"),2)
	# Chimney, flashing and a small vent give roofs readable purpose.
	draw_rect(Rect2(24,22,20,28),Color("34362e"))
	draw_rect(Rect2(21,18,20,28),wall_color.darkened(0.1))
	draw_rect(Rect2(19,16,24,7),Color("a08a70"))
	draw_rect(Rect2(24,17,13,4),Color("2d302b"))
	draw_circle(Vector2(size.x-29,28),8,Color("3e4640"))
	draw_arc(Vector2(size.x-29,28),6,0,TAU,12,Color("929587"),2)
