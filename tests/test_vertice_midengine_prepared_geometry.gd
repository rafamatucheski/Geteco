extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/models/VerticeMidEngineModel.gd"
const PREPARED_PATH := "res://prototypes/living_cast/models/VerticeMidEnginePreparedGeometry.scn"
const CAPTURE_PATH := "res://_codex_diag/vertice-midengine-prepared.png"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const STATIC_VIEW := preload("res://world/mountain_pass/MountainStaticModelView.gd")
const STAGE_BUDGET_USEC := 6000
const MAX_STAGE_SAFETY_STEPS := 512
const EXPECTED_SIGNATURE := 1785881472
const EXPECTED_MESHES := 32
const EXPECTED_TRIANGLES := 16694

var failures: Array[String] = []
var stage_root: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Vertice prepared contract requires a rendered display")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	stage_root = Node3D.new()
	stage_root.name = "VerticePreparedContract"
	root.add_child(stage_root)
	current_scene = stage_root
	for _frame in 3:
		await process_frame
	STATIC_VIEW.reset_global_graphics_prewarm_for_tests()
	var loading_session := STATIC_VIEW.begin_graphics_prewarm_loading_session()
	var global_bootstrap: Dictionary = await STATIC_VIEW.prewarm_graphics_backend(self, 3000, loading_session)
	_check(bool(global_bootstrap.get("ready", false)), "Global loading graphics bootstrap completes")
	var material_bootstrap_ms := await _warm_vehicle_materials()
	_reset_runtime()

	var prepared_scene := load(PREPARED_PATH) as PackedScene
	_check(prepared_scene != null, "Vertice prepared resource loads")
	if prepared_scene == null:
		_finish({"error": "resource_missing"})
		return
	var template := prepared_scene.instantiate() as Node3D
	var clearance_signature := int(template.get_meta("vehicle_wheel_clearance_signature", 0))
	_check(template.get_script() == null, "Vertice prepared root is scriptless")
	_check(int(template.get_meta("vertice_midengine_prepared_geometry_signature", 0)) == EXPECTED_SIGNATURE, "Vertice prepared signature is fixed")
	_check(int(template.get_meta("vertice_midengine_prepared_meshes", 0)) == EXPECTED_MESHES, "Vertice prepared mesh count is fixed")
	_check(int(template.get_meta("vertice_midengine_prepared_triangles", 0)) == EXPECTED_TRIANGLES, "Vertice prepared triangle count is fixed")
	_check(_mesh_count(template) == EXPECTED_MESHES and _triangle_count(template) == EXPECTED_TRIANGLES, "Vertice prepared metadata matches physical geometry")
	_check(clearance_signature != 0, "Vertice prepared wheel-clearance signature is valid")
	_check(String(template.get_meta("silhouette_signature", "")) == "low_wide_mid_engine_wedge", "Vertice prepared silhouette identity is retained")
	template.free()

	var model_script := load(MODEL_PATH) as Script
	_check(model_script != null, "Vertice model script loads")
	if model_script == null:
		_finish({"error": "script_missing"})
		return
	var session := CACHE.begin_region_session(self, &"harbor")
	var job := _job_for_path(CACHE.region_session_jobs(session), MODEL_PATH)
	_check(not job.is_empty(), "Harbor regional manifest exposes Vertice")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		_finish({"error": "job_missing"})
		return
	var prepared_hits_before := CLEARANCE.prepared_hits
	var execution: Dictionary = {"complete": false}
	var rows: Array[Dictionary] = []
	var stage_steps := 0
	while stage_steps < MAX_STAGE_SAFETY_STEPS:
		stage_steps += 1
		execution = CACHE.advance_region_job(session, job, model_script)
		var detail: Dictionary = execution.get("stage_detail", {})
		rows.append({
			"stage": String(execution.get("stage", "")),
			"actual_usec": int(execution.get("actual_usec", 0)),
			"over_budget": bool(execution.get("over_budget", false)),
			"slice_index": int(detail.get("slice_index", -2)),
			"slice_count": int(detail.get("slice_count", 0)),
			"unit_name": String(detail.get("unit_name", "")),
		})
		if execution.has("error") or bool(execution.get("complete", false)):
			break
		await process_frame
	_check(not execution.has("error"), "Vertice regional preparation succeeds")
	_check(bool(execution.get("complete", false)), "Vertice regional preparation reaches atomic commit")
	_check(stage_steps < MAX_STAGE_SAFETY_STEPS, "Vertice regional preparation stays within its corruption safety bound")
	_check(CACHE._models.has(MODEL_PATH) and CACHE._prepared.has(MODEL_PATH), "Vertice publishes model and prepared markers atomically")
	var preparation: Dictionary = execution.get("preparation", {})
	_check(bool(preparation.get("direct_prepared", false)), "Vertice uses the direct prepared resource")
	_check(bool(preparation.get("wheel_mount_deferred_to_restore", false)), "Vertice defers only live wheel pivots to restore")
	_check(_stage_usec(rows, "wheel_mount") == 0, "Vertice regional pipeline performs no wheel carving")
	var max_stage_usec := 0
	for row in rows:
		var stage_usec := int(row.get("actual_usec", 0))
		max_stage_usec = maxi(max_stage_usec, stage_usec)
		_check(stage_usec <= STAGE_BUDGET_USEC, "Vertice stage %s exceeds 6 ms: %.3f ms" % [String(row.get("stage", "")), stage_usec / 1000.0])
	var attach_rows := _stage_rows(rows, "prepared_scene_attach_slice")
	_check(attach_rows.size() == EXPECTED_MESHES, "Vertice fixture follows every variable attach slice")
	_check(CLEARANCE.prepared_hits == prepared_hits_before, "Vertice regional preparation performs no hidden wheel carving")
	var region_report := CACHE.finish_region_session(session, true)
	await process_frame

	CACHE._deferred_constructor_paths[MODEL_PATH] = 1
	var authored := model_script.new() as Node3D
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	authored.call("build_vertice_procedural_source")
	stage_root.add_child(authored)
	var authored_rig := WHEEL_RIG.new()
	_check(authored_rig.mount(authored) and authored_rig.pivots.size() == 4, "Vertice procedural fallback mounts four wheels")
	_check(_triangle_count(authored) == EXPECTED_TRIANGLES, "Vertice procedural fallback preserves prepared triangles")

	var live := model_script.new() as Node3D
	var sibling := model_script.new() as Node3D
	stage_root.add_child(live)
	stage_root.add_child(sibling)
	sibling.visible = false
	_check(live.get_meta("vertice_midengine_geometry_source", &"") == &"prepared", "Vertice cache restore identifies prepared geometry")
	_check(int(live.get_meta("vertice_midengine_prepared_geometry_signature", 0)) == EXPECTED_SIGNATURE, "Vertice cache restore retains its signature")
	_check(bool(live.get_meta("vehicle_mesh_batched", false)), "Vertice cache restore remains pre-batched")
	_check(BATCHER.batch_model(live) == 0, "Vertice cache restore does not repeat batching")
	var hits_before_mount := CLEARANCE.prepared_hits
	var mount_started := Time.get_ticks_usec()
	var live_rig := WHEEL_RIG.new()
	var mounted := live_rig.mount(live)
	var runtime_mount_usec := Time.get_ticks_usec() - mount_started
	_check(mounted and live_rig.pivots.size() == 4, "Vertice cache restore remounts four articulated wheels")
	var maximum_track_center := 0.0
	for pivot in live_rig.pivots:
		maximum_track_center = maxf(maximum_track_center, absf(pivot.position.x))
	_check(maximum_track_center <= 0.761, "Vertice wheels remain tucked under the sculpted shoulders")
	_check(runtime_mount_usec <= STAGE_BUDGET_USEC, "Vertice runtime wheel mount stays within 6 ms, got %.3f ms" % [runtime_mount_usec / 1000.0])
	_check(CLEARANCE.prepared_hits == hits_before_mount + 1, "Vertice runtime mount skips polygon carving")
	_check(_triangle_count(live) == EXPECTED_TRIANGLES, "Vertice prepared path preserves exact triangles")
	_check(_visual_signature(live, 4) == _visual_signature(authored, 4), "Vertice prepared path preserves authored geometry/materials at 0.1 mm")

	var live_paint := live.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	_check(live_paint != null and sibling_paint != null and live_paint != sibling_paint, "Vertice prepared instances retain independent paint")
	if live_paint != null and sibling_paint != null:
		var sibling_color := sibling_paint.albedo_color
		_check(sibling_color.v > 0.15 and sibling_color.a > 0.99, "Vertice prepared paint remains visible and non-black")
		live_paint.albedo_color = Color.MAGENTA
		_check(sibling_paint.albedo_color == sibling_color, "Vertice repaint cannot recolor another instance")
		live_paint.albedo_color = Color("d43b32")
	var originals := live.get("originals") as Dictionary
	var lamps := live.get("lamp_sources") as Dictionary
	_check(originals.size() >= 1, "Vertice prepared body retains damage baselines")
	_check(lamps.size() >= 4, "Vertice prepared body retains four damageable lamps")
	live.call("apply_impact", Vector3(0.75, 0.75, -1.25), Vector3(-1.0, 0.0, 0.0), 9.0)
	_check(int(live.get("impact_count")) == 1 and not (live.get("damaged_vertices") as Dictionary).is_empty(), "Vertice prepared body still deforms")
	if not lamps.is_empty():
		var lamp_data := lamps[lamps.keys()[0]] as Dictionary
		live.call("apply_impact", lamp_data.get("position", Vector3.ZERO), Vector3(0.0, 0.0, 1.0), 9.0)
		_check((live.get("broken_lamps") as Array).has(true) or (live.get("broken_tail_lamps") as Array).has(true), "Vertice prepared lamps still break")
	live.call("repair")
	_check(int(live.get("impact_count")) == 0 and (live.get("damaged_vertices") as Dictionary).is_empty(), "Vertice prepared damage repairs completely")
	_check(not (live.get("broken_lamps") as Array).has(true) and not (live.get("broken_tail_lamps") as Array).has(true), "Vertice repair restores its lamps")

	var corrupt := prepared_scene.instantiate() as Node3D
	corrupt.set_meta("vertice_midengine_prepared_geometry_signature", EXPECTED_SIGNATURE + 1)
	_check(not bool(live.call("validate_vehicle_prepared_template", corrupt)), "Vertice rejects a corrupt prepared signature")
	corrupt.free()
	authored.visible = false
	var capture_error := await _capture(live)
	_check(capture_error == OK, "Vertice rendered capture saves successfully")
	var result := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"global_renderer_bootstrap_ms": int(global_bootstrap.get("elapsed_usec", 0)) / 1000.0,
		"vehicle_material_bootstrap_ms": material_bootstrap_ms,
		"stage_steps": stage_steps,
		"attach_slices": attach_rows.size(),
		"max_stage_usec": max_stage_usec,
		"max_stage_ms": max_stage_usec / 1000.0,
		"regional_total_active_usec": int(execution.get("total_active_usec", 0)),
		"regional_total_active_ms": int(execution.get("total_active_usec", 0)) / 1000.0,
		"over_budget_stages": region_report.get("over_budget_stages", []),
		"stage_rows": rows,
		"runtime_mount_usec": runtime_mount_usec,
		"runtime_mount_ms": runtime_mount_usec / 1000.0,
		"meshes": EXPECTED_MESHES,
		"triangles": EXPECTED_TRIANGLES,
		"signature": EXPECTED_SIGNATURE,
		"wheels": live_rig.pivots.size(),
		"lamps": lamps.size(),
		"damage_parts": originals.size(),
		"capture_path": ProjectSettings.globalize_path(CAPTURE_PATH),
	}
	authored.free()
	live.free()
	sibling.free()
	_finish(result)


