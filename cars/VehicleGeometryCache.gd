extends RefCounted
## Protótipos sem script guardam somente a geometria inicial. Cada carro recebe
## materiais próprios, e o script de dano registra suas próprias peças em _ready.
static var _models: Dictionary = {}
static var hits := 0
static var misses := 0
static var captures := 0
static var restore_usec := 0
static var capture_usec := 0
static var cold_builds := 0
static var cold_build_usec := 0
static var regional_misses := 0
static var regional_cold_builds := 0
static var regional_cold_build_usec := 0
static var max_cold_build_usec := 0
static var last_cold_build_usec := 0
static var last_model_key := ""
static var _miss_started_usec: Dictionary = {}
static var _prepared: Dictionary = {}
# Presentation-only warmups for models whose operational Node references make
# geometry restore unsupported. This is deliberately separate from `_prepared`:
# no cache entry exists for these paths and gameplay must run their constructor.
static var _operationally_warmed_paths: Dictionary = {}
static var _prewarm_complete := false
static var _post_prewarm_misses_baseline := 0
static var _post_prewarm_cold_builds_baseline := 0
static var _post_prewarm_cold_build_usec_baseline := 0
static var _last_prewarm_report: Dictionary = {}
static var _region_reports: Dictionary = {}
static var _retained_regions: Dictionary = {}
static var _active_region_sessions: Dictionary = {}
static var _next_region_session_id := 1
static var _deferred_constructor_paths: Dictionary = {}
static var _regional_capture_suppressed_paths: Dictionary = {}
static var prepared_template_captures := 0
static var prepared_template_failures := 0
static var _vehicle_graphics_bootstrap_state := 0
static var _vehicle_graphics_bootstrap_result: Dictionary = {
	"state": "cold",
	"scope": "loading_global",
	"producer": "vehicle_material_variants",
	"charged_to": "loading",
	"ready": false,
	"reused": false,
	"variant_steps": [],
}
# Prepare the full close-proximity ring before gameplay starts. The runtime
# keeps residents relevant up to the same 700 px radius; leaving this at a
# smaller loading margin pushed otherwise-near 3D builds into the first drive
# through a district and caused frame-time spikes during streaming transitions.
const STARTUP_PRESENTATION_MARGIN := 700.0
const REGION_STAGE_BUDGET_USEC := 6000
const REGION_STAGE_TELEMETRY_LIMIT := 512
const REGION_JOB_STAGE_KEYS: Array[String] = [
	"construct_shell_usec",
	"strategy_select_usec",
	"prepared_materials_usec",
	"prepared_scene_instantiate_usec",
	"prepared_scene_validate_usec",
	"prepared_scene_attach_begin_usec",
	"prepared_scene_attach_slice_usec",
	"prepared_scene_attach_finish_usec",
	"prepared_entry_pack_usec",
	"procedural_build_usec",
	"script_new_packed_scene_instantiate_usec",
	"add_child_ready_usec",
	"wheel_mount_usec",
	"batching_usec",
	"flatten_usec",
	"capture_pack_usec",
	"viewport_request_usec",
	"model_free_usec",
	"commit_usec",
]

static func is_startup_relevant(actor: Node2D) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree() or not actor.is_visible_in_tree():
		return false
	if actor.get_meta("proximity_sleeping", false):
		return false
	if actor.get("is_driven_by_player") == true:
		return true
	var screen_position := actor.get_global_transform_with_canvas().origin
	return screen_position.is_finite() and actor.get_viewport_rect().grow(STARTUP_PRESENTATION_MARGIN).has_point(screen_position)

static func prepare_common_models(tree: SceneTree) -> Dictionary:
	# GameLoading awaits this method while controls remain paused. Shader and
	# pipeline variants are therefore compiled once behind the loading screen,
	# before any regional vehicle slice can reach live gameplay.
	var material_bootstrap := await prewarm_vehicle_graphics_backend(tree)
	var harbor_report := await prepare_region(tree, &"harbor")
	return {
		"material_bootstrap": material_bootstrap,
		"harbor": harbor_report,
	}

static func prewarm_vehicle_graphics_backend(tree: SceneTree) -> Dictionary:
	if tree == null or tree.root == null:
		return {
			"state": "invalid_tree",
			"scope": "loading_global",
			"producer": "vehicle_material_variants",
			"charged_to": "loading",
			"ready": false,
			"reused": false,
			"variant_steps": [],
		}
	if _vehicle_graphics_bootstrap_state == 2:
		var reused := _vehicle_graphics_bootstrap_result.duplicate(true)
		reused["reused"] = true
		return reused
	if _vehicle_graphics_bootstrap_state == 1:
		while _vehicle_graphics_bootstrap_state == 1:
			await tree.process_frame
		var joined := _vehicle_graphics_bootstrap_result.duplicate(true)
		joined["reused"] = true
		return joined
	if DisplayServer.get_name() == "headless":
		return {
			"state": "skipped_headless",
			"scope": "loading_global",
			"producer": "vehicle_material_variants",
			"charged_to": "loading",
			"ready": false,
			"reused": false,
			"skipped_headless": true,
			"variant_steps": [],
		}

	_vehicle_graphics_bootstrap_state = 1
	var total_started := Time.get_ticks_usec()
	var host := Node.new()
	host.name = "VehicleMaterialGraphicsPrewarm"
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	var viewport := SubViewport.new()
	viewport.name = "VehicleMaterialVariants64"
	viewport.size = Vector2i(64, 64)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.positional_shadow_atlas_size = 0
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 0.0, 2.5), Vector3.ZERO, Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	viewport.add_child(sun)
	tree.root.add_child(host)
	var texture := viewport.get_texture()
	await tree.process_frame

	var variant_steps: Array[Dictionary] = []
	for variant in _vehicle_material_bootstrap_variants():
		var probe := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(0.8, 0.8, 0.8)
		probe.mesh = box_mesh
		probe.material_override = variant.material as Material
		var started := Time.get_ticks_usec()
		viewport.add_child(probe)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var elapsed_usec := Time.get_ticks_usec() - started
		variant_steps.append({
			"variant": String(variant.name),
			"elapsed_usec": elapsed_usec,
			"elapsed_ms": elapsed_usec / 1000.0,
			"frame": Engine.get_process_frames(),
		})
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		probe.free()
	await tree.process_frame
	var texture_size := texture.get_size()
	host.queue_free()
	await tree.process_frame
	var elapsed_usec := Time.get_ticks_usec() - total_started
	_vehicle_graphics_bootstrap_state = 2
	_vehicle_graphics_bootstrap_result = {
		"state": "ready",
		"scope": "loading_global",
		"producer": "vehicle_material_variants",
		"charged_to": "loading",
		"ready": true,
		"reused": false,
		"elapsed_usec": elapsed_usec,
		"elapsed_ms": elapsed_usec / 1000.0,
		"variant_steps": variant_steps,
		"texture_size": texture_size,
		"temporary_viewport_released": not is_instance_valid(host),
		"renderer": RenderingServer.get_current_rendering_method(),
	}
	return _vehicle_graphics_bootstrap_result.duplicate(true)

static func vehicle_graphics_bootstrap_snapshot() -> Dictionary:
	return _vehicle_graphics_bootstrap_result.duplicate(true)

static func reset_vehicle_graphics_bootstrap_for_tests() -> void:
	_vehicle_graphics_bootstrap_state = 0
	_vehicle_graphics_bootstrap_result = {
		"state": "cold",
		"scope": "loading_global",
		"producer": "vehicle_material_variants",
		"charged_to": "loading",
		"ready": false,
		"reused": false,
		"variant_steps": [],
	}

static func _vehicle_material_bootstrap_variants() -> Array[Dictionary]:
	var opaque := StandardMaterial3D.new()
	opaque.albedo_color = Color("d8dde3")
	opaque.metallic = 0.0
	opaque.roughness = 0.9
	var emissive := StandardMaterial3D.new()
	emissive.albedo_color = Color("f5f6fa")
	emissive.metallic = 0.1
	emissive.roughness = 0.1
	emissive.emission_enabled = true
	emissive.emission = Color("f5f6fa")
	emissive.emission_energy_multiplier = 0.65
	var double_sided := StandardMaterial3D.new()
	double_sided.albedo_color = Color("314657")
	double_sided.metallic = 0.35
	double_sided.roughness = 0.15
	double_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	var transparent_glass := double_sided.duplicate() as StandardMaterial3D
	transparent_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	transparent_glass.albedo_color.a = 0.45
	return [
		{"name": &"opaque_rubber", "material": opaque},
		{"name": &"emissive_lamp", "material": emissive},
		{"name": &"double_sided_glass", "material": double_sided},
		{"name": &"transparent_double_sided_glass", "material": transparent_glass},
	]

