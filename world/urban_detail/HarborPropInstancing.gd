extends RefCounted
## Comparação reversível: 0 mantém as malhas e sombras originais.

static var enabled := OS.get_environment("GETECO_PROP_INSTANCING") != "0"
static var furniture_enabled := OS.get_environment("GETECO_FURNITURE_MERGE") != "0"
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const FURNITURE_STATE := &"furniture_batch_state"

## Só registra fontes existentes; a identidade continua vindo da montagem original.
static func schedule_furniture(owner: Node3D, tree := false) -> void:
	if not furniture_enabled or Engine.get_meta("geteco_live_preview_build", false): return
	var chunk := owner.get_parent()
	while chunk != null and not str(chunk.name).begins_with("Chunk_"): chunk = chunk.get_parent()
	if chunk == null: return
	var sources: Array[WeakRef] = []
	for source in owner.find_children("*", "MeshInstance3D", true, false):
		if not source.has_meta("furniture_batch_visual"): sources.append(weakref(source))
	_wait_furniture.call_deferred({"owner": weakref(owner), "chunk": weakref(chunk), "sources": sources, "tree": tree})

static func _wait_furniture(job: Dictionary) -> void:
	while true:
		var owner := job.owner.get_ref() as Node3D
		var chunk := job.chunk.get_ref() as Node3D
		if not is_instance_valid(owner) or not is_instance_valid(chunk): return
		if not owner.is_inside_tree() or owner.is_queued_for_deletion() or chunk.is_queued_for_deletion(): return
		if chunk.has_meta("vegetation_ready_frame"): break
		await owner.get_tree().process_frame
	# O retorno de EditableRegion aplica as edições antes desta chamada adiada.
	_finish_furniture.call_deferred(job)

static func _finish_furniture(job: Dictionary) -> void:
	var owner := job.owner.get_ref() as Node3D
	var chunk := job.chunk.get_ref() as Node3D
	if not is_instance_valid(owner) or not is_instance_valid(chunk): return
	if not owner.is_inside_tree() or owner.is_queued_for_deletion() or owner.has_meta(FURNITURE_STATE): return
	if not chunk.is_ancestor_of(owner) or Engine.get_meta("geteco_live_preview_build", false): return
	var groups := {}
	var originals: Array[Dictionary] = []
	var tree_parts: Array[Dictionary] = []
	var batches: Array[WeakRef] = []
	for reference in job.sources:
		var source := reference.get_ref() as MeshInstance3D
		if not is_instance_valid(source) or not _furniture_eligible(source, owner, chunk): continue
		var shadow := source.cast_shadow
		if not job.tree and _small_furniture(source, owner): shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if job.tree:
			var part := _append_tree_part(chunk, source)
			if part.is_empty(): continue
			part["source"] = weakref(source)
			part["shadow"] = source.cast_shadow
			tree_parts.append(part)
			source.visible = false
			continue
		originals.append({"source": weakref(source), "shadow": source.cast_shadow})
		source.cast_shadow = shadow
		var key := "%d|%d|%d|%d|%s" % [source.get_active_material(0).get_instance_id(), shadow, source.layers, source.gi_mode, source.extra_cull_margin]
		if not groups.has(key): groups[key] = []
		groups[key].append(source)
	for entries in groups.values():
		if entries.size() < 2: continue
		var bounds: AABB = entries[0].global_transform * entries[0].get_aabb()
		for source: MeshInstance3D in entries: bounds = bounds.merge(source.global_transform * source.get_aabb())
		if not _outside_furniture_cut(bounds): continue
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for source: MeshInstance3D in entries:
			surface.append_from(source.mesh, 0, owner.global_transform.affine_inverse() * source.global_transform)
		var mesh := surface.commit()
		if mesh == null: continue
		var first: MeshInstance3D = entries[0]
		var batch := MeshInstance3D.new()
		batch.name = "FurnitureStaticBatch_%d" % batches.size()
		batch.mesh = mesh
		batch.material_override = first.get_active_material(0)
		batch.cast_shadow = first.cast_shadow
		batch.layers = first.layers
		batch.gi_mode = first.gi_mode
		batch.extra_cull_margin = first.extra_cull_margin
		batch.set_meta("world_unit_skip", true)
		batch.set_meta("furniture_batch_visual", true)
		owner.add_child(batch)
		batches.append(weakref(batch))
		for source: MeshInstance3D in entries: source.visible = false
	owner.set_meta(FURNITURE_STATE, {"originals": originals, "batches": batches, "tree_parts": tree_parts})
	if not tree_parts.is_empty(): owner.furniture_tree_ready()

