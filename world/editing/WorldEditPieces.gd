extends RefCounted
## Stable editor groups keep visual geometry and collision under the same transform.
const SHAPE := preload("res://world/editing/WorldPieceShape.gd")

static func is_shape_editable(id: String) -> bool:
	return SHAPE.is_shape_editable(id)

static func shape_info(node: Node3D) -> Dictionary:
	return SHAPE.shape_info(node)

static func mark(node: Node3D, key: String, label: String, locked := false) -> void:
	node.set_meta("world_edit_piece_id",key)
	node.set_meta("world_edit_label",label)
	node.set_meta("world_edit_locked",locked)

## `pivot_override` fixa o pivô (X/Z) quando quem chama o calcula de um jeito que não depende do
## renderizador; sem ele o pivô sai do centro de todas as malhas, MultiMesh incluso.
static func group(parent: Node3D, nodes: Array, key: String, label: String, locked := false, pivot_override := Vector3.INF) -> Node3D:
	var points: Array[Vector3] = []
	for node in nodes: _points(node,points)
	var pivot := parent.global_position
	var base_bounds := AABB(pivot,Vector3.ZERO)
	if not points.is_empty():
		var bounds := AABB(points[0],Vector3.ZERO)
		for point in points: bounds = bounds.expand(point)
		pivot.x = bounds.get_center().x
		pivot.z = bounds.get_center().z
		base_bounds = bounds
	if pivot_override.is_finite():
		pivot = pivot_override
	var result := Node3D.new()
	result.name = "EditorPiece_"+key.replace("/","_")
	parent.add_child(result)
	result.global_position = pivot
	for node in nodes: node.reparent(result,true)
	mark(result,key,label,locked)
	# Posição e caixa de ANTES de qualquer edição: a interface desenha a base e aplica o delta.
	result.set_meta("world_edit_base",{"pivot":[pivot.x,pivot.z],"bounds":base_bounds})
	return result