## Incremental, idempotent prewarm for one real runtime region. Loading screens
## keep this compatibility wrapper; runtime proximity uses the explicit session
## API below and routes each model through RuntimeWorkScheduler.
static func prepare_region(
	tree: SceneTree,
	region_id: StringName,
	cancel_check: Callable = Callable()
) -> Dictionary:
	var session := begin_region_session(tree, region_id)
	if not bool(session.get("valid", false)):
		return session.get("report", {}).duplicate(true)
	if _cancel_requested(cancel_check):
		return finish_region_session(session, true)
	for job in region_session_jobs(session):
		if _cancel_requested(cancel_check):
			return finish_region_session(session, true)
		var resource_state := request_region_job_resource(session, job)
		while String(resource_state.get("state", "")) == "loading":
			await tree.process_frame
			if _cancel_requested(cancel_check):
				return finish_region_session(session, true)
			resource_state = poll_region_job_resource(session, job)
		if resource_state.has("error"):
			return finish_region_session(session, false)
		var execution := {"complete": false}
		while not bool(execution.get("complete", false)):
			await tree.process_frame
			if _cancel_requested(cancel_check):
				return finish_region_session(session, true)
			execution = advance_region_job(session, job, resource_state.get("resource") as Resource)
			if execution.has("error"):
				return finish_region_session(session, false)
	return finish_region_session(session, false)

## Opens a region-scoped prewarm session without executing model construction.
## The caller owns cadence and may route every returned job through the global
## runtime scheduler. Dictionaries are intentionally used as opaque handles so
## this API remains usable from loading code and lightweight runtime nodes.
static func begin_region_session(tree: SceneTree, region_id: StringName) -> Dictionary:
	var paths := _region_model_paths(region_id, tree)
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var session_id := _next_region_session_id
	_next_region_session_id += 1
	var report := {
		"session_id": session_id,
		"region": String(region_id),
		"requested_models": paths.size(),
		"requested_paths": paths.duplicate(),
		"models_prepared": 0,
		"cache_hits": 0,
		"operational_warm_hits": 0,
		"cache_misses": 0,
		"failed_models": [],
		"thread_requests": 0,
		"thread_cache_hits": 0,
		"thread_loaded": 0,
		"thread_failures": 0,
		"thread_wait_frames": 0,
		"uncached_models": [],
		"operational_models_warmed": [],
		"cancelled": false,
		"completed": false,
		"elapsed_usec": 0,
		"max_model_usec": 0,
		"max_model_path": "",
		"model_timings": [],
		"stage_budget_usec": REGION_STAGE_BUDGET_USEC,
		"stage_steps": [],
		"stage_steps_dropped": 0,
		"stage_steps_executed": 0,
		"max_stage_usec": 0,
		"max_stage": "",
		"max_stage_path": "",
		"over_budget_stages": [],
		"stage_totals_usec": _empty_region_job_stage_timings(),
		"last_stage_timing": {},
		"memory_before_bytes": memory_before,
		"memory_after_bytes": memory_before,
		"memory_delta_bytes": 0,
		"retained_models": _models.size(),
	}
	var session := {
		"id": session_id,
		"valid": false,
		"active": false,
		"region": region_id,
		"tree": tree,
		"paths": paths,
		"started_usec": Time.get_ticks_usec(),
		"misses_before": misses,
		"cold_builds_before": cold_builds,
		"cold_build_usec_before": cold_build_usec,
		"regional_misses_before": regional_misses,
		"regional_cold_builds_before": regional_cold_builds,
		"regional_cold_build_usec_before": regional_cold_build_usec,
		"report": report,
		"warmup_view": null,
		"resource_states": {},
		"loaded_resources": {},
		"job_states": {},
	}
	if tree == null or tree.root == null:
		report["error"] = "invalid_scene_tree"
		_region_reports[region_id] = report.duplicate(true)
		return session
	if not preload("res://cars/VehiclePrewarmManifest.gd").region_ids().has(region_id):
		report["error"] = "unknown_region"
		_region_reports[region_id] = report.duplicate(true)
		return session
	for path in paths:
		if _prepared.has(path):
			report.cache_hits += 1
		elif _operationally_warmed_paths.has(path):
			report.operational_warm_hits += 1
	var warmup_view := _create_warmup_view(tree, region_id, session_id)
	session.valid = true
	session.active = true
	session.warmup_view = warmup_view
	_active_region_sessions[session_id] = {
		"region": String(region_id),
		"started_usec": session.started_usec,
		"remaining_jobs": region_session_jobs(session).size(),
	}
	return session

static func region_session_jobs(session: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if not bool(session.get("valid", false)) or not bool(session.get("active", false)):
		return jobs
	var region_id := StringName(session.get("region", &""))
	for path_value in session.get("paths", []):
		var path := String(path_value)
		if _prepared.has(path) or _operationally_warmed_paths.has(path) or not ResourceLoader.exists(path):
			continue
		jobs.append(_region_job(region_id, path))
	return jobs

## Starts one model resource load without entering the heavy scheduler budget.
## The returned Resource is session-owned until execute_region_job consumes it.
static func request_region_job_resource(session: Dictionary, job: Dictionary) -> Dictionary:
	var validation := _validate_region_job(session, job)
	if validation.has("error"):
		return validation
	var path := String(validation.path)
	var loaded_resources: Dictionary = session.get("loaded_resources", {})
	if loaded_resources.has(path) and loaded_resources[path] is Resource:
		return {"state": "loaded", "path": path, "resource": loaded_resources[path], "cached": true}
	var resource_states: Dictionary = session.get("resource_states", {})
	var existing: Dictionary = resource_states.get(path, {})
	if String(existing.get("state", "")) == "loading":
		return poll_region_job_resource(session, job)
	if String(existing.get("state", "")) == "failed":
		return {
			"state": "failed",
			"path": path,
			"error": String(existing.get("error", "thread_load_failed")),
			"retryable": true,
		}
	if ResourceLoader.has_cached(path):
		var cached := load(path) as Resource
		if cached != null:
			_store_loaded_region_resource(session, path, cached, true)
			return {"state": "loaded", "path": path, "resource": cached, "cached": true}
	var requested_usec := Time.get_ticks_usec()
	var request_error := ResourceLoader.load_threaded_request(
		path,
		"",
		true,
		ResourceLoader.CACHE_MODE_REUSE
	)
	var status := ResourceLoader.load_threaded_get_status(path)
	if request_error != OK and status not in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED]:
		return _record_thread_load_failure(session, path, "thread_request_failed", request_error)
	resource_states[path] = {
		"state": "loading",
		"requested_usec": requested_usec,
		"wait_frames": 0,
	}
	session["resource_states"] = resource_states
	var report: Dictionary = session.report
	report.thread_requests += 1
	return poll_region_job_resource(session, job)

## Polls only. load_threaded_get() is called exclusively after LOADED, so this
## path never turns an asynchronous request back into a blocking frame.
static func poll_region_job_resource(session: Dictionary, job: Dictionary) -> Dictionary:
	var validation := _validate_region_job(session, job)
	if validation.has("error"):
		return validation
	var path := String(validation.path)
	var loaded_resources: Dictionary = session.get("loaded_resources", {})
	if loaded_resources.has(path) and loaded_resources[path] is Resource:
		return {"state": "loaded", "path": path, "resource": loaded_resources[path], "cached": true}
	var resource_states: Dictionary = session.get("resource_states", {})
	var state: Dictionary = resource_states.get(path, {})
	if String(state.get("state", "")) == "failed":
		return {
			"state": "failed",
			"path": path,
			"error": String(state.get("error", "thread_load_failed")),
			"retryable": true,
		}
	if state.is_empty():
		return {"state": "not_requested", "path": path, "error": "resource_not_requested", "retryable": true}
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			state.wait_frames = int(state.get("wait_frames", 0)) + 1
			state["progress"] = float(progress[0]) if not progress.is_empty() else 0.0
			resource_states[path] = state
			session["resource_states"] = resource_states
			var report: Dictionary = session.report
			report.thread_wait_frames += 1
			return {
				"state": "loading",
				"path": path,
				"progress": float(state.get("progress", 0.0)),
				"wait_frames": int(state.wait_frames),
			}
		ResourceLoader.THREAD_LOAD_LOADED:
			var resource := ResourceLoader.load_threaded_get(path) as Resource
			if resource == null:
				return _record_thread_load_failure(session, path, "thread_result_missing", FAILED)
			_store_loaded_region_resource(session, path, resource, false)
			return {
				"state": "loaded",
				"path": path,
				"resource": resource,
				"cached": false,
				"wait_frames": int(state.get("wait_frames", 0)),
			}
		ResourceLoader.THREAD_LOAD_FAILED:
			return _record_thread_load_failure(session, path, "thread_load_failed", FAILED)
		_:
			return _record_thread_load_failure(session, path, "thread_request_invalid", ERR_INVALID_DATA)

