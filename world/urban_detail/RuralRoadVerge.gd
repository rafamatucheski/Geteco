extends RefCounted
## Opaque earth-to-grass ring, clipped with the same streaming tiles as roads.
static func prepare(polygons: Array[PackedVector2Array]) -> Array:
	var result := []
	for polygon in polygons:
		var expanded := Geometry2D.offset_polygon(polygon,1.4,Geometry2D.JOIN_ROUND)
		if expanded.is_empty(): continue
		var outer: PackedVector2Array = expanded[0]
		for i in outer.size():
			var a := outer[i]
			var b := outer[(i+1)%outer.size()]
			var inner_a := _closest(a,polygon)
			var inner_b := _closest(b,polygon)
			for tri in [PackedVector2Array([a,b,inner_b]),PackedVector2Array([a,inner_b,inner_a])]:
				if absf((tri[1]-tri[0]).cross(tri[2]-tri[0]))<.00001: continue
				result.append({"points":tri,"alphas":PackedFloat32Array([0,0,1]) if tri[1]==b else PackedFloat32Array([0,1,1])})
	return result

static func _closest(point: Vector2,polygon: PackedVector2Array) -> Vector2:
	var best := polygon[0]
	for i in polygon.size():
		var candidate := Geometry2D.get_closest_point_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()])
		if candidate.distance_squared_to(point)<best.distance_squared_to(point): best=candidate
	return best

static func build(parent: Node3D,triangles: Array,clip: PackedVector2Array) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for triangle in triangles:
		var source: PackedVector2Array = triangle.points
		var denominator := (source[1]-source[0]).cross(source[2]-source[0])
		for polygon in Geometry2D.intersect_polygons(source,clip):
			for index in Geometry2D.triangulate_polygon(polygon):
				var p: Vector2 = polygon[index]
				var w1 := (p-source[0]).cross(source[2]-source[0])/denominator
				var w2 := (source[1]-source[0]).cross(p-source[0])/denominator
				var alpha: float = triangle.alphas[0]*(1-w1-w2)+triangle.alphas[1]*w1+triangle.alphas[2]*w2
				surface.set_normal(Vector3.UP)
				surface.set_color(Color(1,1,1,clampf(alpha,0,1)))
				surface.add_vertex(Vector3(p.x,.018,p.y))
				count+=1
	if count==0: return
	var mesh := MeshInstance3D.new()
	mesh.name="EarthRoadVerge"
	mesh.mesh=surface.commit()
	mesh.material_override=preload("res://world/urban_detail/RuralGroundMaterial.gd").material()
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
