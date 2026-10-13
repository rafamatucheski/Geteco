extends RefCounted
## Comparação reversível: 0 mantém as malhas e sombras originais.

static var enabled := OS.get_environment("GETECO_PROP_INSTANCING") != "0"

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