static func _furniture_eligible(source: MeshInstance3D, owner: Node3D, chunk: Node3D) -> bool:
	if not source.is_visible_in_tree() or source.is_queued_for_deletion() or source.mesh == null: return false
	if source.mesh.get_surface_count() != 1 or source.skin != null or source.material_overlay != null: return false
	if source.transparency != 0.0 or source.visibility_range_begin != 0.0 or source.visibility_range_end != 0.0: return false
	if source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: return false
	if source.get_script() != null or source.global_basis.determinant() <= 0.0: return false
	if source.get_meta("furniture_protected", false): return false
	var material := source.get_active_material(0) as StandardMaterial3D
	if material == null or material.emission_enabled or material.next_pass != null: return false
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: return false
	if not owner.is_ancestor_of(source): return false
	var current: Node = source
	while current != null and current != chunk:
		if current is CharacterBody3D or current is RigidBody3D or current is AnimatableBody3D: return false
		if current != owner and current.get_script() != null: return false
		if current.has_meta("street_fragile_registered"):
			# Uma árvore restaura as próprias partes de MultiMesh no primeiro transform de impacto.
			var fragile: Dictionary = current.get_meta("street_fragile_item",{})
			if current != owner or fragile.get("kind","") != "harbor_tree": return false
		if not str(current.get_meta("place_id", "")).is_empty(): return false
		for group in ["exterior_reveal_building", "v2_walkin_facade", "harbor_building_facade", "canal_tunnel"]:
			if current.is_in_group(group): return false
		var label := str(current.name).to_lower()
		for protected in ["door", "glass", "sign", "neon", "lamp", "light", "loot", "fragile"]:
			if label.contains(protected): return false
		current = current.get_parent()
	return current == chunk and _outside_furniture_cut(source.global_transform * source.get_aabb())

static func _small_furniture(source: MeshInstance3D, owner: Node3D) -> bool:
	var current := source.get_parent()
	while current != null and current != owner:
		# Painéis pequenos formam um guarda-sol grande que precisa continuar sombreando.
		if str(current.name) == "Parasol": return false
		current = current.get_parent()
	var size := (source.global_transform * source.get_aabb()).size
	return maxf(size.x, maxf(size.y, size.z)) < 1.5

static func _outside_furniture_cut(bounds: AABB) -> bool:
	var corridor := AABB(Vector3(TUNNEL.W_STUB - 46.0, -8.0, TUNNEL.outer_north() - 46.0),
		Vector3(TUNNEL.E_STUB - TUNNEL.W_STUB + 92.0, 54.0, TUNNEL.outer_south() - TUNNEL.outer_north() + 92.0))
	return not corridor.intersects(bounds)

static func _append_tree_part(chunk: Node3D, source: MeshInstance3D) -> Dictionary:
	var key := "%s|%d|%d|%d|%d|%s" % [_mesh_key(source.mesh), source.get_active_material(0).get_instance_id(), source.cast_shadow, source.layers, source.gi_mode, source.extra_cull_margin]
	var label := "FurnitureTreeBatch_" + key.sha256_text().substr(0, 16)
	var batch := chunk.get_node_or_null(NodePath(label)) as MultiMeshInstance3D
	var transforms: Array[Transform3D] = []
	var placement := chunk.global_transform.affine_inverse() * source.global_transform
	var bounds := source.global_transform * source.get_aabb()
	if batch != null:
		transforms.assign(batch.get_meta("furniture_tree_transforms"))
		if batch.visible: bounds = bounds.merge(batch.get_meta("furniture_tree_bounds"))
		else:
			# Sem proprietários ativos, as vagas antigas não podem expandir a caixa
			# de uma nova árvore para posições de uma visita anterior.
			transforms.clear()
	if not _outside_furniture_cut(bounds): return {}
	# Retornos do cache reutilizam vagas, sem acumular instâncias invisíveis.
	var slot := transforms.size()
	for index in transforms.size():
		if is_zero_approx(transforms[index].basis.determinant()):
			slot = index
			break
	if slot == transforms.size(): transforms.append(placement)
	else: transforms[slot] = placement
	if batch == null:
		batch = create_batch(label, source.mesh, source.get_active_material(0), transforms, true)
		batch.cast_shadow = source.cast_shadow
		batch.layers = source.layers
		batch.gi_mode = source.gi_mode
		batch.extra_cull_margin = source.extra_cull_margin
		batch.set_meta("world_unit_skip", true)
		chunk.add_child(batch)
	else:
		batch.multimesh = _multimesh(batch.multimesh.mesh, transforms)
		batch.visible = true
	batch.set_meta("furniture_tree_transforms", transforms)
	batch.set_meta("furniture_tree_bounds", bounds)
	return {"batch": weakref(batch), "index": slot}