static func _validate_region_job(session: Dictionary, job: Dictionary) -> Dictionary:
	if not bool(session.get("valid", false)) or not bool(session.get("active", false)):
		return {"error": "inactive_session", "retryable": true}
	var path := String(job.get("path", ""))
	if path.is_empty() or not session.get("paths", []).has(path):
		return {"error": "job_outside_session", "retryable": false}
	if not ResourceLoader.exists(path):
		_record_session_failure(session, path, "missing_resource", 0, true)
		return {"state": "failed", "path": path, "error": "missing_resource", "retryable": true}
	return {"path": path}

static func _store_loaded_region_resource(session: Dictionary, path: String, resource: Resource, cached: bool) -> void:
	var loaded_resources: Dictionary = session.get("loaded_resources", {})
	loaded_resources[path] = resource
	session["loaded_resources"] = loaded_resources
	var resource_states: Dictionary = session.get("resource_states", {})
	var previous: Dictionary = resource_states.get(path, {})
	resource_states[path] = {
		"state": "loaded",
		"requested_usec": int(previous.get("requested_usec", Time.get_ticks_usec())),
		"loaded_usec": Time.get_ticks_usec(),
		"wait_frames": int(previous.get("wait_frames", 0)),
		"cached": cached,
	}
	session["resource_states"] = resource_states
	var report: Dictionary = session.report
	if cached:
		report.thread_cache_hits += 1
	else:
		report.thread_loaded += 1

static func _record_thread_load_failure(session: Dictionary, path: String, reason: String, error_code: int) -> Dictionary:
	var resource_states: Dictionary = session.get("resource_states", {})
	resource_states[path] = {
		"state": "failed",
		"error": reason,
		"error_code": error_code,
		"retryable": true,
	}
	session["resource_states"] = resource_states
	var report: Dictionary = session.report
	report.thread_failures += 1
	_record_session_failure(session, path, reason, 0, true, error_code)
	return {
		"state": "failed",
		"path": path,
		"error": reason,
		"error_code": error_code,
		"retryable": true,
	}

static func _record_session_failure(
	session: Dictionary,
	path: String,
	reason: String,
	actual_usec: int,
	retryable: bool,
	error_code := OK,
	stage_timings: Dictionary = {}
) -> void:
	var report: Dictionary = session.get("report", {})
	if report.is_empty():
		return
	for failure in report.get("failed_models", []):
		if String(failure.get("path", "")) == path and String(failure.get("reason", "")) == reason:
			return
	var failure := {
		"path": path,
		"reason": reason,
		"actual_usec": actual_usec,
		"retryable": retryable,
		"error_code": error_code,
	}
	if not stage_timings.is_empty():
		failure["stage_timings"] = stage_timings.duplicate(true)
	report.failed_models.append(failure)

## Advances one resumable stage. Waiting for threaded IO or the scheduler happens
## outside this method and is never included in `actual_usec`. The cache entry is
## kept private in `pending_entry` until the final commit publishes `_models` and
## `_prepared` together.
static func advance_region_job(
	session: Dictionary,
	job: Dictionary,
	loaded_resource: Resource = null,
	scheduler_ticket: Dictionary = {}
) -> Dictionary:
	var validation := _validate_region_job(session, job)
	var path := String(job.get("path", ""))
	var result := {
		"path": path,
		"complete": false,
		"executed": false,
		"actual_usec": 0,
		"retryable": true,
	}
	if validation.has("error"):
		result["error"] = validation.error
		result["retryable"] = bool(validation.get("retryable", true))
		return result
	if _prepared.has(path):
		result["complete"] = true
		result["already_prepared"] = true
		return result
	if _operationally_warmed_paths.has(path):
		result["complete"] = true
		result["already_warmed_operationally"] = true
		return result
	var warmup_view := session.get("warmup_view") as SubViewport
	if not is_instance_valid(warmup_view):
		result["error"] = "missing_warmup_view"
		return result
	if loaded_resource == null:
		var loaded_resources: Dictionary = session.get("loaded_resources", {})
		loaded_resource = loaded_resources.get(path) as Resource
	if loaded_resource == null:
		loaded_resource = load(path) as Resource
	var states: Dictionary = session.get("job_states", {})
	var state: Dictionary = states.get(path, {})
	if state.is_empty():
		var script := loaded_resource as Script
		if script == null:
			result["error"] = "model_resource_not_script"
			_record_session_failure(session, path, result.error, 0, true)
			return result
		if script.resource_path != path:
			result["error"] = "model_resource_path_mismatch"
			_record_session_failure(session, path, result.error, 0, true)
			return result
		state = {
			"path": path,
			"script": script,
			"stage": "construct_shell",
			"model": null,
			"prepared_root": null,
			"prepared_scene": null,
			"prepared_attach_children": [],
			"prepared_attach_index": 0,
			"prepared_attach_visible_child": null,
			"prepared_attach_rendered": false,
			"last_stage_detail": {},
			"pending_entry": {},
			"direct_prepared": false,
			"direct_runtime_metadata": {},
			"model_ready": false,
			"wheel_mounted": false,
			"wheel_mount_deferred_to_restore": false,
			"batched_removed": 0,
			"stage_timings": _empty_region_job_stage_timings(),
			"total_active_usec": 0,
			"started_usec": Time.get_ticks_usec(),
		}
		states[path] = state
		session["job_states"] = states
		_regional_capture_suppressed_paths[path] = int(_regional_capture_suppressed_paths.get(path, 0)) + 1
		var report: Dictionary = session.report
		report.cache_misses += 1
		_note_region_cold_start(path)

	var stage := String(state.get("stage", ""))
	state["last_stage_detail"] = {}
	var started := Time.get_ticks_usec()
	var stage_error := _execute_region_job_stage(state, warmup_view)
	var actual_usec := Time.get_ticks_usec() - started
	var timing_key := "%s_usec" % stage
	var stage_timings: Dictionary = state.get("stage_timings", {})
	stage_timings[timing_key] = int(stage_timings.get(timing_key, 0)) + actual_usec
	state["stage_timings"] = stage_timings
	state["total_active_usec"] = int(state.get("total_active_usec", 0)) + actual_usec
	states[path] = state
	session["job_states"] = states
	result["stage"] = stage
	result["next_stage"] = String(state.get("stage", ""))
	result["actual_usec"] = actual_usec
	result["total_active_usec"] = int(state.total_active_usec)
	result["over_budget"] = actual_usec > REGION_STAGE_BUDGET_USEC
	result["preparation"] = _region_job_summary(state)
	var stage_detail: Dictionary = (state.get("last_stage_detail", {}) as Dictionary).duplicate(true)
	result["stage_detail"] = stage_detail
	result["resource_reused"] = loaded_resource != null
	if not stage_error.is_empty():
		_record_region_stage_step(session.report, path, stage, actual_usec, scheduler_ticket, stage_detail)
		result["error"] = stage_error
		prepared_template_failures += 1
		_record_session_failure(session, path, stage_error, actual_usec, true, OK, stage_timings)
		_cleanup_region_job_state(state)
		states.erase(path)
		session["job_states"] = states
		_miss_started_usec.erase(path)
		return result
	if String(state.get("stage", "")) != "complete":
		_record_region_stage_step(session.report, path, stage, actual_usec, scheduler_ticket, stage_detail)
		return result

	var commit_tail_started := Time.get_ticks_usec()
	var pending_entry: Dictionary = state.get("pending_entry", {})
	if pending_entry.is_empty():
		_record_region_stage_step(session.report, path, stage, actual_usec, scheduler_ticket, stage_detail)
		result["error"] = "template_capture_failed"
		prepared_template_failures += 1
		_record_session_failure(session, path, result.error, actual_usec, true, OK, stage_timings)
		_cleanup_region_job_state(state)
		states.erase(path)
		session["job_states"] = states
		_miss_started_usec.erase(path)
		return result
	# Single synchronous commit: cacheable paths publish `_models` and `_prepared`
	# together. Operational-only paths publish only their distinct warm marker.
	var operational_only := bool(state.get("operational_only", false))
	if operational_only:
		# An explicit policy change must also invalidate any stale in-process entry.
		_models.erase(path)
		_prepared.erase(path)
		_operationally_warmed_paths[path] = true
		var operational_models: Array = session.report.get("operational_models_warmed", [])
		operational_models.append(path)
		session.report["operational_models_warmed"] = operational_models
	else:
		_models[path] = pending_entry
		_prepared[path] = true
		captures += 1
		prepared_template_captures += 1
	_cleanup_region_job_state(state)
	states.erase(path)
	session["job_states"] = states
	var resources: Dictionary = session.get("loaded_resources", {})
	resources.erase(path)
	session["loaded_resources"] = resources
	var commit_tail_usec := Time.get_ticks_usec() - commit_tail_started
	actual_usec += commit_tail_usec
	stage_timings[timing_key] = int(stage_timings.get(timing_key, 0)) + commit_tail_usec
	state["stage_timings"] = stage_timings
	state["total_active_usec"] = int(state.get("total_active_usec", 0)) + commit_tail_usec
	var report: Dictionary = session.report
	var total_active_usec := int(state.get("total_active_usec", 0))
	_finish_region_cold_telemetry(path, total_active_usec)
	if not operational_only:
		report.models_prepared += 1
	report.model_timings.append({
		"path": path,
		"actual_usec": total_active_usec,
		"direct_prepared": bool(state.get("direct_prepared", false)),
		"stage_timings": stage_timings.duplicate(true),
	})
	if total_active_usec > int(report.max_model_usec):
		report.max_model_usec = total_active_usec
		report.max_model_path = path
	result["complete"] = true
	result["executed"] = true
	result["actual_usec"] = actual_usec
	result["total_active_usec"] = total_active_usec
	result["over_budget"] = actual_usec > REGION_STAGE_BUDGET_USEC
	result["preparation"] = _region_job_summary(state)
	_record_region_stage_step(report, path, stage, actual_usec, scheduler_ticket, stage_detail)
	var session_id := int(session.get("id", 0))
	if _active_region_sessions.has(session_id):
		_active_region_sessions[session_id]["remaining_jobs"] = region_session_jobs(session).size()
	return result

