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

static func group(parent: Node3D, nodes: Array, key: String, label: String, locked := false) -> Node3D:
	var points: Array[Vector3] = []
	for node in nodes: _points(node,points)
	var pivot := parent.global_position
	if not points.is_empty():
		var bounds := AABB(points[0],Vector3.ZERO)
		for point in points: bounds = bounds.expand(point)
		pivot.x = bounds.get_center().x
		pivot.z = bounds.get_center().z
	var result := Node3D.new()
	result.name = "EditorPiece_"+key.replace("/","_")
	parent.add_child(result)
	result.global_position = pivot
	for node in nodes: node.reparent(result,true)
	mark(result,key,label,locked)
	return result

static func _points(node: Node, points: Array[Vector3]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var bounds: AABB = node.mesh.get_aabb()
		for corner in 8: points.append(node.global_transform*bounds.get_endpoint(corner))
	for child in node.get_children(): _points(child,points)

static func collect(root: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if root is Node3D and root.has_meta("world_edit_piece_id"): result.append(root)
	for child in root.get_children(): result.append_array(collect(child))
	return result

static func apply(root: Node, changes: Dictionary) -> void:
	for node in collect(root):
		if not is_instance_valid(node): continue
		if node.get_meta("world_edit_locked",false): continue
		var id := "piece/"+str(node.get_meta("world_edit_piece_id"))
		if not changes.has(id): continue
		var row: Dictionary = changes[id]
		if row.get("type","") == "piece" and row.get("deleted",false):
			node.free()
			continue
		if row.get("type","") != "piece" or not row.get("position") is Array or row.position.size() != 2: continue
		if not node.has_meta("world_edit_origin"):
			node.set_meta("world_edit_origin",node.global_transform)
		var origin: Transform3D = node.get_meta("world_edit_origin")
		var transform := origin
		transform.origin.x = float(row.position[0])
		transform.origin.z = float(row.position[1])
		transform.basis = Basis(Vector3.UP,deg_to_rad(float(row.get("rotation",0.0))))*origin.basis
		SHAPE.apply(node,row,origin,transform)

static func record_key(record: Dictionary) -> String:
	var base := record.duplicate(true)
	for key in ["editor_piece_only","editor_piece_exclude","editor_piece_ids"]: base.erase(key)
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
		if str(id).begins_with("piece/transit/"): continue # Built by UrbanTransitPresentation.
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
			if not node.get_meta("world_edit_locked",false) and "piece/"+str(node.get_meta("world_edit_piece_id")) in record.editor_piece_exclude: node.free()

static func _prune(node: Node, ids: Array) -> bool:
	if node.has_meta("world_edit_piece_id") and "piece/"+str(node.get_meta("world_edit_piece_id")) in ids: return not node.get_meta("world_edit_locked",false)
	var keep := false
	for child in node.get_children():
		if _prune(child,ids): keep = true
		else: child.free()
	return keep
