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
	# Cada superfície é lida uma vez (surface_get_arrays lê o buffer de volta da GPU e espera os
	# quadros em voo; antes eram três leituras por superfície, uma por lasca, no quadro do choque:
	# street.pre.props.hit chegou a 28 ms no release de 13/10) e cada triângulo é classificado
	# uma vez. A ordem dos vértices em cada lasca é a mesma de antes.
	var sources: Array=[]
	for source in meshes:
		if source.mesh==null: continue
		var pose: Transform3D=transforms[source]
		var normal_basis:=pose.basis.inverse().transposed()
		for surface in source.mesh.get_surface_count():
			if source.mesh is ArrayMesh and source.mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays: Array=source.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			# Três listas locais: mexer num PackedInt32Array guardado dentro de Array não é garantido.
			var band0:=PackedInt32Array()
			var band1:=PackedInt32Array()
			var band2:=PackedInt32Array()
			for triangle in range(0,indices.size() if not indices.is_empty() else vertices.size(),3):
				var ids := [indices[triangle],indices[triangle+1],indices[triangle+2]] if not indices.is_empty() else [triangle,triangle+1,triangle+2]
				var center: Vector3=pose*((vertices[ids[0]]+vertices[ids[1]]+vertices[ids[2]])/3.0)
				var band := clampi(int((center[axis]-bounds.position[axis])/maxf(bounds.size[axis],.001)*3.0),0,2)
				if band==0: band0.append_array(PackedInt32Array(ids))
				elif band==1: band1.append_array(PackedInt32Array(ids))
				else: band2.append_array(PackedInt32Array(ids))
			var bands: Array=[band0,band1,band2]
			sources.append({"arrays":arrays,"vertices":vertices,"pose":pose,"normal_basis":normal_basis,"bands":bands,"material":source.get_active_material(surface)})
	var result: Array[MeshInstance3D]=[]
	for shard in 3:
		var output: ArrayMesh
		for entry in sources:
			var ids: PackedInt32Array=entry.bands[shard]
			if ids.is_empty(): continue
			var arrays: Array=entry.arrays
			var vertices: PackedVector3Array=entry.vertices
			var pose: Transform3D=entry.pose
			var normal_basis: Basis=entry.normal_basis
			var normals: Variant=arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL]!=null and not arrays[Mesh.ARRAY_NORMAL].is_empty() else null
			var colors: Variant=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null and not arrays[Mesh.ARRAY_COLOR].is_empty() else null
			var uvs: Variant=arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null and not arrays[Mesh.ARRAY_TEX_UV].is_empty() else null
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for index in ids:
				if normals!=null: tool.set_normal((normal_basis*normals[index]).normalized())
				if colors!=null: tool.set_color(colors[index])
				if uvs!=null: tool.set_uv(uvs[index])
				tool.add_vertex(pose*vertices[index])
			tool.set_material(entry.material)
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
