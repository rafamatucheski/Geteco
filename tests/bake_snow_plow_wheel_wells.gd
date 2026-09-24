extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/models/SnowPlowModel.gd"
const OUTPUT_PATH := "res://prototypes/living_cast/models/SnowPlowWheelWells.res"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()
	var script := load(MODEL_PATH) as Script
	if script == null:
		push_error("SnowPlow script failed to load")
		quit(1)
		return
	var model := script.new() as Node3D
	for child in model.get_children():
		model.remove_child(child)
		child.free()
	model.materials.clear()
	model.paint = null
	model._build_procedural_geometry(false)
	root.add_child(model)
	var original_indices: Dictionary = {}
	var original_meshes: Dictionary = {}
	for child_index in model.get_child_count():
		var child := model.get_child(child_index)
		if child is MeshInstance3D:
			original_indices[child] = child_index
			original_meshes[child] = (child as MeshInstance3D).mesh
	var rig := WHEEL_RIG.new()
	if not rig.mount(model):
		push_error("SnowPlow wheel rig failed to mount during bake")
		quit(1)
		return
	var baked: Dictionary = {}
	for child in original_indices:
		if not is_instance_valid(child) or child.get_parent() != model:
			continue
		var part := child as MeshInstance3D
		if part.mesh != original_meshes[child]:
			baked[int(original_indices[child])] = part.mesh
	var signature := int(model.get_meta("vehicle_wheel_clearance_signature", 0))
	var resource := Resource.new()
	resource.set_meta("format_version", 1)
	resource.set_meta("model_id", "snow_plow_truck")
	resource.set_meta("meshes", baked)
	resource.set_meta("mesh_count", baked.size())
	resource.set_meta("wheel_clearance_signature", signature)
	resource.set_meta("visual_signature", _visual_signature(model))
	resource.set_meta("triangle_count", _triangle_count(model))
	var error := ResourceSaver.save(resource, OUTPUT_PATH)
	print("SNOW_PLOW_WHEEL_WELL_BAKE path=%s meshes=%d signature=%d visual=%d triangles=%d error=%d" % [
		OUTPUT_PATH, baked.size(), signature, _visual_signature(model), _triangle_count(model), error,
	])
	model.free()
	quit(0 if error == OK and not baked.is_empty() else 1)


func _triangle_count(parent: Node) -> int:
	var count := 0
	if parent is MeshInstance3D:
		var mesh := (parent as MeshInstance3D).mesh
		if mesh != null:
			for surface_index in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface_index)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
				count += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	for child in parent.get_children():
		count += _triangle_count(child)
	return count


func _visual_signature(model: Node3D) -> int:
	var triangles: Array[String] = []
	_collect_visual_triangles(model, Transform3D.IDENTITY, triangles)
	triangles.sort()
	return hash(triangles)


func _collect_visual_triangles(node: Node, parent_transform: Transform3D, triangles: Array[String]) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var material := part.material_override as StandardMaterial3D
		var color := material.albedo_color if material != null else Color.TRANSPARENT
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
				triangles.append("%.5f,%.5f,%.5f,%.5f:%s" % [color.r, color.g, color.b, color.a, "|".join(points)])
	for child in node.get_children():
		_collect_visual_triangles(child, world_transform, triangles)
