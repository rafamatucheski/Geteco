extends SceneTree
func _initialize()->void:
	var model:Node3D=(load("res://artifacts/vehicle-fit-20261023/utility/originals/boxrunner.scn") as PackedScene).instantiate()
	var part:MeshInstance3D=model.get_node("Body")
	for s in part.mesh.get_surface_count():
		var arrays:=part.mesh.surface_get_arrays(s)
		var vs:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var ids:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var sets:Array=[]
		for i in range(0,ids.size(),3):
			var points:=[vs[ids[i]],vs[ids[i+1]],vs[ids[i+2]]]
			var matches:Array=[]
			for j in sets.size():
				for p:Vector3 in points:
					if sets[j].points.has(p):matches.append(j);break
			var row:Dictionary={"points":{},"tris":0}
			for j:int in matches:
				row.points.merge(sets[j].points)
				row.tris+=int(sets[j].tris)
			matches.reverse()
			for j:int in matches:sets.remove_at(j)
			for p:Vector3 in points:row.points[p]=true
			row.tris+=1;sets.append(row)
		for row:Dictionary in sets:
			var first:=true;var box:=AABB()
			for p:Vector3 in row.points:
				box=AABB(p,Vector3.ZERO) if first else box.expand(p);first=false
			if box.position.z< -1.57 and box.end.y>1.15:
				print("BOX_COMPONENT s=",s," tris=",row.tris," bounds=",box)
	model.free();quit()
