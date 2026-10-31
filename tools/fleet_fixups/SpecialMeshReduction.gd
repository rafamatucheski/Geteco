extends RefCounted
## Simplifica ilhas conectadas independentemente, para que um retrovisor, entrada de ar ou vidro pequeno
## não suma para cumprir a meta de triângulos de uma carroceria bem maior.
static func reduce(source: Mesh, ratio: float) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var tool := SurfaceTool.new()
		tool.create_from(source,surface)
		tool.index()
		var arrays: Array=tool.commit_to_arrays()
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var parents: Array[int]=[]
		parents.resize(points.size())
		var positions := {}
		for i in points.size():
			parents[i]=i
			var key := Vector3i((points[i]*100000.0).round())
			if positions.has(key): parents[i]=int(positions[key])
			else: positions[key]=i
		for start in range(0,indices.size(),3):
			var a := root_of(parents,indices[start])
			for offset in [1,2]:
				var b := root_of(parents,indices[start+offset])
				if a!=b: parents[b]=a
		var islands := {}
		for start in range(0,indices.size(),3):
			var key := root_of(parents,indices[start])
			if not islands.has(key): islands[key]=PackedInt32Array()
			var row: PackedInt32Array=islands[key]
			row.append_array(indices.slice(start,start+3))
			islands[key]=row
		var output := PackedInt32Array()
		for island: PackedInt32Array in islands.values():
			if island.size()<=288:
				output.append_array(island)
				continue
			var subset: Array=arrays.duplicate()
			subset[Mesh.ARRAY_INDEX]=island
			var importer := ImporterMesh.new()
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,subset)
			importer.generate_lods(25.0,60.0,[])
			var wanted := maxi(144,roundi(island.size()*ratio))
			var best := island
			var distance := absi(best.size()-wanted)
			for lod in importer.get_surface_lod_count(0):
				var candidate := importer.get_surface_lod_indices(0,lod)
				if candidate.size()>=144 and absi(candidate.size()-wanted)<distance:
					best=candidate
					distance=absi(candidate.size()-wanted)
			output.append_array(best)
		arrays[Mesh.ARRAY_INDEX]=output
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(surface,source.surface_get_material(surface))
	return result

static func root_of(parents: Array[int], index: int) -> int:
	var key := index
	while parents[key]!=key: key=parents[key]
	while parents[index]!=index:
		var next := parents[index]
		parents[index]=key
		index=next
	return key
