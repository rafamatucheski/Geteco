extends RefCounted
## Malhas mescladas por material ("Batch_*": contêineres do navio, guindastes, galpões do porto)
## escondem objetos inteiros dentro de poucas malhas. Aqui cada malha é cortada em componentes
## ligados (vértices coincidentes) e os componentes que se tocam, de qualquer lote do mesmo pai,
## formam um objeto: um contêiner, uma perna de guindaste. Cada objeto vira um nó com as próprias
## malhas e a própria colisão, e entra em `WorldUnits` como qualquer outra peça.
##
## Só usa dados de malha (iguais na prévia sem renderizador e no jogo), então o resultado e os
## ids derivados dele são os mesmos nos dois.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const MIN_TRIANGLES := 600
const MAX_TRIANGLES := 600000
const JOIN := .04
const CELL := 1.0

static func split_children(parent: Node3D) -> int:
	var batches: Array[MeshInstance3D] = []
	for child in parent.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("Batch_") and child.mesh is ArrayMesh and child.mesh.get_surface_count() == 1 and not child.has_meta("world_edit_piece_id"): batches.append(child)
	if batches.size() < 1: return 0
	var triangles := 0
	for batch in batches: triangles += _index_count(batch.mesh) / 3
	if triangles < MIN_TRIANGLES or triangles > MAX_TRIANGLES: return 0
	var parts: Array[Dictionary] = []
	for batch in batches: _components(batch, parts)
	if parts.size() < 2: return 0
	var clusters := _cluster(parts)
	if clusters.size() < 2: return 0
	clusters.sort_custom(func(a, b): return (a.box as AABB).get_center().x + (a.box as AABB).get_center().z * 1000.0 < (b.box as AABB).get_center().x + (b.box as AABB).get_center().z * 1000.0)
	var layers := {}
	for batch in batches:
		for body in batch.get_children():
			if body is CollisionObject3D: layers[batch] = [body.collision_layer, body.collision_mask]
	var label := _label(batches[0])
	for cluster in clusters:
		var holder := Node3D.new()
		holder.name = "Parte"
		holder.set_meta("world_unit_label", label)
		parent.add_child(holder)
		holder.transform = Transform3D.IDENTITY
		var by_batch := {}
		for part in cluster.parts:
			if not by_batch.has(part.batch): by_batch[part.batch] = []
			by_batch[part.batch].append(part)
		for batch in by_batch:
			var mesh := _sub_mesh(batch, by_batch[batch])
			var instance := MeshInstance3D.new()
			instance.name = str(batch.name)
			instance.mesh = mesh
			instance.material_override = batch.material_override
			instance.cast_shadow = batch.cast_shadow
			instance.transform = batch.transform
			holder.add_child(instance)
			if layers.has(batch):
				instance.create_trimesh_collision()
				for body in instance.get_children():
					if body is StaticBody3D:
						body.collision_layer = layers[batch][0]
						body.collision_mask = layers[batch][1]
	for batch in batches:
		parent.remove_child(batch)
		batch.free()
	return clusters.size()

static func _label(batch: MeshInstance3D) -> String:
	var text := str(batch.name).trim_prefix("Batch_")
	var cut := text.find(" (")
	if cut > 0: text = text.substr(0, cut)
	return text.replace("_", " ").strip_edges()

static func _index_count(mesh: ArrayMesh) -> int:
	var arrays := MESH_ARRAYS.arrays_of(mesh, 0)
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if indices != null and (indices as PackedInt32Array).size() > 0: return (indices as PackedInt32Array).size()
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

static func _find(parents: PackedInt32Array, item: int) -> int:
	while parents[item] != item:
		parents[item] = parents[parents[item]]
		item = parents[item]
	return item

