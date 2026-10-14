extends SceneTree
## Identidade, edição prévia, colisões e seleção real do corte do túnel na ponte.
const BRIDGE := preload("res://world/urban_detail/HarborBridge3D.gd")
const CUTAWAY := preload("res://world/urban_detail/TunnelCutaway.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func selected(chunk: Node3D) -> Array:
	var cutaway := CUTAWAY.new()
	cutaway._rescan([chunk], Vector3(237, -5.5, 63), Vector3(0, 0.2, -0.98), 100.0, 0)
	var ids: Array = cutaway._pending.keys()
	ids.sort()
	return ids

func run() -> void:
	var chunk := Node3D.new()
	chunk.name = "Chunk_3_0"
	root.add_child(chunk)
	var bridge := BRIDGE.new()
	bridge.position = Vector3(3790.0 / 16.0, 0, 400.0 / 16.0)
	chunk.add_child(bridge)
	# Wrappers simulam peças agrupadas pelo editor; a fonte continua a mesma.
	var beams := bridge.find_children("CrossGirder*", "MeshInstance3D", true, false)
	var moving := RigidBody3D.new()
	moving.freeze = true
	bridge.add_child(moving)
	var moving_beam := beams[1] as MeshInstance3D
	moving_beam.reparent(moving)
	var interaction := Node3D.new()
	var interaction_script := GDScript.new()
	interaction_script.source_code = "extends Node3D\nfunc interact() -> void:\n\tpass\n"
	check(interaction_script.reload() == OK, "Fixture interativa não compilou")
	interaction.set_script(interaction_script)
	bridge.add_child(interaction)
	var interactive_beam := beams[2] as MeshInstance3D
	interactive_beam.reparent(interaction)
	var original: Array[Dictionary] = []
	for source: MeshInstance3D in bridge.find_children("*", "MeshInstance3D", true, false):
		original.append({"node": source, "id": source.get_instance_id(), "name": source.name, "parent": source.get_parent(), "transform": source.transform})
	var physics: Array[Dictionary] = []
	for shape: CollisionShape3D in bridge.find_children("*", "CollisionShape3D", true, false):
		physics.append({"node": shape, "id": shape.get_instance_id(), "transform": shape.transform, "shape": shape.shape, "size": shape.shape.size})
	check(original.size() == 196, "Fixture não montou as 196 fontes da ponte")
	# Edição ocorre antes do marco de conclusão; o lote deve enxergar a posição final.
	var edited := bridge.get_node("CrossGirder") as MeshInstance3D
	edited.position.z += 38.0
	for entry in original:
		if entry.node == edited: entry.transform = edited.transform
	var before_selection := selected(chunk)
	check(not before_selection.is_empty(), "Cenário não exercitou peças da ponte procuradas pelo corte")
	await process_frame
	check(not bridge.has_meta("bridge_merge_finished"), "Fusão ocorreu antes das edições do trecho")
	chunk.set_meta("vegetation_ready_frame", 0)
	for frame in 4: await process_frame
	var visible := 0
	var batches := 0
	for source: MeshInstance3D in bridge.find_children("*", "MeshInstance3D", true, false):
		if source.visible: visible += source.mesh.get_surface_count()
		if str(source.name).begins_with("BridgeStaticBatch_"):
			batches += 1
			check(BRIDGE._outside_tunnel_cut(source.global_transform * source.get_aabb()), "Lote entrou no recorte do túnel")
	check(edited.visible, "Peça movida para cima do túnel foi fundida")
	check(moving_beam.visible and interactive_beam.visible, "Fonte sob wrapper móvel/interativo foi fundida")
	check(selected(chunk) == before_selection, "Fusão alterou quais peças o corte do túnel seleciona")
	for entry in original:
		check(is_instance_valid(entry.node) and entry.node.get_instance_id() == entry.id, "Identidade de fonte perdida")
		if is_instance_valid(entry.node):
			check(entry.node.name == entry.name and entry.node.get_parent() == entry.parent and entry.node.transform == entry.transform, "Fonte renomeada, reordenada ou movida")
	for entry in physics:
		check(is_instance_valid(entry.node) and entry.node.get_instance_id() == entry.id, "Colisor removido")
		if is_instance_valid(entry.node):
			check(entry.node.transform == entry.transform and entry.node.shape == entry.shape and entry.node.shape.size == entry.size, "Caixa de colisão mudou")
	if BRIDGE.merge_enabled:
		check(batches > 0 and visible < 196, "Caminho ligado não reduziu superfícies seguras")
	else:
		check(batches == 0 and visible == 196, "Interruptor desligado não preservou fontes originais")
	print("BRIDGE_MERGE superfícies=", visible, " lotes=", batches, " protegidas_pelo_corte=", before_selection.size())
	chunk.free()
	for failure in failures: push_error(failure)
	print("BRIDGE_MERGE ", "OK" if failures.is_empty() else "FALHOU", " falhas=", failures.size())
	quit(0 if failures.is_empty() else 1)
