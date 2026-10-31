extends RefCounted
## Subconjunto em cache, só de captura, de um MultiMesh de lados mistos. Monta uma vez por fonte
## e plano escolhido; o dono o invalida quando essa fonte/plano muda.
## Anexa o nó devolvido DIRETAMENTE sob a fonte com transform identidade:
## source.add_child(proxy). Transform e visibilidade da fonte continuam herdados.
## O dono compartilhado do reflexo exclui captureLayer das câmeras do jogo e
## pula nós com metadado coastal_reflection_proxy durante o registro.
const PLANE_TOLERANCE := .08

static func build(source: MultiMeshInstance3D, plane_normal: Vector3, plane_point: Vector3, capture_layer: int) -> MultiMeshInstance3D:
	if not is_instance_valid(source) or source.multimesh == null: return null
	var original := source.multimesh
	if original.mesh == null or original.transform_format != MultiMesh.TRANSFORM_3D: return null
	if capture_layer == 0 or plane_normal.length_squared() < .000001: return null
	var count := original.instance_count
	if original.visible_instance_count >= 0: count = mini(count, original.visible_instance_count)
	if count == 0: return null
	var normal := plane_normal.normalized()
	var selected: Array[int] = []
	var mesh_bounds := original.mesh.get_aabb()
	for index in count:
		var transform := source.global_transform * original.get_instance_transform(index)
		var entirely_in_front := true
		# Testa direto os cantos transformados da malha, evitando os cantos vazios
		# extras de uma caixa alinhada aos eixos do mundo em volta de um prop girado.
		for corner in 8:
			if normal.dot(transform * mesh_bounds.get_endpoint(corner) - plane_point) < -PLANE_TOLERANCE:
				entirely_in_front = false
				break
		if entirely_in_front: selected.append(index)
	if selected.is_empty(): return null
	var subset := MultiMesh.new()
	subset.transform_format = MultiMesh.TRANSFORM_3D
	subset.use_colors = original.use_colors
	subset.use_custom_data = original.use_custom_data
	subset.mesh = original.mesh
	subset.instance_count = selected.size()
	for target in selected.size():
		var index := selected[target]
		subset.set_instance_transform(target, original.get_instance_transform(index))
		if original.use_colors: subset.set_instance_color(target, original.get_instance_color(index))
		if original.use_custom_data: subset.set_instance_custom_data(target, original.get_instance_custom_data(index))
	var proxy := MultiMeshInstance3D.new()
	proxy.name = "CoastalFacadeBatch"
	# Os getters da fonte dão a pose exibida; não interpola de novo.
	proxy.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	proxy.multimesh = subset
	proxy.material_override = source.material_override
	proxy.material_overlay = source.material_overlay
	proxy.layers = capture_layer
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy.set_meta("coastal_reflection_proxy", true)
	proxy.set_meta("coastal_reflection_source", weakref(source))
	proxy.set_meta("coastal_reflection_source_indices", selected)
	_snapshot(source, proxy)
	proxy.set_process(false)
	proxy.set_physics_process(false)
	return proxy

## Só consulta subconjuntos de reflexo existentes. Os getters de buffer e de instância
## expõem o cache renderizado quando a interpolação de física da fonte está ligada,
## não o estado de física pendente. build() lê primeiro os transforms das instâncias,
## deixando o cache de CPU do RD local; compara esse cache nativamente entre capturas.
static func sync(source: MultiMeshInstance3D, proxy: MultiMeshInstance3D, normal: Vector3, point: Vector3) -> bool:
	var original := source.multimesh
	if original == null:
		proxy.visible = false
		proxy.set_meta("coastal_source_resource", null)
		return false
	var buffer := original.buffer
	if proxy.get_meta("coastal_source_resource", null) == original \
		and proxy.get_meta("coastal_source_buffer", PackedFloat32Array()) == buffer \
		and int(proxy.get_meta("coastal_source_visible_count", -2)) == original.visible_instance_count \
		and proxy.get_meta("coastal_source_transform", Transform3D()) == source.global_transform \
		and proxy.get_meta("coastal_source_mesh", null) == original.mesh:
		return false
	var replacement := build(source, normal, point, proxy.layers)
	proxy.visible = replacement != null
	if replacement != null:
		proxy.multimesh = replacement.multimesh
		proxy.set_meta("coastal_reflection_source_indices", replacement.get_meta("coastal_reflection_source_indices"))
		replacement.free()
	proxy.material_override = source.material_override
	proxy.material_overlay = source.material_overlay
	_snapshot(source, proxy, buffer)
	return true

static func _snapshot(source: MultiMeshInstance3D, proxy: MultiMeshInstance3D, buffer: PackedFloat32Array = PackedFloat32Array()) -> void:
	proxy.set_meta("coastal_source_resource", source.multimesh)
	proxy.set_meta("coastal_source_mesh", source.multimesh.mesh)
	proxy.set_meta("coastal_source_buffer", source.multimesh.buffer if buffer.is_empty() else buffer)
	proxy.set_meta("coastal_source_visible_count", source.multimesh.visible_instance_count)
	proxy.set_meta("coastal_source_transform", source.global_transform)
