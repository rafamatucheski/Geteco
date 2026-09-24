extends RefCounted
## Authored stone branch: cached CanvasItem commands, no extra viewport or lights.
## The central opening matches the existing 48px walk-through door at y = 85.

static func draw_facade(host: Node2D, bounds: Rect2, dark: bool, rain: bool) -> void:
	var stone := Color("c7c6b5")
	var light := Color("e0dfce")
	var shade := Color("92978b")
	var bronze := Color("a49666")
	var ink := Color("263d3c")
	var roof := Color("606b65") if not rain else Color("475b58")
	var left := bounds.position.x
	var right := bounds.end.x
	var front := bounds.end.y
	var lintel := front - 70.0
	# Massive flat roof, inset coping and raised seams stay inside the lot.
	host.draw_rect(Rect2(bounds.position+Vector2(5,7),bounds.size),Color(0.03,0.07,0.07,.28))
	host.draw_rect(bounds,shade)
	host.draw_rect(Rect2(left,bounds.position.y,bounds.size.x,lintel-bounds.position.y),roof)
	for i in 5:
		var seam := left+18+i*(bounds.size.x-36)/4.0
		host.draw_line(Vector2(seam,bounds.position.y+8),Vector2(seam,lintel-10),roof.darkened(.13),1.0)
	host.draw_rect(Rect2(left,bounds.position.y,bounds.size.x,7),light)
	host.draw_rect(Rect2(left,bounds.position.y+7,7,lintel-bounds.position.y-7),stone)
	host.draw_rect(Rect2(right-7,bounds.position.y+7,7,lintel-bounds.position.y-7),shade)
	host.draw_rect(Rect2(left+8,bounds.position.y+7,bounds.size.x-16,2),roof.darkened(.3))
	# Low copper-framed skylight behind the central pediment.
	var sky := Rect2(-34,bounds.position.y+24,68,30)
	host.draw_rect(Rect2(sky.position+Vector2(4,5),sky.size),roof.darkened(.22))
	host.draw_rect(sky,bronze.darkened(.2))
	host.draw_rect(sky.grow(-3),Color("425957"))
	for x in [-17.0,0.0,17.0]:
		host.draw_line(Vector2(x,sky.position.y+3),Vector2(x,sky.end.y-3),bronze,1.5)
	host.draw_line(Vector2(sky.position.x+3,sky.get_center().y),Vector2(sky.end.x-3,sky.get_center().y),bronze,1.5)
	host.draw_line(sky.position+Vector2(4,4),Vector2(sky.end.x-4,sky.position.y+4),Color("93a99a"),2)
	# Ashlar wall: horizontal courses with staggered joints, not a shop sign band.
	host.draw_rect(Rect2(left,lintel,bounds.size.x,front-lintel),stone)
	for row in 5:
		var y := lintel+row*14.0
		host.draw_line(Vector2(left,y),Vector2(right,y),shade,1)
		for column in 6:
			var x := left+column*42+(21 if row%2 else 0)
			if x>left and x<right:
				host.draw_line(Vector2(x,y),Vector2(x,minf(y+14,front)),shade,1)
	# Deep, restrained glazing and metal window bars flank the entrance.
	for side in [-1.0,1.0]:
		var x: float = side*66.0
		host.draw_rect(Rect2(x-23,lintel+9,46,50),shade.darkened(.2))
		host.draw_rect(Rect2(x-20,lintel+12,40,44),ink)
		host.draw_rect(Rect2(x-18,lintel+14,36,15),Color("758b78") if dark else Color("57716b"))
		for bar in [-12.0,0.0,12.0]:
			host.draw_line(Vector2(x+bar,lintel+12),Vector2(x+bar,lintel+31),bronze.darkened(.18),1.5)
		host.draw_line(Vector2(x-20,lintel+31),Vector2(x+20,lintel+31),bronze,2)
		_draw_atm(host,Vector2(x,front-4),dark)
	# The glazed transom sits above the real animated entrance, never over it.
	host.draw_rect(Rect2(-26,lintel+6,52,front-lintel-6),shade.darkened(.28))
	host.draw_rect(Rect2(-23,lintel+8,46,19),ink)
	host.draw_rect(Rect2(-21,lintel+10,42,14),Color("718771") if dark else Color("4c6863"))
	for x in [-12.0,0.0,12.0]:
		host.draw_line(Vector2(x,lintel+9),Vector2(x,lintel+26),bronze,1.5)
	# Four fluted stone columns, each with a base, shaft, capital and side shadow.
	for x in [left+12,-34.0,34.0,right-12]:
		_draw_column(host,x,lintel+5,front,stone,light,shade)
	# A layered entablature and triangular stone pediment give the bank its silhouette.
	host.draw_rect(Rect2(left-2,lintel-3,bounds.size.x+4,8),shade)
	host.draw_rect(Rect2(left-4,lintel-7,bounds.size.x+8,5),light)
	host.draw_rect(Rect2(left-2,lintel-2,bounds.size.x+4,2),bronze.darkened(.15))
	host.draw_colored_polygon(PackedVector2Array([Vector2(-54,lintel-7),Vector2(0,lintel-35),Vector2(54,lintel-7)]),shade.darkened(.1))
	host.draw_colored_polygon(PackedVector2Array([Vector2(-51,lintel-10),Vector2(0,lintel-37),Vector2(51,lintel-10)]),light)
	host.draw_colored_polygon(PackedVector2Array([Vector2(-37,lintel-12),Vector2(0,lintel-31),Vector2(37,lintel-12)]),stone.darkened(.08))
	# An engraved rosette is architectural relief, with no word or currency symbol.
	var seal := Vector2(0,lintel-20)
	host.draw_circle(seal,5.5,bronze.darkened(.2))
	host.draw_arc(seal,4.0,0,TAU,24,light,1.0,true)
	host.draw_colored_polygon(PackedVector2Array([seal+Vector2(0,-3),seal+Vector2(2.5,0),seal+Vector2(0,3),seal+Vector2(-2.5,0)]),light)
	# Small bronze wall lanterns and security cameras. No new runtime light sources.
	for side in [-1.0,1.0]:
		var x: float = side*46
		host.draw_rect(Rect2(x-2,lintel+19,4,12),bronze.darkened(.35))
		host.draw_rect(Rect2(x-3,lintel+21,6,7),Color("f3d99a") if dark else Color("c9c4a1"))
		host.draw_rect(Rect2(x-4,lintel+19,8,2),ink)
		var mount := Vector2(side*85,lintel+7)
		host.draw_line(mount,mount+Vector2(-side*3,4),shade.darkened(.45),2)
		host.draw_colored_polygon(PackedVector2Array([mount+Vector2(-side*3,3),mount+Vector2(-side*11,5),mount+Vector2(-side*10,8),mount+Vector2(-side*2,6)]),Color("d6d9ce"))
		host.draw_circle(mount+Vector2(-side*10,6),1.3,ink)
	# Split plinth leaves the actual threshold open and level with the pavement.
	host.draw_rect(Rect2(left,front-4,-26-left,5),shade)
	host.draw_rect(Rect2(26,front-4,right-26,5),shade)
	host.draw_line(Vector2(-24,front),Vector2(24,front),bronze,2)
	if rain:
		host.draw_line(Vector2(left+8,bounds.position.y+11),Vector2(right-8,bounds.position.y+11),Color(.7,.85,.86,.2),1)

