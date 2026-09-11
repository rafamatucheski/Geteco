extends RefCounted
static var _mesh_cache: Dictionary = {}
static var cache_hits := 0
## Batch only static, compatible sibling surfaces. Call once after extracting wheels
## and reading lamp mounts. Never combine independently animated transforms.
static func batch_model(model: Node3D) -> int:
	if "damaged_vertices" in model and not model.damaged_vertices.is_empty():
		return 0 # Initial assembly only: do not bake a dent into the repair baseline.
	return _batch_branch(model, model)

static func _batch_branch(parent: Node3D, model: Node3D) -> int:
	var removed := 0
	# Recursion stays inside each wheel pivot/spinner (never across transforms).
	for child in parent.get_children():
		if child is Node3D and not child is MeshInstance3D and child.get_script() == null:
			removed += _batch_branch(child, model)
	var groups := {}
	for child in parent.get_children():
		if not child is MeshInstance3D: continue
		var node := child as MeshInstance3D
		if node.has_meta("independent_motion"): continue
		if node.mesh == null or node.mesh.get_surface_count() != 1 or not node.visible: continue
		if node.get_script() != null or node.material_overlay != null or node.skin != null: continue
		if node.mesh is ArrayMesh and node.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES: continue
		if not node.mesh is ArrayMesh and not node.mesh is PrimitiveMesh: continue
		var material: Material = node.material_override
		if material == null: continue
		# Lamp damage uses individual lens positions. Keep those addressable.
		if "materials" in model and material in [model.materials.get("headlight"), model.materials.get("dead_led")]: continue
		# Preserve transparent object sorting and any unextracted wheel articulation.
		if material is BaseMaterial3D and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		if parent == model and node.has_meta("wheel_center"): continue
		var damageable: bool = "originals" in model and model.originals.has(node)
		var key := "%s:%s:%s:%s:%s:%s" % [material.get_instance_id(),_surface_format(node.mesh),node.cast_shadow,node.layers,node.gi_mode,damageable]
		if not groups.has(key): groups[key] = []
		groups[key].append(node)
	for key in groups:
		var sources: Array = groups[key]
		if sources.size() < 2: continue
		var first: MeshInstance3D = sources[0]
		var parts: Array = []
		for source in sources:
			parts.append([source.mesh.get_rid().get_id(),source.transform])
		var geometry_key := var_to_bytes(parts).hex_encode()
		var mesh: ArrayMesh = _mesh_cache.get(geometry_key)
		if mesh == null:
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for source in sources: surface.append_from(source.mesh, 0, source.transform)
			mesh = surface.commit()
			if _mesh_cache.size() >= 256: _mesh_cache.erase(_mesh_cache.keys()[0])
			_mesh_cache[geometry_key] = mesh
			for source in sources:
				if not source.mesh.changed.is_connected(_invalidate_cache): source.mesh.changed.connect(_invalidate_cache)
		else:
			cache_hits += 1
		if mesh == null: continue
		var batch := MeshInstance3D.new()
		batch.name = "BatchedVehicleSurface"
		batch.mesh = mesh
		batch.material_override = first.material_override
		batch.cast_shadow = first.cast_shadow
		batch.layers = first.layers
		batch.gi_mode = first.gi_mode
		# Wheel metadata remains available to inspections after pivot extraction.
		for metadata in first.get_meta_list(): batch.set_meta(metadata,first.get_meta(metadata))
		parent.add_child(batch)
		var tracked: bool = "originals" in model and model.originals.has(first)
		for source in sources:
			if "originals" in model: model.originals.erase(source)
			if "damaged_vertices" in model: model.damaged_vertices.erase(source)
			parent.remove_child(source)
			source.free()
		if tracked: model.originals[batch] = mesh
		removed += sources.size()-1
	return removed

static func _invalidate_cache() -> void:
	_mesh_cache.clear()

static func _surface_format(mesh: Mesh) -> int:
	var arrays := mesh.surface_get_arrays(0)
	var format := 0
	for i in Mesh.ARRAY_MAX:
		if i != Mesh.ARRAY_INDEX and arrays[i] != null and not arrays[i].is_empty(): format |= 1 << i
	return format
