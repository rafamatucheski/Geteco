extends SceneTree
## Fusão geral por trecho (world/chunk_bake/ChunkCellMerge.gd): o trecho do cais do Northstar e o da ponte
## da fundição, montados com e sem a fusão no mesmo processo, precisam mostrar exatamente os mesmos
## triângulos; peças vivas continuam separadas; lote nenhum passa da célula; registro em cache que sai do
## trecho volta a aparecer inteiro.
const REGION := preload("res://world/regions/NativeRegion.gd")
const MERGE := preload("res://world/chunk_bake/ChunkCellMerge.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _triangles(mesh_node: MeshInstance3D) -> int:
	var total := 0
	for surface in mesh_node.mesh.get_surface_count():
		var arrays := mesh_node.mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		total += (indices.size() if indices != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return total

func _snapshot(chunk: Node3D) -> Dictionary:
	var result := {"triangles": 0, "meshes": 0, "batches": 0, "hidden": 0, "oversize": 0, "hoist_visible": 0}
	# Peça de origem mais comprida (borda do cais, casco): um lote pode ter esse tamanho, não mais que isso + célula.
	var longest_source := 0.0
	for found in chunk.find_children("*", "MeshInstance3D", true, false):
		var source := found as MeshInstance3D
		if source.mesh == null or not source.has_meta(MERGE.MERGED_SOURCE): continue
		var extent := (source.global_transform * source.get_aabb()).size
		longest_source = maxf(longest_source, maxf(extent.x, extent.z))
	for found in chunk.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := found as MeshInstance3D
		if mesh_node.mesh == null: continue
		if mesh_node.has_meta(MERGE.MERGED_SOURCE): result.hidden += 1
		if not mesh_node.is_visible_in_tree(): continue
		result.meshes += 1
		result.triangles += _triangles(mesh_node)
		if mesh_node.has_meta(MERGE.BATCH):
			result.batches += 1
			var size := (mesh_node.global_transform * mesh_node.get_aabb()).size
			# Célula de 32 m mais a peça maior que atravessa a borda; um lote do trecho inteiro passaria disso.
			if maxf(size.x, size.z) > longest_source + 2.0 * MERGE.CELL_FAR.x: result.oversize += 1
		var owner := mesh_node.get_parent()
		while owner != null and owner != chunk and owner.get_parent() != chunk: owner = owner.get_parent()
		if owner != null and String(owner.name).begins_with("NorthstarCargoHoist"): result.hoist_visible += 1
	return result

func _build(region: Node, key: Vector2i) -> Node3D:
	region._build_chunk(key)
	var chunk: Node3D = region.chunks[key]
	for frame in 8: await process_frame
	return chunk

func run() -> void:
	# Fusão inteira de uma vez: aqui não se mede tempo de quadro.
	preload("res://world/chunk_bake/ChunkCellMerge.gd").slice_budget_usec = 0
	var keys: Array[Vector2i] = [Vector2i(3, 0), Vector2i(3, 1)]
	var results := {}
	for enabled in [false, true]:
		MERGE.enabled = enabled
		var region = REGION.build_region("harbor", Vector3.INF)
		region.initial_prewarm_only = true
		root.add_child(region)
		while not region.prepared: await process_frame
		for key in keys:
			var chunk: Node3D = await _build(region, key)
			results["%s|%s" % [enabled, key]] = _snapshot(chunk)
			if enabled and key == Vector2i(3, 1):
				# Registro em cache saindo do trecho: as fontes escondidas voltam a aparecer.
				var cached: Array = []
				for child in chunk.get_children():
					if child.has_meta("record_cache_key"): cached.append(child)
				var hidden_before := 0
				for record in cached:
					for mesh in record.find_children("*", "MeshInstance3D", true, false):
						if mesh.has_meta(MERGE.MERGED_SOURCE): hidden_before += 1
				region._detach_cached_records(chunk)
				var hidden_after := 0
				for record in cached:
					for mesh in record.find_children("*", "MeshInstance3D", true, false):
						if mesh.has_meta(MERGE.MERGED_SOURCE) or not mesh.visible: hidden_after += 1
				print("CELL_MERGE cache registros=%d escondidas_antes=%d depois=%d" % [cached.size(), hidden_before, hidden_after])
				check(hidden_before > 0, "Registros em cache do cais entram na fusão")
				check(hidden_after == 0, "Registro em cache que sai do trecho volta a aparecer inteiro")
				for record in cached:
					if is_instance_valid(record) and record.get_parent() == null: record.free()
		region.free()
		await process_frame
	for key in keys:
		var off: Dictionary = results["false|%s" % key]
		var on: Dictionary = results["true|%s" % key]
		print("CELL_MERGE trecho=%s desligado=%s ligado=%s" % [key, JSON.stringify(off), JSON.stringify(on)])
		check(on.triangles == off.triangles, "Trecho %s mostra os mesmos triângulos com e sem fusão (%d x %d)" % [key, on.triangles, off.triangles])
		check(on.meshes < off.meshes, "Trecho %s fica com menos malhas" % key)
		check(on.batches > 0 and on.hidden > 0, "Trecho %s tem lotes e fontes escondidas" % key)
		check(on.oversize == 0, "Trecho %s não tem lote maior que a célula" % key)
		check(off.batches == 0 and off.hidden == 0, "Desligado não cria lote no trecho %s" % key)
	check(results["true|(3, 1)"].hoist_visible == results["false|(3, 1)"].hoist_visible, "Guincho do Northstar continua com as próprias malhas")
	print("CELL_MERGE checks=%d falhas=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