static func draw_inline_cutaway(host: Node2D, bounds: Rect2) -> void:
	# The roof and tall street wall are gone while the player occupies the
	# rendered bank. Low masonry keeps its original footprint legible.
	var stone := Color("c7c6b5")
	var shade := Color("92978b")
	var bronze := Color("a49666")
	host.draw_rect(Rect2(bounds.position.x, bounds.position.y, bounds.size.x, 6), stone)
	host.draw_rect(Rect2(bounds.position.x, bounds.position.y, 6, bounds.size.y), stone)
	host.draw_rect(Rect2(bounds.end.x - 6, bounds.position.y, 6, bounds.size.y), shade)
	var front := bounds.end.y
	host.draw_rect(Rect2(bounds.position.x, front - 8, -26.0 - bounds.position.x, 8), shade)
	host.draw_rect(Rect2(26, front - 8, bounds.end.x - 26.0, 8), shade)
	host.draw_line(Vector2(-24, front), Vector2(24, front), bronze, 2)

static func _draw_column(host: Node2D, x: float, top: float, bottom: float, stone: Color, light: Color, shade: Color) -> void:
	host.draw_colored_polygon(PackedVector2Array([Vector2(x+5,top+6),Vector2(x+12,top+9),Vector2(x+12,bottom),Vector2(x+5,bottom)]),Color(0.17,.22,.20,.25))
	host.draw_rect(Rect2(x-6,top+7,12,bottom-top-12),stone)
	host.draw_rect(Rect2(x-6,top+7,3,bottom-top-12),light)
	host.draw_rect(Rect2(x+3,top+7,3,bottom-top-12),shade)
	for offset in [-2.0,1.0]:
		host.draw_line(Vector2(x+offset,top+10),Vector2(x+offset,bottom-8),shade.lightened(.12),1)
	host.draw_rect(Rect2(x-9,top,18,4),light)
	host.draw_rect(Rect2(x-7,top+4,14,3),shade)
	host.draw_rect(Rect2(x-8,bottom-6,16,3),light)
	host.draw_rect(Rect2(x-10,bottom-3,20,4),shade)
	host.draw_line(Vector2(x-10,bottom-3),Vector2(x+10,bottom-3),light,1)

static func _draw_atm(host: Node2D, bottom: Vector2, dark: bool) -> void:
	var top := bottom+Vector2(-14,-32)
	host.draw_rect(Rect2(top-Vector2(3,2),Vector2(34,35)),Color("263c3c"))
	host.draw_rect(Rect2(top,Vector2(28,32)),Color("8b9b95"))
	host.draw_rect(Rect2(top+Vector2(2,2),Vector2(24,16)),Color("384e4d"))
	host.draw_rect(Rect2(top+Vector2(5,4),Vector2(15,10)),Color("83c5bf") if dark else Color("609c99"))
	host.draw_rect(Rect2(top+Vector2(7,6),Vector2(10,1)),Color("b5d8c7"))
	host.draw_rect(Rect2(top+Vector2(7,9),Vector2(6,1)),Color("b5d8c7"))
	for i in 3:
		host.draw_rect(Rect2(top+Vector2(22,5+i*3),Vector2(2,1.5)),Color("c5cbc0"))
	# Recessed keypad tray, card reader, cash slot and armored lower panel.
	host.draw_colored_polygon(PackedVector2Array([top+Vector2(3,18),top+Vector2(24,18),top+Vector2(26,23),top+Vector2(2,23)]),Color("bdc5b9"))
	for row in 3:
		for column in 3:
			host.draw_rect(Rect2(top+Vector2(7+column*2.6,18+row*1.6),Vector2(1.6,1)),Color("334a47"))
	host.draw_rect(Rect2(top+Vector2(19,19),Vector2(5,1.5)),Color("213d36"))
	host.draw_rect(Rect2(top+Vector2(19,18),Vector2(5,.8)),Color("82b887"))
	host.draw_rect(Rect2(top+Vector2(6,26),Vector2(16,3)),Color("2b4240"))
	host.draw_line(top+Vector2(6,26),top+Vector2(22,26),Color("c6cfc0"),1)
