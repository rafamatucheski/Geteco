extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const FLATBED := preload("res://prototypes/living_cast/models/AmericanFlatbedModel.gd")
const MODEL_PATH := "res://prototypes/living_cast/models/AmericanFlatbedModel.gd"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# A fresh Godot process starts with the model-local primitive cache empty. Erase
	# the packed presentation as well so this first sample exercises the real cold
	# constructor, while the second sample exercises VehicleGeometryCache restore.
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)

	var started := Time.get_ticks_usec()
	var cold: Node3D = FLATBED.new()
	root.add_child(cold)
	var cold_usec := Time.get_ticks_usec() - started
	var cold_signature := _geometry_signature(cold)

	var hits_before := CACHE.hits
	started = Time.get_ticks_usec()
	var warm: Node3D = FLATBED.new()
	root.add_child(warm)
	var warm_usec := Time.get_ticks_usec() - started

	check(CACHE.hits == hits_before + 1, "second flatbed restores from VehicleGeometryCache")
	check(_geometry_signature(warm) == cold_signature, "cached flatbed preserves exact 3D geometry and transforms")
	check(_mesh_count(cold) >= 100, "cold flatbed keeps its detailed 3D presentation")
	check(_mesh_count(warm) == _mesh_count(cold), "cached flatbed keeps every visible 3D part")
	check(_unique_mesh_count(cold) < _mesh_count(cold), "repeated flatbed parts reuse immutable mesh resources")
	check(_wheel_centers(cold).size() == 6, "cold flatbed exposes all six articulated wheel centers")
	check(_wheel_centers(warm).size() == 6, "cached flatbed preserves all six articulated wheel centers")

	var cold_paint := cold.get("paint") as StandardMaterial3D
	var warm_paint := warm.get("paint") as StandardMaterial3D
	check(cold_paint != null and warm_paint != null, "both flatbeds retain visible paint")
	if cold_paint != null and warm_paint != null:
		check(cold_paint != warm_paint, "cached flatbeds own independent paint materials")
		var expected := warm_paint.albedo_color
		cold_paint.albedo_color = Color.MAGENTA
		check(warm_paint.albedo_color == expected, "repainting one flatbed cannot alter another")

	var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
	check(rig.mount(warm), "cached flatbed remains mountable by the live wheel rig")
	check(rig.pivots.size() == 6 and rig.spinners.size() == 6, "live wheel rig mounts all six 3D wheels")

	print("AMERICAN_FLATBED_CACHE_RESULT cold_us=%d warm_us=%d speedup=%.2f meshes=%d unique_meshes=%d signature=%d failures=%d" % [
		cold_usec,
		warm_usec,
		float(cold_usec) / maxf(float(warm_usec), 1.0),
		_mesh_count(cold),
		_unique_mesh_count(cold),
		cold_signature,
		failures.size(),
	])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and node.visible else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count


func _unique_mesh_count(node: Node) -> int:
	var meshes := {}
	_collect_mesh_resources(node, meshes)
	return meshes.size()


func _collect_mesh_resources(node: Node, meshes: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		meshes[(node as MeshInstance3D).mesh.get_instance_id()] = true
	for child in node.get_children():
		_collect_mesh_resources(child, meshes)


func _wheel_centers(model: Node3D) -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for child in model.get_children():
		if child is MeshInstance3D and child.has_meta("wheel_center"):
			var center: Vector3 = child.get_meta("wheel_center")
			if not centers.has(center):
				centers.append(center)
	return centers


func _geometry_signature(model: Node3D) -> int:
	var parts: Array = []
	_collect_geometry(model, Transform3D.IDENTITY, parts)
	return hash(parts)


func _collect_geometry(node: Node, parent_transform: Transform3D, parts: Array) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var material := mesh_node.material_override as StandardMaterial3D
		parts.append([
			mesh_node.mesh.get_class() if mesh_node.mesh != null else "",
			mesh_node.mesh.get_aabb() if mesh_node.mesh != null else AABB(),
			world_transform,
			material.albedo_color if material != null else Color.TRANSPARENT,
			mesh_node.get_meta("wheel_center", Vector3.INF),
			mesh_node.get_meta("wheel_spins", false),
		])
	for child in node.get_children():
		_collect_geometry(child, world_transform, parts)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
