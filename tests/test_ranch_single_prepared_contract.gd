extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/models/RanchSingleModel.gd"
const GEOMETRY_CACHE := preload("res://cars/VehicleGeometryCache.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const WHEEL_CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const MESH_BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const EXPECTED_SIGNATURE := 2058053124
const EXPECTED_MESHES := 14
const EXPECTED_TRIANGLES := 13800

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset_caches()
	var stage := Node3D.new()
	stage.name = "RanchSinglePreparedContract"
	root.add_child(stage)
	var script := load(MODEL_PATH) as Script
	_check(script != null, "RanchSingle script and prepared resource load")
	if script == null:
		_finish({})
		return
	var model := script.new() as Node3D
	stage.add_child(model)
	_check(model.get_meta("ranch_single_geometry_source", &"") == &"prepared", "Runtime accepts the exact RanchSingle prepared resource")
	_check(int(model.get_meta("ranch_single_prepared_geometry_signature", 0)) == EXPECTED_SIGNATURE, "Runtime publishes the RanchSingle prepared signature")
	_check(_mesh_count(model) == EXPECTED_MESHES, "Prepared RanchSingle preserves 14 operational meshes")
	_check(_triangle_count(model) == EXPECTED_TRIANGLES, "Prepared RanchSingle preserves 13,800 triangles")
	_check(_visual_signature(model) == EXPECTED_SIGNATURE, "Prepared RanchSingle preserves exact triangle/material geometry")
	_check(_wheel_centres(model).size() == 4, "Prepared RanchSingle preserves four authored wheel centres")

	var prepared_hits_before := WHEEL_CLEARANCE.prepared_hits
	var rig := WHEEL_RIG.new()
	var mounted: bool = rig.mount(model)
	_check(mounted and rig.pivots.size() == 4, "Prepared RanchSingle mounts four articulated wheels")
	_check(WHEEL_CLEARANCE.prepared_hits == prepared_hits_before + 1, "Prepared RanchSingle reuses baked wheel clearance")
	var batched_removed: int = MESH_BATCHER.batch_model(model)
	_check(batched_removed == 0, "Prepared RanchSingle does not repeat mesh fusion")
	_check(_visual_signature(model) == EXPECTED_SIGNATURE, "Wheel mount and batching preserve exact RanchSingle presentation")

	var originals := model.get("originals") as Dictionary
	_check(not originals.is_empty(), "Damage system captures prepared painted bodywork")
	var lamp_sources := model.get("lamp_sources") as Dictionary
	_check(lamp_sources.size() == 4, "Damage system captures two headlamps and two taillamps")
	var lamp_materials: Dictionary = {}
	for lamp in lamp_sources:
		lamp_materials[lamp] = (lamp as MeshInstance3D).material_override
	model.call("apply_impact", Vector3(0.78, 0.82, -2.48), Vector3(-1.0, 0.0, 0.0), 12.0)
	_check(int(model.get("impact_count")) == 1, "Prepared RanchSingle accepts body damage")
	var broken_lamps := model.get("broken_lamps") as Array
	_check(bool(broken_lamps[1]), "Localized impact breaks the right RanchSingle headlamp")
	var changed_lamps := 0
	for lamp in lamp_materials:
		if is_instance_valid(lamp) and (lamp as MeshInstance3D).material_override != lamp_materials[lamp]:
			changed_lamps += 1
	_check(changed_lamps == 1, "Localized impact changes exactly one lamp material")
	model.call("char_body")
	_check(bool(model.get("is_charred")), "Prepared RanchSingle supports charring")
	model.call("repair")
	_check(int(model.get("impact_count")) == 0 and not bool(model.get("is_charred")), "Repair clears RanchSingle body and char damage")
	var lamps_restored := true
	for lamp in lamp_materials:
		if is_instance_valid(lamp) and (lamp as MeshInstance3D).material_override != lamp_materials[lamp]:
			lamps_restored = false
	_check(lamps_restored, "Repair restores every RanchSingle lamp material")
	_check(_visual_signature(model) == EXPECTED_SIGNATURE, "Repair restores exact RanchSingle geometry")

	var steering_before := rig.steering_angle
	var spinner_before: float = rig.spinners[0].rotation.x
	rig.update(1.0 / 60.0, 8.0, 0.0, 0.3)
	_check(rig.steering_angle != steering_before, "Prepared RanchSingle front wheels steer")
	_check(not is_equal_approx(rig.spinners[0].rotation.x, spinner_before), "Prepared RanchSingle wheels spin")

	var sibling := script.new() as Node3D
	stage.add_child(sibling)
	var paint := model.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	_check(paint != null and sibling_paint != null and paint != sibling_paint, "Prepared RanchSingle paint remains independent per vehicle")
	if paint != null and sibling_paint != null:
		var sibling_color := sibling_paint.albedo_color
		paint.albedo_color = Color.MAGENTA
		_check(sibling_paint.albedo_color == sibling_color, "Repainting one RanchSingle cannot recolor another")
	_check(_mesh_count(sibling) == EXPECTED_MESHES, "Cache restore cannot duplicate RanchSingle geometry")
	_check(_visual_signature(sibling) == EXPECTED_SIGNATURE, "Cache restore rebinds every RanchSingle surface material")

	var result := {
		"signature": EXPECTED_SIGNATURE,
		"meshes": _mesh_count(model),
		"triangles": _triangle_count(model),
		"wheels": rig.pivots.size(),
		"lamps": lamp_sources.size(),
		"batched_removed": batched_removed,
		"cache_hits": GEOMETRY_CACHE.hits,
	}
	model.free()
	sibling.free()
	stage.free()
	_finish(result)


func _reset_caches() -> void:
	GEOMETRY_CACHE._models.erase(MODEL_PATH)
	GEOMETRY_CACHE._prepared.erase(MODEL_PATH)
	GEOMETRY_CACHE._miss_started_usec.erase(MODEL_PATH)
	WHEEL_CLEARANCE._cache.clear()
	WHEEL_CLEARANCE._content_keys.clear()
	MESH_BATCHER._mesh_cache.clear()
	MESH_BATCHER._format_cache.clear()
	MESH_BATCHER._primitive_formats.clear()


func _wheel_centres(model: Node3D) -> Array[Vector3]:
	var centres: Array[Vector3] = []
	for child in model.get_children():
		if child.has_meta("wheel_center"):
			var centre: Vector3 = child.get_meta("wheel_center")
			if not centres.has(centre):
				centres.append(centre)
	return centres


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


func _visual_signature(model: Node3D) -> int:
	var entries: Array[String] = []
	_collect_visual(model, model, Transform3D.IDENTITY, entries)
	entries.sort()
	return hash(entries)


func _collect_visual(model: Node3D, node: Node, parent_transform: Transform3D, entries: Array[String]) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var material_key := _material_key(model, part.get_active_material(surface_index))
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
		_collect_visual(model, child, world_transform, entries)


func _material_key(model: Node3D, material: Material) -> String:
	var materials: Dictionary = model.get("materials")
	for key in materials:
		if materials[key] == material:
			return String(key)
	return "unknown"


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(result: Dictionary) -> void:
	result["failures"] = failures
	print("RANCH_SINGLE_PREPARED_CONTRACT ", JSON.stringify(result))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)
