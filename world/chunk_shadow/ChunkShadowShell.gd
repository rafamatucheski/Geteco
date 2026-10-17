extends RefCounted
## Casca conservadora: só caixas opacas de geradores estáticos conhecidos.
## Fontes editáveis e colisões sobrevivem; o lote nasce depois das edições do trecho.
const BUILDING_BATCH := preload("res://world/urban_detail/HarborBuildingBatch.gd")
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const ORIGINAL_SHADOW := &"chunk_shell_original_shadow"
const FINISHED := &"chunk_shadow_shell_finished"
const STATIC_GENERATORS := [
	"HarborBridge3D.gd", "HarborPortModel3D.gd", "PortShipDressing3D.gd",
	"OriginalSouthPort.gd", "UrbanCommercialBuilding.gd", "UrbanIndustrialBuilding.gd",
	"UrbanServiceBuilding.gd", "UrbanShopfrontBuilding.gd", "UrbanBrownstoneBuilding.gd",
	"UrbanLowriseBuilding.gd", "UrbanSkylineBuilding.gd", "HarborHospitalModel3D.gd",
	"ResidenceExterior3D.gd", "ResidenceParking.gd",
]
static var enabled := OS.get_environment("GETECO_SHADOW_SHELL") != "0"
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
## Trecho descartado continua na árvore escondido (marca da fila de vídeo): a casca para como a fusão (16/10).
const GPU_RELEASE := preload("res://runtime/GpuReleaseQueue.gd")

static func schedule(chunk: Node3D) -> void:
	if not (enabled or preload("res://world/chunk_bake/ChunkCellMerge.gd").enabled) or Engine.get_meta("geteco_live_preview_build", false): return
	# EditableRegion aplica WorldUnits após o retorno de NativeRegion._run_build_job.
	# O adiamento preserva esse contrato também quando o trecho é montado de uma vez.
	_finish_deferred.call_deferred(weakref(chunk))

static func _finish_deferred(reference: WeakRef) -> void:
	var chunk := reference.get_ref() as Node3D
	if not is_instance_valid(chunk) or GPU_RELEASE.is_retired(chunk) or not chunk.is_inside_tree(): return
	# Não ativar a fusão antiga em trechos onde nenhum gerador a agendou. Fatiada (era um quadro só, 17-60 ms
	# na fase 2 de 16/10) e esperada inteira: a fusão por célula e a casca leem o que ela deixou.
	if chunk.has_meta(BUILDING_BATCH.PENDING_META):
		await BUILDING_BATCH.finish_chunk_sliced(chunk, slice_budget_usec)
		if not is_instance_valid(reference.get_ref()) or not chunk.is_inside_tree() or GPU_RELEASE.is_retired(chunk): return
	# Fusão geral por célula antes da casca: a casca lê os volumes que sobraram visíveis.
	await preload("res://world/chunk_bake/ChunkCellMerge.gd").finish_chunk_later(chunk)
	if is_instance_valid(reference.get_ref()) and not GPU_RELEASE.is_retired(chunk): await _finish(chunk, slice_budget_usec)

## Em jogo a casca é montada em fatias: a varredura de todas as malhas do trecho e o laço por vértice em
## GDScript rodavam num quadro só, sem span no log (travessia de 15/10: quadros de 117-239 ms sem atribuição
## logo depois da fusão do trecho). Testes chamam finish_chunk e montam de uma vez.
static var slice_budget_usec := 2000

static func finish_chunk(chunk: Node3D) -> void:
	_finish(chunk, 0)

