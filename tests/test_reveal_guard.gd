extends SceneTree
## Contrato dirigido do guard: contexto real, diagnósticos tardios e fronteiras da geometria.
## A redução no mapa é medida separadamente pelo censo com --reveal-guard-census.
const GUARD := preload("res://world/chunk_bake/RevealOptimizationGuard.gd")
const REVEAL := preload("res://scripts/camera/ExteriorReveal.gd")
const MERGE := preload("res://world/chunk_bake/ChunkCellMerge.gd")
const SHELL := preload("res://world/chunk_shadow/ChunkShadowShell.gd")
const GENERATOR := preload("res://world/urban_detail/UrbanCommercialBuilding.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _scope(chunk: Node3D, label: String) -> Node3D:
	var scope := Node3D.new()
	scope.name = label
	chunk.add_child(scope)
	scope.add_to_group(GUARD.REVEAL_GROUP)
	return scope

func _box(scope: Node3D, label: String, at: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.position = at
	var shape := BoxMesh.new()
	shape.size = Vector3(2, 3, 2)
	mesh.mesh = shape
	mesh.material_override = StandardMaterial3D.new()
	scope.add_child(mesh)
	return mesh

func _slice(chunk: Node3D, generation: int):
	var slice := MERGE.Slice.new()
	slice.reference = weakref(chunk)
	slice.reveal_generation = generation
	return slice

func _invalidation_after_commit(reveal: RefCounted) -> void:
	var chunk := Node3D.new()
	root.add_child(chunk)
	chunk.set_meta(MERGE.FINISHED, true)
	var scope := _scope(chunk, "PartialBuilding")
	var source := MeshInstance3D.new()
	source.name = "TwoSurfaces"
	var mesh := ArrayMesh.new()
	var shape := BoxMesh.new()
	shape.size = Vector3(2, 3, 2)
	var first_material := StandardMaterial3D.new()
	first_material.roughness = 0.25
	var second_material := StandardMaterial3D.new()
	second_material.roughness = 0.75
	for surface in 2:
		var arrays := shape.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		arrays[Mesh.ARRAY_VERTEX] = Transform3D(Basis.IDENTITY, Vector3(surface * 2.0, 1.5, 0)) * vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, first_material)
	mesh.surface_set_material(1, second_material)
	source.mesh = mesh
	scope.add_child(source)
	var complete := _box(scope, "SingleSurface", Vector3(6, 1.5, 0))
	complete.material_override = first_material
	var slice = _slice(chunk, GUARD._capture([], [], false))
	slice.budget_usec = 1
	var state := {"seen": false, "partial": false, "frames": 0}
	var invalidate := func() -> void:
		state.frames += 1
		if bool(state.seen): return
		var holder := chunk.get_node_or_null("CellMergeBatches")
		if holder != null and holder.get_child_count() > 0:
			state.seen = true
			state.partial = source.visible and not complete.visible
			reveal.set("enabled", true)
			reveal.set("enabled", false)
		elif int(state.frames) > 120:
			GUARD.state_changed()
	process_frame.connect(invalidate)
	var report: Dictionary = await MERGE._merge_scope(chunk, [scope], false, slice)
	process_frame.disconnect(invalidate)
	_check(bool(state.seen) and bool(state.partial), "Teste não alcançou commit parcial de duas superfícies")
	_check(slice.reveal_aborted and report.sources == 0 and report.batches == 0, "Invalidação após commit não zerou a execução")
	_check(source.visible and complete.visible and not complete.has_meta(MERGE.MERGED_SOURCE), "Rollback deixou fonte oculta ou marcada")
	_check(not chunk.has_meta(MERGE.FINISHED), "Rollback deixou o trecho falsamente concluído")
	var visible_batches := 0
	for batch in chunk.find_children("CellBatch*", "MeshInstance3D", true, false):
		if batch.is_visible_in_tree(): visible_batches += 1
	_check(visible_batches == 0, "Rollback deixou geometria duplicada desenhando")
	chunk.free()

func _cached_shadow_abort() -> void:
	var old_chunk := Node3D.new()
	root.add_child(old_chunk)
	old_chunk.set_meta("vegetation_ready_frame", 0)
	var building := Node3D.new()
	old_chunk.add_child(building)
	building.set_script(GENERATOR)
	var wall := _box(building, "CachedWall", Vector3(0, 1.5, 0))
	(wall.material_override as StandardMaterial3D).uv1_triplanar = true
	var shell_was_enabled: bool = SHELL.enabled
	SHELL.enabled = true
	SHELL.finish_chunk(old_chunk)
	_check(wall.has_meta(SHELL.ORIGINAL_SHADOW) and wall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Fixture não chegou ao estado de casca cacheada")
	MERGE.restore_sources(building)
	old_chunk.remove_child(building)
	old_chunk.free()
	var new_chunk := Node3D.new()
	root.add_child(new_chunk)
	new_chunk.add_child(building)
	new_chunk.set_meta(SHELL.FINISHED, true)
	SHELL._abort_reveal_generation(new_chunk, 0)
	_check(wall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Abort deixou fonte cacheada sem sombra")
	_check(not new_chunk.has_meta(SHELL.FINISHED), "Abort da casca manteve conclusão falsa")
	SHELL.enabled = shell_was_enabled
	new_chunk.free()

func run() -> void:
	var saved_enabled: bool = GUARD.enabled
	_check(saved_enabled == (OS.get_environment("GETECO_REVEAL_GUARD") == "1"), "Gate não é opt-in")
	GUARD.enabled = true
	_check(GUARD._capture([], [], false) < 0, "Estado desconhecido foi tratado como desligado")
	var reveal := REVEAL.new()
	var generation: int = GUARD._capture([], [], false)
	_check(generation >= 0, "Contexto real desligado não permitiu o experimento")
	var other := REVEAL.new()
	other.enabled = true
	_check(GUARD._capture([], [], false) < 0, "Uma segunda câmera com reveal ligado ficou desprotegida")
	_check(not GUARD.still_allowed(generation), "Registro/ativação não invalidou geração anterior")
	other.enabled = false
	generation = GUARD._capture([], [], false)
	reveal.enabled = true
	reveal.enabled = false
	_check(not GUARD.still_allowed(generation), "Liga/desliga entre fatias reutilizou geração antiga")
	var disposable := REVEAL.new()
	generation = GUARD._capture([], [], false)
	disposable = null
	_check(not GUARD.still_allowed(generation), "Descarte da instância real não invalidou a geração")
	_check(GUARD._launch_protected(["--script", "res://tests/measure/measure_exterior_reveal.gd"], [], false), "Diagnóstico sem flag ficou exposto")
	_check(GUARD._launch_protected(["-s", "res://tests/test_exterior_reveal.gd"], [], false), "Alias -s ficou exposto")
	_check(GUARD._launch_protected(["--script=res://tests/test_exterior_reveal.gd"], [], false), "Forma --script= ficou exposta")
	_check(GUARD._launch_protected([], ["--reveal-on"], false), "Ativação tardia por argumento ficou exposta")
	_check(GUARD.capture() < 0, "Execução atual por --script não foi protegida")
	_check(not GUARD.register_census(self), "Outro teste conseguiu se declarar censo")
	_check(not GUARD._launch_protected(["--script", GUARD.CENSUS_SCRIPT], ["--reveal-guard-census"], true), "Censo controlado foi bloqueado")
	_check(GUARD._launch_protected(["--script", GUARD.CENSUS_SCRIPT], ["--reveal-guard-census", "--reveal-on"], true), "Censo permitiu argumento que ativa reveal")
	GUARD.enabled = false
	_check(GUARD._capture([], [], false) < 0, "Gate desligado liberou escopos")
	GUARD.enabled = true

	var chunk := Node3D.new()
	root.add_child(chunk)
	var first := _scope(chunk, "FirstBuilding")
	var second := _scope(chunk, "SecondBuilding")
	var wall_a := _box(first, "WallA", Vector3(0, 1.5, 0))
	var wall_b := _box(second, "WallB", Vector3(4, 1.5, 0))
	var door := _box(first, "DoorLeaf", Vector3(0, 1.5, 3))
	var glow := _box(first, "EmissiveWall", Vector3(0, 1.5, 6))
	(glow.material_override as StandardMaterial3D).emission_enabled = true
	var collision := StaticBody3D.new()
	first.add_child(collision)
	var original_collision_id := collision.get_instance_id()
	var access := _scope(chunk, "AccessibleBuilding")
	var intermediate := Node3D.new()
	access.add_child(intermediate)
	var building_access := Node3D.new()
	building_access.name = "BuildingAccess"
	intermediate.add_child(building_access)
	var access_wall := _box(access, "AccessWall", Vector3(8, 1.5, 0))
	_check(not MERGE._scope_allowed(first), "Gate padrão mudou a fronteira de reveal")
	_check(MERGE._scope_allowed(first, true), "Escopo sem interação continuou excluído")
	_check(not MERGE._scope_allowed(access, true), "Acesso descendente deixou entrar o prédio")
	for group in [&"harbor_building", &"v2_walkin_facade", &"harbor_building_facade", &"canal_tunnel", &"custom_interaction"]:
		first.add_to_group(group)
		_check(not MERGE._scope_allowed(first, true), "Grupo de acesso/interação perdeu proteção: " + str(group))
		first.remove_from_group(group)
	first.set_meta("place_id", "authored_place")
	_check(not MERGE._scope_allowed(first, true), "Lugar autorado perdeu proteção")
	first.remove_meta("place_id")
	first.set_meta("street_fragile_registered", true)
	_check(not MERGE._scope_allowed(first, true), "Escopo quebrável perdeu proteção")
	first.remove_meta("street_fragile_registered")
	# Identifica gerador sem executar _ready; preserva a mesma lista conservadora da casca.
	first.set_script(GENERATOR)
	_check(not SHELL._eligible(wall_a, chunk), "Casca padrão atravessou o reveal")
	_check(SHELL._eligible(wall_a, chunk, true, {}), "Casca não reconheceu volume elegível")
	_check(not SHELL._eligible(door, chunk, true, {}), "Porta entrou na casca")
	_check(not SHELL._eligible(glow, chunk, true, {}), "Emissão entrou na casca")
	wall_a.add_to_group("custom_interaction")
	_check(not SHELL._eligible(wall_a, chunk, true, {}), "Interação descendente entrou na casca")
	wall_a.remove_from_group("custom_interaction")
	first.add_to_group("harbor_building")
	_check(not SHELL._eligible(wall_a, chunk, true, {}), "Prédio acessível entrou na casca")
	first.remove_from_group("harbor_building")
	first.set_script(null)

	# Exercita a coleta/commit reais com geração já invalidada: nenhuma fonte pode sumir.
	generation = GUARD._capture([], [], false)
	reveal.enabled = true
	var stale: Dictionary = await MERGE._merge_scope(chunk, [first, second, access], false, _slice(chunk, generation))
	_check(stale.batches == 0 and wall_a.visible and wall_b.visible, "Fatia invalidada publicou lote")
	reveal.enabled = false
	generation = GUARD._capture([], [], false)
	var merged: Dictionary = await MERGE._merge_scope(chunk, [first, second, access], false, _slice(chunk, generation))
	_check(merged.sources == 2 and merged.batches == 1, "Dois escopos compatíveis não viraram um lote")
	_check(not wall_a.visible and not wall_b.visible, "Fontes fundidas não ficaram ocultas")
	_check(door.visible and glow.visible and access_wall.visible, "Porta, emissão ou acesso sumiu na fusão")
	_check(is_instance_valid(collision) and collision.get_instance_id() == original_collision_id, "Fusão removeu a colisão original")
	_check(first.is_in_group(GUARD.REVEAL_GROUP) and second.is_in_group(GUARD.REVEAL_GROUP), "Fusão removeu grupo usado por outro sistema")
	chunk.free()
	await _invalidation_after_commit(reveal)
	_cached_shadow_abort()
	GUARD.enabled = saved_enabled
	print("TEST_REVEAL_GUARD ", "OK" if failures.is_empty() else "FALHOU", " checks=", checks, " falhas=", failures.size())
	quit(0 if failures.is_empty() else 1)
