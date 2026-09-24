extends SceneTree

## Rebuilds the exact authored Boss Muscle and saves its post-wheel-clearance,
## post-batching presentation as immutable geometry. Runtime materials remain
## independent and are rebound from stable keys by BossMuscleModel.

const MODEL_PATH := "res://prototypes/living_cast/BossMuscleModel.gd"
const OUTPUT_PATH := "res://prototypes/living_cast/BossMusclePreparedGeometry.scn"
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const MESH_BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const MATERIAL_KEY_META := &"boss_muscle_material_key"
const SURFACE_KEYS_META := &"boss_muscle_surface_material_keys"
const EXPECTED_VISUAL_SIGNATURE := 3943922188
const PREPARED_CONTRACT_VERSION := 2
const EXPECTED_PREPARED_MESHES := 10
const EXPECTED_PREPARED_TRIANGLES := 26582


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fixture := Node3D.new()
	fixture.name = "BossMusclePreparedGeometryBuilder"
	root.add_child(fixture)
	var script := load(MODEL_PATH) as Script
	if script == null:
		_fail("Could not load Boss Muscle source")
		return
	var model := script.new() as Node3D
	if model.has_method("build_procedural_source"):
		model.call("build_procedural_source")
	fixture.add_child(model)
	await process_frame
	var authored_meshes := _mesh_count(model)
	var authored_triangles := _triangle_count(model)

	var mount_started := Time.get_ticks_usec()
	var rig := WHEEL_RIG.new()
	if not rig.mount(model):
		_fail("Boss Muscle source has no wheel markers")
		return
	var mount_ms := _elapsed_ms(mount_started)
	var batch_started := Time.get_ticks_usec()
	var batched_removed: int = MESH_BATCHER.batch_model(model)
	var batch_ms := _elapsed_ms(batch_started)
	_flatten_wheels(model, rig)

	var clearance_signature := int(model.get_meta("vehicle_wheel_clearance_signature", 0))
	if clearance_signature == 0:
		_fail("Wheel clearance did not publish its prepared signature")
		return
	var materials: Dictionary = model.get("materials")
	if not _compact_prepared_geometry(model, materials):
		return
	if not _validate_compacted_geometry(model):
		return
	var baked_root := Node3D.new()
	baked_root.name = "BossMusclePreparedGeometry"
	baked_root.set_meta("vehicle_wheel_clearance_signature", clearance_signature)
	for child in model.get_children():
		_clear_owner(child)
		model.remove_child(child)
		baked_root.add_child(child)
		_set_owner_recursive(child, baked_root)
		var part := child as MeshInstance3D
		if part != null:
			var surface_keys: PackedStringArray = part.get_meta(SURFACE_KEYS_META, PackedStringArray())
			if surface_keys.size() != part.mesh.get_surface_count():
				_fail("Prepared mesh %s has incomplete surface material keys" % part.name)
				return
			part.material_override = null

	var prepared_meshes := _mesh_count(baked_root)
	var prepared_triangles := _triangle_count(baked_root)
	var signature := _geometry_signature(baked_root)
	baked_root.set_meta("boss_muscle_prepared_geometry_signature", signature)
	baked_root.set_meta("boss_muscle_prepared_contract_version", PREPARED_CONTRACT_VERSION)
	baked_root.set_meta("boss_muscle_prepared_meshes", prepared_meshes)
	baked_root.set_meta("boss_muscle_prepared_triangles", prepared_triangles)
	var packed := PackedScene.new()
	var pack_error := packed.pack(baked_root)
	if pack_error != OK:
		_fail("PackedScene.pack failed: %s" % error_string(pack_error))
		return
	var save_error := ResourceSaver.save(packed, OUTPUT_PATH)
	if save_error != OK:
		_fail("ResourceSaver.save failed: %s" % error_string(save_error))
		return

	print("BOSS_MUSCLE_PREPARED_GEOMETRY path=%s authored_meshes=%d authored_triangles=%d mount_ms=%.3f batch_ms=%.3f removed=%d prepared_meshes=%d prepared_triangles=%d clearance_signature=%d geometry_signature=%d" % [
		OUTPUT_PATH, authored_meshes, authored_triangles, mount_ms, batch_ms,
		batched_removed, prepared_meshes, prepared_triangles,
		clearance_signature, signature,
	])
	baked_root.free()
	model.free()
	fixture.free()
	quit(0)


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


func _material_key(materials: Dictionary, material: Material) -> String:
	for key in materials:
		if materials[key] == material:
			return String(key)
	return ""


