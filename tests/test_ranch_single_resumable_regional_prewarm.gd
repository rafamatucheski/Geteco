extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const MODEL_PATH := "res://prototypes/living_cast/models/RanchSingleModel.gd"
const INVALID_MODEL_PATH := "res://tests/InvalidPreparedVehicleModel.gd"
const STAGE_BUDGET_USEC := 6000

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset_ranch_cache()
	_test_invalid_direct_resource_remains_retryable()
	_reset_ranch_cache()
	await _cancel_partial_job_without_publication()
	await _complete_resumable_job()
	print("RANCH_SINGLE_RESUMABLE_REGIONAL_PREWARM failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)


func _test_invalid_direct_resource_remains_retryable() -> void:
	CACHE._models.erase(INVALID_MODEL_PATH)
	CACHE._prepared.erase(INVALID_MODEL_PATH)
	var warmup_view := SubViewport.new()
	root.add_child(warmup_view)
	var report := {
		"cache_misses": 0,
		"failed_models": [],
		"stage_steps": [],
		"stage_steps_executed": 0,
		"stage_totals_usec": {},
		"max_stage_usec": 0,
		"max_stage": "",
		"max_stage_path": "",
		"over_budget_stages": [],
	}
	var session := {
		"valid": true,
		"active": true,
		"region": &"mountain",
		"paths": [INVALID_MODEL_PATH],
		"warmup_view": warmup_view,
		"loaded_resources": {INVALID_MODEL_PATH: load(INVALID_MODEL_PATH)},
		"job_states": {},
		"report": report,
	}
	var job := {"path": INVALID_MODEL_PATH, "region": &"mountain"}
	var result := {"complete": false}
	for _index in 12:
		result = CACHE.advance_region_job(session, job, session.loaded_resources[INVALID_MODEL_PATH] as Resource)
		if result.has("error"):
			break
	_check(String(result.get("error", "")) == "prepared_scene_contract_failed", "invalid direct prepared resource fails its semantic contract")
	_check(bool(result.get("retryable", false)), "invalid direct prepared resource failure remains retryable")
	_check(not CACHE._models.has(INVALID_MODEL_PATH), "invalid direct prepared resource never publishes _models")
	_check(not CACHE._prepared.has(INVALID_MODEL_PATH), "invalid direct prepared resource never publishes _prepared")
	_check((session.get("job_states", {}) as Dictionary).is_empty(), "invalid direct prepared resource releases its resumable state")
	_check(report.failed_models.size() == 1, "invalid direct prepared resource is explicit in failure telemetry")
	warmup_view.free()


func _cancel_partial_job_without_publication() -> void:
	var session := CACHE.begin_region_session(self, &"mountain")
	var job := _ranch_job(session)
	_check(not job.is_empty(), "Mountain session exposes RanchSingle")
	_check(String(job.get("cancel_granularity", "")) == "between_stages", "RanchSingle advertises cancellation between resumable stages")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		return
	var loaded := await _load_job_resource(session, job)
	_check(not loaded.has("error"), "RanchSingle threaded resource resolves before staged work")
	if loaded.has("error"):
		CACHE.finish_region_session(session, true)
		return
	var observed: Array[String] = []
	for _index in 4:
		var step := CACHE.advance_region_job(session, job, loaded.resource as Resource)
		observed.append(String(step.get("stage", "")))
		_check(not step.has("error"), "partial RanchSingle stage succeeds")
		_check(not CACHE._models.has(MODEL_PATH), "partial RanchSingle never publishes _models")
		_check(not CACHE._prepared.has(MODEL_PATH), "partial RanchSingle never publishes _prepared")
		await process_frame
	var cancelled := CACHE.finish_region_session(session, true)
	_check(bool(cancelled.get("cancelled", false)), "partial RanchSingle session is retryable cancellation")
	_check(not CACHE._models.has(MODEL_PATH), "cancelled RanchSingle leaves no cache template")
	_check(not CACHE._prepared.has(MODEL_PATH), "cancelled RanchSingle leaves no false prepared marker")
	_check(not CACHE._miss_started_usec.has(MODEL_PATH), "cancelled RanchSingle clears cold-build timing state")
	_check(not CACHE._deferred_constructor_paths.has(MODEL_PATH), "cancelled RanchSingle clears constructor deferral state")
	_check(not CACHE._regional_capture_suppressed_paths.has(MODEL_PATH), "cancelled RanchSingle clears capture suppression state")
	_check(observed == ["construct_shell", "strategy_select", "prepared_materials", "prepared_scene_instantiate"], "RanchSingle enters the direct prepared-resource path before cancellation")
	await process_frame


func _complete_resumable_job() -> void:
	var session := CACHE.begin_region_session(self, &"mountain")
	var job := _ranch_job(session)
	_check(not job.is_empty(), "resumed Mountain session keeps RanchSingle queued")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		return
	var loaded := await _load_job_resource(session, job)
	_check(not loaded.has("error"), "resumed RanchSingle reacquires its resource")
	if loaded.has("error"):
		CACHE.finish_region_session(session, true)
		return
	var stages: Array[String] = []
	var max_stage_usec := 0
	var result := {"complete": false}
	for _index in 32:
		_check(not CACHE._models.has(MODEL_PATH), "RanchSingle remains private until its commit stage")
		_check(not CACHE._prepared.has(MODEL_PATH), "RanchSingle is not falsely prepared between stages")
		result = CACHE.advance_region_job(session, job, loaded.resource as Resource)
		var stage := String(result.get("stage", ""))
		stages.append(stage)
		max_stage_usec = maxi(max_stage_usec, int(result.get("actual_usec", 0)))
		_check(not result.has("error"), "RanchSingle resumable stage succeeds: %s" % stage)
		_check(int(result.get("actual_usec", 0)) <= STAGE_BUDGET_USEC, "RanchSingle stage %s stays within 6 ms" % stage)
		if bool(result.get("complete", false)):
			break
		await process_frame
	_check(bool(result.get("complete", false)), "RanchSingle staged prewarm reaches atomic commit")
	_check(bool(result.get("executed", false)), "RanchSingle commit counts one completed model")
	_check(bool(result.get("preparation", {}).get("direct_prepared", false)), "RanchSingle publishes its validated prepared resource directly")
	_check(stages.count("prepared_scene_instantiate") == 1, "RanchSingle prepared resource is instantiated exactly once during prewarm")
	_check(not stages.has("procedural_build"), "RanchSingle prewarm does not rebuild procedural geometry")
	_check(not stages.has("capture_pack"), "RanchSingle direct publication avoids a second geometry capture")
	_check(CACHE._models.has(MODEL_PATH) and CACHE._prepared.has(MODEL_PATH), "RanchSingle publishes _models and _prepared together")
	_check(CACHE.regional_misses == 2 and CACHE.misses == CACHE.regional_misses, "cancel plus retry are attributed as two regional misses, not unscheduled gameplay misses")
	_check(CACHE.regional_cold_builds == 1 and CACHE.cold_builds == CACHE.regional_cold_builds, "only the committed RanchSingle build is attributed as regional cold work")
	_check(CACHE.regional_cold_build_usec > 0 and CACHE.cold_build_usec == CACHE.regional_cold_build_usec, "regional active work remains exactly subtractable from global cold-build time")
	if CACHE._models.has(MODEL_PATH):
		_check(bool(CACHE._models[MODEL_PATH].get("direct_prepared_resource", false)), "RanchSingle cache entry records direct prepared publication")

	var report := CACHE.finish_region_session(session, false)
	var ranch_steps: Array = []
	for step in report.get("stage_steps", []):
		if String(step.get("path", "")) == MODEL_PATH:
			ranch_steps.append(step)
	_check(ranch_steps.size() == stages.size(), "RanchSingle report retains telemetry for every active stage")
	_check(int(report.get("max_stage_usec", 0)) <= STAGE_BUDGET_USEC, "regional report keeps RanchSingle stages within 6 ms")
	_check((report.get("over_budget_stages", []) as Array).is_empty(), "regional report exposes no hidden RanchSingle over-budget stage")

	var script := load(MODEL_PATH) as Script
	var hits_before := CACHE.hits
	var live := script.new() as Node3D
	root.add_child(live)
	var sibling := script.new() as Node3D
	root.add_child(sibling)
	_check(CACHE.hits == hits_before + 2, "gameplay instances restore from the directly published cache")
	_check(_mesh_count(live) == 14 and _mesh_count(sibling) == 14, "direct restore preserves the compact RanchSingle geometry")
	_check(_surface_materials_match_runtime_roles(live), "direct restore rebinds every RanchSingle surface to this instance's materials")
	_check(_surface_materials_match_runtime_roles(sibling), "direct restore rebinds sibling surfaces without sharing materials")
	var originals := live.get("originals") as Dictionary
	var lamp_sources := live.get("lamp_sources") as Dictionary
	_check(not originals.is_empty(), "direct restore runs _ready and captures RanchSingle damage geometry")
	_check(lamp_sources.size() == 4, "direct restore runs _ready and captures four RanchSingle lamps")
	var live_paint := live.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	_check(live_paint != null and sibling_paint != null and live_paint != sibling_paint, "direct restore keeps paint independent per instance")
	if live_paint != null and sibling_paint != null:
		var sibling_color := sibling_paint.albedo_color
		live_paint.albedo_color = Color.CYAN
		_check(sibling_paint.albedo_color == sibling_color, "repainting one direct restore cannot recolor its sibling")
	var rig := WHEEL_RIG.new()
	_check(rig.mount(live) and rig.pivots.size() == 4, "direct restore remounts all four RanchSingle wheels")
	_check(BATCHER.batch_model(live) == 0, "direct restore never rebatches RanchSingle")
	_check(bool(live.get_meta("vehicle_mesh_batched", false)), "direct restore retains the prepared batching marker")
	_check(live.get_meta("ranch_single_geometry_source", &"") == &"prepared", "direct restore retains the RanchSingle prepared-source marker")
	live.call("apply_impact", Vector3(0.78, 0.82, -2.48), Vector3(-1.0, 0.0, 0.0), 12.0)
	_check(int(live.get("impact_count")) == 1 and bool((live.get("broken_lamps") as Array)[1]), "direct restore preserves localized RanchSingle body and lamp damage")
	live.call("repair")
	_check(int(live.get("impact_count")) == 0 and not bool((live.get("broken_lamps") as Array)[1]), "direct restore preserves RanchSingle repair")
	_check(max_stage_usec <= STAGE_BUDGET_USEC, "largest RanchSingle stage stays within the scheduler slice")
	live.free()
	sibling.free()


func _ranch_job(session: Dictionary) -> Dictionary:
	for job in CACHE.region_session_jobs(session):
		if String(job.get("path", "")) == MODEL_PATH:
			return job
	return {}


func _load_job_resource(session: Dictionary, job: Dictionary) -> Dictionary:
	var state := CACHE.request_region_job_resource(session, job)
	for _frame in 600:
		if String(state.get("state", "")) != "loading":
			return state
		await process_frame
		state = CACHE.poll_region_job_resource(session, job)
	return {"error": "thread_load_timeout", "retryable": true}


func _mesh_count(node: Node) -> int:
	var result := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		result += _mesh_count(child)
	return result


func _surface_materials_match_runtime_roles(model: Node3D) -> bool:
	var model_materials := model.get("materials") as Dictionary
	for child in model.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			continue
		var roles: PackedStringArray = part.get_meta(&"ranch_single_surface_material_keys", PackedStringArray())
		if roles.size() != part.mesh.get_surface_count():
			return false
		for surface_index in roles.size():
			var expected := model_materials.get(StringName(roles[surface_index])) as Material
			var actual := part.material_override
			if actual == null:
				actual = part.get_surface_override_material(surface_index)
			if actual != expected:
				return false
	return true


func _reset_ranch_cache() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._operationally_warmed_paths.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	CACHE._regional_capture_suppressed_paths.erase(MODEL_PATH)
	CACHE.misses = 0
	CACHE.cold_builds = 0
	CACHE.cold_build_usec = 0
	CACHE.regional_misses = 0
	CACHE.regional_cold_builds = 0
	CACHE.regional_cold_build_usec = 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
