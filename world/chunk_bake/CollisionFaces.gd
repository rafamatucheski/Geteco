extends RefCounted
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
## Colisão de malha a partir das arrays que o próprio código acabou de montar.
## `Mesh.create_trimesh_shape`, `create_convex_shape` e `get_faces` passam por `surface_get_arrays`
## por dentro: o RenderingDevice lê o buffer de volta da placa e o thread principal espera a GPU terminar os
## quadros em voo (o mesmo custo que levou ao MeshArrayCache, auditoria de 19/10). Quem gera a malha já tem
## os vértices na CPU; basta entregá-los ao ConcavePolygonShape3D na mesma ordem que a malha usaria.

## Triângulos (3 vértices cada) na ordem de desenho, com ou sem ARRAY_INDEX.
static func from_arrays(arrays: Array) -> PackedVector3Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: Variant = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else null
	if not (indices is PackedInt32Array) or (indices as PackedInt32Array).is_empty():
		return vertices
	var faces := PackedVector3Array()
	faces.resize((indices as PackedInt32Array).size())
	var i := 0
	for index in indices as PackedInt32Array:
		faces[i] = vertices[index]
		i += 1
	return faces

## Substituto de `mesh.get_faces`. Primitiva (BoxMesh, SphereMesh...) gera as arrays na CPU com
## get_mesh_arrays; malha qualquer passa pelo MeshArrayCache (no máximo uma leitura por malha, não uma por uso).
static func faces_of(mesh: Mesh) -> PackedVector3Array:
	if mesh is PrimitiveMesh:
		return from_arrays((mesh as PrimitiveMesh).get_mesh_arrays())
	var faces := PackedVector3Array()
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
		faces.append_array(from_arrays(MESH_ARRAYS.arrays_of(mesh, surface)))
	return faces

static func shape_from_arrays(arrays: Array, backface := false) -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(from_arrays(arrays))
	shape.backface_collision = backface
	return shape

## SurfaceTool já preenchido: devolve [malha, forma, triângulos] sem ler a malha de volta da GPU.
static func commit_with_shape(surface: SurfaceTool, backface := false) -> Array:
	# commit() mantém o material do set_material e o formato de antes; commit_to_arrays() não esvazia a
	# ferramenta e só monta as mesmas arrays na CPU de novo (barato perto de esperar a GPU).
	var mesh := surface.commit()
	var arrays := surface.commit_to_arrays()
	var faces := from_arrays(arrays)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = backface
	return [mesh, shape, faces]
