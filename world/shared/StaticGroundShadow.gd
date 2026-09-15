extends RefCounted
## Project actual static mesh vertices onto y=0 once, then draw their union.
static func build(host: Node2D, model: Node3D, viewport: SubViewport) -> void:
	if host.has_node("GeometryShadow"): return
	var direction := Vector3(.3,-1,.4)
	for node in viewport.get_children():
		if node is DirectionalLight3D:
			direction = -node.global_basis.z
			break
	if direction.y >= -.01: return
	var polygons: Array[PackedVector2Array] = []
	for node in model.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: continue
		var points := PackedVector2Array()
		for vertex in mesh.mesh.get_faces():
			var point: Vector3 = mesh.global_transform * vertex
			point -= direction * maxf(point.y,0.0)/direction.y
			points.append(host.project_floor(Vector2(point.x,point.z)))
		if points.size()<3: continue
		var hull := Geometry2D.convex_hull(points)
		if hull.size()<4: continue
		hull.resize(hull.size()-1)
		var i := 0
		while i<polygons.size():
			var merged := Geometry2D.merge_polygons(hull,polygons[i])
			if merged.size()==1:
				hull = merged[0]
				polygons.remove_at(i)
				i = 0
			else: i += 1
		polygons.append(hull)
	var shadow := Node2D.new()
	shadow.name = "GeometryShadow"
	host.add_child(shadow)
	host.move_child(shadow,0)
	for outline in polygons:
		var polygon := Polygon2D.new()
		polygon.polygon = outline
		polygon.color = Color(.025,.03,.045,.32)
		polygon.antialiased = true
		shadow.add_child(polygon)