## Compatibility for diagnostics that intentionally measure an entire model in
## one call. Runtime regional streaming must use `advance_region_job`.
static func execute_region_job(session: Dictionary, job: Dictionary, loaded_resource: Resource = null) -> Dictionary:
	var started := Time.get_ticks_usec()
	var step := advance_region_job(session, job, loaded_resource)
	while not step.has("error") and not bool(step.get("complete", false)):
		step = advance_region_job(session, job, loaded_resource)
	step["actual_usec"] = Time.get_ticks_usec() - started
	return step

static func should_defer_constructor(model: Node3D) -> bool:
	if model == null or model.get_script() == null:
		return false
	var path := String(model.get_script().resource_path)
	return int(_deferred_constructor_paths.get(path, 0)) > 0

static func _execute_region_job_stage(state: Dictionary, warmup_view: SubViewport) -> String:
	var stage := String(state.get("stage", ""))
	var model := state.get("model") as Node3D
	match stage:
		"construct_shell":
			var path := String(state.path)
			_deferred_constructor_paths[path] = int(_deferred_constructor_paths.get(path, 0)) + 1
			model = (state.script as Script).new() as Node3D
			var remaining := int(_deferred_constructor_paths.get(path, 1)) - 1
			if remaining <= 0:
				_deferred_constructor_paths.erase(path)
			else:
				_deferred_constructor_paths[path] = remaining
			if model == null:
				return "model_construction_failed"
			state["model"] = model
			state["stage"] = "strategy_select"
		"strategy_select":
			if model == null:
				return "model_construction_failed"
			if _model_requests_operational_only(model):
				state["operational_only"] = true
				state["operational_reason"] = "explicit_model_opt_out"
				state["stage"] = "procedural_build"
				return ""
			if model.has_method("vehicle_prepared_template_resource"):
				var prepared = model.call("vehicle_prepared_template_resource")
				if prepared is PackedScene:
					for required_method in [
						"prepare_vehicle_prewarm_materials",
						"validate_vehicle_prepared_template",
						"bind_vehicle_prepared_template_materials",
					]:
						if not model.has_method(required_method):
							return "incomplete_prepared_template_contract"
					state["prepared_scene"] = prepared
					state["direct_prepared"] = true
					state["stage"] = "prepared_materials"
					return ""
			state["stage"] = "procedural_build"
		"prepared_materials":
			model.call("prepare_vehicle_prewarm_materials")
			if not _model_has_cache_materials(model):
				return "prepared_materials_missing"
			state["stage"] = "prepared_scene_instantiate"
		"prepared_scene_instantiate":
			var prepared_root := (state.prepared_scene as PackedScene).instantiate() as Node3D
			if prepared_root == null:
				return "prepared_scene_instantiate_failed"
			state["prepared_root"] = prepared_root
			state["stage"] = "prepared_scene_validate"
		"prepared_scene_validate":
			var prepared_root := state.get("prepared_root") as Node3D
			if prepared_root == null or prepared_root.get_script() != null or not _static_children(prepared_root):
				return "prepared_scene_not_static"
			if not bool(model.call("validate_vehicle_prepared_template", prepared_root)):
				return "prepared_scene_contract_failed"
			if model.has_method("vehicle_prepared_template_runtime_metadata"):
				var runtime_metadata = model.call("vehicle_prepared_template_runtime_metadata", prepared_root)
				if not runtime_metadata is Dictionary:
					return "prepared_runtime_metadata_invalid"
				state["direct_runtime_metadata"] = (runtime_metadata as Dictionary).duplicate(true)
			state["stage"] = "prepared_scene_attach_begin"
		"prepared_scene_attach_begin":
			var prepared_root := state.get("prepared_root") as Node3D
			if prepared_root == null or prepared_root.is_inside_tree():
				return "prepared_scene_attach_root_invalid"
			# Detach every static presentation group before the root enters the
			# renderer. Adding the empty root is cheap; each group is then restored
			# by a separately scheduled slice on a later frame.
			var attach_children: Array[Node] = []
			for child in prepared_root.get_children():
				# This is the private warmup instance, never the PackedScene used by
				# restore. Clear ownership before temporary detachment so reattachment
				# cannot create an inconsistent owner chain or packing warnings.
				child.owner = null
				prepared_root.remove_child(child)
				attach_children.append(child)
			warmup_view.add_child(prepared_root)
			state["prepared_attach_children"] = attach_children
			state["prepared_attach_index"] = 0
			state["last_stage_detail"] = {
				"slice_index": -1,
				"slice_count": attach_children.size(),
				"unit_name": String(prepared_root.name),
			}
			state["stage"] = "prepared_scene_attach_slice" if not attach_children.is_empty() else "prepared_scene_attach_finish"
		"prepared_scene_attach_slice":
			var prepared_root := state.get("prepared_root") as Node3D
			var attach_children: Array = state.get("prepared_attach_children", []) as Array
			var attach_index := int(state.get("prepared_attach_index", 0))
			if prepared_root == null or not prepared_root.is_inside_tree():
				return "prepared_scene_attach_root_missing"
			if attach_index < 0 or attach_index >= attach_children.size():
				return "prepared_scene_attach_slice_out_of_range"
			var child := attach_children[attach_index] as Node
			if child == null or child.get_parent() != null:
				return "prepared_scene_attach_child_invalid"
			var previous_visible := state.get("prepared_attach_visible_child") as Node3D
			if is_instance_valid(previous_visible):
				previous_visible.visible = false
			model.call("bind_vehicle_prepared_template_materials", child)
			prepared_root.add_child(child)
			if child is Node3D:
				(child as Node3D).visible = true
				state["prepared_attach_visible_child"] = child
			# Rendering happens after this scheduled stage and before the next
			# reservation. Only the newly attached group remains visible, so upload,
			# shader and pipeline cost are attributed to this slice's adjacent frame.
			warmup_view.render_target_update_mode = SubViewport.UPDATE_ONCE
			state["last_stage_detail"] = {
				"slice_index": attach_index,
				"slice_count": attach_children.size(),
				"unit_name": String(child.name),
			}
			attach_index += 1
			state["prepared_attach_index"] = attach_index
			if attach_index >= attach_children.size():
				state["stage"] = "prepared_scene_attach_finish"
		"prepared_scene_attach_finish":
			var prepared_root := state.get("prepared_root") as Node3D
			var attach_children: Array = state.get("prepared_attach_children", []) as Array
			if prepared_root == null or prepared_root.get_child_count() != attach_children.size():
				return "prepared_scene_attach_incomplete"
			var previous_visible := state.get("prepared_attach_visible_child") as Node3D
			if is_instance_valid(previous_visible):
				previous_visible.visible = false
			# Never issue the old aggregate first draw. Restore authored visibility
			# only after disabling the private viewport; live cache restores remain
			# fully visible but perform no combined warmup render here.
			warmup_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			for child in prepared_root.get_children():
				if child is Node3D:
					(child as Node3D).visible = true
			state["prepared_attach_visible_child"] = null
			state["prepared_attach_rendered"] = true
			state["last_stage_detail"] = {
				"slice_index": attach_children.size(),
				"slice_count": attach_children.size(),
				"unit_name": String(prepared_root.name),
			}
			state["model_ready"] = true
			# The baked scene already carries validated wheel markers. Live pivots are
			# intentionally created per gameplay instance after cache restore.
			state["wheel_mount_deferred_to_restore"] = true
			state["stage"] = "prepared_entry_pack"
		"prepared_entry_pack":
			var direct_entry := _cache_entry_for_scene(
				model,
				state.prepared_scene as PackedScene,
				true,
				true,
				state.get("direct_runtime_metadata", {}) as Dictionary
			)
			if direct_entry.is_empty():
				return "prepared_entry_pack_failed"
			state["pending_entry"] = direct_entry
			state["stage"] = "viewport_request"
		"procedural_build":
			if model.get_child_count() == 0:
				if not model.has_method("build"):
					return "model_build_method_missing"
				model.call("build")
			if model.get_child_count() == 0:
				return "model_construction_failed"
			state["model_ready"] = true
			state["stage"] = "add_child_ready"
		"add_child_ready":
			warmup_view.add_child(model)
			state["stage"] = "wheel_mount"
		"wheel_mount":
			var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
			state["rig"] = rig
			state["wheel_mounted"] = rig.mount(model)
			state["stage"] = "batching"
		"batching":
			state["batched_removed"] = preload("res://cars/VehicleMeshBatcher.gd").batch_model(model)
			state["stage"] = "flatten"
		"flatten":
			_flatten_warmup_wheels(model, state.get("rig") as RefCounted)
			model.set_meta("vehicle_mesh_batched", true)
			state["stage"] = "capture_pack"
		"capture_pack":
			if bool(state.get("operational_only", false)) or not _supports(String(state.path)):
				# Operational-only models are warmed but never published into the restore
				# cache. Their constructor will still run when gameplay needs them.
				state["operational_only"] = true
				if String(state.get("operational_reason", "")).is_empty():
					state["operational_reason"] = "unsupported_cache_path"
				state["pending_entry"] = {"operational_only": true}
			else:
				var unsafe_references := _unsafe_operational_node_reference_properties(model)
				if not unsafe_references.is_empty():
					state["unsafe_reference_properties"] = unsafe_references
					return "unsafe_operational_node_references:%s" % ",".join(unsafe_references)
				var procedural_entry := _cache_entry_from_model(model, true)
				if procedural_entry.is_empty():
					return "template_capture_failed"
				state["pending_entry"] = procedural_entry
			state["stage"] = "viewport_request"
		"viewport_request":
			if bool(state.get("prepared_attach_rendered", false)):
				warmup_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			else:
				warmup_view.render_target_update_mode = SubViewport.UPDATE_ONCE
			state["stage"] = "commit"
		"commit":
			state["stage"] = "complete"
		_:
			return "invalid_region_job_stage"
	return ""

