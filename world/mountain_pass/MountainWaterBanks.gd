extends RefCounted
const GROUND := preload("res://world/mountain_pass/ForestGroundBlend.gd")
const WATER := preload("res://world/shared/nature/WaterPresentation.gd")

static func round_bank(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	for pass_index in 2:
		var rounded := PackedVector2Array()
		for i in result.size():
			var a := result[i]
			var b := result[(i+1)%result.size()]
			rounded.append(a.lerp(b,.18))
			rounded.append(a.lerp(b,.82))
		result=rounded
	var noise := FastNoiseLite.new()
	noise.seed=13926
	noise.frequency=.035
	for i in result.size():
		var tangent := result[(i+1)%result.size()]-result[posmod(i-1,result.size())]
		result[i]+=tangent.normalized().orthogonal()*noise.get_noise_2dv(result[i])*5
	return result

static func earth(bank: Polygon2D) -> void:
	bank.polygon=round_bank(bank.polygon)
	GROUND.polygon(bank,"earth",24.0,.80)

static func water(surface: Polygon2D, feather := 16.0) -> void:
	surface.polygon=round_bank(surface.polygon)
	WATER.apply(surface,"lake")
	var edge := MeshInstance2D.new()
	edge.name="ShallowWaterTransition"
	edge.mesh=GROUND.fringe_mesh(surface.polygon,feather)
	edge.material=surface.material
	edge.modulate=surface.color
	edge.show_behind_parent=true
	surface.add_child(edge)

static func stream(line: Line2D) -> void:
	var curve := Curve2D.new()
	for i in line.points.size():
		var tangent := (line.points[mini(i+1,line.points.size()-1)]-line.points[maxi(i-1,0)])*.18
		curve.add_point(line.points[i],-tangent if i>0 else Vector2.ZERO,tangent if i<line.points.size()-1 else Vector2.ZERO)
	line.points=curve.tessellate(4,4)
	line.joint_mode=Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode=Line2D.LINE_CAP_ROUND
	line.end_cap_mode=Line2D.LINE_CAP_ROUND
	var widths := Curve.new()
	widths.add_point(Vector2(0,.58))
	widths.add_point(Vector2(.35,.9))
	widths.add_point(Vector2(.7,.72))
	widths.add_point(Vector2(1,1))
	line.width_curve=widths

static func stream_banks(line: Line2D) -> void:
	var tint := line.default_color
	var bank := Line2D.new()
	bank.points=line.points
	bank.width=line.width+14
	bank.show_behind_parent=true
	line.add_child(bank)
	GROUND.path(bank,12)
	for outline in Geometry2D.offset_polyline(line.points,line.width*.5,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND):
		var surface := Polygon2D.new()
		surface.polygon=outline
		surface.color=tint
		surface.material=line.material
		line.add_child(surface)
		var edge := MeshInstance2D.new()
		edge.mesh=GROUND.fringe_mesh(outline,6)
		edge.material=line.material
		edge.modulate=tint
		edge.show_behind_parent=true
		surface.add_child(edge)
	line.default_color=Color.TRANSPARENT
