extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const MOTORCYCLES := [
	preload("res://cars/motorcycles/UrbanMotorcycle.gd"),
	preload("res://cars/motorcycles/SportMotorcycle.gd"),
	preload("res://cars/motorcycles/CruiserMotorcycle.gd"),
]
const PREWARM_MOTORCYCLES := [
	preload("res://cars/motorcycles/UrbanMotorcycle.gd"),
	preload("res://cars/motorcycles/SportMotorcycle.gd"),
	preload("res://cars/motorcycles/CruiserMotorcycle.gd"),
	preload("res://police/PoliceMotorcycleModel.gd"),
]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for model_script in PREWARM_MOTORCYCLES:
		_test_out_of_tree_prewarm_build(model_script)
	var total_cold_usec := 0
	var total_cached_usec := 0
	for model_script in MOTORCYCLES:
		var key: String = model_script.resource_path
		CACHE._models.erase(key)
		CACHE._prepared.erase(key)

		var started := Time.get_ticks_usec()
		var cold: Node3D = model_script.new()
		root.add_child(cold)
		var cold_usec := Time.get_ticks_usec() - started

		var hits_before := CACHE.hits
		started = Time.get_ticks_usec()
		var cached: Node3D = model_script.new()
		root.add_child(cached)
		var cached_usec := Time.get_ticks_usec() - started
		total_cold_usec += cold_usec
		total_cached_usec += cached_usec

		check(CACHE.hits == hits_before + 1, "%s restores from VehicleGeometryCache" % key)
		check(cached.get_meta("vehicle_kind", "") == "motorcycle", "%s keeps the motorcycle 3D contract" % key)
		check(cached.get_node_or_null("Rider") is Node3D, "%s restores a 3D rider" % key)
		check(cached.get_node_or_null("Stand") is Node3D, "%s restores the 3D stand" % key)
		check(cached.get("_arm_parts").size() == 2 and cached.get("_leg_parts").size() == 2, "%s rebinds the rider pose" % key)
		check(_mesh_count(cached) >= 25, "%s keeps detailed 3D geometry after restore" % key)
		check(_mesh_count(cached.get_node_or_null("Rider")) >= 8, "%s keeps rider body geometry after restore" % key)

		var cold_paint: StandardMaterial3D = cold.get("paint") as StandardMaterial3D
		var cached_paint: StandardMaterial3D = cached.get("paint") as StandardMaterial3D
		check(cold_paint != null and cached_paint != null, "%s keeps visible paint materials" % key)
		if cold_paint != null and cached_paint != null:
			check(cold_paint != cached_paint, "%s gives each instance an independent paint material" % key)
			var expected_color := cached_paint.albedo_color
			cold_paint.albedo_color = Color.MAGENTA
			check(cached_paint.albedo_color == expected_color, "%s cannot turn another cached motorcycle black/repaint it" % key)
			check(expected_color.v > 0.20 and expected_color.a > 0.99, "%s restored paint remains visible" % key)

		var jacket := cached.get("rider_jacket") as StandardMaterial3D
		var helmet := cached.get("rider_helmet") as StandardMaterial3D
		check(jacket != null and helmet != null, "%s rebinds rider materials" % key)
		if jacket != null and helmet != null:
			check(jacket.albedo_color.v > 0.15 and helmet.albedo_color.v > 0.40, "%s rider is not restored as a black silhouette" % key)

		# Mirror the common-model warmup: fuse static surfaces, flatten its temporary
		# wheel rig, recapture, then prove a live rig can still discover both wheels.
		var warmup_rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
		check(warmup_rig.mount(cached), "%s warmup finds authored wheel geometry" % key)
		preload("res://cars/VehicleMeshBatcher.gd").batch_model(cached)
		CACHE._flatten_warmup_wheels(cached, warmup_rig)
		cached.set_meta("vehicle_mesh_batched", true)
		CACHE.capture(cached, true)
		var prepared: Node3D = model_script.new()
		root.add_child(prepared)
		var live_rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
		check(live_rig.mount(prepared), "%s cached warmup remains mountable at runtime" % key)
		check(live_rig.pivots.size() == 2 and live_rig.spinners.size() == 2, "%s restores two articulated 3D wheels" % key)
		check(prepared.get_meta("vehicle_mesh_batched", false), "%s restores the pre-batched presentation" % key)
		check(_mesh_count(prepared.get_node_or_null("Rider")) >= 6, "%s pre-batched cache keeps rider geometry" % key)

		print("MOTORCYCLE_CACHE_SAMPLE path=%s cold_us=%d cached_us=%d meshes=%d rider_meshes=%d" % [
			key, cold_usec, cached_usec, _mesh_count(cached), _mesh_count(cached.get_node_or_null("Rider"))
		])
		cold.free()
		cached.free()
		prepared.free()

	var stats := CACHE.telemetry()
	check(int(stats.misses) >= MOTORCYCLES.size(), "Telemetry records cold cache misses")
	check(int(stats.cold_builds) >= MOTORCYCLES.size(), "Telemetry records completed cold builds")
	check(int(stats.cold_build_usec) > 0 and int(stats.restore_usec) > 0 and int(stats.capture_usec) > 0, "Telemetry exposes cumulative cache costs")
	print("MOTORCYCLE_CACHE_RESULT cold_us=%d cached_us=%d speedup=%.2f cache_hits=%d failures=%d" % [
		total_cold_usec,
		total_cached_usec,
		float(total_cold_usec) / maxf(float(total_cached_usec), 1.0),
		CACHE.hits,
		failures.size(),
	])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _test_out_of_tree_prewarm_build(model_script: Script) -> void:
	var key := String(model_script.resource_path)
	CACHE._models.erase(key)
	CACHE._prepared.erase(key)
	CACHE._operationally_warmed_paths.erase(key)
	CACHE._regional_capture_suppressed_paths[key] = 1
	var model := model_script.new() as Node3D
	check(model != null and not model.is_inside_tree(), "%s creates an out-of-tree prewarm shell" % key)
	if model == null:
		CACHE._regional_capture_suppressed_paths.erase(key)
		return
	model.call("build")
	CACHE._regional_capture_suppressed_paths.erase(key)
	check(not CACHE._models.has(key) and not CACHE._prepared.has(key), "%s out-of-tree build cannot publish before atomic commit" % key)
	check(model.get_node_or_null("Rider") is Node3D, "%s out-of-tree build keeps its rider hierarchy" % key)
	check(model.get_node_or_null("Stand") is Node3D, "%s out-of-tree build keeps its stand hierarchy" % key)
	check(_mesh_count(model.get_node_or_null("Rider/RiderArmL/Upper")) > 0, "%s preserves nested arm geometry without global transforms" % key)
	check(_mesh_count(model.get_node_or_null("Rider/RiderLegL/Upper")) > 0, "%s preserves nested leg geometry without global transforms" % key)
	check(_mesh_count(model.get_node_or_null("Stand")) > 0, "%s preserves stand geometry without global transforms" % key)
	var stats := _model_space_geometry_stats(model)
	var bounds_size: Vector3 = stats.max_point - stats.min_point
	var min_abs: Vector3 = stats.min_point.abs()
	var max_abs: Vector3 = stats.max_point.abs()
	var furthest := maxf(maxf(min_abs.x, min_abs.y), maxf(min_abs.z, maxf(max_abs.x, maxf(max_abs.y, max_abs.z))))
	check(int(stats.mesh_count) >= 25, "%s out-of-tree build keeps detailed 3D geometry" % key)
	check(stats.min_point.is_finite() and stats.max_point.is_finite(), "%s out-of-tree geometry has finite local bounds" % key)
	check(bounds_size.x > 0.5 and bounds_size.y > 0.8 and bounds_size.z > 1.3, "%s out-of-tree geometry retains motorcycle-scale bounds" % key)
	check(furthest < 10.0, "%s out-of-tree geometry is not teleported away" % key)
	model.free()