func _compact_prepared_geometry(model: Node3D, materials: Dictionary) -> bool:
	var groups: Dictionary = {}
	var lamp_index := 0
	for child in model.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			continue
		var material_key := _material_key(materials, part.material_override)
		if material_key.is_empty():
			_fail("Could not classify material for %s" % part.name)
			return false
		var group_key := "static_misc"
		if material_key in ["headlight", "tail"]:
			group_key = "lamp_%02d" % lamp_index
			lamp_index += 1
		elif part.has_meta("wheel_center"):
			var center: Vector3 = part.get_meta("wheel_center")
			group_key = "wheel_%.3f_%.3f" % [center.x, center.z]
		elif material_key == "paint":
			group_key = "damage_body"
		if not groups.has(group_key):
			groups[group_key] = []
		groups[group_key].append({"node": part, "material_key": material_key})

	for group_key in groups:
		var sources: Array = groups[group_key]
		var compact := _merge_group(String(group_key), sources)
		if compact == null:
			return false
		model.add_child(compact)
		for source_data in sources:
			var source := source_data.node as MeshInstance3D
			model.remove_child(source)
			source.free()
	return true


func _validate_compacted_geometry(model: Node3D) -> bool:
	var wheel_groups := 0
	var lamp_groups := 0
	var damage_groups := 0
	var static_groups := 0
	for child in model.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			continue
		if String(part.name).begins_with("BossMuscle_wheel_"):
			wheel_groups += 1
			if not part.has_meta("wheel_center") or not bool(part.get_meta("wheel_spins", false)):
				_fail("Compacted wheel %s lost articulation metadata" % part.name)
				return false
		elif String(part.name).begins_with("BossMuscle_lamp_"):
			lamp_groups += 1
			if absf(part.position.x) < 0.4 or absf(part.position.z) < 2.4:
				_fail("Compacted lamp %s lost its authored damage position" % part.name)
				return false
		elif part.has_meta("boss_muscle_damage_body"):
			damage_groups += 1
			if part.mesh.get_surface_count() != 1:
				_fail("Damage body must remain one surface for CoupeDamageModel, got %d" % part.mesh.get_surface_count())
				return false
		elif part.name == &"BossMuscle_static_misc":
			static_groups += 1
	var mesh_count := _mesh_count(model)
	var triangle_count := _triangle_count(model)
	var signature := _geometry_signature(model)
	if mesh_count != EXPECTED_PREPARED_MESHES:
		_fail("Compaction must produce %d operational meshes, got %d" % [EXPECTED_PREPARED_MESHES, mesh_count])
		return false
	if triangle_count != EXPECTED_PREPARED_TRIANGLES:
		_fail("Compaction changed triangle count: expected %d, got %d" % [EXPECTED_PREPARED_TRIANGLES, triangle_count])
		return false
	if signature != EXPECTED_VISUAL_SIGNATURE:
		_fail("Compaction changed exact geometry signature: expected %d, got %d" % [EXPECTED_VISUAL_SIGNATURE, signature])
		return false
	if wheel_groups != 4 or lamp_groups != 4 or damage_groups != 1 or static_groups != 1:
		_fail("Unexpected operational groups: wheels=%d lamps=%d damage=%d static=%d" % [wheel_groups, lamp_groups, damage_groups, static_groups])
		return false
	return true


func _merge_group(group_key: String, sources: Array) -> MeshInstance3D:
	var material_keys := PackedStringArray()
	var merged := ArrayMesh.new()
	if group_key == "damage_body":
		var paint_arrays := _merge_damage_body_arrays(sources)
		if paint_arrays.is_empty():
			return null
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, paint_arrays)
		material_keys.append("paint")
	elif group_key.begins_with("lamp_"):
		if sources.size() != 1:
			_fail("Independent lamp group %s must have one source, got %d" % [group_key, sources.size()])
			return null
		var source := sources[0].node as MeshInstance3D
		for surface_index in source.mesh.get_surface_count():
			material_keys.append(String(sources[0].material_key))
			merged.add_surface_from_arrays(
				_source_primitive_type(source.mesh, surface_index),
				source.mesh.surface_get_arrays(surface_index)
			)
	else:
		for source_data in sources:
			var material_key := String(source_data.material_key)
			var source := source_data.node as MeshInstance3D
			for surface_index in source.mesh.get_surface_count():
				material_keys.append(material_key)
				merged.add_surface_from_arrays(
					_source_primitive_type(source.mesh, surface_index),
					_transformed_arrays(source.mesh.surface_get_arrays(surface_index), source.transform)
				)
	var compact := MeshInstance3D.new()
	compact.name = "BossMuscle_%s" % group_key
	compact.mesh = merged
	if group_key.begins_with("lamp_"):
		compact.transform = (sources[0].node as MeshInstance3D).transform
	compact.set_meta(SURFACE_KEYS_META, material_keys)
	if _all_same(material_keys):
		compact.set_meta(MATERIAL_KEY_META, material_keys[0])
	if group_key == "damage_body":
		compact.set_meta("boss_muscle_damage_body", true)
	if group_key.begins_with("wheel_"):
		var source := sources[0].node as MeshInstance3D
		for metadata in source.get_meta_list():
			if metadata in ["wheel_center", "wheel_spins", "wheel_radius", "wheel_style"]:
				compact.set_meta(metadata, source.get_meta(metadata))
	return compact


