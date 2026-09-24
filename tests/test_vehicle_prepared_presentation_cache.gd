extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const FRAME_BUDGET_MS := 1000.0 / 60.0
const CASES := [
	{
		"id": "union_sedan",
		"path": "res://prototypes/living_cast/models/UnionSedanModel.gd",
	},
	{
		"id": "american_flatbed",
		"path": "res://prototypes/living_cast/models/AmericanFlatbedModel.gd",
	},
	{
		"id": "vertice_mid_engine",
		"path": "res://prototypes/living_cast/models/VerticeMidEngineModel.gd",
	},
	{
		"id": "nordic_estate",
		"path": "res://prototypes/living_cast/models/NordicEstateModel.gd",
	},
	{
		"id": "vale_crossover",
		"path": "res://prototypes/living_cast/models/ValeCrossoverModel.gd",
	},
]

var failures: Array[String] = []
var warmup_view: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	warmup_view = SubViewport.new()
	warmup_view.name = "PreparedPresentationCacheFixture"
	warmup_view.size = Vector2i(256, 256)
	warmup_view.own_world_3d = true
	warmup_view.transparent_bg = true
	warmup_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(warmup_view)
	var camera := Camera3D.new()
	warmup_view.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 8.0, 4.0), Vector3(0.0, 0.45, 0.0), Vector3.UP)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	warmup_view.add_child(sun)

	var rows: Array[Dictionary] = []
	for case_data in CASES:
		rows.append(await _exercise_case(case_data))

	print("VEHICLE_PREPARED_PRESENTATION_CACHE ", JSON.stringify({
		"kind": "rendered" if DisplayServer.get_name() != "headless" else "headless_structural",
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else "not_measured",
		"frame_budget_ms": FRAME_BUDGET_MS,
		"rows": rows,
		"failures": failures,
	}))
	warmup_view.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _exercise_case(case_data: Dictionary) -> Dictionary:
	var id := String(case_data.id)
	var path := String(case_data.path)
	var script := load(path) as Script
	check(script != null, "%s model script loads" % id)
	if script == null:
		return {"vehicle": id, "error": "load_failed"}

	_reset_model_cache(path)
	_reset_pipeline_caches()
	var started := Time.get_ticks_usec()
	var cold := script.new() as Node3D
	warmup_view.add_child(cold)
	var cold_rig := WHEEL_RIG.new()
	var cold_mounted := cold_rig.mount(cold)
	var cold_removed := BATCHER.batch_model(cold)
	var cold_pipeline_ms := _elapsed_ms(started)
	var cold_signature := _visual_signature(cold)
	var cold_wheel_count := cold_rig.pivots.size()
	check(cold_mounted and cold_wheel_count >= 4, "%s cold presentation keeps four articulated 3D wheels" % id)
	check(cold_removed > 0, "%s cold presentation exercises real mesh batching" % id)
	cold.free()

	# This is a second deliberately cold geometry-cache pass. It proves that the
	# loading preparation itself pays the miss/build/carve/batch work, then replaces
	# the raw constructor cache with the final presentation template.
	_reset_model_cache(path)
	_reset_pipeline_caches()
	var misses_before := CACHE.misses
	var cold_builds_before := CACHE.cold_builds
	var prepared_captures_before := CACHE.prepared_template_captures
	started = Time.get_ticks_usec()
	var prewarm_report: Dictionary = CACHE._prepare_model_template(path, warmup_view)
	var prewarm_ms := _elapsed_ms(started)
	check(CACHE.misses == misses_before + 1, "%s prewarm starts from a real geometry-cache miss" % id)
	check(CACHE.cold_builds == cold_builds_before + 1, "%s prewarm performs exactly one cold model build" % id)
	check(CACHE.prepared_template_captures == prepared_captures_before + 1, "%s prewarm captures the prepared template" % id)
	check(bool(prewarm_report.get("wheel_mounted", false)), "%s prewarm mounts authored wheels before capture" % id)
	check(int(prewarm_report.get("batched_removed", 0)) > 0, "%s prewarm fuses static presentation geometry" % id)
	check(bool(prewarm_report.get("captured", false)), "%s prepared cache replacement succeeds" % id)
	check(bool(CACHE._models[path].get("prepared_presentation", false)), "%s cache entry is marked presentation-ready" % id)

	if DisplayServer.get_name() != "headless":
		warmup_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw

	var hits_before := CACHE.hits
	var clearance_hits_before := CLEARANCE.prepared_hits
	started = Time.get_ticks_usec()
	var live := script.new() as Node3D
	warmup_view.add_child(live)
	var restore_add_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var live_rig := WHEEL_RIG.new()
	var live_mounted := live_rig.mount(live)
	var mount_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var batch_removed := 0
	if not bool(live.get_meta("vehicle_mesh_batched", false)):
		batch_removed = BATCHER.batch_model(live)
		live.set_meta("vehicle_mesh_batched", true)
	var batch_ms := _elapsed_ms(started)
	var post_prewarm_ms := restore_add_ms + mount_ms + batch_ms

	check(CACHE.hits == hits_before + 1, "%s runtime model restores from prepared cache" % id)
	check(CLEARANCE.prepared_hits == clearance_hits_before + 1, "%s runtime mount reuses prepared wheel clearance" % id)
	check(live_mounted and live_rig.pivots.size() == cold_wheel_count, "%s runtime rig restores every authored wheel" % id)
	check(bool(live.get_meta("vehicle_mesh_batched", false)), "%s runtime template remains marked pre-batched" % id)
	check(batch_removed == 0, "%s runtime does not repeat static mesh fusion" % id)
	check(_visual_signature(live) == cold_signature, "%s prepared cache preserves the cold visual triangle/material signature" % id)
	check(post_prewarm_ms < FRAME_BUDGET_MS, "%s post-prewarm restore + mount + batch gate must stay below %.2f ms, got %.3f ms" % [id, FRAME_BUDGET_MS, post_prewarm_ms])

	var sibling := script.new() as Node3D
	warmup_view.add_child(sibling)
	var live_paint := live.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	check(live_paint != null and sibling_paint != null, "%s cached instances retain visible paint" % id)
	if live_paint != null and sibling_paint != null:
		check(live_paint != sibling_paint, "%s paint remains independent per instance" % id)
		var sibling_color := sibling_paint.albedo_color
		live_paint.albedo_color = Color.MAGENTA
		check(sibling_paint.albedo_color == sibling_color, "%s repainting one instance cannot recolor another" % id)
		check(sibling_color.v > 0.15 and sibling_color.a > 0.99, "%s cached paint stays visible instead of black" % id)

	var first_presented_ms = null
	if DisplayServer.get_name() != "headless":
		started = Time.get_ticks_usec()
		warmup_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		first_presented_ms = _elapsed_ms(started)

	live.free()
	sibling.free()
	return {
		"vehicle": id,
		"cold_pipeline_ms": cold_pipeline_ms,
		"prewarm_ms": prewarm_ms,
		"post_restore_add_ms": restore_add_ms,
		"post_mount_ms": mount_ms,
		"post_batch_gate_ms": batch_ms,
		"post_pipeline_ms": post_prewarm_ms,
		"post_first_presented_ms": first_presented_ms,
		"cold_batched_removed": cold_removed,
		"prewarm_batched_removed": int(prewarm_report.get("batched_removed", 0)),
		"runtime_batched_removed": batch_removed,
		"wheels": cold_wheel_count,
	}


func _reset_model_cache(path: String) -> void:
	CACHE._models.erase(path)
	CACHE._prepared.erase(path)
	CACHE._miss_started_usec.erase(path)


func _reset_pipeline_caches() -> void:
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()


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
