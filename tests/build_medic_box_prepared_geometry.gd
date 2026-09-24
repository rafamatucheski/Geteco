extends SceneTree

## Rebuilds the authored MedicBox, performs the expensive wheel carving and
## batching offline, and stores a scriptless operational template. Runtime
## materials remain per-instance and are rebound from stable role metadata.

const MODEL_PATH := "res://prototypes/living_cast/models/MedicBoxModel.gd"
const OUTPUT_PATH := "res://prototypes/living_cast/models/MedicBoxPreparedGeometry.scn"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const MATERIAL_KEY_META := &"medic_box_material_key"
const CONTRACT_VERSION := 1
const EXPECTED_TRIANGLES := 23503


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset_runtime()
	var script := load(MODEL_PATH) as Script
	if script == null:
		_fail("MedicBox prepared builder could not load the model script")
		return
	CACHE._deferred_constructor_paths[MODEL_PATH] = 1
	var model := script.new() as Node3D
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	if model == null or not model.has_method("build_procedural_source"):
		_fail("MedicBox prepared builder could not create an authored source shell")
		return
	model.call("build_procedural_source", false)
	if model.get_child_count() == 0:
		_fail("MedicBox authored source produced no geometry")
		return
	root.add_child(model)

	var mount_started := Time.get_ticks_usec()
	var rig := WHEEL_RIG.new()
	if not rig.mount(model) or rig.pivots.size() != 4:
		_fail("MedicBox authored source did not mount four wheels")
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

	if not _tag_material_roles(model, materials):
		return
	var mesh_count := _mesh_count(model)
	var triangle_count := _triangle_count(model)
	var signature := _geometry_signature(model)
	var wheel_centres := _wheel_centres(model)
	var left := model.get_node_or_null("RearDoorLeft") as Node3D
	var right := model.get_node_or_null("RearDoorRight") as Node3D
	var left_meshes := left.find_children("*", "MeshInstance3D", true, false).size() if left != null else 0
	var right_meshes := right.find_children("*", "MeshInstance3D", true, false).size() if right != null else 0
	var clearance_signature := int(model.get_meta("vehicle_wheel_clearance_signature", 0))
	if mesh_count <= 0 \
			or triangle_count != EXPECTED_TRIANGLES \
			or signature == 0 \
			or authored_visual_signature != prepared_visual_signature \
			or wheel_centres.size() != 4 \
			or clearance_signature == 0 \
			or left_meshes < 3 or right_meshes < 3:
		_fail("MedicBox prepared source invalid meshes=%d triangles=%d signature=%d visual=%d/%d wheels=%d doors=%d/%d clearance=%d" % [
			mesh_count, triangle_count, signature, authored_visual_signature,
			prepared_visual_signature, wheel_centres.size(), left_meshes,
			right_meshes, clearance_signature,
		])
		return

	var baked_root := Node3D.new()
	baked_root.name = "MedicBoxPreparedGeometry"
	baked_root.set_meta("medic_box_prepared_contract_version", CONTRACT_VERSION)
	baked_root.set_meta("medic_box_prepared_geometry_signature", signature)
	baked_root.set_meta("medic_box_prepared_meshes", mesh_count)
	baked_root.set_meta("medic_box_prepared_triangles", triangle_count)
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
		_fail("MedicBox PackedScene.pack failed: %s" % error_string(pack_error))
		return
	var save_error := ResourceSaver.save(packed, OUTPUT_PATH)
	if save_error != OK:
		_fail("MedicBox ResourceSaver.save failed: %s" % error_string(save_error))
		return
	print("MEDIC_BOX_PREPARED_GEOMETRY path=%s meshes=%d triangles=%d signature=%d visual_signature=%d wheels=%d doors=%d/%d clearance_signature=%d mount_ms=%.3f batch_ms=%.3f removed=%d" % [
		OUTPUT_PATH, mesh_count, triangle_count, signature, prepared_visual_signature, wheel_centres.size(),
		left_meshes, right_meshes, clearance_signature, mount_usec / 1000.0,
		batch_usec / 1000.0, removed,
	])
	baked_root.free()
	model.free()
	_reset_runtime()
	quit(0)


func _tag_material_roles(node: Node, materials: Dictionary) -> bool:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var key := _material_key(materials, part.material_override)
		if key.is_empty():
			_fail("MedicBox prepared builder could not classify material for %s" % part.name)
			return false
		part.set_meta(MATERIAL_KEY_META, StringName(key))
	for child in node.get_children():
		if not _tag_material_roles(child, materials):
			return false
	return true


func _material_key(materials: Dictionary, material: Material) -> String:
	for key in materials:
		if materials[key] == material:
			return String(key)
	return ""


func _material_visual_signature(model: Node3D, materials: Dictionary, decimals: int) -> int:
	var entries: Array[String] = []
	_collect_material_visual(model, materials, Transform3D.IDENTITY, entries, decimals)
	entries.sort()
	return hash(entries)


func _collect_material_visual(node: Node, materials: Dictionary, parent_transform: Transform3D, entries: Array[String], decimals: int) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var material_key := _material_key(materials, part.material_override)
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var arrays := part.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var triangles := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			for triangle_index in triangles:
				var points: Array[String] = []
				for corner in 3:
					var vertex_index := indices[triangle_index * 3 + corner] if not indices.is_empty() else triangle_index * 3 + corner
					var point := world_transform * vertices[vertex_index]
					points.append(_point_key(point, decimals))
				points.sort()
				entries.append("%s:%s" % [material_key, "|".join(points)])
	for child in node.get_children():
		_collect_material_visual(child, materials, world_transform, entries, decimals)


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


func _geometry_signature(model: Node3D) -> int:
	var entries: Array[String] = []
	_collect_geometry(model, Transform3D.IDENTITY, entries)
	entries.sort()
	return hash(entries)


func _collect_geometry(node: Node, parent_transform: Transform3D, entries: Array[String]) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var material_key := String(part.get_meta(MATERIAL_KEY_META, &""))
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var arrays := part.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var triangles := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			for triangle_index in triangles:
				var points: Array[String] = []
				for corner in 3:
					var vertex_index := indices[triangle_index * 3 + corner] if not indices.is_empty() else triangle_index * 3 + corner
					var point := world_transform * vertices[vertex_index]
					points.append("%.5f,%.5f,%.5f" % [point.x, point.y, point.z])
				points.sort()
				entries.append("%s:%s" % [material_key, "|".join(points)])
	for child in node.get_children():
		_collect_geometry(child, world_transform, entries)


func _clear_material_overrides(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = null
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
