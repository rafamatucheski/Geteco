extends RefCounted
## Recuperação pontual: sem varredura por frame e sem recriar o chunk.
const DELAY := 45.0

static func capture(item: Dictionary) -> void:
	var saved := {"parts": [], "nodes": []}
	if item.has("multimesh"):
		var parts: Array = [{"multimesh": item.multimesh, "index": item.index}]
		parts.append_array(item.extra)
		for part in parts:
			saved.parts.append([part.multimesh, part.index, part.multimesh.get_instance_transform(part.index)])
	else:
		var source = item.root.get_ref()
		if not is_instance_valid(source): return
		saved.transform = source.global_transform
		var pending: Array[Node] = [source]
		while not pending.is_empty():
			var node: Node = pending.pop_back()
			var properties := {}
			if node is Node3D: properties.visible = node.visible
			if node is CollisionObject3D:
				properties.collision_layer = node.collision_layer
				properties.collision_mask = node.collision_mask
			if node is CollisionShape3D: properties.disabled = node.disabled
			if node is Light3D:
				properties.light_energy = node.light_energy
			if node is MeshInstance3D: properties.material_override = node.material_override
			saved.nodes.append([weakref(node), properties])
			pending.append_array(node.get_children())
	var pool: Dictionary = item.get("pool", {})
	if is_instance_valid(pool.get("multimesh")):
		saved.parts.append([pool.multimesh, pool.index, pool.multimesh.get_instance_transform(pool.index)])
	item.recovery = saved

static func schedule(item: Dictionary, director: Node, delay := DELAY) -> void:
	var chunk = item.chunk.get_ref()
	if not is_instance_valid(chunk) or not chunk.is_inside_tree(): return
	# Timer owned by the chunk: unloading it cancels recovery with it.
	var timer: Tween = chunk.create_tween()
	timer.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	timer.tween_interval(delay)
	timer.tween_callback(func():
		if not is_instance_valid(director) or item.state != "down": return
		var space: PhysicsDirectSpaceState3D = chunk.get_world_3d().direct_space_state
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 6.0
		query.shape = sphere
		query.transform.origin = item.point + Vector3.UP
		query.collision_mask = 2 | 4
		if not space.intersect_shape(query, 1).is_empty():
			schedule(item, director, 5.0)
			return
		restore(item))

static func restore(item: Dictionary) -> void:
	if not item.has("recovery"): return
	var saved: Dictionary = item.recovery
	for part in saved.parts:
		if is_instance_valid(part[0]) and part[1] < part[0].instance_count:
			part[0].set_instance_transform(part[1], part[2])
	if item.has("root"):
		var source = item.root.get_ref()
		if not is_instance_valid(source): return
		source.global_transform = saved.transform
		for entry in saved.nodes:
			var node = entry[0].get_ref()
			if not is_instance_valid(node): continue
			for property in entry[1]: node.set(property, entry[1][property])
			if node is Light3D: node.remove_meta("street_destroyed")
	item.state = "standing"
	item.erase("recovery")
