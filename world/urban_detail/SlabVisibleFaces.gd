extends RefCounted
## Mantém a face de baixo e as paredes de uma laje estrutural, excluindo faces de cima escondidas.
## A física pertence ao sólido original; este auxiliar só monta dados de render.
const CUT := preload("res://world/urban_detail/GroundCut.gd")

static func box_with_top_opening(size: Vector3, opening: Rect2) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size=size
	var source: Array=box.get_mesh_arrays()
	var vertices: PackedVector3Array=source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=source[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array=source[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array=source[Mesh.ARRAY_INDEX]
	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_uv := PackedVector2Array()
	for i in range(0,indices.size(),3):
		if normals[indices[i]].y>.9: continue
		for j in 3:
			var index := indices[i+j]
			out_vertices.append(vertices[index]); out_normals.append(normals[index]); out_uv.append(uv[index])
	var footprint := Rect2(-Vector2(size.x,size.z)*.5,Vector2(size.x,size.z))
	var exposed := CUT.subtract_exact([CUT.rect_polygon(footprint)],[CUT.rect_polygon(opening)])
	# Arrays direto da triangulação: montar a malha só para ler de volta custava uma ida à GPU.
	var top: Array=CUT.flat_arrays(exposed,size.y*.5,1.0)
	if not top.is_empty():
		var arrays: Array=top
		for index in arrays[Mesh.ARRAY_INDEX]:
			out_vertices.append(arrays[Mesh.ARRAY_VERTEX][index])
			out_normals.append(arrays[Mesh.ARRAY_NORMAL][index])
			out_uv.append(arrays[Mesh.ARRAY_TEX_UV][index])
	var result := ArrayMesh.new()
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=out_vertices
	arrays[Mesh.ARRAY_NORMAL]=out_normals
	arrays[Mesh.ARRAY_TEX_UV]=out_uv
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result
