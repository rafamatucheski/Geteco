extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/models/ValeCrossoverModel.gd"
const WHEEL_WELL_RESOURCE_PATH := "res://prototypes/living_cast/models/ValeCrossoverWheelWells.res"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const FRAME_BUDGET_MS := 1000.0 / 60.0
const EXPECTED_VISUAL_SIGNATURE := 3459121497
const EXPECTED_TRIANGLES := 17209
const RENDERED_COLD_BASELINE_MS := 2163.55
const MAX_COLD_END_TO_END_MS := RENDERED_COLD_BASELINE_MS * 0.10
const MAX_COLD_PREWARM_MS := 150.0

var failures: Array[String] = []
var fixture: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	fixture = SubViewport.new()
	fixture.name = "ValeCrossoverColdConstructionFixture"
	fixture.size = Vector2i(256, 256)
	fixture.own_world_3d = true
	fixture.transparent_bg = true
	fixture.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(fixture)

	check(ResourceLoader.exists(WHEEL_WELL_RESOURCE_PATH, "Resource"), "Vale baked wheel-well resource exists")
	if not ResourceLoader.exists(WHEEL_WELL_RESOURCE_PATH, "Resource"):
		_finish({"error": "wheel_well_resource_missing"})
		return
	var wheel_well_resource := load(WHEEL_WELL_RESOURCE_PATH) as Resource
	check(wheel_well_resource != null, "Vale baked wheel-well resource loads")
	if wheel_well_resource == null:
		_finish({"error": "wheel_well_resource_corrupt"})
		return
	var resource_meshes: Dictionary = wheel_well_resource.get_meta("meshes", {})
	check(int(wheel_well_resource.get_meta("format_version", 0)) == 1, "Vale wheel-well resource format version is supported")
	check(String(wheel_well_resource.get_meta("model_id", "")) == "vale_crossover", "Vale wheel-well resource belongs to the correct model")
	check(int(wheel_well_resource.get_meta("visual_signature", 0)) == EXPECTED_VISUAL_SIGNATURE, "Vale wheel-well resource declares the exact visual signature")
	check(int(wheel_well_resource.get_meta("triangle_count", 0)) == EXPECTED_TRIANGLES, "Vale wheel-well resource declares the exact triangle count")
	check(int(wheel_well_resource.get_meta("mesh_count", 0)) == 54, "Vale wheel-well resource contains all 54 carved meshes")
	check(resource_meshes.size() == 54, "Vale wheel-well resource mesh map is complete")
	for child_index in resource_meshes:
		check(int(child_index) >= 0 and resource_meshes[child_index] is ArrayMesh, "Vale wheel-well resource entry %s is a valid ArrayMesh" % child_index)

	var started := Time.get_ticks_usec()
	var script := load(MODEL_PATH) as Script
	var script_load_ms := _elapsed_ms(started)
	check(script != null and script.can_instantiate(), "Vale Crossover model script loads and can instantiate")
	if script == null or not script.can_instantiate():
		_finish({"error": "load_failed"})
		return

	_reset_all_caches()
	started = Time.get_ticks_usec()
	var cold := script.new() as Node3D
	var constructor_ms := _elapsed_ms(started)
	fixture.add_child(cold)
	var raw_signature := _visual_signature(cold)
	var raw_triangles := _triangle_count(cold)
	var raw_meshes := _mesh_count(cold)
	var raw_unique_meshes := _unique_mesh_count(cold)
	var cold_paint := cold.get("paint") as StandardMaterial3D
	var wheel_centers := _wheel_centers(cold)
	check(wheel_centers.size() == 4, "Vale keeps exactly four authored 3D wheel centres")
	check(cold_paint != null and cold_paint.albedo_color.v > 0.15, "Vale cold paint remains visible instead of black")
	check(raw_signature == EXPECTED_VISUAL_SIGNATURE, "Vale raw authored triangle/material signature remains exact")
	check(raw_triangles == EXPECTED_TRIANGLES, "Vale raw authored triangle count remains exact")
	check(raw_unique_meshes < raw_meshes, "Vale cold construction reuses immutable mesh resources")

	started = Time.get_ticks_usec()
	var cold_rig := WHEEL_RIG.new()
	var mounted := cold_rig.mount(cold)
	var mount_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var removed := BATCHER.batch_model(cold)
	var batch_ms := _elapsed_ms(started)
	var prepared_signature := _visual_signature(cold)
	var prepared_triangles := _triangle_count(cold)
	var cold_first_presented_ms = null
	if DisplayServer.get_name() != "headless":
		started = Time.get_ticks_usec()
		fixture.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		cold_first_presented_ms = _elapsed_ms(started)
	check(mounted and cold_rig.pivots.size() == 4, "Vale mounts four articulated wheel rigs")
	check(removed > 0, "Vale exercises the real static mesh batching path")
	check(cold.has_meta("vehicle_wheel_clearance_signature"), "Vale prepared form retains wheel-well metadata")
	check(int(cold.get_meta("vehicle_wheel_clearance_signature")) == int(wheel_well_resource.get_meta("wheel_clearance_signature")), "Vale runtime wheel-well signature matches its authored resource")
	check(prepared_signature == EXPECTED_VISUAL_SIGNATURE, "Vale prepared triangle/material signature remains exact")
	check(prepared_triangles == EXPECTED_TRIANGLES, "Vale prepared triangle count remains exact")
	check(script_load_ms + constructor_ms + mount_ms + batch_ms < MAX_COLD_END_TO_END_MS, "Vale cold end-to-end path must remain at least 90%% below the %.2f ms rendered baseline, got %.3f ms" % [RENDERED_COLD_BASELINE_MS, script_load_ms + constructor_ms + mount_ms + batch_ms])
	cold.free()

	_reset_all_caches()
	started = Time.get_ticks_usec()
	var report: Dictionary = CACHE._prepare_model_template(MODEL_PATH, fixture)
	var prewarm_ms := _elapsed_ms(started)
	check(bool(report.get("wheel_mounted", false)), "Vale prewarm mounts its wheels")
	check(int(report.get("batched_removed", 0)) > 0, "Vale prewarm batches its static geometry")
	check(bool(report.get("captured", false)), "Vale prewarm captures a prepared presentation template")
	check(prewarm_ms < MAX_COLD_PREWARM_MS, "Vale clean-cache prewarm stays below %.1f ms, got %.3f ms" % [MAX_COLD_PREWARM_MS, prewarm_ms])
	check(script_load_ms + prewarm_ms < MAX_COLD_PREWARM_MS, "Vale first script load plus clean-cache prewarm stays below %.1f ms, got %.3f ms" % [MAX_COLD_PREWARM_MS, script_load_ms + prewarm_ms])

	started = Time.get_ticks_usec()
	var live := script.new() as Node3D
	fixture.add_child(live)
	var restore_add_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var live_rig := WHEEL_RIG.new()
	var live_mounted := live_rig.mount(live)
	var restore_mount_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var live_removed := 0
	if not bool(live.get_meta("vehicle_mesh_batched", false)):
		live_removed = BATCHER.batch_model(live)
	var restore_batch_ms := _elapsed_ms(started)
	var runtime_ms := restore_add_ms + restore_mount_ms + restore_batch_ms
	check(live_mounted and live_rig.pivots.size() == 4, "Prepared Vale restores four articulated wheels")
	check(live_removed == 0, "Prepared Vale does not repeat mesh batching at runtime")
	check(_visual_signature(live) == prepared_signature, "Prepared Vale preserves the cold prepared triangle/material signature")
	check(runtime_ms < FRAME_BUDGET_MS, "Prepared Vale restore path stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, runtime_ms])

	var sibling := script.new() as Node3D
	fixture.add_child(sibling)
	var live_paint := live.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	check(live_paint != null and sibling_paint != null and live_paint != sibling_paint, "Vale paint remains independent per cached instance")
	if live_paint != null and sibling_paint != null:
		var sibling_color := sibling_paint.albedo_color
		live_paint.albedo_color = Color.MAGENTA
		check(sibling_paint.albedo_color == sibling_color, "Repainting one Vale cannot recolor another")
		check(sibling_color.v > 0.15 and sibling_color.a > 0.99, "Prepared Vale paint remains non-black and opaque")

	var runtime_first_presented_ms = null
	if DisplayServer.get_name() != "headless":
		started = Time.get_ticks_usec()
		fixture.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		runtime_first_presented_ms = _elapsed_ms(started)
		check(runtime_first_presented_ms < FRAME_BUDGET_MS, "Prepared Vale first presented frame stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, runtime_first_presented_ms])

	# CoupeDamageModel must still own deformable body geometry after preparation.
	var originals: Dictionary = live.get("originals")
	check(not originals.is_empty(), "Prepared Vale retains deformable body parts")
	if live.has_method("apply_impact"):
		live.apply_impact(Vector3(0.65, 0.75, -1.0), Vector3(-1.0, 0.0, 0.0), 12.0)
		check(int(live.get("impact_count")) == 1, "Prepared Vale still accepts gameplay damage")

	var result := {
		"kind": "rendered" if DisplayServer.get_name() != "headless" else "headless_structural",
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else "not_measured",
		"frame_budget_ms": FRAME_BUDGET_MS,
		"script_load_ms": script_load_ms,
		"constructor_ms": constructor_ms,
		"mount_ms": mount_ms,
		"batch_ms": batch_ms,
		"cold_pipeline_ms": constructor_ms + mount_ms + batch_ms,
		"cold_end_to_end_ms": script_load_ms + constructor_ms + mount_ms + batch_ms,
		"cold_first_presented_ms": cold_first_presented_ms,
		"prewarm_ms": prewarm_ms,
		"first_load_plus_prewarm_ms": script_load_ms + prewarm_ms,
		"runtime_restore_add_ms": restore_add_ms,
		"runtime_mount_ms": restore_mount_ms,
		"runtime_batch_ms": restore_batch_ms,
		"runtime_pipeline_ms": runtime_ms,
		"runtime_first_presented_ms": runtime_first_presented_ms,
		"raw_signature": raw_signature,
		"prepared_signature": prepared_signature,
		"raw_triangles": raw_triangles,
		"prepared_triangles": prepared_triangles,
		"raw_meshes": raw_meshes,
		"raw_unique_meshes": raw_unique_meshes,
		"cold_batched_removed": removed,
		"wheel_centres": wheel_centers.size(),
		"damage_parts": originals.size(),
	}
	live.free()
	sibling.free()
	_finish(result)


func _reset_all_caches() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()


func _wheel_centers(model: Node3D) -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for node in model.get_children():
		if node.has_meta("wheel_center"):
			var center: Vector3 = node.get_meta("wheel_center")
			if not centers.has(center):
				centers.append(center)
	return centers


func _mesh_count(parent: Node) -> int:
	var count := 1 if parent is MeshInstance3D and (parent as MeshInstance3D).mesh != null else 0
	for child in parent.get_children():
		count += _mesh_count(child)
	return count


func _unique_mesh_count(parent: Node) -> int:
	var ids: Dictionary = {}
	_collect_mesh_ids(parent, ids)
	return ids.size()


func _collect_mesh_ids(parent: Node, ids: Dictionary) -> void:
	if parent is MeshInstance3D and (parent as MeshInstance3D).mesh != null:
		ids[(parent as MeshInstance3D).mesh.get_instance_id()] = true
	for child in parent.get_children():
		_collect_mesh_ids(child, ids)


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


func _elapsed_ms(started_usec: int) -> float:
	return (Time.get_ticks_usec() - started_usec) / 1000.0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(result: Dictionary) -> void:
	result["failures"] = failures
	print("VALE_CROSSOVER_COLD_CONSTRUCTION ", JSON.stringify(result))
	if is_instance_valid(fixture):
		fixture.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)
