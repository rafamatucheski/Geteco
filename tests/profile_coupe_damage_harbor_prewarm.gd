extends SceneTree

## Diagnostic only: profiles the exact resumable Harbor prewarm path for the
## base CoupeDamageModel. It does not alter or optimize model/cache behavior.

const MODEL_PATH := "res://prototypes/living_cast/CoupeDamageModel.gd"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const STATIC_VIEW := preload("res://world/mountain_pass/MountainStaticModelView.gd")
const STAGE_BUDGET_USEC := 6000
const MAX_STAGE_SAFETY_STEPS := 512

var failures: Array[String] = []
var stage_root: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("CoupeDamage Harbor profiler requires a rendered display")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	stage_root = Node3D.new()
	stage_root.name = "CoupeDamageHarborDiagnostic"
	root.add_child(stage_root)
	current_scene = stage_root
	for _frame in 3:
		await process_frame
	STATIC_VIEW.reset_global_graphics_prewarm_for_tests()
	var loading_session := STATIC_VIEW.begin_graphics_prewarm_loading_session()
	var global_bootstrap: Dictionary = await STATIC_VIEW.prewarm_graphics_backend(self, 3000, loading_session)
	_check(bool(global_bootstrap.get("ready", false)), "Global loading graphics bootstrap completes before Coupe profiling")
	var vehicle_material_bootstrap_ms := await _warm_renderer()
	_reset_runtime()

	var resource_cached_before_load := ResourceLoader.has_cached(MODEL_PATH)
	var load_started := Time.get_ticks_usec()
	var model_resource := load(MODEL_PATH) as Resource
	var resource_load_usec := Time.get_ticks_usec() - load_started
	_check(model_resource is Script, "CoupeDamageModel script loads")
	if not model_resource is Script:
		_finish({"resource_load_usec": resource_load_usec})
		return

	var session_started := Time.get_ticks_usec()
	var session := CACHE.begin_region_session(self, &"harbor")
	var session_setup_usec := Time.get_ticks_usec() - session_started
	var job := _job_for_path(CACHE.region_session_jobs(session), MODEL_PATH)
	_check(not job.is_empty(), "Harbor regional manifest exposes CoupeDamageModel")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		_finish({"resource_load_usec": resource_load_usec, "session_setup_usec": session_setup_usec})
		return

	var warmup_view := session.get("warmup_view") as SubViewport
	RenderingServer.viewport_set_measure_render_time(warmup_view.get_viewport_rid(), true)
	var rows: Array[Dictionary] = []
	var execution: Dictionary = {"complete": false}
	var first_present_wait_usec := 0
	var viewport_cpu_ms := 0.0
	var viewport_gpu_ms := 0.0
	var construct_children := -1
	var construct_meshes := -1
	var construct_triangles := -1
	var carve_control: Node3D
	var mount_control: Node3D
	var diagnostic_wells: Array[Dictionary] = []
	var stage_steps := 0
	while stage_steps < MAX_STAGE_SAFETY_STEPS:
		stage_steps += 1
		var wall_started := Time.get_ticks_usec()
		execution = CACHE.advance_region_job(session, job, model_resource)
		var wall_usec := Time.get_ticks_usec() - wall_started
		var executed_stage := String(execution.get("stage", ""))
		var model := _active_model(session)
		var row := {
			"stage": executed_stage,
			"actual_usec": int(execution.get("actual_usec", 0)),
			"wall_usec": wall_usec,
			"over_budget": bool(execution.get("over_budget", false)),
			"children_after": model.get_child_count() if model != null else -1,
			"nodes_after": _node_count(model) if model != null else -1,
			"meshes_after": _mesh_count(model) if model != null else -1,
			"triangles_after": _triangle_count(model) if model != null else -1,
			"deferred_shell_meta": bool(model.get_meta("vehicle_deferred_prewarm_shell", false)) if model != null else false,
		}
		rows.append(row)
		if executed_stage == "construct_shell" and model != null:
			construct_children = model.get_child_count()
			construct_meshes = _mesh_count(model)
			construct_triangles = _triangle_count(model)
		if executed_stage == "add_child_ready" and model != null:
			# Keep two untouched scriptless copies before the real wheel stage. They
			# are measured only after the real job commits, so they cannot warm its
			# clearance or batching caches.
			carve_control = _clone_static_model(model)
			mount_control = _clone_static_model(model)
			diagnostic_wells = _wheel_wells(model)
		if execution.has("error") or bool(execution.get("complete", false)):
			break
		if executed_stage == "viewport_request":
			var present_started := Time.get_ticks_usec()
			await RenderingServer.frame_post_draw
			first_present_wait_usec = Time.get_ticks_usec() - present_started
			viewport_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(warmup_view.get_viewport_rid())
			viewport_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(warmup_view.get_viewport_rid())
			# A second explicit update exposes delayed GPU timers and separates
			# steady renderer cost from the first-present synchronization wait.
			warmup_view.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			viewport_cpu_ms = maxf(viewport_cpu_ms, RenderingServer.viewport_get_measured_render_time_cpu(warmup_view.get_viewport_rid()))
			viewport_gpu_ms = maxf(viewport_gpu_ms, RenderingServer.viewport_get_measured_render_time_gpu(warmup_view.get_viewport_rid()))
		else:
			await process_frame

	_check(not execution.has("error"), "CoupeDamageModel regional job finishes without an execution error")
	_check(bool(execution.get("complete", false)), "CoupeDamageModel regional job reaches commit")
	_check(stage_steps < MAX_STAGE_SAFETY_STEPS, "CoupeDamageModel regional job stays within the corruption safety bound")
	for row in rows:
		_check(int(row.get("actual_usec", 0)) <= STAGE_BUDGET_USEC, "CoupeDamageModel stage %s exceeds 6 ms: %.3f ms" % [String(row.get("stage", "")), int(row.get("actual_usec", 0)) / 1000.0])
	var standalone_carve_usec := -1
	var mount_without_carve_usec := -1
	var mount_without_carve_ok := false
	if carve_control != null and mount_control != null and not diagnostic_wells.is_empty():
		stage_root.add_child(carve_control)
		stage_root.add_child(mount_control)
		CLEARANCE._cache.clear()
		CLEARANCE._content_keys.clear()
		var carve_started := Time.get_ticks_usec()
		CLEARANCE.carve(carve_control, diagnostic_wells)
		standalone_carve_usec = Time.get_ticks_usec() - carve_started
		mount_control.set_meta(CLEARANCE.PREPARED_SIGNATURE_META, CLEARANCE._wells_signature(diagnostic_wells))
		var mount_started := Time.get_ticks_usec()
		var control_rig := WHEEL_RIG.new()
		mount_without_carve_ok = control_rig.mount(mount_control)
		mount_without_carve_usec = Time.get_ticks_usec() - mount_started
		carve_control.free()
		mount_control.free()
	var report := CACHE.finish_region_session(session, false)
	var dominant := _dominant_stage(rows)
	var total_active_usec := int(execution.get("total_active_usec", 0))
	var result := {
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"resolution": [root.size.x, root.size.y],
		"model_path": MODEL_PATH,
		"stage_budget_usec": STAGE_BUDGET_USEC,
		"global_renderer_bootstrap_ms": int(global_bootstrap.get("elapsed_usec", 0)) / 1000.0,
		"vehicle_material_bootstrap_ms": vehicle_material_bootstrap_ms,
		"resource_cached_before_load": resource_cached_before_load,
		"resource_load_usec": resource_load_usec,
		"resource_load_ms": resource_load_usec / 1000.0,
		"session_setup_usec": session_setup_usec,
		"session_setup_ms": session_setup_usec / 1000.0,
		"stage_rows": rows,
		"stage_steps": stage_steps,
		"total_active_usec": total_active_usec,
		"total_active_ms": total_active_usec / 1000.0,
		"dominant_stage": dominant.get("stage", ""),
		"dominant_stage_usec": int(dominant.get("actual_usec", 0)),
		"dominant_share_percent": 100.0 * int(dominant.get("actual_usec", 0)) / maxi(total_active_usec, 1),
		"construct_shell_children": construct_children,
		"construct_shell_meshes": construct_meshes,
		"construct_shell_triangles": construct_triangles,
		"constructor_bypassed_deferred_shell": construct_children > 0,
		"first_present_wait_usec": first_present_wait_usec,
		"first_present_wait_ms": first_present_wait_usec / 1000.0,
		"viewport_render_cpu_ms": viewport_cpu_ms,
		"viewport_render_gpu_ms": viewport_gpu_ms,
		"standalone_wheel_carve_usec": standalone_carve_usec,
		"standalone_wheel_carve_ms": standalone_carve_usec / 1000.0,
		"mount_without_carve_usec": mount_without_carve_usec,
		"mount_without_carve_ms": mount_without_carve_usec / 1000.0,
		"mount_without_carve_ok": mount_without_carve_ok,
		"wheel_well_count": diagnostic_wells.size(),
		"cache_published": CACHE._models.has(MODEL_PATH) and CACHE._prepared.has(MODEL_PATH),
		"over_budget_stages": report.get("over_budget_stages", []),
	}
	_finish(result)


