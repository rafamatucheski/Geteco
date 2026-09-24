extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/models/NimbusMinivanModel.gd"
const OUTPUT_PATH := "res://prototypes/living_cast/models/NimbusMinivanPreparedGeometry.scn"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const MATERIAL_META := &"nimbus_minivan_material_key"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset()
	var script := load(MODEL_PATH) as Script
	if script == null:
		_fail("Nimbus builder could not load model")
		return
	CACHE._deferred_constructor_paths[MODEL_PATH] = 1
	var model := script.new() as Node3D
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	if model == null or not model.has_method("build_nimbus_procedural_source"):
		_fail("Nimbus builder could not create procedural shell")
		return
	model.call("build_nimbus_procedural_source")
	root.add_child(model)
	var mount_started := Time.get_ticks_usec()
	var rig := WHEEL_RIG.new()
	if not rig.mount(model) or rig.pivots.size() != 4:
		_fail("Nimbus source did not mount four wheels")
		return
	var mount_usec := Time.get_ticks_usec() - mount_started
	var materials := model.get("materials") as Dictionary
	var before_signature := _visual_signature(model, materials, 4, false)
	var batch_started := Time.get_ticks_usec()
	var removed := BATCHER.batch_model(model)
	var batch_usec := Time.get_ticks_usec() - batch_started
	_flatten_wheels(model, rig)
	model.set_meta("vehicle_mesh_batched", true)
	var after_signature := _visual_signature(model, materials, 4, false)
	if not _tag(model, materials, model.get("lamp_sources") as Dictionary, model.get("originals") as Dictionary):
		return
	var meshes := _mesh_count(model)
	var triangles := _triangle_count(model)
	var signature := _visual_signature(model, {}, 5, true)
	var wheels := _wheel_centres(model)
	var lamps := _count_meta(model, &"nimbus_minivan_lamp")
	var damage_bodies := _count_meta(model, &"nimbus_minivan_damage_body")
	var clearance := int(model.get_meta("vehicle_wheel_clearance_signature", 0))
	if meshes <= 0 or triangles <= 0 or signature == 0 or before_signature != after_signature \
			or wheels.size() != 4 or lamps < 4 or damage_bodies < 1 or clearance == 0:
		_fail("Nimbus prepared source invalid meshes=%d triangles=%d signature=%d visual=%d/%d wheels=%d lamps=%d damage=%d clearance=%d" % [
			meshes, triangles, signature, before_signature, after_signature,
			wheels.size(), lamps, damage_bodies, clearance,
		])
		return
	var baked := Node3D.new()
	baked.name = "NimbusMinivanPreparedGeometry"
	for metadata in model.get_meta_list():
		baked.set_meta(metadata, model.get_meta(metadata))
	baked.set_meta("nimbus_minivan_prepared_contract_version", 1)
	baked.set_meta("nimbus_minivan_prepared_geometry_signature", signature)
	baked.set_meta("nimbus_minivan_prepared_meshes", meshes)
	baked.set_meta("nimbus_minivan_prepared_triangles", triangles)
	baked.set_meta("vehicle_wheel_clearance_signature", clearance)
	for child in model.get_children():
		_clear_owner(child)
		model.remove_child(child)
		baked.add_child(child)
		_clear_materials(child)
		_set_owner(child, baked)
	var packed := PackedScene.new()
	var error := packed.pack(baked)
	if error != OK:
		_fail("Nimbus pack failed: %s" % error_string(error))
		return
	error = ResourceSaver.save(packed, OUTPUT_PATH)
	if error != OK:
		_fail("Nimbus save failed: %s" % error_string(error))
		return
	print("NIMBUS_MINIVAN_PREPARED_GEOMETRY ", JSON.stringify({
		"path": OUTPUT_PATH, "meshes": meshes, "triangles": triangles,
		"signature": signature, "visual_signature": after_signature,
		"wheels": wheels.size(), "lamps": lamps, "damage_bodies": damage_bodies,
		"clearance_signature": clearance, "mount_usec": mount_usec,
		"batch_usec": batch_usec, "batched_removed": removed,
	}))
	baked.free()
	model.free()
	_reset()
	quit(0)


func _tag(node: Node, materials: Dictionary, lamp_sources: Dictionary, originals: Dictionary) -> bool:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var key := _material_key(materials, part.material_override)
		if key.is_empty():
			_fail("Nimbus builder could not classify material for %s" % part.name)
			return false
		part.set_meta(MATERIAL_META, StringName(key))
		if lamp_sources.has(part):
			part.set_meta("nimbus_minivan_lamp", true)
		if originals.has(part):
			if key != "paint" or part.mesh.get_surface_count() != 1:
				_fail("Nimbus damage body lost independent paint surface")
				return false
			part.set_meta("nimbus_minivan_damage_body", true)
	for child in node.get_children():
		if not _tag(child, materials, lamp_sources, originals):
			return false
	return true


func _material_key(materials: Dictionary, material: Material) -> String:
	for key in materials:
		if materials[key] == material:
			return String(key)
	return ""


func _visual_signature(model: Node3D, materials: Dictionary, decimals: int, metadata_roles: bool) -> int:
	var entries: Array[String] = []
	_collect_visual(model, materials, Transform3D.IDENTITY, entries, decimals, metadata_roles)
	entries.sort()
	return hash(entries)


func _collect_visual(node: Node, materials: Dictionary, parent_transform: Transform3D, entries: Array[String], decimals: int, metadata_roles: bool) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var role := String(part.get_meta(MATERIAL_META, &"")) if metadata_roles else _material_key(materials, part.material_override)
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var arrays := part.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			for triangle_index in count:
				var points: Array[String] = []
				for corner in 3:
					var vertex_index := indices[triangle_index * 3 + corner] if not indices.is_empty() else triangle_index * 3 + corner
					var point := world_transform * vertices[vertex_index]
					var scale := pow(10.0, decimals)
					points.append("%d,%d,%d" % [roundi(point.x * scale), roundi(point.y * scale), roundi(point.z * scale)])
				points.sort()
				entries.append("%s:%s" % [role, "|".join(points)])
	for child in node.get_children():
		_collect_visual(child, materials, world_transform, entries, decimals, metadata_roles)


func _flatten_wheels(model: Node3D, rig: RefCounted) -> void:
	for pivot in rig.pivots:
		if is_instance_valid(pivot):
			_flatten_branch(pivot, model)
			pivot.free()


func _flatten_branch(parent: Node, model: Node3D) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D:
			child.reparent(model, true)
		elif child is Node3D:
			_flatten_branch(child, model)


func _wheel_centres(node: Node) -> Array[Vector3]:
	var result: Array[Vector3] = []
	_collect_centres(node, result)
	return result


func _collect_centres(node: Node, result: Array[Vector3]) -> void:
	if node.has_meta("wheel_center"):
		var centre: Vector3 = node.get_meta("wheel_center")
		if not result.has(centre):
			result.append(centre)
	for child in node.get_children():
		_collect_centres(child, result)


func _count_meta(node: Node, key: StringName) -> int:
	var count := 1 if bool(node.get_meta(key, false)) else 0
	for child in node.get_children():
		count += _count_meta(child, key)
	return count


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count


func _triangle_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface_index in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface_index)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
				count += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	for child in node.get_children():
		count += _triangle_count(child)
	return count


func _clear_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		part.material_override = null
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			part.set_surface_override_material(surface_index, null)
	for child in node.get_children():
		_clear_materials(child)


func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)


func _set_owner(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children():
		_set_owner(child, owner_node)


func _reset() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	CACHE._regional_capture_suppressed_paths.erase(MODEL_PATH)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