static func _region_job_summary(state: Dictionary) -> Dictionary:
	var path := String(state.get("path", ""))
	return {
		"path": path,
		"model_ready": bool(state.get("model_ready", false)),
		"wheel_mounted": bool(state.get("wheel_mounted", false)),
		"wheel_mount_deferred_to_restore": bool(state.get("wheel_mount_deferred_to_restore", false)),
		"batched_removed": int(state.get("batched_removed", 0)),
		"entry_ready": not (state.get("pending_entry", {}) as Dictionary).is_empty(),
		"captured": _models.has(path) and _prepared.has(path),
		"direct_prepared": bool(state.get("direct_prepared", false)),
		"operational_only": bool(state.get("operational_only", false)),
		"operational_reason": String(state.get("operational_reason", "")),
		"unsafe_reference_properties": state.get("unsafe_reference_properties", PackedStringArray()),
		"stage": String(state.get("stage", "")),
		"stage_timings": (state.get("stage_timings", {}) as Dictionary).duplicate(true),
		"stage_sum_usec": int(state.get("total_active_usec", 0)),
		"prepared_attach_index": int(state.get("prepared_attach_index", 0)),
		"prepared_attach_count": (state.get("prepared_attach_children", []) as Array).size(),
	}

static func _cleanup_region_job_state(state: Dictionary) -> void:
	# During resumable attachment, groups not reached yet are deliberately
	# parentless. Free them explicitly before freeing the staging root so cancel,
	# validation failure and retry cannot retain a partial template.
	for child_value in state.get("prepared_attach_children", []):
		var child := child_value as Node
		if is_instance_valid(child) and child.get_parent() == null:
			child.free()
	state["prepared_attach_children"] = []
	var prepared_root := state.get("prepared_root") as Node3D
	if is_instance_valid(prepared_root):
		prepared_root.free()
	var model := state.get("model") as Node3D
	if is_instance_valid(model):
		model.free()
	state["prepared_root"] = null
	state["model"] = null
	state.erase("rig")
	var path := String(state.get("path", ""))
	var remaining_suppression := int(_regional_capture_suppressed_paths.get(path, 1)) - 1
	if remaining_suppression <= 0:
		_regional_capture_suppressed_paths.erase(path)
	else:
		_regional_capture_suppressed_paths[path] = remaining_suppression

static func _note_region_cold_start(path: String) -> void:
	misses += 1
	regional_misses += 1
	if not _miss_started_usec.has(path):
		_miss_started_usec[path] = Time.get_ticks_usec()
	last_model_key = path

static func _record_region_stage_step(
	report: Dictionary,
	path: String,
	stage: String,
	actual_usec: int,
	scheduler_ticket: Dictionary = {},
	stage_detail: Dictionary = {}
) -> void:
	report.stage_steps_executed = int(report.get("stage_steps_executed", 0)) + 1
	var steps: Array = report.get("stage_steps", [])
	var step := {
		"path": path,
		"stage": stage,
		"actual_usec": actual_usec,
		"over_budget": actual_usec > REGION_STAGE_BUDGET_USEC,
		"ticket_id": int(scheduler_ticket.get("id", -1)),
		"frame": int(scheduler_ticket.get("frame", Engine.get_process_frames())),
		"producer": String(scheduler_ticket.get("producer", "")),
		"expected_usec": int(scheduler_ticket.get("expected_usec", REGION_STAGE_BUDGET_USEC)),
		"waited_frames": int(scheduler_ticket.get("waited_frames", 0)),
		"stage_detail": stage_detail.duplicate(true),
	}
	for key in stage_detail:
		step[key] = stage_detail[key]
	steps.append(step)
	if steps.size() > REGION_STAGE_TELEMETRY_LIMIT:
		steps.pop_front()
		report["stage_steps_dropped"] = int(report.get("stage_steps_dropped", 0)) + 1
	report["stage_steps"] = steps
	var totals: Dictionary = report.get("stage_totals_usec", {})
	var timing_key := "%s_usec" % stage
	totals[timing_key] = int(totals.get(timing_key, 0)) + actual_usec
	report["stage_totals_usec"] = totals
	report["last_stage_timing"] = steps.back().duplicate(true)
	if actual_usec > int(report.get("max_stage_usec", 0)):
		report["max_stage_usec"] = actual_usec
		report["max_stage"] = stage
		report["max_stage_path"] = path
	if actual_usec > REGION_STAGE_BUDGET_USEC:
		var over_budget: Array = report.get("over_budget_stages", [])
		over_budget.append(steps.back().duplicate(true))
		if over_budget.size() > REGION_STAGE_TELEMETRY_LIMIT:
			over_budget.pop_front()
		report["over_budget_stages"] = over_budget

