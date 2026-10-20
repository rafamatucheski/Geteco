extends SceneTree
## Conta, por zona do porto, o que as peças do Blender (HarborRouteProps._add_modeled)
## mudam na cena: MeshInstance3D, superfícies (≈ chamadas de desenho por passe), triângulos
## e quantas projetam sombra, com o interruptor ligado e desligado. Não mede tempo: é a
## contagem que explica uma diferença medida em release.
## Uso: tools/run_godot_locked.sh --path . --script res://tests/measure/count_harbor_route_props.gd

func _initialize() -> void:
	var rows := {}
	for modeled in [true, false]:
		HarborRouteProps.blender_props_enabled = modeled
		for zone_id: String in HarborRouteDetail3D.ALL_ZONES:
			var zone := HarborRouteDetail3D.build_zone(zone_id)
			rows["%s_%s" % [zone_id, "blender" if modeled else "procedural"]] = _count(zone)
			zone.free()
	HarborRouteProps.blender_props_enabled = true
	print("CONTAGEM_PORTO ", JSON.stringify(rows))
	for key: String in rows: print(key, " ", rows[key])
	quit(0)


func _count(root: Node) -> Dictionary:
	var result := {"meshes": 0, "surfaces": 0, "triangles": 0, "shadow_meshes": 0, "shadow_surfaces": 0, "shadow_triangles": 0, "materials": {}}
	for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null: continue
		var triangles := 0
		for s in node.mesh.get_surface_count():
			# Ferramenta fora do jogo: aqui o custo de ler os arrays não importa.
			var arrays := node.mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			triangles += (indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var material := node.material_override if node.material_override else node.get_active_material(s)
			if material: result.materials[material.get_instance_id()] = true
		result.meshes += 1
		result.surfaces += node.mesh.get_surface_count()
		result.triangles += triangles
		if node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			result.shadow_meshes += 1
			result.shadow_surfaces += node.mesh.get_surface_count()
			result.shadow_triangles += triangles
	result.materials = result.materials.size()
	return result
