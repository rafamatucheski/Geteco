@tool
extends RefCounted
## Split a passive snapshot without changing its hierarchy, IDs or local transforms.
## Each imported part is small enough to instantiate between editor input frames.
const MAX_PART_NODES := 384

static func clear_owners(node: Node) -> void:
	node.owner = null
	for child in node.get_children(): clear_owners(child)

static func attach(part: Node, parent: Node) -> void:
	# PackedScene descendants still belong to the temporary wrapper. Clear that
	# relationship before moving them; ownership is irrelevant to the live view.
	for child in part.get_children():
		clear_owners(child)
		part.remove_child(child)
		parent.add_child(child)

static func _use(resource: Resource, uses: Dictionary) -> void:
	if resource == null: return
	uses[resource] = int(uses.get(resource,0))+1
	if uses[resource] != 1: return
	if resource is Mesh:
		for index in resource.get_surface_count(): _use(resource.surface_get_material(index),uses)
	elif resource is MultiMesh: _use(resource.mesh,uses)

static func _resources(node: Node, uses: Dictionary) -> void:
	if node is MeshInstance3D:
		_use(node.mesh,uses)
		if node.mesh != null:
			for index in node.mesh.get_surface_count(): _use(node.get_surface_override_material(index),uses)
	elif node is MultiMeshInstance3D: _use(node.multimesh,uses)
	if node is GeometryInstance3D:
		_use(node.material_override,uses)
		_use(node.material_overlay,uses)
	if node is CollisionShape3D: _use(node.shape,uses)
	for child in node.get_children(): _resources(child,uses)

static func _share_resources(snapshot: Node, folder: String, revision: int) -> Error:
	# Generated meshes/materials shared by different parts must stay shared after
	# import. Otherwise splitting a forest would duplicate its GPU resources.
	var uses := {}
	_resources(snapshot,uses)
	var resources: Array = uses.keys()
	resources.sort_custom(func(a,b): return a is Material and not b is Material)
	var index := 0
	for resource in resources:
		var previous_preview := str(resource.resource_path).begins_with(folder+"/view_")
		if not previous_preview and (int(uses[resource]) < 2 or not resource.resource_path.is_empty()): continue
		var path := folder+"/view_%d_asset_%d.res" % [revision,index]
		var result := ResourceSaver.save(resource,path,ResourceSaver.FLAG_CHANGE_PATH)
		if result != OK: return result
		resource.take_over_path(path)
		index += 1
	return OK

static func _sizes(node: Node, sizes: Dictionary) -> int:
	var count := 1
	for child in node.get_children(): count += _sizes(child,sizes)
	sizes[node.get_instance_id()] = count
	return count

static func _split(node: Node, root: Node, sizes: Dictionary, groups: Array) -> void:
	var pending: Array[Node] = []
	var count := 0
	var parent_path := str(root.get_path_to(node))
	for child in node.get_children():
		var child_count := int(sizes[child.get_instance_id()])
		if child_count > MAX_PART_NODES:
			_split(child,root,sizes,groups)
			continue
		if count+child_count > MAX_PART_NODES and not pending.is_empty():
			groups.append({"parent":parent_path,"nodes":pending,"count":count})
			pending = []
			count = 0
		clear_owners(child)
		node.remove_child(child)
		pending.append(child)
		count += child_count
	if not pending.is_empty(): groups.append({"parent":parent_path,"nodes":pending,"count":count})

static func _owners(node: Node, owner_root: Node) -> void:
	node.owner = owner_root
	for child in node.get_children(): _owners(child,owner_root)

static func _save(node: Node, path: String) -> Error:
	var packed := PackedScene.new()
	var result := packed.pack(node)
	return ResourceSaver.save(packed,path) if result == OK else result

static func write(snapshot: Node3D, folder: String, revision: int, tree: SceneTree, report: Callable, cancelled: Callable) -> Dictionary:
	var shared_result := _share_resources(snapshot,folder,revision)
	if shared_result != OK: return {"path":"","parts":[],"error":shared_result,"nodes":0}
	var sizes := {}
	var total_nodes := _sizes(snapshot,sizes)
	var groups: Array = []
	_split(snapshot,snapshot,sizes,groups)
	var path := folder+"/view_%d.scn" % revision
	var result := _save(snapshot,path)
	var parts: Array = []
	for index in groups.size():
		var group: Dictionary = groups[index]
		if result == OK and not cancelled.call():
			var holder := Node3D.new()
			holder.name = "PreviewPart"
			for node in group.nodes:
				holder.add_child(node)
				_owners(node,holder)
			var part_path := folder+"/view_%d_part_%d.scn" % [revision,index]
			result = _save(holder,part_path)
			holder.free()
			if result == OK: parts.append({"path":part_path,"parent":group.parent,"nodes":group.count})
		else:
			for node in group.nodes:
				if is_instance_valid(node): node.free()
			if result == OK: result = ERR_SKIP
		report.call("Preparando partes 3D",index+1,groups.size(),index == 0 or index+1 == groups.size())
		await tree.process_frame
	return {"path":path,"parts":parts,"error":result,"nodes":total_nodes}
