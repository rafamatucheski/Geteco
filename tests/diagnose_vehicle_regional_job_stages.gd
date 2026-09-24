extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const STAGE_BUDGET_USEC := 6000
const MAX_STAGE_STEPS := 64
const MODEL_PATHS := {
	"snow_plow": "res://prototypes/living_cast/models/SnowPlowModel.gd",
	"ranch_single": "res://prototypes/living_cast/models/RanchSingleModel.gd",
}

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model_id := _requested_model_id()
	var model_path := String(MODEL_PATHS.get(model_id, ""))
	_check(not model_path.is_empty(), "model must be snow_plow or ranch_single")
	if model_path.is_empty():
		_finish({"model_id": model_id, "error": "unknown_model"})
		return
	_reset_model_caches(model_path)

	var session := CACHE.begin_region_session(self, &"mountain")
	var job := _job_for_path(CACHE.region_session_jobs(session), model_path)
	_check(not job.is_empty(), "Mountain session exposes %s" % model_path)
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		_finish({"model_id": model_id, "model_path": model_path, "error": "job_missing"})
		return

	var request_started := Time.get_ticks_usec()
	var resource_state := CACHE.request_region_job_resource(session, job)
	var request_usec := Time.get_ticks_usec() - request_started
	var wait_started := Time.get_ticks_usec()
	var wait_frames := 0
	while String(resource_state.get("state", "")) == "loading" and wait_frames < 600:
		await process_frame
		wait_frames += 1
		resource_state = CACHE.poll_region_job_resource(session, job)
	var wait_usec := Time.get_ticks_usec() - wait_started
	_check(not resource_state.has("error"), "threaded resource load succeeds")
	_check(resource_state.get("resource") is Script, "threaded resource resolves to the model Script")
	if resource_state.has("error") or not resource_state.get("resource") is Script:
		CACHE.finish_region_session(session, true)
		_finish({
			"model_id": model_id,
			"model_path": model_path,
			"request_usec": request_usec,
			"wait_usec": wait_usec,
			"wait_frames": wait_frames,
			"resource_state": resource_state,
		})
		return

	var execution: Dictionary = {"complete": false}
	var stage_advances: Array[Dictionary] = []
	var execution_started := Time.get_ticks_usec()
	for _step_index in MAX_STAGE_STEPS:
		execution = CACHE.advance_region_job(
			session,
			job,
			resource_state.get("resource") as Resource
		)
		stage_advances.append({
			"path": String(execution.get("path", model_path)),
			"stage": String(execution.get("stage", "")),
			"next_stage": String(execution.get("next_stage", "")),
			"actual_usec": int(execution.get("actual_usec", 0)),
			"over_budget": bool(execution.get("over_budget", false)),
		})
		if execution.has("error") or bool(execution.get("complete", false)):
			break
		await process_frame
	var execution_wall_usec := Time.get_ticks_usec() - execution_started
	var preparation: Dictionary = execution.get("preparation", {})
	var stages: Dictionary = preparation.get("stage_timings", {})
	_check(not execution.has("error"), "regional staged execution succeeds")
	_check(bool(execution.get("executed", false)), "regional job executes")
	_check(bool(execution.get("resource_reused", false)), "regional job reuses the threaded Script")
	_check(bool(execution.get("complete", false)), "regional job completes within the bounded stage count")
	_check(not stages.is_empty(), "regional job reports every measured stage")
	var report := CACHE.finish_region_session(session, false)
	var max_stage_usec := int(report.get("max_stage_usec", 0))
	var over_budget_stages: Array = report.get("over_budget_stages", [])
	_check(max_stage_usec <= STAGE_BUDGET_USEC, "%s has a stage above 6 ms: %s" % [model_id, JSON.stringify(over_budget_stages)])
	_check(over_budget_stages.is_empty(), "%s over-budget path/stages: %s" % [model_id, JSON.stringify(_over_budget_path_stages(over_budget_stages))])
	await process_frame
	await process_frame
	_finish({
		"model_id": model_id,
		"model_path": model_path,
		"request_usec": request_usec,
		"request_ms": request_usec / 1000.0,
		"async_wait_usec": wait_usec,
		"async_wait_ms": wait_usec / 1000.0,
		"async_wait_frames": wait_frames,
		"execution_wall_usec": execution_wall_usec,
		"execution_wall_ms": execution_wall_usec / 1000.0,
		"stage_budget_usec": STAGE_BUDGET_USEC,
		"stage_advances": stage_advances,
		"stage_timings_usec": stages,
		"stage_timings_ms": _stage_timings_ms(stages),
		"stage_sum_usec": preparation.get("stage_sum_usec", 0),
		"max_stage_usec": max_stage_usec,
		"max_stage_ms": max_stage_usec / 1000.0,
		"max_stage": report.get("max_stage", ""),
		"max_stage_path": report.get("max_stage_path", ""),
		"over_budget_stages": over_budget_stages,
		"over_budget_path_stages": _over_budget_path_stages(over_budget_stages),
		"report_last_stage": report.get("last_stage_timing", {}),
	})


func _requested_model_id() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("model="):
			return argument.trim_prefix("model=")
	return "snow_plow"


func _reset_model_caches(model_path: String) -> void:
	CACHE._models.erase(model_path)
	CACHE._prepared.erase(model_path)
	CACHE._miss_started_usec.erase(model_path)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()


func _job_for_path(jobs: Array[Dictionary], model_path: String) -> Dictionary:
	for job in jobs:
		if String(job.get("path", "")) == model_path:
			return job
	return {}


func _stage_timings_ms(stage_timings: Dictionary) -> Dictionary:
	var result := {}
	for stage in stage_timings:
		result[String(stage).trim_suffix("_usec") + "_ms"] = int(stage_timings[stage]) / 1000.0
	return result


func _over_budget_path_stages(over_budget_stages: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in over_budget_stages:
		var stage := value as Dictionary
		result.append({
			"path": String(stage.get("path", "")),
			"stage": String(stage.get("stage", "")),
			"actual_usec": int(stage.get("actual_usec", 0)),
		})
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(result: Dictionary) -> void:
	result["failures"] = failures
	print("VEHICLE_REGIONAL_JOB_STAGES ", JSON.stringify(result))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)