static func finish_region_session(session: Dictionary, cancelled := false) -> Dictionary:
	var report: Dictionary = session.get("report", {})
	if report.is_empty():
		return report
	if not bool(session.get("active", false)):
		return report.duplicate(true)
	var job_states: Dictionary = session.get("job_states", {})
	for path_value in job_states:
		var path := String(path_value)
		_cleanup_region_job_state(job_states[path])
		_miss_started_usec.erase(path)
	job_states.clear()
	session["job_states"] = job_states
	session.active = false
	report.cancelled = cancelled
	report.completed = not cancelled and region_session_jobs_for_paths(session.get("paths", [])).is_empty()
	var uncached_paths: Array[String] = []
	for path_value in session.get("paths", []):
		var path := String(path_value)
		if ResourceLoader.exists(path) and not _models.has(path):
			uncached_paths.append(path)
	report.uncached_models = uncached_paths
	report["cached_models"] = int(report.requested_models) - uncached_paths.size()
	report["geometry_misses"] = misses - int(session.get("misses_before", misses))
	report["cold_builds"] = cold_builds - int(session.get("cold_builds_before", cold_builds))
	report["cold_build_usec"] = cold_build_usec - int(session.get("cold_build_usec_before", cold_build_usec))
	report["regional_misses"] = regional_misses - int(session.get("regional_misses_before", regional_misses))
	report["regional_cold_builds"] = regional_cold_builds - int(session.get("regional_cold_builds_before", regional_cold_builds))
	report["regional_cold_build_usec"] = regional_cold_build_usec - int(session.get("regional_cold_build_usec_before", regional_cold_build_usec))
	report.elapsed_usec = Time.get_ticks_usec() - int(session.get("started_usec", Time.get_ticks_usec()))
	report.memory_after_bytes = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	report.memory_delta_bytes = int(report.memory_after_bytes) - int(report.memory_before_bytes)
	report.retained_models = _models.size()
	var region_id := StringName(session.get("region", &""))
	if bool(report.completed):
		_retained_regions[region_id] = session.get("paths", []).duplicate()
	_region_reports[region_id] = report.duplicate(true)
	_last_prewarm_report = report.duplicate(true)
	if region_id == &"harbor" and bool(report.completed):
		_post_prewarm_misses_baseline = misses
		_post_prewarm_cold_builds_baseline = cold_builds
		_post_prewarm_cold_build_usec_baseline = cold_build_usec
		_prewarm_complete = true
	_active_region_sessions.erase(int(session.get("id", 0)))
	var warmup_view := session.get("warmup_view") as SubViewport
	if is_instance_valid(warmup_view):
		warmup_view.queue_free()
	session.warmup_view = null
	var loaded_resources: Dictionary = session.get("loaded_resources", {})
	loaded_resources.clear()
	session["loaded_resources"] = loaded_resources
	var resource_states: Dictionary = session.get("resource_states", {})
	resource_states.clear()
	session["resource_states"] = resource_states
	return report.duplicate(true)

static func region_session_jobs_for_paths(paths: Array) -> Array[String]:
	var remaining: Array[String] = []
	for path_value in paths:
		var path := String(path_value)
		if ResourceLoader.exists(path) and not _prepared.has(path) and not _operationally_warmed_paths.has(path):
			remaining.append(path)
	return remaining

static func _create_warmup_view(tree: SceneTree, region_id: StringName, session_id: int) -> SubViewport:
	var warmup_view := SubViewport.new()
	warmup_view.name = "VehicleWarmupViewport_%s_%d" % [String(region_id), session_id]
	warmup_view.size = Vector2i(96, 96)
	warmup_view.own_world_3d = true
	warmup_view.transparent_bg = true
	warmup_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(warmup_view)
	var cam := Camera3D.new()
	warmup_view.add_child(cam)
	cam.look_at_from_position(Vector3(0, 8, 4), Vector3(0, 0.45, 0), Vector3.UP)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.0
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	warmup_view.add_child(sun)
	return warmup_view

static func _region_job(region_id: StringName, path: String) -> Dictionary:
	return {
		"region": region_id,
		"path": path,
		"producer": StringName("vehicle_prewarm:%s" % String(region_id)),
		"priority": 100,
		"estimated_usec": 6000,
		"cancel_granularity": "between_stages",
	}

## Stable job descriptors used by loading diagnostics and by the runtime
## coordinator before it opens a session.
static func region_jobs(region_id: StringName, tree: SceneTree) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	for path in _region_model_paths(region_id, tree):
		if _prepared.has(path) or _operationally_warmed_paths.has(path) or not ResourceLoader.exists(path):
			continue
		jobs.append(_region_job(region_id, path))
	return jobs

static func region_telemetry(region_id: StringName = &"") -> Dictionary:
	if region_id != &"":
		return _region_reports.get(region_id, {}).duplicate(true)
	return {
		"regions": _region_reports.duplicate(true),
		"active_sessions": _active_region_sessions.duplicate(true),
		"retained_regions": _retained_regions.duplicate(true),
		"retained_models": _models.size(),
		"prepared_paths": _prepared.size(),
		"memory_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"eviction_supported": false,
		"eviction_note": "Cache entries are retained because live instances are not reference-tracked.",
	}

## Runtime readiness requires a packed template for every cacheable model and a
## distinct completed warm marker for explicit/unsupported operational models.
## Operational markers never authorize restore and never imply `_prepared`.
static func region_cache_readiness(region_id: StringName, tree: SceneTree) -> Dictionary:
	var requested := _region_model_paths(region_id, tree)
	var supported: Array[String] = []
	var missing: Array[String] = []
	var operational_ready: Array[String] = []
	for path in requested:
		if _operationally_warmed_paths.has(path):
			operational_ready.append(path)
			continue
		if not _supports(path):
			continue
		supported.append(path)
		if not _models.has(path):
			missing.append(path)
	return {
		"region": String(region_id),
		"requested_models": requested.size(),
		"supported_models": supported.size(),
		"ready_models": supported.size() - missing.size(),
		"operational_ready_models": operational_ready.size(),
		"operational_ready_paths": operational_ready,
		"missing_supported_paths": missing,
		"ready": missing.is_empty(),
	}

static func _region_model_paths(region_id: StringName, tree: SceneTree) -> Array[String]:
	var paths := preload("res://cars/VehiclePrewarmManifest.gd").model_paths(region_id)
	if region_id != &"harbor":
		return paths
	# Include authored/saved Harbor actors already materialized before loading.
	for group in ["modern_traffic", "modern_parked_vehicle", "regional_coach"]:
		for vehicle in tree.get_nodes_in_group(group):
			if not is_instance_valid(vehicle): continue
			var pending_spec = vehicle.get("_pending_spec")
			if not pending_spec is Dictionary or pending_spec.is_empty(): continue
			var path := String(pending_spec.get("model_class", ""))
			if not path.is_empty() and ResourceLoader.exists(path) and not paths.has(path):
				paths.append(path)
	paths.sort()
	return paths

static func _cancel_requested(cancel_check: Callable) -> bool:
	return cancel_check.is_valid() and bool(cancel_check.call())

