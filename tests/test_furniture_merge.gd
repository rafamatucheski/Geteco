extends SceneTree
## Edição antes do lote, peças protegidas e recuperação das fontes no cache.
const TERRACE := preload("res://world/urban_detail/HarborRestaurantTerrace3D.gd")
const PROP := preload("res://world/urban_detail/HarborProp3D.gd")
const REALM := preload("res://world/urban_detail/HarborPublicRealm3D.gd")
const BATCH := preload("res://world/urban_detail/HarborPropInstancing.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func terrace(chunk: Node3D, index: int, position: Vector3) -> Node3D:
	var node := TERRACE.new()
	node.configure("anchor", index, Color("b96a46"))
	node.position = position
	chunk.add_child(node)
	return node

func tree(chunk: Node3D, position: Vector3) -> Node3D:
	var node := PROP.new()
	node.configure(PROP._tree_record(Vector2(1465, 865), 1, 1.25, "446b53", "fixture"))
	node.position = position
	chunk.add_child(node)
	return node

func visible_surfaces(holder: Node3D) -> int:
	var count := 0
	for visual in holder.find_children("*", "GeometryInstance3D", true, false):
		if not visual.is_visible_in_tree() or visual.is_queued_for_deletion(): continue
		if visual is MeshInstance3D and visual.mesh != null: count += visual.mesh.get_surface_count()
		elif visual is MultiMeshInstance3D and visual.multimesh != null: count += visual.multimesh.mesh.get_surface_count()
	return count

func ready_frames() -> void:
	for frame in 4: await process_frame

func run() -> void:
	var chunk := Node3D.new()
	chunk.name = "Chunk_0_1"
	root.add_child(chunk)
	var table := terrace(chunk, 0, Vector3(15, 0, 80))
	var second := terrace(chunk, 1, Vector3(20, 0, 80))
	var removed_table := terrace(chunk, 2, Vector3(25, 0, 80))
	removed_table.free()
	var plant := tree(chunk, Vector3(30, 0, 80))
	var other_plant := tree(chunk, Vector3(40, 0, 80))
	var removed_plant := tree(chunk, Vector3(50, 0, 80))
	removed_plant.free()
	var courtyard := REALM.new()
	courtyard.zone_id = "foundry_courtyard"
	courtyard.position = Vector3(45, 0, 70)
	chunk.add_child(courtyard)
	# Mesma sequência do editor: transformar/excluir fontes antes da finalização.
	table.position += Vector3(2, 0, 3)
	table.rotation.y = 0.3
	plant.position += Vector3(3, 0, 4)
	plant.scale *= 1.1
	var protected_table := terrace(chunk, 3, Vector3(220, 0, 70))
	var fragile_table := terrace(chunk, 4, Vector3(60, 0, 80))
	fragile_table.set_meta("street_fragile_registered", true)
	var sources: Array[Dictionary] = []
	var shapes: Array[Dictionary] = []
	for source: MeshInstance3D in chunk.find_children("*", "MeshInstance3D", true, false):
		sources.append({"node": source, "id": source.get_instance_id(), "parent": source.get_parent(), "name": source.name, "transform": source.transform})
	for shape: CollisionShape3D in chunk.find_children("*", "CollisionShape3D", true, false):
		shapes.append({"node": shape, "id": shape.get_instance_id(), "transform": shape.transform, "shape": shape.shape})
	var before := visible_surfaces(chunk)
	await process_frame
	check(visible_surfaces(chunk) == before, "Geometria alterada antes das edições terminarem")
	chunk.set_meta("vegetation_ready_frame", 0)
	await ready_frames()
	var after := visible_surfaces(chunk)
	for entry in sources:
		check(is_instance_valid(entry.node) and entry.node.get_instance_id() == entry.id, "Fonte editável removida")
		if is_instance_valid(entry.node):
			check(entry.node.name == entry.name and entry.node.get_parent() == entry.parent and entry.node.transform == entry.transform, "Fonte editável mudou identidade ou transformação")
	for entry in shapes:
		check(is_instance_valid(entry.node) and entry.node.get_instance_id() == entry.id and entry.node.transform == entry.transform and entry.node.shape == entry.shape, "Colisão da mobília/árvore mudou")
	check(table.get_node("Parasol").get_child_count() == 8, "Painéis autorados do guarda-sol foram removidos")
	check(table.find_children("*", "CollisionShape3D", true, false).size() == 3, "Mesa perdeu suas três caixas exatas")
	for source in table.find_children("Glass*", "MeshInstance3D", true, false): check(source.visible, "Vidro da mesa foi fundido")
	for source in table.find_children("*", "MeshInstance3D", true, false):
		if source.get_meta("furniture_protected", false): check(source.visible, "Copo com nome automático foi fundido")
	check(visible_surfaces(protected_table) == 52 and visible_surfaces(fragile_table) == 52, "Túnel ou quebrável foram fundidos")
	if BATCH.furniture_enabled:
		check(after < before, "Lotes não reduziram superfícies")
		check(not chunk.find_children("FurnitureTreeBatch_*", "MultiMeshInstance3D", false, false).is_empty(), "Árvores não foram instanciadas")
		# A lista CPU é autoritativa também no renderizador dummy da prévia.
		var tree_state: Dictionary = plant.get_meta(BATCH.FURNITURE_STATE)
		for part in tree_state.tree_parts:
			var source: MeshInstance3D = part.source.get_ref()
			var batch: MultiMeshInstance3D = part.batch.get_ref()
			var poses: Array = batch.get_meta("furniture_tree_transforms")
			check((chunk.global_transform * poses[part.index]).is_equal_approx(source.global_transform), "Instância ignorou a edição da árvore")
	else: check(after == before, "Interruptor desligado alterou o caminho original")
	# Cache real de publicrealm conserva a raiz; retirada restaura fontes e reentrada refaz lotes.
	var courtyard_id := courtyard.get_instance_id()
	var courtyard_surfaces := visible_surfaces(courtyard)
	for cycle in 2:
		chunk.remove_child(courtyard)
		await ready_frames()
		chunk.add_child(courtyard)
		await ready_frames()
		check(courtyard.get_instance_id() == courtyard_id and visible_surfaces(courtyard) == courtyard_surfaces, "Reentrada do cache perdeu/duplicou mobília")
		chunk.remove_child(plant)
		await ready_frames()
		chunk.add_child(plant)
		await ready_frames()
		check(visible_surfaces(chunk) == after, "Reentrada perdeu/duplicou árvore ou mobília")
	plant.position.x += 2.0
	await ready_frames()
	for source in plant.find_children("*", "MeshInstance3D", true, false): check(source.visible, "Árvore movida depois do lote não recuperou fontes")
	# Uma vaga vazia a leste não pode estender o AABB até (0,0,0), cruzando o tubo.
	var east_chunk := Node3D.new()
	east_chunk.name = "Chunk_6_1"
	root.add_child(east_chunk)
	east_chunk.set_meta("vegetation_ready_frame", 0)
	var east_a := tree(east_chunk, Vector3(410, 0, 80))
	var east_b := tree(east_chunk, Vector3(420, 0, 80))
	await ready_frames()
	east_chunk.remove_child(east_a)
	await ready_frames()
	if BATCH.furniture_enabled:
		var tested := 0
		for batch: MultiMeshInstance3D in east_chunk.find_children("FurnitureTreeBatch_*", "MultiMeshInstance3D", false, false):
			if not batch.visible: continue
			var poses: Array = batch.get_meta("furniture_tree_transforms")
			# Inclui slots zerados no envelope, como o AABB automático do MultiMesh.
			var bounds: AABB = poses[0] * batch.multimesh.mesh.get_aabb()
			for pose: Transform3D in poses: bounds = bounds.merge(pose * batch.multimesh.mesh.get_aabb())
			check(BATCH._outside_furniture_cut(east_chunk.global_transform * bounds), "Retirada de árvore expandiu lote para o corredor do túnel")
			tested += 1
		check(tested > 0 and is_instance_valid(east_b), "Fixture leste não manteve árvore visível")
	east_chunk.remove_child(east_b)
	await ready_frames()
	var relocated := tree(east_chunk, Vector3(300, 0, 150))
	await ready_frames()
	if BATCH.furniture_enabled:
		var reused := 0
		for batch: MultiMeshInstance3D in east_chunk.find_children("FurnitureTreeBatch_*", "MultiMeshInstance3D", false, false):
			if not batch.visible: continue
			var poses: Array = batch.get_meta("furniture_tree_transforms")
			var bounds: AABB = poses[0] * batch.multimesh.mesh.get_aabb()
			for pose: Transform3D in poses: bounds = bounds.merge(pose * batch.multimesh.mesh.get_aabb())
			check(poses.size() == 1, "Lote totalmente vazio conservou vagas de proprietários antigos")
			check(BATCH._outside_furniture_cut(east_chunk.global_transform * bounds), "Novo local herdou AABB de árvore retirada")
			reused += 1
		check(reused > 0 and is_instance_valid(relocated), "Fixture não reutilizou lote vazio em outro local")
	east_a.free()
	east_b.free()
	east_chunk.free()
	# A prévia mantém fontes para arrastar sem reconstruir o mundo.
	Engine.set_meta("geteco_live_preview_build", true)
	var preview_table := terrace(chunk, 6, Vector3(5, 0, 70))
	var preview_tree := tree(chunk, Vector3(5, 0, 80))
	await ready_frames()
	check(visible_surfaces(preview_table) == 52 and not preview_tree.has_meta(BATCH.FURNITURE_STATE), "Prévia criou lote antes de editar")
	Engine.remove_meta("geteco_live_preview_build")
	print("FURNITURE_MERGE antes=", before, " depois=", after, " mesa=", visible_surfaces(table), " segunda=", visible_surfaces(second))
	chunk.free()
	await process_frame
	for failure in failures: push_error(failure)
	print("FURNITURE_MERGE ", "OK" if failures.is_empty() else "FALHOU", " falhas=", failures.size())
	quit(0 if failures.is_empty() else 1)
