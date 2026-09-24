extends SceneTree

## Rebuilds the exact ArcticJeep authorship and stores its post-clearance,
## post-batching representation. This is a build tool, never a gameplay path.

const MODEL_PATH := "res://prototypes/living_cast/models/ArcticJeepModel.gd"
const OUTPUT_PATH := "res://prototypes/living_cast/models/ArcticJeepPreparedGeometry.scn"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const MATERIAL_ROLE_META := &"arctic_jeep_material_role"
const SURFACE_ROLES_META := &"arctic_jeep_surface_material_roles"
const CONTRACT_VERSION := 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset_caches()
	var fixture := Node3D.new()
	fixture.name = "ArcticJeepPreparedGeometryBuilder"
	root.add_child(fixture)
	var script := load(MODEL_PATH) as Script
	if script == null:
		_fail("Could not load ArcticJeep source")
		return
	var model := script.new() as Node3D
	if model == null:
		_fail("Could not instantiate ArcticJeep source")
		return
	for child in model.get_children():
		model.remove_child(child)
		child.free()
	(model.get("materials") as Dictionary).clear()
	model.set("paint", null)
	(model.get("originals") as Dictionary).clear()
	(model.get("lamp_sources") as Dictionary).clear()
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
		_fail("ArcticJeep source has no wheel markers")
		return
	var mount_usec := Time.get_ticks_usec() - mount_started
	var batch_started := Time.get_ticks_usec()
	var removed := BATCHER.batch_model(model)
	var batch_usec := Time.get_ticks_usec() - batch_started
	_flatten_wheels(model, rig)
	model.set_meta("vehicle_mesh_batched", true)

	var materials: Dictionary = model.get("materials")
	var role_counts: Dictionary = {}
	var wheel_centres: Array[Vector3] = []
	var wheel_flags: Dictionary = {}
	var headlamps := 0
	for child in model.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null or part.mesh.get_surface_count() != 1:
			_fail("Prepared ArcticJeep child is not a single-surface mesh: %s" % child.name)
			return
		var role := _material_role(materials, part.material_override)
		if role == &"":
			_fail("Prepared ArcticJeep child has no runtime material role: %s" % child.name)
			return
		part.set_meta(MATERIAL_ROLE_META, role)
		role_counts[role] = int(role_counts.get(role, 0)) + 1
		if role == &"headlight":
			headlamps += 1
		if part.has_meta("wheel_center"):
			var centre: Vector3 = part.get_meta("wheel_center")
			if not wheel_centres.has(centre):
				wheel_centres.append(centre)
			var flags := int(wheel_flags.get(centre, 0))
			if bool(part.get_meta("wheel_spins", false)):
				flags |= 1
			else:
				flags |= 2
			wheel_flags[centre] = flags
	if wheel_centres.size() != 4 or headlamps != 2:
		_fail("Prepared ArcticJeep lost wheels or headlamps: wheels=%d headlamps=%d" % [wheel_centres.size(), headlamps])
		return
	for centre in wheel_flags:
		if int(wheel_flags[centre]) != 3:
			_fail("Prepared ArcticJeep wheel lost spinning/fixed geometry: %s" % centre)
			return
	if not _compact_prepared_geometry(model):
		return

	var signature := _geometry_signature(model, materials)
	var prepared_meshes := _mesh_count(model)
	var prepared_triangles := _triangle_count(model)
	var clearance_signature := int(model.get_meta("vehicle_wheel_clearance_signature", 0))
	if signature == 0 or prepared_meshes <= 0 or prepared_triangles <= 0 or clearance_signature == 0:
		_fail("Prepared ArcticJeep contract is incomplete")
		return

	var baked_root := Node3D.new()
	baked_root.name = "ArcticJeepPreparedGeometry"
	for metadata in model.get_meta_list():
		baked_root.set_meta(metadata, model.get_meta(metadata))
	baked_root.set_meta("arctic_jeep_prepared_contract_version", CONTRACT_VERSION)
	baked_root.set_meta("arctic_jeep_prepared_geometry_signature", signature)
	baked_root.set_meta("arctic_jeep_prepared_meshes", prepared_meshes)
	baked_root.set_meta("arctic_jeep_prepared_triangles", prepared_triangles)
	baked_root.set_meta("arctic_jeep_material_role_counts", role_counts)
	for child in model.get_children():
		var part := child as MeshInstance3D
		part.material_override = null
		for surface_index in part.mesh.get_surface_count():
			part.set_surface_override_material(surface_index, null)
		_clear_owner(part)
		model.remove_child(part)
		baked_root.add_child(part)
		_set_owner_recursive(part, baked_root)

	var packed := PackedScene.new()
	var pack_error := packed.pack(baked_root)
	if pack_error != OK:
		_fail("ArcticJeep PackedScene.pack failed: %s" % error_string(pack_error))
		return
	var save_error := ResourceSaver.save(packed, OUTPUT_PATH)
	if save_error != OK:
		_fail("ArcticJeep prepared resource save failed: %s" % error_string(save_error))
		return
	print("ARCTIC_JEEP_PREPARED_GEOMETRY ", JSON.stringify({
		"path": OUTPUT_PATH,
		"authored_meshes": authored_meshes,
		"authored_triangles": authored_triangles,
		"mount_usec": mount_usec,
		"batch_usec": batch_usec,
		"batched_removed": removed,
		"prepared_meshes": prepared_meshes,
		"prepared_triangles": prepared_triangles,
		"clearance_signature": clearance_signature,
		"geometry_signature": signature,
		"material_role_counts": role_counts,
		"wheels": wheel_centres.size(),
		"headlamps": headlamps,
	}))
	baked_root.free()
	model.free()
	fixture.free()
	_reset_caches()
	quit(0)


