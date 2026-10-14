extends SceneTree
const SLAB := preload("res://world/urban_detail/SlabVisibleFaces.gd")
var failures: Array[String]=[]
func _initialize() -> void:
	for row in [[Vector3.ONE,Rect2(-.25,-.5,.5,1),.5],[Vector3(2.6,.35,17.2),Rect2(-1.15,-8.55,2.3,17.1),5.39]]:
		var mesh := SLAB.box_with_top_opening(row[0],row[1])
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var area := 0.0
		var underside := 0.0
		for i in range(0,vertices.size(),3):
			var a := vertices[i]; var b := vertices[i+1]; var c := vertices[i+2]
			var triangle_area := (b-a).cross(c-a).length()*.5
			if normals[i].y>.9:
				area+=triangle_area
				var center := (a+b+c)/3
				if row[1].grow(-.0001).has_point(Vector2(center.x,center.z)): failures.append("Top face inside opening")
			if normals[i].y<-.9: underside+=triangle_area
		if absf(area-float(row[2]))>.001: failures.append("Exposed top area %s != %s"%[area,row[2]])
		if absf(underside-row[0].x*row[0].z)>.001: failures.append("Structural underside lost")
	print("SLAB_VISIBLE_FACES failures=",failures)
	quit(0 if failures.is_empty() else 1)