static func prepare_resident_presentations(tree: SceneTree) -> int:
	var batch := preload("res://ui/LoadingWorkBatch.gd").new()
	# Only the entry view belongs on the critical loading path. Deferred actors
	# already keep a lightweight silhouette and remain queued in PresentationBudget,
	# which resolves them shortly before they enter the camera. Building the whole
	# city's rigs here made every save wait for distant residents it could not see.
	var prepared := 0
	for vehicle in tree.get_nodes_in_group("modern_traffic"):
		if not is_instance_valid(vehicle) or not vehicle.has_method("ensure_presentation"): continue
		if vehicle.get("_pending_spec") == null or vehicle.get("_pending_spec").is_empty(): continue
		if not is_startup_relevant(vehicle): continue
		await batch.checkpoint(tree)
		if not is_instance_valid(vehicle) or not vehicle.is_inside_tree(): continue
		vehicle.ensure_presentation()
		prepared += 1
	for car in tree.get_nodes_in_group("modern_parked_vehicle") + tree.get_nodes_in_group("regional_coach"):
		if not is_instance_valid(car) or not car.has_method("ensure_presentation"): continue
		if car.get("_pending_spec") == null or car.get("_pending_spec").is_empty(): continue
		if not is_startup_relevant(car): continue
		await batch.checkpoint(tree)
		if not is_instance_valid(car) or not car.is_inside_tree(): continue
		car.ensure_presentation()
		prepared += 1
	for walker in tree.get_nodes_in_group("pedestrian") + tree.get_nodes_in_group("authored_sidewalk_pedestrian"):
		if not is_instance_valid(walker) or not walker.has_method("ensure_presentation"): continue
		if walker.get("viewport") != null: continue
		if not is_startup_relevant(walker): continue
		await batch.checkpoint(tree)
		if not is_instance_valid(walker) or not walker.is_inside_tree(): continue
		walker.ensure_presentation()
		prepared += 1
	for signal_post in tree.get_nodes_in_group("fixed_traffic_signal"):
		if not is_instance_valid(signal_post) or not signal_post.has_method("ensure_presentation"): continue
		if not is_startup_relevant(signal_post): continue
		await batch.checkpoint(tree)
		if not is_instance_valid(signal_post) or not signal_post.is_inside_tree(): continue
		var original_state: int = int(signal_post.get("signal_state"))
		for state in [0, 1, 2]:
			signal_post.signal_state = state
			signal_post.ensure_presentation()
		signal_post.signal_state = original_state
		signal_post.ensure_presentation()
		prepared += 1
	return prepared

static func restore(model: Node3D) -> bool:
	var started := Time.get_ticks_usec()
	var key: String = model.get_script().resource_path
	if _model_requests_operational_only(model): return false
	if not _supports(key): return false
	if not _models.has(key):
		misses += 1
		if not _miss_started_usec.has(key):
			_miss_started_usec[key] = started
		restore_usec += Time.get_ticks_usec() - started
		last_model_key = key
		return false
	var data: Dictionary = _models[key]
	var raw: Node3D = data.scene.instantiate()
	var copies := {}
	model.materials = {}
	for role in data.materials:
		model.materials[role] = _material(data.materials[role],copies)
	if "vehicle_id" in model: model.vehicle_id = data.get("vehicle_id", "")
	if "paint" in model:
		model.paint = _material(data.get("paint"), copies)
		if model.paint == null and model.materials.has("paint"):
			model.paint = model.materials["paint"]
	if bool(data.get("direct_prepared_resource", false)) and model.has_method("bind_vehicle_prepared_template_materials"):
		model.call("bind_vehicle_prepared_template_materials", raw)
	else:
		_rebind(raw,copies)
	_own_children(raw,null)
	for metadata in raw.get_meta_list(): model.set_meta(metadata,raw.get_meta(metadata))
	for metadata in data.get("model_metadata", {}):
		model.set_meta(metadata, data.model_metadata[metadata])
	for child in raw.get_children():
		raw.remove_child(child)
		model.add_child(child)
	raw.free()
	hits += 1
	restore_usec += Time.get_ticks_usec() - started
	last_model_key = key
	return true

static func capture(model: Node3D, replace_existing := false) -> void:
	var started := Time.get_ticks_usec()
	var key: String = model.get_script().resource_path
	if _model_requests_operational_only(model): return
	if not _supports(key): return
	# Some models call capture() from build/_ready. A regional job owns an atomic
	# pending entry, so those nested calls must never publish `_models` early.
	if int(_regional_capture_suppressed_paths.get(key, 0)) > 0:
		last_model_key = key
		return
	if (_models.has(key) and not replace_existing) or not _static_children(model):
		_finish_capture_telemetry(key, started)
		return
	# Equipamentos com âncoras de operação (canhão d'água, guindaste) ainda
	# precisam executar seu construtor para ligar as referências de gameplay.
	var is_motorcycle := key.begins_with("res://cars/motorcycles/")
	# A model that was safely captured by its constructor may gain transient Node
	# references in _ready() (damage originals, lamp lists). The prepared template
	# packs a plain root and excludes those references, so they must not veto the
	# loading-time replacement of an already-known-safe cache entry.
	var replacing_safe_entry := replace_existing and _models.has(key)
	for property in model.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and _has_node_reference(model.get(property.name)):
			# MotorcycleModel owns runtime rider/pose references. Its cache is captured
			# before those dynamic accessories are created; restore then builds that
			# small runtime layer afresh. Other authored vehicles keep the conservative
			# rejection.
			if not is_motorcycle and not replacing_safe_entry:
				_finish_capture_telemetry(key, started)
				return
	var entry := _cache_entry_from_model(model, replace_existing)
	if not entry.is_empty():
		_models[key] = entry
		captures += 1
	_finish_capture_telemetry(key, started)

static func _cache_entry_from_model(model: Node3D, prepared_presentation: bool) -> Dictionary:
	if model == null or not _static_children(model) or not _model_has_cache_materials(model):
		return {}
	var raw := _duplicate_presentation_root(model) if prepared_presentation else model.duplicate(0) as Node3D
	if raw == null:
		return {}
	var copies := {}
	var materials := {}
	for role in model.materials:
		materials[role] = _material(model.materials[role], copies)
	var paint := _material(model.paint, copies)
	_rebind(raw, copies)
	_own_children(raw, raw)
	var scene := PackedScene.new()
	var packed := scene.pack(raw) == OK
	raw.free()
	if not packed:
		return {}
	return {
		"scene": scene,
		"materials": materials,
		"paint": paint,
		"vehicle_id": model.get("vehicle_id") if "vehicle_id" in model else "",
		"prepared_presentation": prepared_presentation,
		"direct_prepared_resource": false,
	}

static func _cache_entry_for_scene(
	model: Node3D,
	scene: PackedScene,
	prepared_presentation: bool,
	direct_prepared_resource: bool,
	model_metadata: Dictionary = {}
) -> Dictionary:
	if model == null or scene == null or not _model_has_cache_materials(model):
		return {}
	var copies := {}
	var materials := {}
	for role in model.materials:
		materials[role] = _material(model.materials[role], copies)
	var paint := _material(model.paint, copies)
	if paint == null and materials.has("paint"):
		paint = materials["paint"]
	if paint == null:
		return {}
	return {
		"scene": scene,
		"materials": materials,
		"paint": paint,
		"vehicle_id": model.get("vehicle_id") if "vehicle_id" in model else "",
		"prepared_presentation": prepared_presentation,
		"direct_prepared_resource": direct_prepared_resource,
		"model_metadata": model_metadata.duplicate(true),
	}

static func _model_has_cache_materials(model: Node3D) -> bool:
	if model == null:
		return false
	var model_materials = model.get("materials")
	return model_materials is Dictionary and not model_materials.is_empty() and model.get("paint") is Material

static func telemetry() -> Dictionary:
	# O(1) cumulative counters: the frame-stall tracer can diff snapshots without
	# walking vehicle nodes or touching cached scenes.
	return {
		"hits": hits,
		"misses": misses,
		"captures": captures,
		"models": _models.size(),
		"restore_usec": restore_usec,
		"capture_usec": capture_usec,
		"cold_builds": cold_builds,
		"cold_build_usec": cold_build_usec,
		"regional_misses": regional_misses,
		"regional_cold_builds": regional_cold_builds,
		"regional_cold_build_usec": regional_cold_build_usec,
		"max_cold_build_usec": max_cold_build_usec,
		"last_cold_build_usec": last_cold_build_usec,
		"last_model_key": last_model_key,
		"prepared_template_captures": prepared_template_captures,
		"prepared_template_failures": prepared_template_failures,
		"prewarm_complete": _prewarm_complete,
		"prewarm": _last_prewarm_report.duplicate(true),
		"regional_prewarm": region_telemetry(),
		"post_prewarm_misses": maxi(0, misses - _post_prewarm_misses_baseline) if _prewarm_complete else misses,
		"post_prewarm_cold_builds": maxi(0, cold_builds - _post_prewarm_cold_builds_baseline) if _prewarm_complete else cold_builds,
		"post_prewarm_cold_build_usec": maxi(0, cold_build_usec - _post_prewarm_cold_build_usec_baseline) if _prewarm_complete else cold_build_usec,
	}

static func _supports(key: String) -> bool:
	return key.begins_with("res://prototypes/living_cast/models/") or key.begins_with("res://prototypes/living_cast/") or key.begins_with("res://cars/motorcycles/")

