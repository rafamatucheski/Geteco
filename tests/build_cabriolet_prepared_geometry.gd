extends SceneTree

## Regenerates Cabriolet's exact post-clearance, post-batching presentation.
## The packed scene contains immutable meshes/transforms/metadata only. Live
## instances rebuild independent materials and damage dictionaries normally.

const MODEL_PATH := "res://prototypes/living_cast/CabrioletModel.gd"
const OUTPUT_PATH := "res://prototypes/living_cast/CabrioletPreparedGeometry.scn"
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const MESH_BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const MATERIAL_KEY_META := &"cabriolet_material_key"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fixture := Node3D.new()
	fixture.name = "CabrioletPreparedGeometryBuilder"
	root.add_child(fixture)
	var script := load(MODEL_PATH) as Script
	if script == null:
		_fail("Could not load Cabriolet source")
		return
	var model := script.new() as Node3D
	fixture.add_child(model)
	await process_frame
	var authored_meshes := _mesh_count(model)
	var authored_triangles := _triangle_count(model)

	var mount_started := Time.get_ticks_usec()
	var rig := WHEEL_RIG.new()
	if not rig.mount(model):
		_fail("Cabriolet source has no wheel markers")
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
	var baked_root := Node3D.new()
	baked_root.name = "CabrioletPreparedGeometry"
	baked_root.set_meta("vehicle_wheel_clearance_signature", clearance_signature)
	for child in model.get_children():
		_clear_owner(child)
		model.remove_child(child)
		baked_root.add_child(child)
		_set_owner_recursive(child, baked_root)
		var part := child as MeshInstance3D
		if part != null:
			var material_key := _material_key(materials, part.material_override)
			if material_key.is_empty():
				_fail("Prepared mesh %s has no stable material key" % part.name)
				return
			part.set_meta(MATERIAL_KEY_META, material_key)
			part.material_override = null

	var prepared_meshes := _mesh_count(baked_root)
	var prepared_triangles := _triangle_count(baked_root)
	var signature := _geometry_signature(baked_root)
	baked_root.set_meta("cabriolet_prepared_geometry_signature", signature)
	var packed := PackedScene.new()
	var pack_error := packed.pack(baked_root)
	if pack_error != OK:
		_fail("PackedScene.pack failed: %s" % error_string(pack_error))
		return
	var save_error := ResourceSaver.save(packed, OUTPUT_PATH)
	if save_error != OK:
		_fail("ResourceSaver.save failed: %s" % error_string(save_error))
		return

	print("CABRIOLET_PREPARED_GEOMETRY path=%s authored_meshes=%d authored_triangles=%d mount_ms=%.3f batch_ms=%.3f removed=%d prepared_meshes=%d prepared_triangles=%d clearance_signature=%d geometry_signature=%d" % [
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
		var material_key := String(part.get_meta(MATERIAL_KEY_META, ""))
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
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
