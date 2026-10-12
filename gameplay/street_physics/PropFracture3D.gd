extends RefCounted
## Split authored mesh surfaces into three spatial shards, retaining their materials.
## Runs only at impact; debris lifetime and body count belong to FragileProps3D.
static func split(root: Node3D, axis: int) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D]=[]
	if root is MeshInstance3D: meshes.append(root)
	for child in root.find_children("*","MeshInstance3D",true,false): meshes.append(child)
	var bounds := AABB()
	var first := true
	var transforms := {}
	for mesh in meshes:
		var pose := _pose(mesh,root)
		transforms[mesh]=pose
		var box: AABB=pose*mesh.get_aabb()
		bounds=box if first else bounds.merge(box)
		first=false
	var result: Array[MeshInstance3D]=[]
	for shard in 3:
		var output: ArrayMesh
		for source in meshes:
			if source.mesh==null: continue
			var pose: Transform3D=transforms[source]
			for surface in source.mesh.get_surface_count():
				if source.mesh is ArrayMesh and source.mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: continue
				var arrays: Array=source.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				var count := 0
				for triangle in range(0,indices.size() if not indices.is_empty() else vertices.size(),3):
					var ids := [indices[triangle],indices[triangle+1],indices[triangle+2]] if not indices.is_empty() else [triangle,triangle+1,triangle+2]
					var center: Vector3=pose*((vertices[ids[0]]+vertices[ids[1]]+vertices[ids[2]])/3.0)
					var band := clampi(int((center[axis]-bounds.position[axis])/maxf(bounds.size[axis],.001)*3.0),0,2)
					if band!=shard: continue
					for index in ids:
						if arrays[Mesh.ARRAY_NORMAL]!=null and not arrays[Mesh.ARRAY_NORMAL].is_empty(): tool.set_normal((pose.basis.inverse().transposed()*arrays[Mesh.ARRAY_NORMAL][index]).normalized())
						if arrays[Mesh.ARRAY_COLOR]!=null and not arrays[Mesh.ARRAY_COLOR].is_empty(): tool.set_color(arrays[Mesh.ARRAY_COLOR][index])
						if arrays[Mesh.ARRAY_TEX_UV]!=null and not arrays[Mesh.ARRAY_TEX_UV].is_empty(): tool.set_uv(arrays[Mesh.ARRAY_TEX_UV][index])
						tool.add_vertex(pose*vertices[index])
						count+=1
				if count==0: continue
				tool.set_material(source.get_active_material(surface))
				output=tool.commit(output)
		if output!=null:
			var piece := MeshInstance3D.new()
			piece.mesh=output
			result.append(piece)
	return result

static func _pose(node: Node3D, root: Node3D) -> Transform3D:
	var pose := node.transform
	var parent := node.get_parent()
	while node!=root and parent!=null and parent!=root:
		if parent is Node3D: pose=parent.transform*pose
		parent=parent.get_parent()
	return root.transform*pose if node!=root else pose
