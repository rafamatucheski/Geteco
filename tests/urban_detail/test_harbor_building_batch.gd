extends SceneTree
## Contrato da fusão nos chunks reais, incluindo acabamento, recarga e isolamento.
const REGION := preload("res://world/regions/NativeRegion.gd")
const EDITABLE_REGION := preload("res://world/editing/EditableRegion.gd")
const BATCH := preload("res://world/urban_detail/HarborBuildingBatch.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const CUTAWAY := preload("res://world/urban_detail/TunnelCutaway.gd")
var failures: Array[String] = []
var checks := 0
var reduced_chunks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func target_meshes(chunk: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node in chunk.find_children("*", "MeshInstance3D", true, false):
		var owner_node: Node = node
		while owner_node != chunk and owner_node.get_script() == null:
			owner_node = owner_node.get_parent()
		if owner_node.get_script() != null and owner_node.get_script().resource_path in _targets():
			result.append(node)
	return result

func geometry_signature(meshes: Array[MeshInstance3D]) -> Dictionary:
	var signature := {}
	for mesh in meshes:
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			# Malha sem índice (triângulos soltos) também entra na assinatura; antes dava SCRIPT ERROR e ficava de fora.
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var material := mesh.get_active_material(surface)
			var material_id := material.get_instance_id() if material != null else 0
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for index in count:
				var vertex := vertices[indices[index] if not indices.is_empty() else index]
				var point := mesh.global_transform * vertex
				if not signature.has(material_id): signature[material_id] = []
				signature[material_id].append(point)
	return signature

func same_geometry(before: Dictionary, after: Dictionary) -> bool:
	if before.size() != after.size(): return false
	var maximum_error := 0.0
	for material_id in before:
		if not after.has(material_id) or before[material_id].size() != after[material_id].size(): return false
		var buckets := {}
		for point: Vector3 in before[material_id]:
			var cell := Vector3i((point * 1000.0).floor())
			if not buckets.has(cell): buckets[cell] = []
			buckets[cell].append(point)
		for point: Vector3 in after[material_id]:
			var cell := Vector3i((point * 1000.0).floor())
			var matched := false
			for x in range(-1, 2):
				for y in range(-1, 2):
					for z in range(-1, 2):
						if matched: continue
						var nearby := cell + Vector3i(x, y, z)
						if not buckets.has(nearby): continue
						var candidates: Array = buckets[nearby]
						for index in candidates.size():
							var error := point.distance_to(candidates[index])
							# Bake muda a ordem das operações float32; limite de 0,1 mm.
							if error <= .0001:
								maximum_error = maxf(maximum_error, error)
								candidates.remove_at(index)
								matched = true
								break
			if not matched:
				print("VERTICE_SEM_CORRESPONDENCIA material=", material_id, " posição=", point)
				return false
	print("ERRO_MAXIMO_GEOMETRIA metros=", maximum_error)
	return true

## Lojas e prédios baixos/altos entram na fusão junto com GETECO_CELL_MERGE (2026-10-14).
func _targets() -> Array:
	var targets: Array = BATCH.TARGET_SCRIPTS.duplicate()
	if preload("res://world/chunk_bake/ChunkCellMerge.gd").enabled: targets.append_array(BATCH.EXTENDED_TARGET_SCRIPTS)
	return targets

func protected_snapshot(chunk: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var animated := {}
	for owner_node in chunk.find_children("*", "Node3D", true, false):
		var leaves: Array = []
		for property in ["door_leaves", "public_leaves", "police_door_visuals"]:
			if not property in owner_node: continue
			leaves.append_array(owner_node.get(property))
		if "fire_door_visual" in owner_node and is_instance_valid(owner_node.get("fire_door_visual")):
			leaves.append(owner_node.get("fire_door_visual"))
		for leaf: Node3D in leaves:
			animated[leaf.get_instance_id()] = true
			for child in leaf.find_children("*", "Node3D", true, false): animated[child.get_instance_id()] = true
	for node in chunk.find_children("*", "Node3D", true, false):
		var scripted_branch := false
		var ancestor: Node = node
		while ancestor != chunk:
			if ancestor.get_script() != null and not ancestor.get_script().resource_path in _targets():
				scripted_branch = true
				break
			ancestor = ancestor.get_parent()
		# Portas sem nome, luzes, grupos e subárvores com script têm contrato próprio,
		# independente da decisão de elegibilidade do otimizador.
		if animated.has(node.get_instance_id()) or scripted_branch or node is Light3D or not node.get_groups().is_empty() or node.get_script() != null or node is CollisionObject3D or node is CollisionShape3D or (node is MeshInstance3D and not BATCH._eligible(node)):
			var entry := {"node": node, "transform": node.global_transform, "groups": node.get_groups()}
			if node is MeshInstance3D:
				entry.mesh = node.mesh
				entry.material = node.material_override
			result.append(entry)
	return result

func door_motion_snapshot(chunk: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for owner_node in chunk.find_children("*", "Node3D", true, false):
		if "door_leaves" in owner_node:
			result.append(_door_case(owner_node, "set_door_amount", "door_amount", owner_node.get("door_leaves")))
		if "public_leaves" in owner_node:
			result.append(_door_case(owner_node, "set_open_amount", "open_amount", owner_node.get("public_leaves")))
		if "police_door_visuals" in owner_node and not owner_node.get("police_door_visuals").is_empty():
			result.append(_door_case(owner_node, "set_open_amount", "open_amount", owner_node.get("police_door_visuals")))
		if "fire_door_visual" in owner_node and is_instance_valid(owner_node.get("fire_door_visual")):
			result.append(_door_case(owner_node, "set_open_amount", "open_amount", [owner_node.get("fire_door_visual")]))
		if owner_node.get_script() != null and owner_node.get_script().resource_path == "res://world/places/WalkupFacadeDoor.gd":
			result.append(_door_case(owner_node, "set_open_amount", "open_amount", [owner_node.get("hinge")]))
	return result

func _door_case(owner_node: Node3D, method: String, state_property: String, leaves: Array) -> Dictionary:
	var entry := {"owner": owner_node, "method": method, "property": state_property, "state": owner_node.get(state_property), "leaves": leaves.duplicate(), "original": [], "closed": [], "opened": []}
	for leaf: Node3D in leaves: entry.original.append(leaf.transform)
	owner_node.call(method, 0.0)
	for leaf: Node3D in leaves: entry.closed.append(leaf.transform)
	owner_node.call(method, 1.0)
	for leaf: Node3D in leaves: entry.opened.append(leaf.transform)
	owner_node.call(method, entry.state)
	for index in leaves.size(): leaves[index].transform = entry.original[index]
	return entry

func verify_door_motion(cases: Array[Dictionary]) -> void:
	for entry in cases:
		var intact := is_instance_valid(entry.owner)
		for leaf in entry.leaves: intact = intact and is_instance_valid(leaf)
		check(intact, "preserva pivôs e folhas das portas autoradas")
		if not intact: continue
		check(not entry.leaves.is_empty(), "a verificação de movimento inclui folhas reais")
		entry.owner.call(entry.method, 0.0)
		for index in entry.leaves.size():
			check(entry.leaves[index].transform.is_equal_approx(entry.closed[index]), "porta fecha na mesma posição após fusão")
		entry.owner.call(entry.method, 1.0)
		for index in entry.leaves.size():
			check(entry.leaves[index].transform.is_equal_approx(entry.opened[index]), "porta abre na mesma posição após fusão")
			check(not entry.opened[index].is_equal_approx(entry.closed[index]), "folha continua móvel após fusão")
		entry.owner.call(entry.method, entry.state)
		for index in entry.leaves.size(): entry.leaves[index].transform = entry.original[index]

func verify_service_doors() -> void:
	var chunk := Node3D.new()
	root.add_child(chunk)
	for kind in ["police_precinct", "fire_station"]:
		var service := UrbanServiceBuilding.new()
		service.setup({"id": "Police" if kind == "police_precinct" else "NorthFireStation", "kind": kind, "size": Vector2(16, 12)})
		chunk.add_child(service)
	var protected := protected_snapshot(chunk)
	var doors := door_motion_snapshot(chunk)
	# Com a fachada pintada (GETECO_PAINTED_FACADES, ligada por padrão) o quartel
	# (PaintedFireStation) não tem mais a persiana 3D `fire_door_visual`: os portões das viaturas
	# são vãos sem folha e as portas de pedestre (frente e fundos) são folhas do kit
	# (PaintedFacadeKit.PaintedDoor). Elas entram no mesmo exercício de movimento para o quartel
	# continuar coberto; a delegacia pintada já entra por `police_door_visuals`. A contagem
	# exata de 2 casos (um por prédio) valia só para o 3D antigo; o contrato é cada prédio ter folhas.
	for service: UrbanServiceBuilding in chunk.get_children():
		if service.building_kind != "fire_station" or is_instance_valid(service.fire_door_visual): continue
		for leaf in service.find_children("*", "Node3D", true, false):
			if leaf is PaintedFacadeKit.PaintedDoor: doors.append(_door_case(leaf, "set_open_amount", "open_amount", [leaf.hinge]))
	var covered := {}
	for entry in doors:
		for service: UrbanServiceBuilding in chunk.get_children():
			if service == entry.owner or service.is_ancestor_of(entry.owner): covered[service.building_kind] = true
	check(covered.has("police_precinct") and covered.has("fire_station"), "exercita portas da delegacia e do quartel fora dos trechos medidos")
	chunk.set_meta("vegetation_ready_frame", Engine.get_physics_frames())
	BATCH.finish_chunk(chunk)
	for entry in protected:
		check(is_instance_valid(entry.node), "preserva peças individuais das portas de serviço")
		if not is_instance_valid(entry.node): continue
		check(entry.node.global_transform.is_equal_approx(entry.transform), "preserva pose de portas e colisões de serviço")
		if entry.has("mesh"):
			check(entry.node.mesh == entry.mesh, "não funde malhas das folhas móveis de serviço")
	verify_door_motion(doors)
	chunk.free()

func roofs(chunk: Node3D) -> Dictionary:
	var result := {}
	for child in chunk.get_children():
		if child is UrbanBuildingBase:
			result[child.get_instance_id()] = DRESSING._roof_slabs(child)
	return result

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("O contrato exige --no-save.")
		quit(1)
		return
	var original_enabled: bool = BATCH.enabled
	BATCH.enabled = false
	var region = REGION.build_region("harbor", Vector3.INF)
	region.initial_prewarm_only = true
	root.add_child(region)
	while not region.prepared: await process_frame
	for key in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(5, 1), Vector2i(6, 1)]:
		BATCH.enabled = false
		region._build_chunk(key)
		var chunk: Node3D = region.chunks[key]
		await process_frame
		var before := target_meshes(chunk)
		var before_count := before.size()
		var signature := geometry_signature(before)
		var protected := protected_snapshot(chunk)
		var doors := door_motion_snapshot(chunk)
		var roof_snapshot := roofs(chunk)
		BATCH.finish_chunk(chunk)
		check(not chunk.has_meta(BATCH.FINISHED_META), "%s interruptor desliga a fusão" % key)
		var ready_frame: Variant = chunk.get_meta("vegetation_ready_frame")
		chunk.remove_meta("vegetation_ready_frame")
		BATCH.enabled = true
		BATCH.finish_chunk(chunk)
		check(not chunk.has_meta(BATCH.FINISHED_META), "%s aguarda o acabamento" % key)
		chunk.set_meta("vegetation_ready_frame", ready_frame)
		# Metade dos trechos pela versão fatiada do jogo, cedendo o quadro a cada grupo (orçamento de 1 µs):
		# o resultado tem de ser o mesmo da fusão inteira de uma vez.
		if key.x % 2 == 0:
			await BATCH.finish_chunk_sliced(chunk, 1)
			check(chunk.has_meta(BATCH.DONE_META), "%s fusão fatiada termina" % key)
		else:
			BATCH.finish_chunk(chunk)
		var after := target_meshes(chunk)
		check(after.size() <= before_count, "%s não aumenta malhas dos prédios" % key)
		if after.size() < before_count: reduced_chunks += 1
		var after_signature := geometry_signature(after)
		check(same_geometry(signature, after_signature), "%s preserva vértices indexados no mundo e seus materiais" % key)
		check(roofs(chunk) == roof_snapshot, "%s preserva as lajes reconhecidas pelo acabamento" % key)
		for entry in protected:
			check(is_instance_valid(entry.node), "%s preserva nó protegido" % key)
			if not is_instance_valid(entry.node): continue
			check(entry.node.global_transform.is_equal_approx(entry.transform), "%s preserva transformação protegida" % key)
			check(entry.node.get_groups() == entry.groups, "%s preserva grupos de reveal/noite" % key)
			if entry.has("mesh"):
				check(entry.node.mesh == entry.mesh and entry.node.material_override == entry.material, "%s preserva malha e acabamento protegidos" % key)
		verify_door_motion(doors)
		BATCH.finish_chunk(chunk)
		check(target_meshes(chunk).size() == after.size(), "%s fusão idempotente" % key)
		# O corte precisa conseguir restaurar material e sombra também dos lotes novos.
		var cutaway := CUTAWAY.new()
		for mesh in after:
			var material := mesh.material_override
			var shadows := mesh.cast_shadow
			cutaway._fade(mesh)
			cutaway.release()
			check(mesh.material_override == material and mesh.cast_shadow == shadows, "%s corte restaura material e sombra" % key)
		region.chunks.erase(key)
		region._detach_cached_records(chunk)
		chunk.free()
	check(reduced_chunks >= 3, "reduz os três chunks que contêm prédios alvo")
	# Fluxo de produção: construção fatiada, finalização automática e descarregamento.
	BATCH.enabled = true
	region._build_chunk(Vector2i(1, 1), false)
	while not region.is_streaming_idle(): await process_frame
	await process_frame
	await process_frame
	var rebuilt: Node3D = region.chunks[Vector2i(1, 1)]
	# A fusão em jogo é fatiada (2 ms por quadro): espera ela terminar, não um número fixo de quadros.
	for frame in 600:
		if rebuilt.has_meta(BATCH.DONE_META): break
		await process_frame
	check(rebuilt.has_meta(BATCH.DONE_META), "fusão fatiada termina")
	check(rebuilt.has_meta(BATCH.FINISHED_META), "recarga fatiada aplica a fusão automaticamente")
	check(rebuilt.find_child("BuildingBatchFinalizer", true, false) == null, "finalizador não deixa processamento permanente")
	region.free()
	# O adaptador usado pela sessão real herda o gerador e aplica as edições locais.
	var editable = EDITABLE_REGION.build_region("harbor", Vector3.INF)
	editable.initial_prewarm_only = true
	root.add_child(editable)
	while not editable.prepared: await process_frame
	editable._build_chunk(Vector2i(1, 1), false)
	while not editable.is_streaming_idle(): await process_frame
	await process_frame
	await process_frame
	var production_chunk: Node3D = editable.chunks[Vector2i(1, 1)]
	for frame in 600:
		if production_chunk.has_meta(BATCH.DONE_META): break
		await process_frame
	check(production_chunk.has_meta(BATCH.FINISHED_META), "EditableRegion ativa fusão no caminho real do jogo")
	check(production_chunk.find_child("BuildingStaticBatch", true, false) != null, "EditableRegion contém geometria fundida")
	check(production_chunk.find_child("BuildingBatchFinalizer", true, false) == null, "EditableRegion libera finalizador transitório")
	editable.free()
	verify_service_doors()
	BATCH.enabled = original_enabled
	print("CONTRATO_FUSAO_PREDIOS verificações=", checks, " falhas=", failures.size())
	quit(0 if failures.is_empty() else 1)