func _warm_renderer() -> float:
	var viewport := SubViewport.new()
	viewport.name = "CoupeDamageRendererWarmup"
	viewport.size = Vector2i(96, 96)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stage_root.add_child(viewport)
	var camera := Camera3D.new()
	camera.position = Vector3(4.0, 3.0, 5.0)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	viewport.add_child(camera)
	var opaque := StandardMaterial3D.new()
	opaque.albedo_color = Color("b83632")
	opaque.metallic = 0.25
	opaque.roughness = 0.24
	var double_sided := opaque.duplicate() as StandardMaterial3D
	double_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	var emissive := opaque.duplicate() as StandardMaterial3D
	emissive.emission_enabled = true
	emissive.emission = Color("e6f0ed")
	emissive.emission_energy_multiplier = 0.65
	for index in 3:
		var sample := MeshInstance3D.new()
		sample.mesh = BoxMesh.new()
		sample.position.x = float(index) * 1.5 - 1.5
		sample.material_override = [opaque, double_sided, emissive][index]
		viewport.add_child(sample)
	var started := Time.get_ticks_usec()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	viewport.free()
	await process_frame
	return elapsed


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
	var dominant: Dictionary = {}
	for row in rows:
		if int(row.get("actual_usec", 0)) > int(dominant.get("actual_usec", -1)):
			dominant = row
	return dominant