## Recuperação pontual: cache/reparentamento nunca conserva fontes ocultas sem lote.
static func restore_furniture(owner: Node3D) -> void:
	if not owner.has_meta(FURNITURE_STATE): return
	var state: Dictionary = owner.get_meta(FURNITURE_STATE)
	owner.remove_meta(FURNITURE_STATE)
	for entry in state.originals:
		var source := entry.source.get_ref() as MeshInstance3D
		if is_instance_valid(source):
			source.visible = true
			source.cast_shadow = entry.shadow
	for reference in state.batches:
		var batch := reference.get_ref() as MeshInstance3D
		if is_instance_valid(batch):
			batch.visible = false
			batch.queue_free()
	for part in state.tree_parts:
		var source := part.source.get_ref() as MeshInstance3D
		if is_instance_valid(source):
			source.visible = true
			source.cast_shadow = part.shadow
		var batch := part.batch.get_ref() as MultiMeshInstance3D
		if not is_instance_valid(batch): continue
		var transforms: Array[Transform3D] = []
		transforms.assign(batch.get_meta("furniture_tree_transforms"))
		# Escala zero oculta a instância; manter seu ponto evita que o AABB do
		# MultiMesh alcance a origem do mundo e passe a interceptar o túnel.
		var removed_pose: Transform3D = transforms[part.index]
		transforms[part.index] = Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), removed_pose.origin)
		batch.multimesh = _multimesh(batch.multimesh.mesh, transforms)
		batch.set_meta("furniture_tree_transforms", transforms)
		batch.visible = transforms.any(func(pose: Transform3D) -> bool: return not is_zero_approx(pose.basis.determinant()))

## Lotes pertencem ao chunk; referências fracas não mantêm chunks descarregados vivos.
static func append_lamp_part(parent: Node3D, item: MeshInstance3D, material: Material) -> Dictionary:
	var label := "Instanced" + String(item.name)
	var batch := parent.get_node_or_null(NodePath(label)) as MultiMeshInstance3D
	var transforms: Array[Transform3D] = []
	if batch != null:
		transforms.assign(batch.get_meta("lamp_transforms"))
	var placement := parent.global_transform.affine_inverse() * item.global_transform
	transforms.append(placement)
	if batch == null:
		batch = create_batch(label, item.mesh, material, transforms, item.name == &"StreetLampPost")
		parent.add_child(batch)
	else:
		# Redimensionar um buffer já anexado pode zerar poses antes da sincronização.
		# A cópia CPU é autoritativa e o novo recurso só entra depois de preenchido.
		batch.multimesh = _multimesh(batch.multimesh.mesh, transforms)
	batch.set_meta("lamp_transforms", transforms)
	return {"batch": weakref(batch), "index": transforms.size() - 1, "transform": placement}

static func set_lamp_part_visible(part: Dictionary, visible: bool) -> void:
	var batch = part.batch.get_ref()
	if not is_instance_valid(batch): return
	var placement: Transform3D = part.transform if visible else Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO)
	var transforms: Array[Transform3D] = []
	transforms.assign(batch.get_meta("lamp_transforms"))
	transforms[part.index] = placement
	batch.set_meta("lamp_transforms", transforms)
	# A troca é pontual (ocultar, mover ou atingir o poste), nunca por quadro.
	# Também evita um quadro duplicado entre o lote e as peças restauradas.
	batch.multimesh = _multimesh(batch.multimesh.mesh, transforms)

## Cada lote fica no mesmo dono das peças: tampas e escadas continuam animáveis.
static func batch_children(parent: Node3D) -> void:
	if not enabled: return
	var groups := {}
	for child in parent.get_children():
		if not child is MeshInstance3D: continue
		var item := child as MeshInstance3D
		# Paredes do poço carregam colisores e conservam sombra para vedar a abertura.
		if item.get_child_count() != 0 or item.mesh == null: continue
		item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var key := _mesh_key(item.mesh) + ":" + str(item.material_override.get_instance_id() if item.material_override != null else 0)
		if not groups.has(key): groups[key] = []
		groups[key].append(item)
	for key in groups:
		var items: Array = groups[key]
		if items.size() < 2: continue
		var first := items[0] as MeshInstance3D
		var transforms: Array[Transform3D] = []
		for item in items: transforms.append(item.transform)
		var batch := create_batch(String(first.name) + "Instances", first.mesh, first.material_override, transforms, false)
		parent.add_child(batch)
		for item in items:
			parent.remove_child(item)
			item.free()

static func create_batch(label: String, mesh: Mesh, material: Material, transforms: Array[Transform3D], shadows: bool) -> MultiMeshInstance3D:
	var result := MultiMeshInstance3D.new()
	result.name = label
	result.multimesh = _multimesh(mesh, transforms)
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return result

static func _multimesh(mesh: Mesh, transforms: Array[Transform3D]) -> MultiMesh:
	var data := MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.mesh = mesh
	data.instance_count = transforms.size()
	for index in transforms.size(): data.set_instance_transform(index, transforms[index])
	return data

static func _mesh_key(mesh: Mesh) -> String:
	if mesh is BoxMesh: return "box:" + str(mesh.size)
	if mesh is CylinderMesh:
		return "cylinder:%s:%s:%s:%s:%s:%s:%s" % [mesh.top_radius, mesh.bottom_radius, mesh.height, mesh.radial_segments, mesh.rings, mesh.cap_top, mesh.cap_bottom]
	return str(mesh.get_instance_id())
