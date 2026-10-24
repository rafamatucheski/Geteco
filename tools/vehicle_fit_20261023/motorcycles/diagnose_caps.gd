extends SceneTree
func _initialize() -> void:
	for id: String in ["bike_sport","bike_cruiser","bike_urban"]:
		var model: Node3D=(load("res://artifacts/vehicle-fit-20261023/motorcycles/originals/"+id+".scn") as PackedScene).instantiate()
		var part:=model.get_node("Body") as MeshInstance3D
		for s in part.mesh.get_surface_count():
			if preload("res://runtime/VehicleSurfaceRoles.gd").key(part,s)!="trim": continue
			var arrays:=part.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var points:=[]
			for p: Vector3 in verts:
				if absf(p.x)<.10 and p.y>1.02 and p.z>-.35 and p.z<.2: points.append(p)
			if not points.is_empty():
				var box:=AABB(points[0],Vector3.ZERO)
				for p: Vector3 in points: box=box.expand(p)
				print("CAP_COMPONENT ",id," s=",s," count=",points.size()," bounds=",box)
		model.free()
	quit(0)
