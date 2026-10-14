extends SceneTree
const REGION := preload("res://world/desert/DesertRegion.gd")
const DETAIL := preload("res://world/desert/DesertSurfaceDetail.gd")
const CUT := preload("res://world/urban_detail/GroundCut.gd")
var failures: Array[String]=[]
var report: Array=[]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var region := REGION.new()
	region.initial_prewarm_only=true
	root.add_child(region)
	region.set_process(false)
	region.prepare_data()
	var raw := Node3D.new()
	root.add_child(raw)
	var raw_rect := Rect2(-192,-960,96,96)
	region._surface(raw,"DesertGround",raw_rect,0,preload("res://world/desert/DesertGeometry.gd").material(Color("b9a079"),true),true)
	region.road_geometry.build_chunk(raw,raw_rect)
	DETAIL.build_sites_ground(raw,raw_rect)
	var physics_before := physics_signature(raw)
	preload("res://world/desert/DesertGroundOwnership.gd").compose(raw,raw_rect,region.road_geometry)
	var physics_after := physics_signature(raw)
	var unchanged := physics_before==physics_after
	if not unchanged: failures.append("Visual ownership changed collision resources/transforms/layers")
	raw.free()
	var cells := {}
	var polygons := DETAIL.site_polygons()
	polygons.append(CUT.rect_polygon(preload("res://world/desert/DesertLayout.gd").DRAG_MEET_BOUNDS))
	for polygon in polygons:
		var bounds := CUT.bounds(polygon)
		for z in range(floori(bounds.position.y/96),ceili(bounds.end.y/96)):
			for x in range(floori(bounds.position.x/96),ceili(bounds.end.x/96)): cells[Vector2i(x,z)]=true
	for cell: Vector2i in cells:
		var rect := Rect2(Vector2(cell)*96,Vector2.ONE*96)
		var chunk := Node3D.new()
		root.add_child(chunk)
		region._build_surfaces(chunk,rect)
		var layers := {}
		var removed := 0.0
		var triangle_count := 0
		var changed_meshes := 0
		var retired_meshes := 0
		var removed_by_surface := {}
		for child in chunk.get_children():
			if not child is MeshInstance3D: continue
			removed+=float(child.get_meta("removed_hidden_ground_m2",0))
			if float(child.get_meta("removed_hidden_ground_m2",0))>.001:
				changed_meshes+=1
				if child.mesh==null: retired_meshes+=1
				var label := "DesertGround" if child.get_meta("desert_base_ground",false) else str(child.name)
				removed_by_surface[label]=float(removed_by_surface.get(label,0))+float(child.get_meta("removed_hidden_ground_m2",0))
			if child.mesh==null: continue
			if not child.get_meta("desert_base_ground",false) and child.name not in [&"GravelShoulder",&"WeatheredAsphalt",&"TruckApron",&"DigoApron",&"DragMeetPaddock"]: continue
			var own := {}
			for surface in child.mesh.get_surface_count():
				var arrays: Array=child.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				triangle_count+=vertices.size()/3
				for i in range(0,vertices.size(),3):
					var triangle := PackedVector2Array()
					for j in 3: triangle.append(Vector2(vertices[i+j].x,vertices[i+j].z))
					var bounds := CUT.bounds(triangle)
					for z in range(floori(bounds.position.y/4),ceili(bounds.end.y/4)):
						for x in range(floori(bounds.position.x/4),ceili(bounds.end.x/4)):
							var p := Vector2(x*4+.371,z*4+.613)
							if Geometry2D.is_point_in_polygon(p,triangle): own[Vector2i(x,z)]=true
			for p in own: layers[p]=int(layers.get(p,0))+1
		var duplicate := 0
		var missing := 0
		for z in range(floori(rect.position.y/4),ceili(rect.end.y/4)):
			for x in range(floori(rect.position.x/4),ceili(rect.end.x/4)):
				var count := int(layers.get(Vector2i(x,z),0))
				if count>1: duplicate+=1
				if count==0: missing+=1
		if duplicate>0 or missing>0: failures.append("%s duplicate=%d missing=%d"%[cell,duplicate,missing])
		await physics_frame
		await physics_frame
		var hits := 0
		for offset: Vector2 in [Vector2(7,7),Vector2(48,48),Vector2(87,87)]:
			var p := rect.position+offset
			var point := Vector3(p.x,0,p.y)
			var hit := chunk.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.2,point-Vector3.UP,1))
			if not hit.is_empty(): hits+=1
		if hits!=3: failures.append("%s physical support %d/3"%[cell,hits])
		report.append({"cell":str(cell),"sample_spacing_m":4,"duplicate_samples":duplicate,"missing_samples":missing,"removed_hidden_m2":removed,"removed_by_surface":removed_by_surface,"changed_meshes":changed_meshes,"retired_meshes":retired_meshes,"triangles":triangle_count,"support_hits":hits})
		chunk.free()
	region.free()
	FileAccess.open("res://evidence/desert-floor-fix-20261014/ownership.json",FileAccess.WRITE).store_string(JSON.stringify({"cells":report,"collision_fingerprint_unchanged":unchanged,"collision_fingerprint":physics_before,"failures":failures},"\t"))
	print("DESERT_OWNERSHIP ",JSON.stringify({"cells":report,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func physics_signature(chunk: Node3D) -> String:
	var signature: Array=[]
	for collider in chunk.find_children("*","CollisionShape3D",true,false):
		var body: CollisionObject3D=collider.get_parent()
		var faces: PackedVector3Array=collider.shape.get_faces() if collider.shape is ConcavePolygonShape3D else PackedVector3Array()
		signature.append([str(chunk.get_path_to(collider)),collider.global_transform,collider.disabled,body.collision_layer,body.collision_mask,collider.shape.get_instance_id(),faces])
	return var_to_bytes(signature).hex_encode().sha256_text()
