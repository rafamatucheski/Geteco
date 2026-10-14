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

static func schedule(chunk: Node3D) -> void:
	if not (enabled or preload("res://world/chunk_bake/ChunkCellMerge.gd").enabled) or Engine.get_meta("geteco_live_preview_build", false): return
	# EditableRegion aplica WorldUnits após o retorno de NativeRegion._run_build_job.
	# O adiamento preserva esse contrato também quando o trecho é montado de uma vez.
	_finish_deferred.call_deferred(weakref(chunk))

static func _finish_deferred(reference: WeakRef) -> void:
	var chunk := reference.get_ref() as Node3D
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion() or not chunk.is_inside_tree(): return
	# Não ativar a fusão antiga em trechos onde nenhum gerador a agendou.
	if chunk.has_meta(BUILDING_BATCH.PENDING_META): BUILDING_BATCH.finish_chunk(chunk)
	# Fusão geral por célula antes da casca: a casca lê os volumes que sobraram visíveis.
	await preload("res://world/chunk_bake/ChunkCellMerge.gd").finish_chunk_later(chunk)
	if is_instance_valid(reference.get_ref()): finish_chunk(chunk)

static func finish_chunk(chunk: Node3D) -> void:
	if not enabled or chunk.has_meta(FINISHED) or not chunk.has_meta("vegetation_ready_frame"): return
	if Engine.get_meta("geteco_live_preview_build", false): return
	chunk.set_meta(FINISHED, true)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var covered: Array[MeshInstance3D] = []
	var small: Array[MeshInstance3D] = []
	var inverse := chunk.global_transform.affine_inverse()
	for found in chunk.find_children("*", "MeshInstance3D", true, false):
		var source := found as MeshInstance3D
		if not _eligible(source, chunk): continue
		var original := int(source.get_meta(ORIGINAL_SHADOW, source.cast_shadow))
		if original == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: continue
		var size := (source.global_transform * source.get_aabb()).size
		if maxf(size.x, maxf(size.y, size.z)) < 1.5:
			small.append(source)
			continue
		# A caixa local transformada preserva orientação; uma AABB mundial inflaria
		# paredes diagonais. Malhas compostas não viram blocos que tapariam seus vãos.
		var arrays := source.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var triangles: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var transform := inverse * source.global_transform
		var normal_transform := transform.basis.inverse().transposed()
		var offset := vertices.size()
		for point in points: vertices.append(transform * point)
		for normal in source_normals: normals.append((normal_transform * normal).normalized())
		if triangles.is_empty():
			for index in points.size(): triangles.append(index)
		for triangle in range(0, triangles.size(), 3):
			indices.append(offset + triangles[triangle])
			# A escala negativa deixa de estar no nó ao assar a transformação.
			indices.append(offset + triangles[triangle + (2 if transform.basis.determinant() < 0.0 else 1)])
			indices.append(offset + triangles[triangle + (1 if transform.basis.determinant() < 0.0 else 2)])
		covered.append(source)
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