static func _finish(chunk: Node3D, budget_usec: int) -> void:
	if not enabled or chunk.has_meta(FINISHED) or not chunk.has_meta("vegetation_ready_frame"): return
	if Engine.get_meta("geteco_live_preview_build", false): return
	chunk.set_meta(FINISHED, true)
	var reference: WeakRef = weakref(chunk)
	var began := STALL_WORK.begin()
	# Relógio do orçamento separado do span: com o rastreio desligado `began` é 0 e cada malha cedia o quadro.
	var budget_began := Time.get_ticks_usec()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var covered: Array[MeshInstance3D] = []
	var small: Array[MeshInstance3D] = []
	var inverse := chunk.global_transform.affine_inverse()
	for found in chunk.find_children("*", "MeshInstance3D", true, false):
		if budget_usec > 0 and Time.get_ticks_usec() - budget_began >= budget_usec:
			STALL_WORK.finish_slow("chunk.shadow_shell", began, 1500)
			await chunk.get_tree().process_frame
			began = STALL_WORK.begin()
			budget_began = Time.get_ticks_usec()
			if not is_instance_valid(reference.get_ref()) or not chunk.is_inside_tree() or GPU_RELEASE.is_retired(chunk): return
		if not is_instance_valid(found): continue
		var source := found as MeshInstance3D
		if not chunk.is_ancestor_of(source) or not _eligible(source, chunk): continue
		var original := int(source.get_meta(ORIGINAL_SHADOW, source.cast_shadow))
		if original == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: continue
		var size := (source.global_transform * source.get_aabb()).size
		if maxf(size.x, maxf(size.y, size.z)) < 1.5:
			small.append(source)
			continue
		# A caixa local transformada preserva orientação; uma AABB mundial inflaria
		# paredes diagonais. Malhas compostas não viram blocos que tapariam seus vãos.
		# Do cache: cada surface_get_arrays espera a GPU terminar (MeshArrayCache), e as caixas se repetem.
		var arrays := MESH_ARRAYS.arrays_of(source.mesh, 0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var triangles: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var transform := inverse * source.global_transform
		var normal_transform := transform.basis.inverse().transposed()
		var offset := vertices.size()
		# Em bloco: a normal vai sem normalized() porque o vértice a grava em octaedro (o tamanho se perde).
		vertices.append_array(transform * points)
		normals.append_array(Transform3D(normal_transform, Vector3.ZERO) * source_normals)
		if triangles.is_empty():
			for index in points.size(): triangles.append(index)
		# A escala negativa deixa de estar no nó ao assar a transformação.
		var flip := transform.basis.determinant() < 0.0
		var start := indices.size()
		indices.resize(start + triangles.size())
		for triangle in range(0, triangles.size(), 3):
			indices[start + triangle] = offset + triangles[triangle]
			indices[start + triangle + 1] = offset + triangles[triangle + (2 if flip else 1)]
			indices[start + triangle + 2] = offset + triangles[triangle + (1 if flip else 2)]
		covered.append(source)
	# Fonte liberada ou levada para outro trecho enquanto a casca era montada: a casca teria a sombra dela.
	# Sem casca neste trecho (as fontes ficam com a sombra própria); só perde a economia.
	for source in covered + small:
		if not is_instance_valid(source) or not chunk.is_ancestor_of(source):
			STALL_WORK.finish_slow("chunk.shadow_shell", began, 1500)
			return
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		var geometry := ArrayMesh.new()
		geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var shell := MeshInstance3D.new()
		shell.name = "ChunkShadowShell"
		shell.mesh = geometry
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		shell.set_meta("world_unit_skip", true)
		# Sem material herdado: a casca não recebe animação noturna nem molhado.
		chunk.add_child(shell)
	for source in covered + small:
		# Registros em cache sobrevivem à casca. O modo original permite reconstruí-la
		# na próxima visita, mesmo quando a fonte já volta com cast_shadow desligado.
		if not source.has_meta(ORIGINAL_SHADOW): source.set_meta(ORIGINAL_SHADOW, source.cast_shadow)
		source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.set_meta("chunk_shadow_shell_counts", {"covered": covered.size(), "small": small.size()})
	STALL_WORK.finish_slow("chunk.shadow_shell", began, 1500)

static func _eligible(source: MeshInstance3D, chunk: Node3D) -> bool:
	if not source.is_visible_in_tree() or source.is_queued_for_deletion(): return false
	if not source.mesh is BoxMesh or source.mesh.get_surface_count() != 1: return false
	if source.skin != null or source.material_overlay != null or source.transparency != 0.0: return false
	if source.visibility_range_begin != 0.0 or source.visibility_range_end != 0.0: return false
	if source.layers != 1 or source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: return false
	var material := source.get_active_material(0) as StandardMaterial3D
	if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return false
	if material.emission_enabled or material.next_pass != null or material.get_meta("city_window", false): return false
	if _near_tunnel(source.global_transform * source.get_aabb()): return false
	var node: Node = source
	var known_generator := false
	while node != chunk and node != null:
		if node is CharacterBody3D or node is RigidBody3D or node is AnimatableBody3D: return false
		if node.has_meta("street_fragile_registered") or not str(node.get_meta("place_id", "")).is_empty(): return false
		for group in ["exterior_reveal_building", "v2_walkin_facade", "harbor_building_facade", "canal_tunnel"]:
			if node.is_in_group(group): return false
		var label := str(node.name).to_lower()
		for protected in ["door", "shutter", "glass", "sign", "nameplate", "neon", "lamp", "light", "tree", "canopy", "trunk", "hoist", "loot", "fragile"]:
			if label.contains(protected): return false
		var script := node.get_script() as Script
		if script != null:
			if script.resource_path.get_file() not in STATIC_GENERATORS: return false
			known_generator = true
		node = node.get_parent()
	return known_generator

static func _near_tunnel(box: AABB) -> bool:
	# TunnelCutaway pode varrer 46 m em qualquer direção da câmera. Excluir o
	# corredor completo evita uma casca única apagar sombras fora da janela ou
	# continuar escurecendo o túnel quando a geometria original fica transparente.
	var corridor := AABB(Vector3(TUNNEL.W_STUB - 46.0, -8.0, TUNNEL.outer_north() - 46.0),
		Vector3(TUNNEL.E_STUB - TUNNEL.W_STUB + 92.0, 54.0, TUNNEL.outer_south() - TUNNEL.outer_north() + 92.0))
	return corridor.intersects(box)
