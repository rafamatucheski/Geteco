extends Polygon2D
## A low, walkable rock. The water system uses this same authored footprint.
## All surface detail is cached CanvasItem drawing; no viewport or frame loop.
var variant := 0

func _ready() -> void:
	color = Color.TRANSPARENT
	queue_redraw()

func _draw() -> void:
	if polygon.size() < 3: return
	var rng := RandomNumberGenerator.new()
	rng.seed = 63017 + variant * 431
	var rim := PackedVector2Array()
	# Keep the existing dry footprint: bevel the rendered upper face inside it.
	var outline := PackedVector2Array([
		Vector2(-12,-6),Vector2(-10,-9),Vector2(-4,-9.5),Vector2(2,-9.7),
		Vector2(8,-9.8),Vector2(11,-7),Vector2(11.8,-2),Vector2(12.5,4),
		Vector2(10,8.7),Vector2(5,9.3),Vector2(-1,9.5),Vector2(-7,9.8),
		Vector2(-10,7),Vector2(-10.8,2)])
	for p in outline:
		rim.append(p + Vector2(rng.randf_range(-.45,.45),rng.randf_range(-.35,.35)))
	var top := PackedVector2Array()
	for p in rim: top.append(p * .84 + Vector2(-.6,-2.7))
	var shadow := PackedVector2Array()
	for p in rim: shadow.append(p * 1.13 + Vector2(1.3,2.5))
	draw_colored_polygon(shadow,Color(.015,.065,.07,.32))
	draw_colored_polygon(rim,Color("344447"))
	# Dark saturated sides, broken strata and lighter dry upper planes.
	for i in rim.size():
		var j := (i+1)%rim.size()
		var side := Color("4d5b5d").lightened(rng.randf_range(-.12,.07))
		if rim[i].y > 0: side = side.darkened(.14)
		draw_colored_polygon(PackedVector2Array([rim[i],rim[j],top[j],top[i]]),side)
		if rim[i].y > 1:
			draw_line(rim[i].lerp(top[i],.4),rim[j].lerp(top[j],.46),Color("293d40"),.35,true)
	var center := Vector2(-2.3,-3.2)
	for i in top.size():
		var j := (i+1)%top.size()
		var tone := Color("82908a").lightened(rng.randf_range(-.10,.055))
		draw_colored_polygon(PackedVector2Array([center,top[i],top[j]]),tone)
	# Broad mineral planes interrupt the radial facets.
	draw_colored_polygon(PackedVector2Array([Vector2(-7,-7),Vector2(2,-9),Vector2(7,-5),Vector2(1,-2),Vector2(-5,-3)]),Color("929b91"))
	draw_colored_polygon(PackedVector2Array([Vector2(-6,-2),Vector2(1,-1),Vector2(5,3),Vector2(-3,5),Vector2(-7,2)]),Color("76837f"))
	for i in 52:
		var p := Vector2(rng.randf_range(-10,10),rng.randf_range(-10,6))
		if Geometry2D.is_point_in_polygon(p,top):
			var tone := Color(.76,.79,.69,.36) if i%3==0 else Color(.18,.25,.25,.27)
			draw_line(p,p+Vector2(rng.randf_range(.15,.65),-.12),tone,.28,true)
	var crack := PackedVector2Array([top[2],Vector2(-3,-5),Vector2(-.6,-3.4),Vector2(-1,1.2),top[10]])
	draw_polyline(crack,Color("465958"),.48,true)
	draw_polyline(PackedVector2Array([Vector2(-.6,-3.4),Vector2(3,-3),top[5]]),Color("566862"),.33,true)
	for i in [0,1,2,3,12]:
		draw_line(top[i],top[(i+1)%top.size()],Color(.70,.75,.67,.7),.48,true)
	# Small broken waterline glints replace the geometric ring around each rock.
	for segment in 3:
		var points := PackedVector2Array()
		for i in 13:
			var angle := .2 + segment*2.15 + float(i)*.075
			points.append(Vector2(cos(angle)*15.2,sin(angle)*11.8)+Vector2(0,1.3))
		draw_polyline(points,Color(.44,.68,.70,.28),.42,true)
