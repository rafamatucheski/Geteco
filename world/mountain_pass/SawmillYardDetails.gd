extends Node2D
## Low stacks of sawn boards and loose sawdust; authored once, no frame updates.
var boards: Array[PackedVector2Array] = []

func _ready() -> void:
	name = "SawmillYardDetails"
	for row in 4:
		var x: float = 1.0 + [2.0, -1.0, 0.0, 3.0][row]
		var y := 64.0 + row * 9.0
		var outline := PackedVector2Array([Vector2(x,y),Vector2(x+54-row%2*3,y),Vector2(x+54-row%2*3,y+6),Vector2(x,y+6)])
		boards.append(outline)
		var body := StaticBody2D.new()
		body.name = "BoardStack%d" % row
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionPolygon2D.new()
		# The same outline draws the wood and blocks the whole stack.
		collision.polygon = outline
		body.add_child(collision)
		add_child(body)
	queue_redraw()

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6350560
	# Scattered chips fade out naturally; the loose dust is walkable terrain.
	for i in 420:
		var angle := rng.randf_range(0, TAU)
		var radius := sqrt(rng.randf())
		var p := Vector2(-30,81) + Vector2(cos(angle)*22,sin(angle)*17)*radius
		var tint := Color("b28b52").lightened(rng.randf_range(-.22,.17))
		tint.a = (1.0-radius*.75)*.75
		draw_line(p,p+Vector2(rng.randf_range(.4,1.8),rng.randf_range(-.5,.5)),tint,.65)
	for row in boards.size():
		var outline := boards[row]
		var a := outline[0]
		var b := outline[2]
		var rect := Rect2(a,b-a)
		draw_rect(rect.grow(1.1),Color(0.12,.08,.04,.25))
		draw_colored_polygon(outline,Color("755033"))
		draw_rect(Rect2(a,Vector2(rect.size.x,4.3)),Color("af8653").lightened(row*.022))
		draw_line(a,a+Vector2(rect.size.x,0),Color("d2ad76"),.5)
		for seam in [4.6,5.4]:
			draw_line(a+Vector2(0,seam),a+Vector2(rect.size.x,seam),Color("493421"),.35)
		for grain in 9:
			var p := a+Vector2(rng.randf_range(2,32),rng.randf_range(.7,3.8))
			draw_line(p,p+Vector2(rng.randf_range(6,17),rng.randf_range(-.25,.25)),Color(.31,.20,.10,.38),.35)
		var knot := a+Vector2(18+row*9,2.2)
		_draw_knot(knot,Vector2(2,.6),Color("896039"))
		# Two narrow steel packing straps wrap over the stacked board edges.
		for offset in [10.0,44.0]:
			draw_rect(Rect2(a+Vector2(offset,0),Vector2(1.25,6)),Color("55554a"))
			draw_line(a+Vector2(offset,0),a+Vector2(offset,4),Color("929083"),.35)

func _draw_knot(center: Vector2, radius: Vector2, tint: Color) -> void:
	var points := PackedVector2Array()
	for i in 16:
		var angle := TAU*i/16.0
		points.append(center+Vector2(cos(angle),sin(angle))*radius)
	draw_colored_polygon(points,tint)
