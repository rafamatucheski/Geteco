extends SceneTree
const ART := preload("res://world/mining/MiningExterior.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene:=Node3D.new()
	root.add_child(scene)
	if "--floor-diagnostic" in OS.get_cmdline_user_args():
		await _floor_diagnostic(scene)
		quit()
		return
	ART.build_surfaces(scene,Rect2(-384,-1824,96,96))
	await physics_frame
	await physics_frame
	var space:=scene.get_world_3d().direct_space_state
	var centre:=Vector3(-290.844,0,-1756.199)
	for x in [-.003,0.0,.003]:
		for z in [-.003,0.0,.003]:
			var p:=centre+Vector3(x,0,z)
			var query:=PhysicsRayQueryParameters3D.create(p+Vector3.UP*.45,p-Vector3.UP*.3,1)
			var hit:=space.intersect_ray(query)
			print("CONTACT_PROBE ",JSON.stringify({"point":[p.x,p.y,p.z],"hit":str(hit.get("position",Vector3.INF)),"height":ART.surface_height(Vector2(p.x,p.z))}))
	for row in ART._road_triangles:
		if row.bounds.grow(.05).has_point(Vector2(centre.x,centre.z)):
			print("CONTACT_TRI ",row.faces)
	quit()

func _floor_diagnostic(scene: Node3D) -> void:
	for x in [-3,-2]:
		for z in [-19,-18]: ART.build_surfaces(scene,Rect2(float(x)*96,float(z)*96,96,96))
	await physics_frame
	await physics_frame
	var holes: Array[Dictionary]=[]
	var checked:=0
	var space:=scene.get_world_3d().direct_space_state
	for x in range(-31,32,2):
		for z in range(-49,14,2):
			var local:=Vector2(float(x),float(z))
			if (local-Vector2(0,-18)).length()>32: continue
			var p:=local+Vector2(-180,-1760)
			var expected:=ART.surface_height(p)
			var ray:=PhysicsRayQueryParameters3D.create(Vector3(p.x,expected+.2,p.y),Vector3(p.x,expected-.2,p.y),1)
			var hit:=space.intersect_ray(ray)
			checked+=1
			if hit.is_empty() or absf(float(hit.position.y)-expected)>.025:
				holes.append({"xz":str(p),"expected":expected,"hit":str(hit.get("position",Vector3.INF))})
	var normal_min:=1.0
	var floor_vertices:=0
	for mesh in scene.find_children("ExcavatedOreBenches","MeshInstance3D",true,false):
		var arrays: Array=mesh.mesh.surface_get_arrays(0)
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		for i in points.size():
			if absf(points[i].y+28.0)<.0001:
				floor_vertices+=1
				normal_min=minf(normal_min,normals[i].y)
	print("MINING_FLOOR_GEOMETRY ",JSON.stringify({"rays":checked,"holes":holes,"flat_floor_vertices":floor_vertices,"minimum_flat_vertex_normal_y":normal_min,"note":"Physics rays target the same face arrays emitted for rendering; distant visual fallback has no collider."}))