## Componentes ligados de uma malha: {batch, triangles: PackedInt32Array de índices de triângulo, box}.
static func _components(batch: MeshInstance3D, parts: Array[Dictionary]) -> void:
	var arrays := MESH_ARRAYS.arrays_of(batch.mesh, 0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := indices.size() if indices.size() > 0 else vertices.size()
	var welded := {}
	var parents := PackedInt32Array()
	var vertex_node := PackedInt32Array()
	vertex_node.resize(vertices.size())
	for index in vertices.size():
		var key := Vector3i((vertices[index] * 1000.0).round())
		if not welded.has(key):
			welded[key] = parents.size()
			parents.append(parents.size())
		vertex_node[index] = welded[key]
	for corner in range(0, count - 2, 3):
		var a := vertex_node[indices[corner] if indices.size() > 0 else corner]
		var b := vertex_node[indices[corner + 1] if indices.size() > 0 else corner + 1]
		var c := vertex_node[indices[corner + 2] if indices.size() > 0 else corner + 2]
		parents[_find(parents, b)] = _find(parents, a)
		parents[_find(parents, c)] = _find(parents, a)
	var groups := {}
	for corner in range(0, count - 2, 3):
		var root := _find(parents, vertex_node[indices[corner] if indices.size() > 0 else corner])
		if not groups.has(root): groups[root] = {"batch": batch, "triangles": PackedInt32Array(), "box": AABB(), "started": false}
		var group: Dictionary = groups[root]
		group.triangles.append(corner)
		for k in 3:
			var point := batch.transform * vertices[indices[corner + k] if indices.size() > 0 else corner + k]
			if not group.started:
				group.box = AABB(point, Vector3.ZERO)
				group.started = true
			else: group.box = (group.box as AABB).expand(point)
	for group in groups.values(): parts.append(group)

## Une componentes cujas caixas se tocam (grade de 1 m para não comparar tudo com tudo).
static func _cluster(parts: Array[Dictionary]) -> Array[Dictionary]:
	var parents := PackedInt32Array()
	for index in parts.size(): parents.append(index)
	var grid := {}
	for index in parts.size():
		var box: AABB = (parts[index].box as AABB).grow(JOIN)
		var low := Vector3i((box.position / CELL).floor())
		var high := Vector3i((box.end / CELL).floor())
		for x in range(low.x, high.x + 1):
			for y in range(low.y, high.y + 1):
				for z in range(low.z, high.z + 1):
					var key := Vector3i(x, y, z)
					if not grid.has(key): grid[key] = []
					for other in grid[key]:
						if (parts[other].box as AABB).grow(JOIN).intersects(box): parents[_find(parents, index)] = _find(parents, other)
					grid[key].append(index)
	var by_root := {}
	for index in parts.size():
		var root := _find(parents, index)
		if not by_root.has(root): by_root[root] = {"parts": [], "box": parts[index].box}
		by_root[root].parts.append(parts[index])
		by_root[root].box = (by_root[root].box as AABB).merge(parts[index].box)
	var result: Array[Dictionary] = []
	for cluster in by_root.values(): result.append(cluster)
	return result

static func _sub_mesh(batch: MeshInstance3D, parts: Array) -> ArrayMesh:
	var arrays := MESH_ARRAYS.arrays_of(batch.mesh, 0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var uvs2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	var out_uvs2 := PackedVector2Array()
	var out_colors := PackedColorArray()
	for part in parts:
		for corner in part.triangles:
			for k in 3:
				var source: int = indices[corner + k] if indices.size() > 0 else corner + k
				out_vertices.append(vertices[source])
				if normals.size() > source: out_normals.append(normals[source])
				if uvs.size() > source: out_uvs.append(uvs[source])
				if uvs2.size() > source: out_uvs2.append(uvs2[source])
				if colors.size() > source: out_colors.append(colors[source])
	var result_arrays: Array = []
	result_arrays.resize(Mesh.ARRAY_MAX)
	result_arrays[Mesh.ARRAY_VERTEX] = out_vertices
	if out_normals.size() == out_vertices.size(): result_arrays[Mesh.ARRAY_NORMAL] = out_normals
	if out_uvs.size() == out_vertices.size(): result_arrays[Mesh.ARRAY_TEX_UV] = out_uvs
	if out_uvs2.size() == out_vertices.size(): result_arrays[Mesh.ARRAY_TEX_UV2] = out_uvs2
	if out_colors.size() == out_vertices.size(): result_arrays[Mesh.ARRAY_COLOR] = out_colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result_arrays)
	var material: Material = batch.mesh.surface_get_material(0)
	if material != null: mesh.surface_set_material(0, material)
	return mesh
