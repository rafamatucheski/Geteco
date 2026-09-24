extends SceneTree

## Rebuilds the authored RanchSingle source and stores its exact post-clearance,
## post-batching presentation. Runtime materials are rebound per vehicle.

const MODEL_PATH := "res://prototypes/living_cast/models/RanchSingleModel.gd"
const OUTPUT_PATH := "res://prototypes/living_cast/models/RanchSinglePreparedGeometry.scn"
const GEOMETRY_CACHE := preload("res://cars/VehicleGeometryCache.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const MESH_BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const MATERIAL_KEY_META := &"ranch_single_material_key"
const SURFACE_KEYS_META := &"ranch_single_surface_material_keys"
const CONTRACT_VERSION := 1
const EXPECTED_SIGNATURE := 2058053124
const EXPECTED_MESHES := 14
const EXPECTED_TRIANGLES := 13800


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fixture := Node3D.new()
	fixture.name = "RanchSinglePreparedGeometryBuilder"
	root.add_child(fixture)
	var script := load(MODEL_PATH) as Script
	if script == null:
		_fail("Could not load RanchSingle source")
		return
	_reset_model_cache()
	var model := script.new() as Node3D
	if model == null:
		_fail("Could not instantiate RanchSingle source")
		return
	# Reproduction never trusts the current runtime template. Start from an empty
	# instance and invoke the retained authored source explicitly.
	for child in model.get_children():
		model.remove_child(child)
		child.free()
	(model.get("materials") as Dictionary).clear()
	model.set("paint", null)
	model.remove_meta("vehicle_wheel_clearance_signature")
	model.remove_meta("vehicle_mesh_batched")
	model.call("build_procedural_source")
	fixture.add_child(model)
	await process_frame
	var authored_meshes := _mesh_count(model)
	var authored_triangles := _triangle_count(model)

	var mount_started := Time.get_ticks_usec()
	var rig := WHEEL_RIG.new()
	if not rig.mount(model):
		_fail("RanchSingle source has no wheel markers")
		return
	var mount_ms := _elapsed_ms(mount_started)
	var batch_started := Time.get_ticks_usec()
	var batched_removed: int = MESH_BATCHER.batch_model(model)
	var batch_ms := _elapsed_ms(batch_started)
	_flatten_wheels(model, rig)

	var clearance_signature := int(model.get_meta("vehicle_wheel_clearance_signature", 0))
	if clearance_signature == 0:
		_fail("Wheel clearance did not publish a prepared signature")
		return
	var materials: Dictionary = model.get("materials")
	if not _compact_prepared_geometry(model, materials):
		return
	var wheel_centres := _wheel_centres(model)
	var signature := _geometry_signature(model, materials)
	var prepared_meshes := _mesh_count(model)
	var prepared_triangles := _triangle_count(model)
	if prepared_meshes != EXPECTED_MESHES or prepared_triangles != EXPECTED_TRIANGLES or signature != EXPECTED_SIGNATURE or wheel_centres.size() != 4:
		_fail("Prepared geometry mismatch meshes=%d triangles=%d signature=%d wheels=%d" % [prepared_meshes, prepared_triangles, signature, wheel_centres.size()])
		return

	var baked_root := Node3D.new()
	baked_root.name = "RanchSinglePreparedGeometry"
	baked_root.set_meta("vehicle_wheel_clearance_signature", clearance_signature)
	baked_root.set_meta("ranch_single_prepared_contract_version", CONTRACT_VERSION)
	baked_root.set_meta("ranch_single_prepared_geometry_signature", signature)
	baked_root.set_meta("ranch_single_prepared_meshes", prepared_meshes)
	baked_root.set_meta("ranch_single_prepared_triangles", prepared_triangles)
	for child in model.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			_fail("Prepared RanchSingle child %s is not a mesh" % child.name)
			return
		var surface_keys: PackedStringArray = part.get_meta(SURFACE_KEYS_META, PackedStringArray())
		if surface_keys.size() != part.mesh.get_surface_count():
			_fail("Prepared RanchSingle child %s has incomplete surface material keys" % child.name)
			return
		part.material_override = null
		_clear_owner(part)
		model.remove_child(part)
		baked_root.add_child(part)
		_set_owner_recursive(part, baked_root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(baked_root)
	if pack_error != OK:
		_fail("PackedScene.pack failed: %s" % error_string(pack_error))
		return
	var save_error := ResourceSaver.save(packed, OUTPUT_PATH)
	if save_error != OK:
		_fail("ResourceSaver.save failed: %s" % error_string(save_error))
		return
	print("RANCH_SINGLE_PREPARED_GEOMETRY path=%s authored_meshes=%d authored_triangles=%d mount_ms=%.3f batch_ms=%.3f removed=%d prepared_meshes=%d prepared_triangles=%d clearance_signature=%d geometry_signature=%d wheels=%d" % [
		OUTPUT_PATH, authored_meshes, authored_triangles, mount_ms, batch_ms,
		batched_removed, prepared_meshes, prepared_triangles, clearance_signature,
		signature, wheel_centres.size(),
	])
	baked_root.free()
	model.free()
	fixture.free()
	_reset_model_cache()
	quit(0)


func _compact_prepared_geometry(model: Node3D, materials: Dictionary) -> bool:
	var groups: Dictionary = {}
	var lamp_index := 0
	for child in model.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			continue
		var material_key := _material_key(materials, part.material_override)
		if material_key.is_empty():
			_fail("Could not classify RanchSingle material for %s" % part.name)
			return false
		var group_key := "static_misc"
		if material_key in ["headlight", "taillight"]:
			group_key = "lamp_%02d" % lamp_index
			lamp_index += 1
		elif part.has_meta("wheel_center"):
			var center: Vector3 = part.get_meta("wheel_center")
			var motion := "spin" if bool(part.get_meta("wheel_spins", false)) else "fixed"
			group_key = "wheel_%.3f_%.3f_%s" % [center.x, center.z, motion]
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
	return _validate_compacted_groups(model)


func _validate_compacted_groups(model: Node3D) -> bool:
	var spinning_wheels := 0
	var fixed_wheels := 0
	var lamps := 0
	var damage_bodies := 0
	var static_groups := 0
	for child in model.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			continue
		var name_value := String(part.name)
		if name_value.begins_with("RanchSingle_wheel_"):
			if not part.has_meta("wheel_center"):
				_fail("Compacted RanchSingle wheel lost its center")
				return false
			if bool(part.get_meta("wheel_spins", false)):
				spinning_wheels += 1
			else:
				fixed_wheels += 1
		elif name_value.begins_with("RanchSingle_lamp_"):
			lamps += 1
			if absf(part.position.x) < 0.7 or absf(part.position.z) < 2.4:
				_fail("Compacted RanchSingle lamp %s lost its damage position" % part.name)
				return false
		elif bool(part.get_meta("ranch_single_damage_body", false)):
			damage_bodies += 1
			if part.mesh.get_surface_count() != 1:
				_fail("RanchSingle damage body must remain one surface")
				return false
		elif part.name == &"RanchSingle_static_misc":
			static_groups += 1
	if spinning_wheels != 4 or fixed_wheels != 4 or lamps != 4 or damage_bodies != 1 or static_groups != 1:
		_fail("Unexpected RanchSingle groups spin=%d fixed=%d lamps=%d damage=%d static=%d" % [spinning_wheels, fixed_wheels, lamps, damage_bodies, static_groups])
		return false
	return true


func _merge_group(group_key: String, sources: Array) -> MeshInstance3D:
	var material_keys := PackedStringArray()
	var merged := ArrayMesh.new()
	var keep_source_transform := group_key.begins_with("lamp_")
	if group_key == "damage_body":
		var paint_arrays := _merge_damage_body_arrays(sources)
		if paint_arrays.is_empty():
			return null
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, paint_arrays)
		material_keys.append("paint")
	elif keep_source_transform:
		if sources.size() != 1:
			_fail("Independent RanchSingle lamp %s must have one source" % group_key)
			return null
		var source := sources[0].node as MeshInstance3D
		for surface_index in source.mesh.get_surface_count():
			material_keys.append(String(sources[0].material_key))
			merged.add_surface_from_arrays(_source_primitive_type(source.mesh, surface_index), source.mesh.surface_get_arrays(surface_index))
	else:
		for source_data in sources:
			var source := source_data.node as MeshInstance3D
			for surface_index in source.mesh.get_surface_count():
				material_keys.append(String(source_data.material_key))
				merged.add_surface_from_arrays(
					_source_primitive_type(source.mesh, surface_index),
					_transformed_arrays(source.mesh.surface_get_arrays(surface_index), source.transform)
				)
	var compact := MeshInstance3D.new()
	compact.name = "RanchSingle_%s" % group_key
	compact.mesh = merged
	compact.set_meta(SURFACE_KEYS_META, material_keys)
	if _all_same(material_keys):
		compact.set_meta(MATERIAL_KEY_META, material_keys[0])
	if keep_source_transform:
		compact.transform = (sources[0].node as MeshInstance3D).transform
	if group_key == "damage_body":
		compact.set_meta("ranch_single_damage_body", true)
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
				_fail("RanchSingle damage source is not triangle geometry")
				return []
			var arrays := _transformed_arrays(source.mesh.surface_get_arrays(surface_index), source.transform)
			var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			if source_normals.size() != source_vertices.size():
				_fail("RanchSingle damage source has incomplete normals")
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


func _source_primitive_type(mesh: Mesh, surface_index: int) -> int:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_primitive_type(surface_index)
	return Mesh.PRIMITIVE_TRIANGLES


func _all_same(values: PackedStringArray) -> bool:
	if values.is_empty():
		return false
	for value in values:
		if value != values[0]:
			return false
	return true


func _reset_model_cache() -> void:
	GEOMETRY_CACHE._models.erase(MODEL_PATH)
	GEOMETRY_CACHE._prepared.erase(MODEL_PATH)
	GEOMETRY_CACHE._miss_started_usec.erase(MODEL_PATH)


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


func _wheel_centres(model: Node3D) -> Array[Vector3]:
	var centres: Array[Vector3] = []
	for child in model.get_children():
		if child.has_meta("wheel_center"):
			var centre: Vector3 = child.get_meta("wheel_center")
			if not centres.has(centre):
				centres.append(centre)
	return centres


func _material_key(materials: Dictionary, material: Material) -> String:
	for key in materials:
		if materials[key] == material:
			return String(key)
	return ""


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


func _geometry_signature(model: Node3D, materials: Dictionary) -> int:
	var entries: Array[String] = []
	_collect_geometry(model, model, materials, Transform3D.IDENTITY, entries)
	entries.sort()
	return hash(entries)


func _collect_geometry(model: Node3D, node: Node, materials: Dictionary, parent_transform: Transform3D, entries: Array[String]) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var surface_keys: PackedStringArray = part.get_meta(SURFACE_KEYS_META, PackedStringArray())
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var material_key := String(surface_keys[surface_index]) if surface_index < surface_keys.size() else _material_key(materials, part.material_override)
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
		_collect_geometry(model, child, materials, world_transform, entries)


func _elapsed_ms(started_usec: int) -> float:
	return (Time.get_ticks_usec() - started_usec) / 1000.0


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
