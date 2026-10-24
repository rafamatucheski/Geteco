extends SceneTree
func _initialize() -> void:
	for id: String in ["bike_sport","bike_cruiser","bike_urban"]:
		var model: Node3D=(load("res://artifacts/vehicle-fit-20261023/motorcycles/originals/"+id+".scn") as PackedScene).instantiate()
		var part:=model.get_node("Body") as MeshInstance3D
		for s in part.mesh.get_surface_count():
			if preload("res://runtime/VehicleSurfaceRoles.gd").key(part,s)!="trim": continue
			var arrays:=part.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var parents:=PackedInt32Array(); parents.resize(vertices.size()); var points:={}
			for i in vertices.size():
				var key:=vertices[i].snapped(Vector3.ONE*.0001)
				parents[i]=points[key] if points.has(key) else i
				if not points.has(key): points[key]=i
			for first in range(0,indices.size(),3):
				for k in [1,2]: parents[find(parents,indices[first+k])]=find(parents,indices[first])
			var boxes:={}
			for i in vertices.size():
				var key:=find(parents,i)
				boxes[key]=(boxes[key] as AABB).expand(vertices[i]) if boxes.has(key) else AABB(vertices[i],Vector3.ZERO)
			for key in boxes:
				var box: AABB=boxes[key]
				if box.position.y<.08: print("LOW_COMPONENT ",id," s=",s," key=",key," ",box)
		model.free()
	quit(0)
func find(parents: PackedInt32Array,index: int) -> int:
	while parents[index]!=index: index=parents[index]
	return index
