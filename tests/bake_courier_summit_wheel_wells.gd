extends SceneTree

## Build-time utility for the two regional vehicles covered by this contract.
## It saves only body meshes changed by VehicleWheelClearance; wheels and all
## runtime materials remain authored by each model script.

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")

const MODELS := [
	{
		"id": "courier_van",
		"path": "res://prototypes/living_cast/models/CourierVanModel.gd",
		"output": "res://prototypes/living_cast/models/CourierVanWheelWells.res",
	},
	{
		"id": "summit_suv",
		"path": "res://prototypes/living_cast/models/SummitSUVModel.gd",
		"output": "res://prototypes/living_cast/models/SummitSUVWheelWells.res",
	},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed := false
	for spec in MODELS:
		if not _bake(spec):
			failed = true
	quit(1 if failed else 0)


func _bake(spec: Dictionary) -> bool:
	var model_path := String(spec.path)
	_reset_model_cache(model_path)
	var script := load(model_path) as Script
	if script == null:
		push_error("Wheel-well bake could not load %s" % model_path)
		return false

	# Constructor deferral gives the baker an empty shell. build(false) is the
	# explicit model-local escape hatch that prevents an old resource from being
	# installed while its replacement is generated.
	CACHE._deferred_constructor_paths[model_path] = 1
	var model := script.new() as Node3D
	CACHE._deferred_constructor_paths.erase(model_path)
	if model == null or not model.has_method("wheel_well_source_structure_signature"):
		push_error("Wheel-well bake contract missing for %s" % model_path)
		if model != null:
			model.free()
		return false
	model.call("build", false)
	if model.get_child_count() == 0:
		push_error("Wheel-well bake produced no source geometry for %s" % model_path)
		model.free()
		return false
	# VehicleWheelRig reparents authored wheel pieces while preserving their
	# global transforms, so the source model must be inside the SceneTree just as
	# it is during regional prewarm.
	root.add_child(model)

	var source_signature := int(model.call("wheel_well_source_structure_signature"))
	var original_indices: Dictionary = {}
	var original_meshes: Dictionary = {}
	for child_index in model.get_child_count():
		var child := model.get_child(child_index)
		if child is MeshInstance3D:
			original_indices[child] = child_index
			original_meshes[child] = (child as MeshInstance3D).mesh

	var rig := WHEEL_RIG.new()
	if not rig.mount(model) or rig.pivots.size() != 4:
		push_error("Wheel-well bake failed to mount four wheels for %s" % model_path)
		model.free()
		return false

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
	resource.set_meta("model_id", String(spec.id))
	resource.set_meta("source_structure_signature", source_signature)
	resource.set_meta("meshes", baked)
	resource.set_meta("mesh_count", baked.size())
	resource.set_meta("wheel_clearance_signature", signature)
	resource.set_meta("visual_signature", _visual_signature(model, 5))
	resource.set_meta("triangle_count", _triangle_count(model))
	resource.set_meta("wheel_centres", rig.pivots.size())
	var error := ResourceSaver.save(resource, String(spec.output))
	print("COURIER_SUMMIT_WHEEL_WELL_BAKE id=%s path=%s meshes=%d source_signature=%d clearance_signature=%d visual_signature=%d triangles=%d error=%d" % [
		String(spec.id), String(spec.output), baked.size(), source_signature, signature,
		int(resource.get_meta("visual_signature", 0)), int(resource.get_meta("triangle_count", 0)), error,
	])
	model.free()
	return error == OK and not baked.is_empty() and signature != 0


func _reset_model_cache(model_path: String) -> void:
	CACHE._models.erase(model_path)
	CACHE._prepared.erase(model_path)
	CACHE._miss_started_usec.erase(model_path)
	CACHE._deferred_constructor_paths.erase(model_path)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()


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


func _visual_signature(model: Node3D, decimals: int) -> int:
	var triangles: Array[String] = []
	_collect_visual_triangles(model, Transform3D.IDENTITY, triangles, decimals)
	triangles.sort()
	return hash(triangles)


func _collect_visual_triangles(node: Node, parent_transform: Transform3D, triangles: Array[String], decimals: int) -> void:
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
					points.append(_point_key(point, decimals))
				points.sort()
				triangles.append("%.5f,%.5f,%.5f,%.5f:%s" % [color.r, color.g, color.b, color.a, "|".join(points)])
	for child in node.get_children():
		_collect_visual_triangles(child, world_transform, triangles, decimals)


func _point_key(point: Vector3, decimals: int) -> String:
	var scale := pow(10.0, decimals)
	return "%d,%d,%d" % [roundi(point.x * scale), roundi(point.y * scale), roundi(point.z * scale)]
