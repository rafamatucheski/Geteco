extends SceneTree
## Contratos da casca: fronteiras protegidas, identidade e retorno de registro em cache.
const SHELL := preload("res://world/chunk_shadow/ChunkShadowShell.gd")
const GENERATOR := preload("res://world/urban_detail/UrbanCommercialBuilding.gd")
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _box(parent: Node3D, label: String, size: Vector3, at: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = StandardMaterial3D.new()
	mesh.position = at
	parent.add_child(mesh)
	return mesh

func _chunk() -> Node3D:
	var chunk := Node3D.new()
	root.add_child(chunk)
	chunk.set_meta("vegetation_ready_frame", 0)
	return chunk

func run() -> void:
	var chunk := _chunk()
	# O gerador só identifica o escopo estático; não executamos sua montagem.
	var building := Node3D.new()
	building.process_mode = Node.PROCESS_MODE_DISABLED
	# _ready não roda novamente depois que o nó vazio já entrou na árvore.
	chunk.add_child(building)
	building.set_script(GENERATOR)
	var wall := _box(building, "MainVolume", Vector3(4, 8, 6), Vector3(0, 4, 0))
	wall.rotation.y = 0.4
	var detail := _box(building, "SmallTrim", Vector3.ONE * 0.5, Vector3(0, 9, 0))
	var door := _box(building, "DoorLeaf", Vector3(2, 3, 0.2), Vector3(0, 1.5, 4))
	var glass := _box(building, "WindowGlass", Vector3(2, 3, 0.2), Vector3(2, 4, 4))
	var fragile := _box(building, "BreakableBox", Vector3.ONE * 2.0, Vector3(8, 1, 0))
	fragile.set_meta("street_fragile_registered", true)
	var reveal := Node3D.new()
	reveal.add_to_group("exterior_reveal_building")
	building.add_child(reveal)
	var facade := _box(reveal, "FacadeWall", Vector3(4, 8, 6), Vector3(20, 4, 0))
	var tunnel := _box(building, "TunnelVolume", Vector3(4, 8, 6), Vector3(230, 4, 63))
	var tree := _box(building, "TreeTrunk", Vector3(2, 8, 2), Vector3(-10, 4, 0))
	var original_transform := wall.transform
	var original_count := building.get_child_count()
	var original_id := wall.get_instance_id()
	SHELL.finish_chunk(chunk)
	if not SHELL.enabled:
		_check(chunk.get_node_or_null("ChunkShadowShell") == null, "Interruptor desligado criou casca")
		_check(wall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Interruptor desligado alterou sombra")
	else:
		var shell := chunk.get_node_or_null("ChunkShadowShell") as MeshInstance3D
		_check(shell != null, "Volume seguro não gerou casca")
		if shell != null:
			_check(shell.mesh.get_surface_count() == 1, "Casca não ficou em uma superfície")
			_check(shell.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "Casca ficou visível")
		_check(wall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Volume coberto manteve sombra duplicada")
		_check(detail.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Miúdo seguro manteve sombra")
		for protected in [door, glass, fragile, facade, tunnel, tree]:
			_check(protected.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Peça protegida perdeu sombra: " + str(protected.name))
		_check(wall.transform == original_transform and wall.get_instance_id() == original_id, "Identidade/transformação da fonte mudou")
		_check(building.get_child_count() == original_count, "Fontes foram removidas/reordenadas")
		# Simula o contrato de NativeRegion: o registro sobrevive, a casca não.
		chunk.remove_child(building)
		chunk.free()
		chunk = _chunk()
		chunk.add_child(building)
		SHELL.finish_chunk(chunk)
		_check(chunk.get_node_or_null("ChunkShadowShell") != null, "Registro reaproveitado voltou sem sombra")
	chunk.free()
	for failure in failures: push_error(failure)
	print("CHUNK_SHADOW_SHELL ", "OK" if failures.is_empty() else "FALHOU", " falhas=", failures.size())
	quit(0 if failures.is_empty() else 1)