func _model_space_geometry_stats(model: Node3D) -> Dictionary:
	var stats := {
		"mesh_count": 0,
		"min_point": Vector3(INF, INF, INF),
		"max_point": Vector3(-INF, -INF, -INF),
	}
	_collect_model_space_geometry(model, Transform3D.IDENTITY, stats)
	return stats


func _collect_model_space_geometry(node: Node, parent_transform: Transform3D, stats: Dictionary) -> void:
	var node_transform := parent_transform
	if node is Node3D:
		node_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		stats.mesh_count = int(stats.mesh_count) + 1
		var bounds := (node as MeshInstance3D).mesh.get_aabb()
		for x in [0.0, 1.0]:
			for y in [0.0, 1.0]:
				for z in [0.0, 1.0]:
					var local_point := bounds.position + bounds.size * Vector3(x, y, z)
					var point := node_transform * local_point
					var min_point: Vector3 = stats.min_point
					var max_point: Vector3 = stats.max_point
					stats.min_point = min_point.min(point)
					stats.max_point = max_point.max(point)
	for child in node.get_children():
		_collect_model_space_geometry(child, node_transform, stats)


func _mesh_count(node: Node) -> int:
	if not is_instance_valid(node):
		return 0
	var count := 1 if node is MeshInstance3D and node.visible else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