func _warm_vehicle_materials() -> float:
	CACHE.reset_vehicle_graphics_bootstrap_for_tests()
	var report: Dictionary = await CACHE.prewarm_vehicle_graphics_backend(self)
	_check(bool(report.get("ready", false)), "Canonical vehicle material bootstrap completes")
	return float(report.get("elapsed_ms", 0.0))


func _capture(live: Node3D) -> Error:
	RenderingServer.set_default_clear_color(Color("66788a"))
	var camera := Camera3D.new()
	camera.position = Vector3(4.4, 2.35, 5.2)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.58, 0.0), Vector3.UP)
	stage_root.add_child(camera)
	camera.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	stage_root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 140.0, 0.0)
	fill.light_energy = 0.7
	stage_root.add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	ground.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("c4ccd3")
	floor_material.roughness = 0.85
	ground.material_override = floor_material
	stage_root.add_child(ground)
	live.visible = true
	for _frame in 2:
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(CAPTURE_PATH))


func _job_for_path(jobs: Array[Dictionary], path: String) -> Dictionary:
	for job in jobs:
		if String(job.get("path", "")) == path:
			return job
	return {}


func _stage_rows(rows: Array[Dictionary], wanted: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in rows:
		if String(row.get("stage", "")) == wanted:
			result.append(row)
	return result


func _stage_usec(rows: Array[Dictionary], wanted: String) -> int:
	for row in rows:
		if String(row.get("stage", "")) == wanted:
			return int(row.get("actual_usec", 0))
	return 0


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


func _visual_signature(model: Node3D, decimals: int) -> int:
	var entries: Array[String] = []
	_collect_visual(model, Transform3D.IDENTITY, entries, decimals)
	entries.sort()
	return hash(entries)


func _collect_visual(node: Node, parent_transform: Transform3D, entries: Array[String], decimals: int) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var material := part.get_active_material(surface_index) as StandardMaterial3D
			var color := material.albedo_color if material != null else Color.TRANSPARENT
			var arrays := part.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			for triangle_index in triangle_count:
				var points: Array[String] = []
				for corner in 3:
					var vertex_index := indices[triangle_index * 3 + corner] if not indices.is_empty() else triangle_index * 3 + corner
					var point := world_transform * vertices[vertex_index]
					var scale := pow(10.0, decimals)
					points.append("%d,%d,%d" % [roundi(point.x * scale), roundi(point.y * scale), roundi(point.z * scale)])
				points.sort()
				entries.append("%.5f,%.5f,%.5f,%.5f:%s" % [color.r, color.g, color.b, color.a, "|".join(points)])
	for child in node.get_children():
		_collect_visual(child, world_transform, entries, decimals)


func _reset_runtime() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._operationally_warmed_paths.erase(MODEL_PATH)
	CACHE._region_reports.erase(&"harbor")
	CACHE._retained_regions.erase(&"harbor")
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	CACHE._regional_capture_suppressed_paths.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()


func _finish(result: Dictionary) -> void:
	result["failures"] = failures
	print("VERTICE_MIDENGINE_PREPARED_CONTRACT ", JSON.stringify(result))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