func _merge_damage_body_arrays(sources: Array) -> Array:
	var combined: Array = []
	combined.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for source_data in sources:
		var source := source_data.node as MeshInstance3D
		for surface_index in source.mesh.get_surface_count():
			if _source_primitive_type(source.mesh, surface_index) != Mesh.PRIMITIVE_TRIANGLES:
				_fail("Damage body source %s is not triangle geometry" % source.name)
				return []
			var arrays := _transformed_arrays(source.mesh.surface_get_arrays(surface_index), source.transform)
			var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			if source_normals.size() != source_vertices.size():
				_fail("Damage body source %s has incomplete normals" % source.name)
				return []
			var vertex_offset := vertices.size()
			vertices.append_array(source_vertices)
			normals.append_array(source_normals)
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if source_indices.is_empty():
				for vertex_index in source_vertices.size():
					indices.append(vertex_offset + vertex_index)
			else:
				for source_index in source_indices:
					indices.append(vertex_offset + source_index)
	combined[Mesh.ARRAY_VERTEX] = vertices
	combined[Mesh.ARRAY_NORMAL] = normals
	combined[Mesh.ARRAY_INDEX] = indices
	return combined


func _source_primitive_type(mesh: Mesh, surface_index: int) -> int:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_primitive_type(surface_index)
	return Mesh.PRIMITIVE_TRIANGLES


func _transformed_arrays(source_arrays: Array, transform: Transform3D) -> Array:
	var arrays := source_arrays.duplicate(true)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index in vertices.size():
		vertices[index] = transform * vertices[index]
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var normal_basis := transform.basis.inverse().transposed()
		for index in normals.size():
			normals[index] = (normal_basis * normals[index]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = normals
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var tangent_basis := transform.basis.inverse().transposed()
		for index in range(0, tangents.size(), 4):
			var tangent := (tangent_basis * Vector3(tangents[index], tangents[index + 1], tangents[index + 2])).normalized()
			tangents[index] = tangent.x
			tangents[index + 1] = tangent.y
			tangents[index + 2] = tangent.z
		arrays[Mesh.ARRAY_TANGENT] = tangents
	return arrays


func _all_same(values: PackedStringArray) -> bool:
	if values.is_empty():
		return false
	for value in values:
		if value != values[0]:
			return false
	return true


func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children():
		_set_owner_recursive(child, owner_node)


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


func _geometry_signature(node: Node) -> int:
	var entries: Array[String] = []
	_collect_geometry(node, Transform3D.IDENTITY, entries)
	entries.sort()
	return hash(entries)


func _collect_geometry(node: Node, parent_transform: Transform3D, entries: Array[String]) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var surface_keys: PackedStringArray = part.get_meta(SURFACE_KEYS_META, PackedStringArray())
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var material_key := String(surface_keys[surface_index]) if surface_index < surface_keys.size() else String(part.get_meta(MATERIAL_KEY_META, ""))
			var arrays := part.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			for triangle_index in triangle_count:
				var points: Array[String] = []
				for corner in 3:
					var vertex_index := indices[triangle_index * 3 + corner] if not indices.is_empty() else triangle_index * 3 + corner
					var point := world_transform * vertices[vertex_index]
					points.append("%.5f,%.5f,%.5f" % [point.x, point.y, point.z])
				points.sort()
				entries.append("%s:%s" % [material_key, "|".join(points)])
	for child in node.get_children():
		_collect_geometry(child, world_transform, entries)


func _elapsed_ms(started_usec: int) -> float:
	return (Time.get_ticks_usec() - started_usec) / 1000.0


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
