extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/models/SnowPlowModel.gd"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const STAGE_BUDGET_USEC := 6000

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()

	var session := CACHE.begin_region_session(self, &"mountain")
	_check(bool(session.get("valid", false)), "Mountain regional prewarm session opens")
	var snow_job: Dictionary = {}
	for job in CACHE.region_session_jobs(session):
		if String(job.get("path", "")) == MODEL_PATH:
			snow_job = job
			break
	_check(not snow_job.is_empty(), "Mountain manifest exposes the SnowPlow job")
	if snow_job.is_empty():
		CACHE.finish_region_session(session, true)
		_finish({"error": "snow_job_missing"})
		return

	var request_started := Time.get_ticks_usec()
	var resource_state := CACHE.request_region_job_resource(session, snow_job)
	var request_usec := Time.get_ticks_usec() - request_started
	var async_started := Time.get_ticks_usec()
	var wait_frames := 0
	while String(resource_state.get("state", "")) == "loading" and wait_frames < 600:
		_check(not CACHE._prepared.has(MODEL_PATH), "Threaded SnowPlow load does not mark the model prepared")
		await process_frame
		wait_frames += 1
		resource_state = CACHE.poll_region_job_resource(session, snow_job)
	var async_wait_usec := Time.get_ticks_usec() - async_started
	_check(not resource_state.has("error"), "Threaded SnowPlow resource load succeeds: %s" % resource_state)
	_check(String(resource_state.get("state", "")) == "loaded", "Threaded SnowPlow resource becomes ready without blocking execution")
	_check(resource_state.get("resource") is Resource, "Threaded SnowPlow load returns a reusable Resource")
	_check(not CACHE._prepared.has(MODEL_PATH), "Resource readiness alone does not mark SnowPlow prepared")
	if resource_state.has("error") or not resource_state.get("resource") is Resource:
		CACHE.finish_region_session(session, true)
		_finish({"error": "snow_resource_load_failed", "resource_state": resource_state})
		return

	var result: Dictionary = {"complete": false}
	var stages: Array[String] = []
	var max_stage_usec := 0
	for _index in 32:
		result = CACHE.advance_region_job(
			session,
			snow_job,
			resource_state.get("resource") as Resource
		)
		var stage := String(result.get("stage", ""))
		var stage_usec := int(result.get("actual_usec", 0))
		stages.append(stage)
		max_stage_usec = maxi(max_stage_usec, stage_usec)
		_check(stage_usec <= STAGE_BUDGET_USEC, "SnowPlow regional stage %s stays within 6 ms, got %.3f ms" % [stage, stage_usec / 1000.0])
		if result.has("error") or bool(result.get("complete", false)):
			break
		await process_frame
	var actual_usec := int(result.get("total_active_usec", 0))
	var stage_timings: Dictionary = result.get("preparation", {}).get("stage_timings", {})
	_check(not result.has("error"), "Regional staged SnowPlow job succeeds: %s" % result)
	_check(bool(result.get("complete", false)), "Regional staged SnowPlow job reaches atomic commit")
	_check(bool(result.get("executed", false)), "Regional API executes the SnowPlow job")
	_check(bool(result.get("resource_reused", false)), "Regional job reuses the threaded SnowPlow Resource")
	_check(bool(result.get("preparation", {}).get("direct_prepared", false)), "Regional SnowPlow job publishes SnowPlowGeometry directly")
	_check(not stages.has("procedural_build") and not stages.has("batching") and not stages.has("capture_pack"), "Regional SnowPlow job avoids procedural rebuild, rebatch and capture")
	_check(max_stage_usec <= STAGE_BUDGET_USEC, "SnowPlow maximum regional stage stays within 6 ms")
	_check(not stage_timings.is_empty(), "SnowPlow regional job exposes per-stage timings")
	_check(int(result.get("preparation", {}).get("stage_sum_usec", 0)) == actual_usec, "SnowPlow stage telemetry accounts for all active work")
	_check(CACHE._prepared.has(MODEL_PATH), "Regional job marks SnowPlow prepared")
	_check(CACHE._models.has(MODEL_PATH), "Regional job retains the SnowPlow prepared template")
	_check(bool(CACHE._models.get(MODEL_PATH, {}).get("prepared_presentation", false)), "Regional SnowPlow template is presentation-ready")

	var hits_before := CACHE.hits
	var script := resource_state.get("resource") as Script
	var live := script.new() as Node3D
	root.add_child(live)
	var rig := WHEEL_RIG.new()
	var mounted := rig.mount(live)
	var removed := BATCHER.batch_model(live) if not bool(live.get_meta("vehicle_mesh_batched", false)) else 0
	_check(CACHE.hits == hits_before + 1, "Runtime SnowPlow restores from the regional cache")
	_check(mounted and rig.pivots.size() == 6, "Runtime SnowPlow restores all six wheel rigs")
	_check(removed == 0, "Runtime SnowPlow repeats no mesh batching")
	live.free()
	var report := CACHE.finish_region_session(session, false)
	await process_frame
	await process_frame
	_finish({
		"baseline_sync_cold_ms": 56.133,
		"request_usec": request_usec,
		"request_ms": request_usec / 1000.0,
		"async_wait_usec": async_wait_usec,
		"async_wait_ms": async_wait_usec / 1000.0,
		"async_wait_frames": wait_frames,
		"actual_usec": actual_usec,
		"actual_ms": actual_usec / 1000.0,
		"stage_timings_usec": stage_timings,
		"stage_timings_ms": _stage_timings_ms(stage_timings),
		"stage_budget_ms": STAGE_BUDGET_USEC / 1000.0,
		"max_stage_usec": max_stage_usec,
		"session_max_model_path": report.get("max_model_path", ""),
		"session_max_model_usec": report.get("max_model_usec", 0),
		"cache_hits": CACHE.hits - hits_before,
	})


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _stage_timings_ms(stage_timings: Dictionary) -> Dictionary:
	var result := {}
	for stage in stage_timings:
		result[String(stage).trim_suffix("_usec") + "_ms"] = int(stage_timings[stage]) / 1000.0
	return result


func _finish(result: Dictionary) -> void:
	result["failures"] = failures
	print("SNOW_PLOW_REGIONAL_PREWARM_JOB ", JSON.stringify(result))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)