func _clone_static_model(source: Node3D) -> Node3D:
	var clone := Node3D.new()
	for metadata in source.get_meta_list():
		clone.set_meta(metadata, source.get_meta(metadata))
	for child in source.get_children():
		clone.add_child(child.duplicate(0))
	return clone


func _wheel_wells(model: Node3D) -> Array[Dictionary]:
	var centres: Array[Vector3] = []
	for child in model.get_children():
		if child.has_meta("wheel_center"):
			var centre: Vector3 = child.get_meta("wheel_center")
			if not centres.has(centre):
				centres.append(centre)
	if centres.is_empty():
		return []
	var min_z := INF
	var max_z := -INF
	for centre in centres:
		min_z = minf(min_z, centre.z)
		max_z = maxf(max_z, centre.z)
	var front_limit := (min_z + max_z) * 0.5
	var rear_steering := bool(model.get_meta("rear_steering", false))
	var wells: Array[Dictionary] = []
	for centre in centres:
		var radius := WHEEL_RIG.DEFAULT_TIRE_RADIUS
		var half_width := 0.0
		for part in model.get_children():
			if part is MeshInstance3D and part.get_meta("wheel_center", Vector3.INF) == centre:
				radius = float(part.get_meta("wheel_radius", radius))
				var bounds: AABB = part.transform * part.mesh.get_aabb()
				half_width = maxf(half_width, maxf(absf(bounds.position.x - centre.x), absf(bounds.end.x - centre.x)))
		var angle := WHEEL_RIG.MAX_STEER_ANGLE if (centre.z < front_limit) != rear_steering else 0.0
		var reach := radius * sin(angle) + half_width * cos(angle)
		wells.append({
			"center": centre,
			"radius": sqrt(radius * radius + half_width * half_width) + 0.035,
			"inner": maxf(0.05, absf(centre.x) - reach - 0.035),
		})
	return wells


func _node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _node_count(child)
	return count


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
	print("COUPE_DAMAGE_HARBOR_DIAG ", JSON.stringify(result))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
