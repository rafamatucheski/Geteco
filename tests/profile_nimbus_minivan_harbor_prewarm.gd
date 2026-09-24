extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/models/NimbusMinivanModel.gd"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const STATIC_VIEW := preload("res://world/mountain_pass/MountainStaticModelView.gd")
const MAX_STAGE_SAFETY_STEPS := 512

var failures: Array[String] = []
var stage_root: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Nimbus Harbor profiler requires a rendered display")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	stage_root = Node3D.new()
	root.add_child(stage_root)
	current_scene = stage_root
	for _frame in 3:
		await process_frame
	STATIC_VIEW.reset_global_graphics_prewarm_for_tests()
	var loading_session := STATIC_VIEW.begin_graphics_prewarm_loading_session()
	var global_bootstrap: Dictionary = await STATIC_VIEW.prewarm_graphics_backend(self, 3000, loading_session)
	_check(bool(global_bootstrap.get("ready", false)), "Global loading bootstrap completes")
	var material_bootstrap_ms := await _warm_materials()
	_reset_runtime()

	var script := load(MODEL_PATH) as Script
	_check(script != null, "Nimbus model script loads")
	if script == null:
		_finish({"error": "script_missing"})
		return
	var session := CACHE.begin_region_session(self, &"harbor")
	var job := _job_for_path(CACHE.region_session_jobs(session), MODEL_PATH)
	_check(not job.is_empty(), "Harbor exposes Nimbus regional job")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		_finish({"error": "job_missing"})
		return
	var execution: Dictionary = {"complete": false}
	var rows: Array[Dictionary] = []
	var carve_control: Node3D
	var mount_control: Node3D
	var wells: Array[Dictionary] = []
	var authored_meshes := -1
	var authored_triangles := -1
	var stage_steps := 0
	while stage_steps < MAX_STAGE_SAFETY_STEPS:
		stage_steps += 1
		execution = CACHE.advance_region_job(session, job, script)
		var stage := String(execution.get("stage", ""))
		rows.append({
			"stage": stage,
			"actual_usec": int(execution.get("actual_usec", 0)),
			"over_budget": bool(execution.get("over_budget", false)),
		})
		if stage == "add_child_ready":
			var model := _active_model(session)
			if model != null:
				authored_meshes = _mesh_count(model)
				authored_triangles = _triangle_count(model)
				carve_control = _clone_static_model(model)
				mount_control = _clone_static_model(model)
				wells = _wheel_wells(model)
		if execution.has("error") or bool(execution.get("complete", false)):
			break
		await process_frame
	_check(not execution.has("error"), "Nimbus regional job has no execution error")
	_check(bool(execution.get("complete", false)), "Nimbus regional job reaches commit")
	_check(stage_steps < MAX_STAGE_SAFETY_STEPS, "Nimbus regional job stays within safety bound")

	var carve_usec := -1
	var mount_without_carve_usec := -1
	var mount_without_carve_ok := false
	if carve_control != null and mount_control != null and not wells.is_empty():
		stage_root.add_child(carve_control)
		stage_root.add_child(mount_control)
		CLEARANCE._cache.clear()
		CLEARANCE._content_keys.clear()
		var started := Time.get_ticks_usec()
		CLEARANCE.carve(carve_control, wells)
		carve_usec = Time.get_ticks_usec() - started
		mount_control.set_meta(CLEARANCE.PREPARED_SIGNATURE_META, CLEARANCE._wells_signature(wells))
		started = Time.get_ticks_usec()
		var rig := WHEEL_RIG.new()
		mount_without_carve_ok = rig.mount(mount_control)
		mount_without_carve_usec = Time.get_ticks_usec() - started
		carve_control.free()
		mount_control.free()
	var report := CACHE.finish_region_session(session, false)
	var dominant := _dominant_stage(rows)
	_finish({
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"global_renderer_bootstrap_ms": int(global_bootstrap.get("elapsed_usec", 0)) / 1000.0,
		"vehicle_material_bootstrap_ms": material_bootstrap_ms,
		"stage_steps": stage_steps,
		"stage_rows": rows,
		"total_active_usec": int(execution.get("total_active_usec", 0)),
		"total_active_ms": int(execution.get("total_active_usec", 0)) / 1000.0,
		"dominant_stage": String(dominant.get("stage", "")),
		"dominant_stage_usec": int(dominant.get("actual_usec", 0)),
		"authored_meshes": authored_meshes,
		"authored_triangles": authored_triangles,
		"wheel_wells": wells.size(),
		"standalone_carve_usec": carve_usec,
		"mount_without_carve_usec": mount_without_carve_usec,
		"mount_without_carve_ok": mount_without_carve_ok,
		"cache_published": CACHE._models.has(MODEL_PATH) and CACHE._prepared.has(MODEL_PATH),
		"over_budget_stages": report.get("over_budget_stages", []),
	})


func _warm_materials() -> float:
	CACHE.reset_vehicle_graphics_bootstrap_for_tests()
	var report: Dictionary = await CACHE.prewarm_vehicle_graphics_backend(self)
	_check(bool(report.get("ready", false)), "Canonical vehicle material bootstrap completes")
	return float(report.get("elapsed_ms", 0.0))


func _active_model(session: Dictionary) -> Node3D:
	var states: Dictionary = session.get("job_states", {})
	var state: Dictionary = states.get(MODEL_PATH, {})
	return state.get("model") as Node3D


func _job_for_path(jobs: Array[Dictionary], path: String) -> Dictionary:
	for job in jobs:
		if String(job.get("path", "")) == path:
			return job
	return {}


func _dominant_stage(rows: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for row in rows:
		if int(row.get("actual_usec", 0)) > int(result.get("actual_usec", -1)):
			result = row
	return result


func _clone_static_model(model: Node3D) -> Node3D:
	var clone := Node3D.new()
	for metadata in model.get_meta_list():
		clone.set_meta(metadata, model.get_meta(metadata))
	for child in model.get_children():
		clone.add_child(child.duplicate(0))
	return clone


func _wheel_wells(model: Node3D) -> Array[Dictionary]:
	var centres: Array[Vector3] = []
	for child in model.get_children():
		if child.has_meta("wheel_center"):
			var centre: Vector3 = child.get_meta("wheel_center")
			if not centres.has(centre):
				centres.append(centre)
	var min_z := INF
	var max_z := -INF
	for centre in centres:
		min_z = minf(min_z, centre.z)
		max_z = maxf(max_z, centre.z)
	var front_limit := (min_z + max_z) * 0.5
	var result: Array[Dictionary] = []
	for centre in centres:
		var radius := WHEEL_RIG.DEFAULT_TIRE_RADIUS
		var half_width := 0.0
		for part in model.get_children():
			if part is MeshInstance3D and part.get_meta("wheel_center", Vector3.INF) == centre:
				radius = float(part.get_meta("wheel_radius", radius))
				var bounds: AABB = part.transform * part.mesh.get_aabb()
				half_width = maxf(half_width, maxf(absf(bounds.position.x - centre.x), absf(bounds.end.x - centre.x)))
		var angle := WHEEL_RIG.MAX_STEER_ANGLE if centre.z < front_limit else 0.0
		var reach := radius * sin(angle) + half_width * cos(angle)
		result.append({
			"center": centre,
			"radius": sqrt(radius * radius + half_width * half_width) + 0.035,
			"inner": maxf(0.05, absf(centre.x) - reach - 0.035),
		})
	return result


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
	print("NIMBUS_MINIVAN_HARBOR_DIAG ", JSON.stringify(result))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
