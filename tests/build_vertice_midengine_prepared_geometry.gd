extends SceneTree

## Rebuilds the authored Vertice, performs wheel carving and batching offline,
## and stores a scriptless template whose materials remain per live instance.

const MODEL_PATH := "res://prototypes/living_cast/models/VerticeMidEngineModel.gd"
const OUTPUT_PATH := "res://prototypes/living_cast/models/VerticeMidEnginePreparedGeometry.scn"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const MATERIAL_KEY_META := &"vertice_midengine_material_key"
const CONTRACT_VERSION := 1
const EXPECTED_TRIANGLES := 16694


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset_runtime()
	var script := load(MODEL_PATH) as Script
	if script == null:
		_fail("Vertice prepared builder could not load the model script")
		return
	CACHE._deferred_constructor_paths[MODEL_PATH] = 1
	var model := script.new() as Node3D
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	if model == null or not model.has_method("build_vertice_procedural_source"):
		_fail("Vertice prepared builder could not create an authored source shell")
		return
	model.call("build_vertice_procedural_source")
	if model.get_child_count() == 0:
		_fail("Vertice authored source produced no geometry")
		return
	root.add_child(model)

	var mount_started := Time.get_ticks_usec()
	var rig := WHEEL_RIG.new()
	if not rig.mount(model) or rig.pivots.size() != 4:
		_fail("Vertice authored source did not mount four wheels")
		return
	var mount_usec := Time.get_ticks_usec() - mount_started
	var materials := model.get("materials") as Dictionary
	var authored_visual_signature := _material_visual_signature(model, materials, 4)
	var batch_started := Time.get_ticks_usec()
	var removed := BATCHER.batch_model(model)
	var batch_usec := Time.get_ticks_usec() - batch_started
	_flatten_wheels(model, rig)
	model.set_meta("vehicle_mesh_batched", true)
	var prepared_visual_signature := _material_visual_signature(model, materials, 4)
	if not _tag_semantic_roles(model, materials):
		return

	var mesh_count := _mesh_count(model)
	var triangle_count := _triangle_count(model)
	var signature := _geometry_signature(model)
	var wheel_centres := _wheel_centres(model)
	var lamp_count := _count_meta(model, &"vertice_midengine_lamp")
	var damage_body_count := _count_meta(model, &"vertice_midengine_damage_body")
	var clearance_signature := int(model.get_meta("vehicle_wheel_clearance_signature", 0))
	if mesh_count <= 0 \
			or triangle_count != EXPECTED_TRIANGLES \
			or signature == 0 \
			or authored_visual_signature != prepared_visual_signature \
			or wheel_centres.size() != 4 \
			or lamp_count < 4 \
			or damage_body_count < 1 \
			or clearance_signature == 0:
		_fail("Vertice prepared source invalid meshes=%d triangles=%d signature=%d visual=%d/%d wheels=%d lamps=%d damage=%d clearance=%d" % [
			mesh_count, triangle_count, signature, authored_visual_signature,
			prepared_visual_signature, wheel_centres.size(), lamp_count,
			damage_body_count, clearance_signature,
		])
		return

	var baked_root := Node3D.new()
	baked_root.name = "VerticeMidEnginePreparedGeometry"
	for metadata in model.get_meta_list():
		baked_root.set_meta(metadata, model.get_meta(metadata))
	baked_root.set_meta("vertice_midengine_prepared_contract_version", CONTRACT_VERSION)
	baked_root.set_meta("vertice_midengine_prepared_geometry_signature", signature)
	baked_root.set_meta("vertice_midengine_prepared_meshes", mesh_count)
	baked_root.set_meta("vertice_midengine_prepared_triangles", triangle_count)
	baked_root.set_meta("vehicle_wheel_clearance_signature", clearance_signature)
	for child in model.get_children():
		_clear_owner(child)
		model.remove_child(child)
		baked_root.add_child(child)
		_clear_material_overrides(child)
		_set_owner_recursive(child, baked_root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(baked_root)
	if pack_error != OK:
		_fail("Vertice PackedScene.pack failed: %s" % error_string(pack_error))
		return
	var save_error := ResourceSaver.save(packed, OUTPUT_PATH)
	if save_error != OK:
		_fail("Vertice ResourceSaver.save failed: %s" % error_string(save_error))
		return
	print("VERTICE_MIDENGINE_PREPARED_GEOMETRY ", JSON.stringify({
		"path": OUTPUT_PATH,
		"meshes": mesh_count,
		"triangles": triangle_count,
		"signature": signature,
		"visual_signature": prepared_visual_signature,
		"wheels": wheel_centres.size(),
		"lamps": lamp_count,
		"damage_bodies": damage_body_count,
		"clearance_signature": clearance_signature,
		"mount_usec": mount_usec,
		"batch_usec": batch_usec,
		"batched_removed": removed,
	}))
	baked_root.free()
	model.free()
	_reset_runtime()
	quit(0)


func _tag_semantic_roles(model: Node3D, materials: Dictionary) -> bool:
	return _tag_branch(model, materials, model.get("lamp_sources") as Dictionary, model.get("originals") as Dictionary)


func _tag_branch(node: Node, materials: Dictionary, lamp_sources: Dictionary, originals: Dictionary) -> bool:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var key := _material_key(materials, part.material_override)
		if key.is_empty():
			_fail("Vertice prepared builder could not classify material for %s" % part.name)
			return false
		part.set_meta(MATERIAL_KEY_META, StringName(key))
		if lamp_sources.has(part):
			part.set_meta("vertice_midengine_lamp", true)
		if originals.has(part):
			if key != "paint" or part.mesh.get_surface_count() != 1:
				_fail("Vertice damage body lost its independent single paint surface")
				return false
			part.set_meta("vertice_midengine_damage_body", true)
	for child in node.get_children():
		if not _tag_branch(child, materials, lamp_sources, originals):
			return false
	return true


func _material_key(materials: Dictionary, material: Material) -> String:
	for key in materials:
		if materials[key] == material:
			return String(key)
	return ""


func _material_visual_signature(model: Node3D, materials: Dictionary, decimals: int) -> int:
	var entries: Array[String] = []
	_collect_visual(model, materials, Transform3D.IDENTITY, entries, decimals, false)
	entries.sort()
	return hash(entries)


func _geometry_signature(model: Node3D) -> int:
	var entries: Array[String] = []
	_collect_visual(model, {}, Transform3D.IDENTITY, entries, 5, true)
	entries.sort()
	return hash(entries)


func _collect_visual(node: Node, materials: Dictionary, parent_transform: Transform3D, entries: Array[String], decimals: int, use_metadata: bool) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var material_key := String(part.get_meta(MATERIAL_KEY_META, &"")) if use_metadata else _material_key(materials, part.material_override)
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var arrays := part.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			for triangle_index in triangle_count:
				var points: Array[String] = []
				for corner in 3:
					var vertex_index := indices[triangle_index * 3 + corner] if not indices.is_empty() else triangle_index * 3 + corner
					points.append(_point_key(world_transform * vertices[vertex_index], decimals))
				points.sort()
				entries.append("%s:%s" % [material_key, "|".join(points)])
	for child in node.get_children():
		_collect_visual(child, materials, world_transform, entries, decimals, use_metadata)


func _point_key(point: Vector3, decimals: int) -> String:
	var scale := pow(10.0, decimals)
	return "%d,%d,%d" % [roundi(point.x * scale), roundi(point.y * scale), roundi(point.z * scale)]


func _flatten_wheels(model: Node3D, rig: RefCounted) -> void:
	for pivot in rig.pivots:
		if not is_instance_valid(pivot):
			continue
		_flatten_mesh_descendants(pivot, model)
		pivot.free()


func _flatten_mesh_descendants(parent: Node, model: Node3D) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D:
			child.reparent(model, true)
		elif child is Node3D:
			_flatten_mesh_descendants(child, model)


func _wheel_centres(node: Node) -> Array[Vector3]:
	var centres: Array[Vector3] = []
	_collect_wheel_centres(node, centres)
	return centres


func _collect_wheel_centres(node: Node, centres: Array[Vector3]) -> void:
	if node.has_meta("wheel_center"):
		var centre: Vector3 = node.get_meta("wheel_center")
		if not centres.has(centre):
			centres.append(centre)
	for child in node.get_children():
		_collect_wheel_centres(child, centres)


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


func _clear_material_overrides(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		part.material_override = null
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			part.set_surface_override_material(surface_index, null)
	for child in node.get_children():
		_clear_material_overrides(child)


func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children():
		_set_owner_recursive(child, owner_node)


func _reset_runtime() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	CACHE._regional_capture_suppressed_paths.erase(MODEL_PATH)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
