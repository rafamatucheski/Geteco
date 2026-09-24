extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const MODEL_PATH := "res://prototypes/living_cast/models/ArcticJeepModel.gd"
const MAX_STAGES := 32


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset_caches()
	var session := CACHE.begin_region_session(self, &"mountain")
	var job: Dictionary = {}
	for candidate in CACHE.region_session_jobs(session):
		if String(candidate.get("path", "")) == MODEL_PATH:
			job = candidate
			break
	if job.is_empty():
		push_error("Mountain manifest does not expose ArcticJeep")
		CACHE.finish_region_session(session, true)
		quit(1)
		return
	var resource_state := CACHE.request_region_job_resource(session, job)
	var wait_frames := 0
	while String(resource_state.get("state", "")) == "loading" and wait_frames < 600:
		await process_frame
		wait_frames += 1
		resource_state = CACHE.poll_region_job_resource(session, job)
	if resource_state.has("error") or not resource_state.get("resource") is Script:
		push_error("ArcticJeep threaded load failed: %s" % resource_state)
		CACHE.finish_region_session(session, true)
		quit(1)
		return
	var steps: Array[Dictionary] = []
	var result: Dictionary = {"complete": false}
	for _index in MAX_STAGES:
		result = CACHE.advance_region_job(session, job, resource_state.get("resource") as Resource)
		steps.append({
			"stage": String(result.get("stage", "")),
			"actual_usec": int(result.get("actual_usec", 0)),
			"over_budget": bool(result.get("over_budget", false)),
		})
		if result.has("error") or bool(result.get("complete", false)):
			break
		await process_frame
	var report := CACHE.finish_region_session(session, result.has("error"))
	print("ARCTIC_JEEP_REGIONAL_PROFILE ", JSON.stringify({
		"complete": bool(result.get("complete", false)),
		"error": String(result.get("error", "")),
		"wait_frames": wait_frames,
		"steps": steps,
		"max_stage": String(report.get("max_stage", "")),
		"max_stage_usec": int(report.get("max_stage_usec", 0)),
		"total_active_usec": int(result.get("total_active_usec", 0)),
		"direct_prepared": bool(result.get("preparation", {}).get("direct_prepared", false)),
	}))
	quit(0 if bool(result.get("complete", false)) and not result.has("error") else 1)


func _reset_caches() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._operationally_warmed_paths.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	CACHE._regional_capture_suppressed_paths.erase(MODEL_PATH)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()
