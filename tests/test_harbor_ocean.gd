extends SceneTree

func polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size(): area += polygon[i].cross(polygon[(i+1)%polygon.size()])
	return absf(area)*0.5

func dry_geometry(surface: MeshInstance3D, land: Array[PackedVector2Array]) -> float:
	if surface == null: return 0.0
	var area := 0.0
	var faces := surface.mesh.get_faces()
	for i in range(0,faces.size(),3):
		var triangle := PackedVector2Array()
		for j in 3: triangle.append(Vector2(faces[i+j].x,faces[i+j].z))
		area += polygon_area(triangle)
		for polygon in land:
			if polygon.size() < 3: continue
			for overlap in Geometry2D.intersect_polygons(triangle,polygon):
				assert(polygon_area(overlap)<0.00001,"No water triangle may cover dry land, including partial cells")
	var wash := surface.get_node_or_null("ShoreWash") as MeshInstance3D
	if wash != null: dry_geometry(wash,land)
	return area

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ocean := preload("res://world/regions/HarborOcean.gd").new()
	ocean.configure([[0,0,160,160]],[])
	assert(is_equal_approx(ocean.shore_distance(Vector2(12,5)),2.0),"Distance uses metres")
	assert(is_equal_approx(ocean.shore_distance(Vector2(100,100)),24.0),"Distance is bounded")
	var holder := Node3D.new()
	root.add_child(holder)
	var a := ocean.build_chunk(holder,Rect2(0,0,64,64))
	var b := ocean.build_chunk(holder,Rect2(64,0,64,64))
	assert(a.material_override == b.material_override,"Chunks share one material")
	assert(a.find_children("*","CollisionObject3D",true,false).is_empty(),"Water must not create walkable collision")
	assert(a.get_node_or_null("ShoreWash") != null,"Exposed shore receives wash")
	assert(b.get_node_or_null("ShoreWash") == null,"Open water has no shoreline pass")
	assert(a.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var aa := a.mesh.surface_get_arrays(0)
	var bb := b.mesh.surface_get_arrays(0)
	assert(aa[Mesh.ARRAY_VERTEX].size() >= 289,"Original seam grid retained; only coastal pieces add vertices")
	assert(is_equal_approx(dry_geometry(a,ocean.shores),4096.0-100.0),"Exact coast preserves all open sea, with no square holes")
	for z in 17:
		assert(aa[Mesh.ARRAY_VERTEX][z*17+16] == bb[Mesh.ARRAY_VERTEX][z*17],"Seam position")
		assert(aa[Mesh.ARRAY_COLOR][z*17+16] == bb[Mesh.ARRAY_COLOR][z*17],"Seam shading")
	for point in aa[Mesh.ARRAY_VERTEX]: assert(is_equal_approx(point.y,-0.94),"Original water height")
	assert(ocean.build_chunk(holder,Rect2(0,0,8,8)) == null,"Entirely dry chunks have no ocean mesh")
	var island := PackedVector2Array([Vector2(1.25,1.25),Vector2(1.75,1.25),Vector2(1.75,1.75),Vector2(1.25,1.75)])
	var diagonal := PackedVector2Array([Vector2(5,1),Vector2(9,1),Vector2(5,7)])
	ocean.configure([],[island,diagonal])
	var coast := ocean.build_chunk(holder,Rect2(0,0,16,16))
	assert(absf(dry_geometry(coast,ocean.shores)-(256.0-0.25-12.0))<0.0001,"Tiny islands and oblique shores retain exact water area")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	ocean.configure(source.harbor_land,[])
	for row in source.harbor_land:
		var corner := Vector2(row[0],row[1])/16.0
		var boundary := ocean.build_chunk(holder,Rect2(corner-Vector2(8,8),Vector2(16,16)))
		dry_geometry(boundary,ocean.shores)
	ocean.configure([],[])
	assert(is_equal_approx(dry_geometry(ocean.build_chunk(holder,Rect2(0,0,16,16)),[]),256.0),"Reconfigure does not retain stale dry land")
	holder.free()
	print("HARBOR_OCEAN PASS: exact dry land exclusion, tiny islands, oblique/coastal area, empty dry chunks, shared material, seams, height, no collision and reload")
	quit()
