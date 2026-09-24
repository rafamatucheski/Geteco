extends SceneTree

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
	assert(aa[Mesh.ARRAY_VERTEX].size() == 289,"Bounded geometry")
	for z in 17:
		assert(aa[Mesh.ARRAY_VERTEX][z*17+16] == bb[Mesh.ARRAY_VERTEX][z*17],"Seam position")
		assert(aa[Mesh.ARRAY_COLOR][z*17+16] == bb[Mesh.ARRAY_COLOR][z*17],"Seam shading")
	for point in aa[Mesh.ARRAY_VERTEX]: assert(is_equal_approx(point.y,-0.94),"Original water height")
	holder.free()
	print("HARBOR_OCEAN PASS: distance, shared material, bounded mesh, seamless chunks, preserved height and no collision")
	quit()