static func _finish_capture_telemetry(key: String, capture_started: int) -> void:
	var finished := Time.get_ticks_usec()
	capture_usec += finished - capture_started
	last_model_key = key
	if not _miss_started_usec.has(key): return
	var elapsed := finished - int(_miss_started_usec[key])
	_miss_started_usec.erase(key)
	cold_builds += 1
	cold_build_usec += elapsed
	max_cold_build_usec = maxi(max_cold_build_usec, elapsed)
	last_cold_build_usec = elapsed

static func _finish_region_cold_telemetry(key: String, active_usec: int) -> void:
	# Regional jobs may wait many frames for scheduler reservations. Record only
	# active stage work so telemetry never presents queue latency as constructor CPU.
	_miss_started_usec.erase(key)
	last_model_key = key
	cold_builds += 1
	cold_build_usec += maxi(0, active_usec)
	regional_cold_builds += 1
	regional_cold_build_usec += maxi(0, active_usec)
	max_cold_build_usec = maxi(max_cold_build_usec, active_usec)
	last_cold_build_usec = maxi(0, active_usec)

## Builds the exact presentation form used by TrafficVehicle while the loading
## screen owns the frame budget. The packed template keeps carved bodywork and
## fused static surfaces, but wheel pivots remain per live actor.
static func _prepare_model_template(path: String, warmup_view: SubViewport, loaded_resource: Resource = null) -> Dictionary:
	var stage_timings := _empty_region_job_stage_timings()
	var result := {
		"path": path,
		"model_ready": false,
		"wheel_mounted": false,
		"batched_removed": 0,
		"captured": false,
		"stage_timings": stage_timings,
	}
	var script := loaded_resource as Script if loaded_resource != null else load(path) as Script
	if script == null:
		result["resource_error"] = "model_resource_not_script"
		prepared_template_failures += 1
		return result
	if loaded_resource != null and script.resource_path != path:
		result["resource_error"] = "model_resource_path_mismatch"
		prepared_template_failures += 1
		return result
	var stage_started := Time.get_ticks_usec()
	var model := script.new() as Node3D
	stage_timings["script_new_packed_scene_instantiate_usec"] = Time.get_ticks_usec() - stage_started
	if model == null:
		prepared_template_failures += 1
		return result
	stage_started = Time.get_ticks_usec()
	warmup_view.add_child(model)
	stage_timings["add_child_ready_usec"] = Time.get_ticks_usec() - stage_started
	result.model_ready = true
	var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
	stage_started = Time.get_ticks_usec()
	result.wheel_mounted = rig.mount(model)
	stage_timings["wheel_mount_usec"] = Time.get_ticks_usec() - stage_started
	stage_started = Time.get_ticks_usec()
	result.batched_removed = preload("res://cars/VehicleMeshBatcher.gd").batch_model(model)
	stage_timings["batching_usec"] = Time.get_ticks_usec() - stage_started
	# Pivots/spinners carry live steering state. Flatten their already-fused mesh
	# descendants so the cached template again exposes authored wheel metadata to
	# the runtime rig without retaining shared animation nodes.
	stage_started = Time.get_ticks_usec()
	_flatten_warmup_wheels(model, rig)
	stage_timings["flatten_usec"] = Time.get_ticks_usec() - stage_started
	stage_started = Time.get_ticks_usec()
	model.set_meta("vehicle_mesh_batched", true)
	capture(model, true)
	stage_timings["capture_pack_usec"] = Time.get_ticks_usec() - stage_started
	result.captured = _models.has(path) and bool(_models[path].get("prepared_presentation", false))
	if result.captured:
		prepared_template_captures += 1
	else:
		prepared_template_failures += 1
	stage_started = Time.get_ticks_usec()
	warmup_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	stage_timings["viewport_request_usec"] = Time.get_ticks_usec() - stage_started
	stage_started = Time.get_ticks_usec()
	model.free()
	stage_timings["model_free_usec"] = Time.get_ticks_usec() - stage_started
	return result

static func _empty_region_job_stage_timings() -> Dictionary:
	var result := {}
	for stage in REGION_JOB_STAGE_KEYS:
		result[stage] = 0
	return result

static func _sum_region_job_stage_timings(stage_timings: Dictionary, include_unattributed := false) -> int:
	var total := 0
	for stage in REGION_JOB_STAGE_KEYS:
		total += int(stage_timings.get(stage, 0))
	if include_unattributed:
		total += int(stage_timings.get("instrumentation_unattributed_usec", 0))
	return total

static func _record_region_job_stage_telemetry(
	report: Dictionary,
	path: String,
	actual_usec: int,
	stage_timings: Dictionary
) -> void:
	report["last_stage_timing"] = {
		"path": path,
		"actual_usec": actual_usec,
		"stage_timings": stage_timings.duplicate(true),
	}
	var totals: Dictionary = report.get("stage_totals_usec", {})
	if totals.is_empty():
		totals = _empty_region_job_stage_timings()
		totals["instrumentation_unattributed_usec"] = 0
	for stage in REGION_JOB_STAGE_KEYS:
		totals[stage] = int(totals.get(stage, 0)) + int(stage_timings.get(stage, 0))
	totals["instrumentation_unattributed_usec"] = (
		int(totals.get("instrumentation_unattributed_usec", 0))
		+ int(stage_timings.get("instrumentation_unattributed_usec", 0))
	)
	report["stage_totals_usec"] = totals

static func _flatten_warmup_wheels(model: Node3D, rig: RefCounted) -> void:
	# Pivots/spinners belong to the live actor's rig state, not to shared geometry.
	# Move their already-batched mesh children back to the model before packing.
	for pivot in rig.pivots:
		if not is_instance_valid(pivot): continue
		_flatten_mesh_descendants(pivot, model)
		pivot.free()

static func _flatten_mesh_descendants(parent: Node, model: Node3D) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D:
			child.reparent(model, true)
		elif child is Node3D:
			_flatten_mesh_descendants(child, model)

static func _duplicate_presentation_root(model: Node3D) -> Node3D:
	# Packing a plain root deliberately excludes runtime dictionaries such as
	# damage `originals`, whose Node references are rebuilt by _ready(). Children
	# are scriptless static presentation nodes (enforced by _static_children).
	var raw := Node3D.new()
	raw.name = model.name
	for metadata in model.get_meta_list():
		raw.set_meta(metadata, model.get_meta(metadata))
	for child in model.get_children():
		var copy := child.duplicate(0)
		if copy != null:
			raw.add_child(copy)
	return raw

static func _has_node_reference(value: Variant) -> bool:
	if value is Node: return true
	if value is Array:
		for item in value:
			if _has_node_reference(item): return true
	if value is Dictionary:
		for key in value:
			if _has_node_reference(key) or _has_node_reference(value[key]): return true
	return false

static func _model_requests_operational_only(model: Node3D) -> bool:
	if model == null or not model.has_method("vehicle_geometry_cache_operational_only"):
		return false
	return bool(model.call("vehicle_geometry_cache_operational_only"))

static func _unsafe_operational_node_reference_properties(model: Node3D) -> PackedStringArray:
	var unsafe := PackedStringArray()
	if model == null:
		return unsafe
	var key := String(model.get_script().resource_path) if model.get_script() != null else ""
	# MotorcycleModel has an explicit restore path that rebinds Rider/Stand and
	# articulated limb references by stable node names in _ready().
	if key.begins_with("res://cars/motorcycles/"):
		return unsafe
	# CoupeDamageModel rebuilds these transient references from restored children
	# every time _ready runs. No other Node-valued script property is assumed safe.
	var rebuilt_in_ready := {
		&"originals": true,
		&"damaged_vertices": true,
		&"lamp_sources": true,
		&"marks": true,
	}
	for property in model.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var property_name := StringName(property.name)
		if rebuilt_in_ready.has(property_name):
			continue
		if _has_node_reference(model.get(property_name)):
			unsafe.append(String(property_name))
	unsafe.sort()
	return unsafe

static func _static_children(node: Node) -> bool:
	for child in node.get_children():
		if child.get_script() != null or not _static_children(child): return false
	return true

static func _own_children(node: Node,owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own_children(child,owner_node)

static func _material(source: Material,copies: Dictionary) -> Material:
	if source == null: return null
	if not copies.has(source): copies[source] = source.duplicate()
	return copies[source]

static func _rebind(node: Node,copies: Dictionary) -> void:
	if node is GeometryInstance3D:
		node.material_override = _material(node.material_override,copies)
		node.material_overlay = _material(node.material_overlay,copies)
	for child in node.get_children(): _rebind(child,copies)
