class_name PortMeshOptimizer
extends RefCounted

## Otimizador de malhas estáticas portuárias por agrupamento de material (Draw Call Batching).
## Percorre uma hierarquia de Node3D, agrupa todos os MeshInstance3D que compartilham
## o mesmo StandardMaterial3D e combina suas geometrias em um único ArrayMesh por material
## via SurfaceTool, preservando transformações relativas e AABBs.

static func optimize_hierarchy(root_node: Node3D, remove_source_meshes: bool = true) -> Dictionary:
	var collected_items: Array[Dictionary] = []
	_collect_meshes_recursive(root_node, root_node, Transform3D.IDENTITY, collected_items)

	var before_count := collected_items.size()
	if before_count == 0:
		return {
			"before_count": 0,
			"after_count": 0,
			"unique_materials": 0,
			"reduction_percent": 0.0
		}

	# Agrupa por material
	var material_groups: Dictionary = {}
	for item in collected_items:
		var mat: Material = item["material"]
		var key: Variant = mat.resource_name if (mat and not mat.resource_name.is_empty()) else mat
		if not material_groups.has(key):
			material_groups[key] = {
				"material": mat,
				"entries": []
			}
		material_groups[key]["entries"].append(item)

	# Se for para remover as malhas antigas, removemos ou ocultamos os nós originais
	if remove_source_meshes:
		for item in collected_items:
			var mi: MeshInstance3D = item["node"]
			mi.queue_free()

	# Container dos lotes otimizados
	var batch_container := Node3D.new()
	batch_container.name = "BatchedStaticGeometry"
	root_node.add_child(batch_container)

	var after_count := 0
	for key in material_groups.keys():
		var group: Dictionary = material_groups[key]
		var mat: Material = group["material"]
		var entries: Array = group["entries"]

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		for entry in entries:
			var mesh: Mesh = entry["mesh"]
			var xform: Transform3D = entry["transform"]
			st.append_from(mesh, 0, xform)

		var committed_mesh: ArrayMesh = st.commit()
		if committed_mesh and committed_mesh.get_surface_count() > 0:
			var batch_mi := MeshInstance3D.new()
			batch_mi.name = "Batch_" + str(key)
			batch_mi.mesh = committed_mesh
			batch_mi.material_override = mat
			batch_container.add_child(batch_mi)
			after_count += 1

	var reduction := (1.0 - float(after_count) / float(max(1, before_count))) * 100.0

	return {
		"before_count": before_count,
		"after_count": after_count,
		"unique_materials": material_groups.size(),
		"reduction_percent": reduction
	}

static func _collect_meshes_recursive(current: Node, root: Node3D, current_xform: Transform3D, out_list: Array[Dictionary]) -> void:
	var next_xform := current_xform
	if current is Node3D and current != root:
		next_xform = current_xform * (current as Node3D).transform

	if current is MeshInstance3D and (current as MeshInstance3D).mesh != null:
		var mi := current as MeshInstance3D
		var mat: Material = mi.material_override
		if mat == null and mi.get_surface_override_material_count() > 0:
			mat = mi.get_surface_override_material(0)
		if mat == null and mi.mesh:
			mat = mi.mesh.surface_get_material(0)

		out_list.append({
			"node": mi,
			"mesh": mi.mesh,
			"transform": next_xform,
			"material": mat
		})

	for child in current.get_children():
		# Não coletar se já for um lote otimizado
		if child.name == "BatchedStaticGeometry":
			continue
		_collect_meshes_recursive(child, root, next_xform, out_list)