static func _points(node: Node, points: Array[Vector3]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var bounds: AABB = node.mesh.get_aabb()
		for corner in 8: points.append(node.global_transform*bounds.get_endpoint(corner))
	elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
		var bounds: AABB = node.multimesh.mesh.get_aabb()
		var transforms: Array = node.get_meta("preview_instance_transforms",node.get_meta("editor_transforms",[]))
		var count: int = node.multimesh.instance_count if node.multimesh.visible_instance_count<0 else node.multimesh.visible_instance_count
		for i in count:
			var transform: Transform3D = transforms[i] if i<transforms.size() else node.multimesh.get_instance_transform(i)
			for corner in 8: points.append(node.global_transform*transform*bounds.get_endpoint(corner))
	for child in node.get_children(): _points(child,points)

static func collect(root: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if root is Node3D and root.has_meta("world_edit_piece_id"): result.append(root)
	for child in root.get_children(): result.append_array(collect(child))
	return result

## `ground` (opcional) devolve a altura do chão num ponto XZ: a peça acompanha o relevo ao
## ser movida, preservando a distância que ela tinha do chão original.
static func apply(root: Node, changes: Dictionary, ground := Callable()) -> void:
	for node in collect(root): apply_one(node,changes,ground)

## O cadeado (`world_edit_locked`) só avisa na interface: o usuário pode mexer em tudo.
static func apply_one(node: Node3D, changes: Dictionary, ground := Callable()) -> void:
	if not is_instance_valid(node): return
	var id := "piece/"+str(node.get_meta("world_edit_piece_id"))
	if not changes.has(id): return
	var row: Dictionary = changes[id]
	if row.get("type","") == "piece" and row.get("deleted",false):
		node.free()
		return
	if row.get("type","") != "piece" or not row.get("position") is Array or row.position.size() != 2: return
	if not node.has_meta("world_edit_origin"):
		node.set_meta("world_edit_origin",node.global_transform)
	var origin: Transform3D = node.get_meta("world_edit_origin")
	var transform := origin
	transform.origin.x = float(row.position[0])
	transform.origin.z = float(row.position[1])
	transform.origin.y += float(row.get("lift",0.0))
	if ground.is_valid():
		transform.origin.y += float(ground.call(Vector2(transform.origin.x,transform.origin.z)))-float(ground.call(Vector2(origin.origin.x,origin.origin.z)))
	transform.basis = Basis(Vector3.UP,deg_to_rad(float(row.get("rotation",0.0))))*origin.basis
	SHAPE.apply(node,row,origin,transform)

## Cópias (`piece/clone/...`): duplicam a peça de origem ANTES de ela ser editada, para que a
## cópia parta da forma original, e depois recebem a edição própria. Nascem ao lado da origem,
## no mesmo chunk (a origem precisa estar construída para ser copiada).
static func spawn_clones(group: Node3D, changes: Dictionary, ground := Callable()) -> void:
	var source_id := "piece/"+str(group.get_meta("world_edit_piece_id"))
	var parent := group.get_parent()
	if parent == null or group.has_meta("world_edit_origin"): return
	for id in changes:
		var row: Dictionary = changes[id]
		if str(row.get("clone_of","")) != source_id or row.get("deleted",false): continue
		# Sem scripts, grupos nem sinais: a cópia é cenário puro (um terraço duplicado com script
		# reconstruiria os filhos e se registraria como um segundo terraço funcional).
		var copy := group.duplicate(0) as Node3D
		for key in group.get_meta_list():
			if key not in [&"record_cache_key",&"world_edit_origin",&"world_edit_geometry",&"world_edit_shape_info"]: copy.set_meta(key,group.get_meta(key))
		copy.set_meta("world_edit_piece_id",str(id).trim_prefix("piece/"))
		copy.set_meta("world_edit_label",str(group.get_meta("world_edit_label","Peça"))+" (cópia)")
		copy.remove_meta("world_edit_origin")
		copy.name = "EditorPiece_"+str(id).trim_prefix("piece/").replace("/","_")
		parent.add_child(copy)
		copy.global_transform = group.global_transform
		apply_one(copy,changes,ground)

static func record_key(record: Dictionary) -> String:
	var base := record.duplicate(true)
	for key in ["editor_piece_only","editor_piece_exclude","editor_piece_ids","world_key"]: base.erase(key)
	return JSON.stringify(base).sha256_text()

static func prepare(region: Node3D, changes: Dictionary) -> void:
	var sources := {}
	for cell in region.records:
		for record in region.records[cell]:
			sources[record_key(record)] = {"cell":cell,"record":record}
	var additions := {}
	for id in changes:
		var row: Dictionary = changes[id]
		if row.get("type","") != "piece": continue
		if str(id).begins_with("piece/clone/"):
			# A cópia nasce junto da origem (spawn_clones): só garante que o registro dela seja agrupado.
			if sources.has(row.get("source_record","")):
				var origin_record: Dictionary = sources[row.source_record].record
				if not origin_record.has("editor_piece_ids"): origin_record.editor_piece_ids = []
				origin_record.editor_piece_ids.append(row.get("clone_of",""))
			continue
		if str(id).begins_with("piece/transit/") or str(id).begins_with("piece/unit/") or str(id).begins_with("piece/pl/"): continue # Built by UrbanTransitPresentation / pelo chunk (WorldUnits, WorldPlacements).
		if not sources.has(row.get("source_record","")):
			push_warning("Editor de mundo: origem da peça não encontrada: "+str(id))
			continue
		var source: Dictionary = sources[row.source_record]
		var record: Dictionary = source.record
		if not record.has("editor_piece_ids"): record.editor_piece_ids = []
		record.editor_piece_ids.append(id)
		if row.get("deleted",false): continue
		var target := Vector2i(floori(float(row.position[0])/64.0),floori(float(row.position[1])/64.0))
		if target == source.cell: continue
		if not record.has("editor_piece_exclude"): record.editor_piece_exclude = []
		record.editor_piece_exclude.append(id)
		var key: String = str(row.source_record)+"/"+str(target)
		if not additions.has(key):
			var clone := record.duplicate(true)
			clone.erase("editor_piece_exclude")
			clone.editor_piece_only = []
			additions[key] = {"cell":target,"record":clone}
		additions[key].record.editor_piece_only.append(id)
	for item in additions.values():
		if not region.records.has(item.cell): region.records[item.cell] = []
		region.records[item.cell].append(item.record)

static func filter_record(root: Node, record: Dictionary) -> void:
	if record.has("editor_piece_only"):
		_prune(root,record.editor_piece_only)
	elif record.has("editor_piece_exclude"):
		for node in collect(root):
			if "piece/"+str(node.get_meta("world_edit_piece_id")) in record.editor_piece_exclude: node.free()

static func _prune(node: Node, ids: Array) -> bool:
	if node.has_meta("world_edit_piece_id") and "piece/"+str(node.get_meta("world_edit_piece_id")) in ids: return true
	var keep := false
	for child in node.get_children():
		if _prune(child,ids): keep = true
		else: child.free()
	return keep
