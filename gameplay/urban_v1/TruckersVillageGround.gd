extends RefCounted
## Small worn yards, footpaths and soft verges; road access belongs to road data.
static func build(village: Node3D, homes: Array) -> void:
	var shader := preload("res://world/urban_detail/RuralGroundMaterial.gd").material()
	var yard := PackedVector2Array([Vector2(-51,-25),Vector2(-31,-28),Vector2(-9,-27),Vector2(-6,-17),Vector2(-7,1),Vector2(-21,4),Vector2(-42,5),Vector2(-52,-3)])
	var plots: Array[PackedVector2Array] = [yard]
	_path(plots,PackedVector2Array([Vector2(-56,4),Vector2(-35,6),Vector2(-10,6),Vector2(14,5),Vector2(36,7),Vector2(49,7)]),3.2)
	for i in homes.size():
		var center: Vector3 = homes[i][0]
		var yaw: float = homes[i][2]
		var basis := Basis(Vector3.UP,yaw)
		var plot := PackedVector2Array()
		for offset in [Vector3(-9,0,-6),Vector3(8,0,-6),Vector3(10,0,5),Vector3(7,0,9),Vector3(-8,0,9),Vector3(-10,0,3)]:
			var point: Vector3 = center+basis*offset
			plot.append(Vector2(point.x,point.z))
		plots.append(plot)
		var porch: Vector3 = center+basis*Vector3(0,0,8)
		var destination := Vector2(clampf(porch.x,-51,36),clampf(porch.z,-5,12))
		_path(plots,PackedVector2Array([Vector2(porch.x,porch.z),Vector2(porch.x,porch.z).lerp(destination,.5)+Vector2(1.6,-.6),destination]),2.2)
	_path(plots,PackedVector2Array([Vector2(34,4),Vector2(51,9),Vector2(61,6)]),2.6)
	_path(plots,PackedVector2Array([Vector2(-53,5),Vector2(-63,16),Vector2(-67,25)]),2.3)
	_path(plots,PackedVector2Array([Vector2(38,11),Vector2(45,23),Vector2(60,27)]),2.2)
	for spot in preload("res://gameplay/urban_v1/TruckersVillageFleet.gd").SPOTS:
		var at: Vector3=spot[1]
		var bike: bool=str(spot[0]).begins_with("bike_")
		var half := Vector2(1.05,1.8) if bike else Vector2(1.8,3.3)
		var parking := PackedVector2Array()
		for corner in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),Vector2(half.x,half.y),Vector2(-half.x,half.y)]:
			parking.append(Vector2(at.x,at.z)+corner.rotated(-float(spot[2])))
		plots.append(parking)
	# Join plots before fading their edges; internal borders must never paint
	# strips of grass across other dirt paths. Road core remains above the rim.
	var merged := true
	while merged:
		merged=false
		for a in plots.size():
			for b in range(a+1,plots.size()):
				var union := Geometry2D.merge_polygons(plots[a],plots[b])
				if union.size()!=1: continue
				plots[a]=union[0]
				plots.remove_at(b)
				merged=true
				break
			if merged: break
	for i in plots.size(): _patch(village,"VillageEarth%d"%i,plots[i],shader,.022)
	village.set_meta("earth_plots",plots)
	# Broken apron edge instead of a raised slab. It meets the truck yard at grade.
	var concrete := preload("res://world/editing/WorldGroundFactory.gd").material("concrete")
	var apron := PackedVector2Array()
	for p in [Vector2(-49,-27),Vector2(-8,-27),Vector2(-8,-4),Vector2(-12,2),Vector2(-39,2),Vector2(-49,-3)]:
		var at: Vector3 = village.STATION_TRANSFORM*Vector3(p.x,0,p.y)
		apron.append(Vector2(at.x,at.z))
	_flat(village,"WornStationApron",apron,concrete,.037)
	_flat(village,"WorkshopFloor",PackedVector2Array([Vector2(53.4,-9),Vector2(68.6,-9),Vector2(68.6,2),Vector2(67,3),Vector2(53.4,2)]),concrete,.038)

static func _path(plots: Array[PackedVector2Array],points: PackedVector2Array,width: float) -> void:
	plots.append_array(Geometry2D.offset_polyline(points,width*.5,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND))

static func _patch(parent: Node3D,label: String,points: PackedVector2Array,material: Material,y: float) -> void:
	# A short opaque transition ring inherits the exact surrounding grass texture.
	_flat(parent,label,points,material,y)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var area := 0.0
	for i in points.size(): area+=points[i].cross(points[(i+1)%points.size()])
	for i in points.size():
		var a := points[i]
		var b := points[(i+1)%points.size()]
		var outward := Vector2((b-a).y,-(b-a).x).normalized()*1.2*signf(area)
		var pieces: Array[PackedVector2Array] = [PackedVector2Array([a,b,b+outward,a+outward])]
		# Short fans close convex corners without bridges across concave paths.
		for side in 8:
			pieces.append(PackedVector2Array([a,a+Vector2.from_angle(side*TAU/8)*1.2,a+Vector2.from_angle((side+1)*TAU/8)*1.2]))
		for piece in pieces:
			for outside in Geometry2D.clip_polygons(piece,points):
				for index in Geometry2D.triangulate_polygon(outside):
					var p: Vector2 = outside[index]
					surface.set_normal(Vector3.UP)
					surface.set_color(Color(1,1,1,clampf(1.0-p.distance_to(_closest(p,points))/1.2,0,1)))
					surface.add_vertex(Vector3(p.x,y-.002,p.y))
	var rim := MeshInstance3D.new()
	rim.name=label+"Verge"
	rim.mesh=surface.commit()
	rim.material_override=material
	rim.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(rim)

static func _closest(point: Vector2,polygon: PackedVector2Array) -> Vector2:
	var closest := polygon[0]
	var distance := INF
	for i in polygon.size():
		var candidate := Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()])
		if point.distance_squared_to(candidate)<distance:
			distance=point.distance_squared_to(candidate)
			closest=candidate
	return closest

static func _flat(parent: Node3D,label: String,polygon: PackedVector2Array,material: Material,y: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in Geometry2D.triangulate_polygon(polygon):
		var p := polygon[index]
		surface.set_normal(Vector3.UP)
		surface.set_color(Color.WHITE)
		surface.set_uv(p*.4)
		surface.add_vertex(Vector3(p.x,y,p.y))
	var display := MeshInstance3D.new()
	display.name=label
	display.mesh=surface.commit()
	display.material_override=material
	display.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(display)