func _material_role(materials: Dictionary, material: Material) -> StringName:
	for role in materials:
		if materials[role] == material:
			return StringName(role)
	return &""


func _compact_prepared_geometry(model: Node3D) -> bool:
	var groups: Dictionary = {}
	var lamp_index := 0
	for child in model.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			continue
		var role := StringName(part.get_meta(MATERIAL_ROLE_META, &""))
		var group_key := "static_misc"
		if role == &"headlight":
			group_key = "lamp_%02d" % lamp_index
			lamp_index += 1
		elif part.has_meta("wheel_center"):
			var centre: Vector3 = part.get_meta("wheel_center")
			var motion := "spin" if bool(part.get_meta("wheel_spins", false)) else "fixed"
			group_key = "wheel_%.3f_%.3f_%s" % [centre.x, centre.z, motion]
		elif role == &"paint":
			group_key = "damage_body"
		if not groups.has(group_key):
			groups[group_key] = []
		groups[group_key].append(part)
	for group_key in groups:
		var compact := _merge_group(String(group_key), groups[group_key] as Array)
		if compact == null:
			return false
		model.add_child(compact)
		for source in groups[group_key]:
			model.remove_child(source)
			source.free()
	return _validate_compacted_geometry(model)


func _merge_group(group_key: String, sources: Array) -> MeshInstance3D:
	var keep_transform := group_key.begins_with("lamp_")
	if keep_transform and sources.size() != 1:
		_fail("ArcticJeep lamp group must retain one independent source")
		return null
	var merged := ArrayMesh.new()
	var surface_roles := PackedStringArray()
	var surface_materials: Array[Material] = []
	for source_value in sources:
		var source := source_value as MeshInstance3D
		var role := StringName(source.get_meta(MATERIAL_ROLE_META, &""))
		for surface_index in source.mesh.get_surface_count():
			var arrays := source.mesh.surface_get_arrays(surface_index)
			if not keep_transform:
				arrays = _transformed_arrays(arrays, source.transform)
			var primitive := (source.mesh as ArrayMesh).surface_get_primitive_type(surface_index) if source.mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
			merged.add_surface_from_arrays(primitive, arrays)
			surface_roles.append(String(role))
			surface_materials.append(source.material_override)
	var compact := MeshInstance3D.new()
	compact.name = "ArcticJeep_%s" % group_key
	compact.mesh = merged
	compact.set_meta(SURFACE_ROLES_META, surface_roles)
	if _all_same(surface_roles):
		compact.set_meta(MATERIAL_ROLE_META, StringName(surface_roles[0]))
		compact.material_override = surface_materials[0]
	else:
		for surface_index in surface_materials.size():
			compact.set_surface_override_material(surface_index, surface_materials[surface_index])
	if keep_transform:
		compact.transform = (sources[0] as MeshInstance3D).transform
	if group_key == "damage_body":
		compact.set_meta("arctic_jeep_damage_body", true)
	if group_key.begins_with("wheel_"):
		var source := sources[0] as MeshInstance3D
		for metadata in source.get_meta_list():
			if metadata in [&"wheel_center", &"wheel_spins", &"wheel_radius", &"wheel_style"]:
				compact.set_meta(metadata, source.get_meta(metadata))
	return compact


func _validate_compacted_geometry(model: Node3D) -> bool:
	var wheel_flags: Dictionary = {}
	var lamps := 0
	var damage_bodies := 0
	var static_groups := 0
	for child in model.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			return false
		var roles: PackedStringArray = part.get_meta(SURFACE_ROLES_META, PackedStringArray())
		if roles.size() != part.mesh.get_surface_count():
			_fail("Compacted ArcticJeep group lost surface material roles")
			return false
		if String(part.name).begins_with("ArcticJeep_lamp_"):
			lamps += 1
		elif part.has_meta("wheel_center"):
			var centre: Vector3 = part.get_meta("wheel_center")
			var flags := int(wheel_flags.get(centre, 0))
			if bool(part.get_meta("wheel_spins", false)):
				flags |= 1
			else:
				flags |= 2
			wheel_flags[centre] = flags
		elif bool(part.get_meta("arctic_jeep_damage_body", false)):
			damage_bodies += 1
		elif part.name == &"ArcticJeep_static_misc":
			static_groups += 1
	if model.get_child_count() != 12 or wheel_flags.size() != 4 or lamps != 2 or damage_bodies != 1 or static_groups != 1:
		_fail("Unexpected compact ArcticJeep groups meshes=%d wheels=%d lamps=%d damage=%d static=%d" % [model.get_child_count(), wheel_flags.size(), lamps, damage_bodies, static_groups])
		return false
	for centre in wheel_flags:
		if int(wheel_flags[centre]) != 3:
			return false
	return true


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
		var surface_roles: PackedStringArray = part.get_meta(SURFACE_ROLES_META, PackedStringArray())
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var role := StringName(surface_roles[surface_index]) if surface_index < surface_roles.size() else _material_role(materials, part.get_active_material(surface_index))
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
				entries.append("%s:%s" % [role, "|".join(points)])
	for child in node.get_children():
		_collect_geometry(model, child, materials, world_transform, entries)


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


func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children():
		_set_owner_recursive(child, owner_node)


func _reset_caches() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
