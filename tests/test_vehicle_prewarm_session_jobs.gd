extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_reset_cache()
	var expected_jobs := CACHE.region_jobs(&"mountain", self)
	var session := CACHE.begin_region_session(self, &"mountain")
	_check(bool(session.get("valid", false)), "mountain session opens")
	_check(bool(session.get("active", false)), "new session is active")
	var jobs := CACHE.region_session_jobs(session)
	_check(jobs.size() == expected_jobs.size(), "session exposes only Mountain jobs")
	_check(not jobs.is_empty(), "Mountain fixture has at least one cold job")

	var executed_path := ""
	if not jobs.is_empty():
		var loaded := await _load_job_resource(session, jobs[0])
		_check(not loaded.has("error"), "first job resource loads asynchronously")
		_check(not CACHE._prepared.has(String(jobs[0].path)), "loaded resource is not falsely marked prepared")
		var result := CACHE.execute_region_job(session, jobs[0], loaded.get("resource") as Resource)
		executed_path = String(result.get("path", ""))
		_check(bool(result.get("executed", false)), "one explicit job executes")
		_check(bool(result.get("resource_reused", false)), "explicit job reuses its threaded resource")
		_check(int(result.get("actual_usec", 0)) >= 0, "job returns measured cost")
		_check(CACHE.region_session_jobs(session).size() == jobs.size() - 1, "executed job leaves the session queue")
	# Begin loading another model, then cancel before construction. The next
	# session must keep the model queued and may safely attach to the same global
	# threaded request if it is still in flight.
	var cancelled_loading_path := ""
	var remaining_before_cancel := CACHE.region_session_jobs(session)
	if not remaining_before_cancel.is_empty():
		cancelled_loading_path = String(remaining_before_cancel[0].path)
		var pending := CACHE.request_region_job_resource(session, remaining_before_cancel[0])
		_check(not pending.has("error"), "a pending resource request can be cancelled between jobs")
		_check(not CACHE._prepared.has(cancelled_loading_path), "cancelled resource request never marks prepared")
	var cancelled := CACHE.finish_region_session(session, true)
	_check(bool(cancelled.get("cancelled", false)), "partial session is reported as cancelled")
	_check(not bool(cancelled.get("completed", true)), "partial cancellation is not reported complete")
	_check(CACHE.region_telemetry().active_sessions.is_empty(), "finished session leaves no active handle")
	await process_frame
	await process_frame
	_check(not _has_warmup_view_prefix("VehicleWarmupViewport_mountain_"), "cancelled session releases its viewport")

	var resumed := CACHE.begin_region_session(self, &"mountain")
	var resumed_jobs := CACHE.region_session_jobs(resumed)
	_check(resumed_jobs.size() == maxi(0, expected_jobs.size() - 1), "resumed session keeps completed work and exposes only remaining jobs")
	if not executed_path.is_empty():
		for job in resumed_jobs:
			_check(String(job.get("path", "")) != executed_path, "completed model is not scheduled twice")
	if not cancelled_loading_path.is_empty():
		_check(_jobs_contain(resumed_jobs, cancelled_loading_path), "cancelled in-flight model remains queued on resume")
		var resumed_job := _job_for_path(resumed_jobs, cancelled_loading_path)
		var resumed_resource := await _load_job_resource(resumed, resumed_job)
		_check(not resumed_resource.has("error"), "resumed session safely reacquires the in-flight resource")
		_check(resumed_resource.get("resource") is Resource, "resumed resource request resolves explicitly")
	CACHE.finish_region_session(resumed, true)
	await process_frame
	await process_frame
	_check(not _has_warmup_view_prefix("VehicleWarmupViewport_mountain_"), "resumed session releases its viewport")

	# A supported path whose script cannot construct a Node3D must remain queued.
	# This guards against falsely declaring a region warm and paying the failed
	# constructor again on the player's crossing frame.
	var invalid_path := "res://prototypes/living_cast/VehicleWheelRig.gd"
	var invalid_view := SubViewport.new()
	root.add_child(invalid_view)
	var invalid_session := {
		"id": -1,
		"valid": true,
		"active": true,
		"paths": [invalid_path],
		"warmup_view": invalid_view,
		"report": {
			"cache_misses": 0,
			"models_prepared": 0,
			"failed_models": [],
			"model_timings": [],
			"max_model_usec": 0,
			"max_model_path": "",
		},
	}
	var invalid_result := CACHE.execute_region_job(invalid_session, {"path": invalid_path})
	_check(String(invalid_result.get("error", "")) == "model_construction_failed", "invalid supported constructor reports a hard prewarm failure")
	_check(not bool(invalid_result.get("executed", false)), "failed constructor is not counted as executed")
	_check(CACHE.region_session_jobs(invalid_session).size() == 1, "failed constructor remains retryable instead of becoming falsely prepared")
	_check(invalid_session.report.failed_models.size() == 1, "failed model is retained in session telemetry")
	invalid_view.free()

	var wrong_resource_view := SubViewport.new()
	root.add_child(wrong_resource_view)
	var wrong_resource_session := {
		"id": -2,
		"valid": true,
		"active": true,
		"paths": [invalid_path],
		"warmup_view": wrong_resource_view,
		"loaded_resources": {},
		"report": {
			"cache_misses": 0,
			"models_prepared": 0,
			"failed_models": [],
			"model_timings": [],
			"max_model_usec": 0,
			"max_model_path": "",
		},
	}
	var wrong_resource := CACHE.execute_region_job(
		wrong_resource_session,
		{"path": invalid_path},
		Gradient.new()
	)
	_check(String(wrong_resource.get("error", "")) == "model_resource_not_script", "regional execution rejects a threaded resource that is not a Script")
	_check(not CACHE._prepared.has(invalid_path), "wrong threaded resource never marks its path prepared")
	_check(wrong_resource_session.report.failed_models.size() == 1, "wrong threaded resource is explicit in failed_models")
	wrong_resource_view.free()

	# Missing resources fail explicitly and remain retryable; they never enter
	# `_prepared`, matching the constructor/capture failure contract above.
	var missing_path := "res://tests/fixtures/vehicle_that_does_not_exist.gd"
	var missing_session := {
		"valid": true,
		"active": true,
		"paths": [missing_path],
		"loaded_resources": {},
		"resource_states": {},
		"report": {"failed_models": [], "thread_failures": 0},
	}
	var missing := CACHE.request_region_job_resource(missing_session, {"path": missing_path})
	_check(String(missing.get("error", "")) == "missing_resource", "missing threaded resource reports an explicit error")
	_check(bool(missing.get("retryable", false)), "threaded resource failure remains retryable")
	_check(missing_session.report.failed_models.size() == 1, "threaded resource failure is retained in failed_models")
	_check(not CACHE._prepared.has(missing_path), "threaded resource failure never marks prepared")

	print("VEHICLE_PREWARM_SESSION initial_jobs=%d resumed_jobs=%d executed=%s failures=%s" % [
		expected_jobs.size(), resumed_jobs.size(), executed_path, failures,
	])
	quit(0 if failures.is_empty() else 1)

func _reset_cache() -> void:
	CACHE._models.clear()
	CACHE._prepared.clear()
	CACHE._operationally_warmed_paths.clear()
	CACHE._region_reports.clear()
	CACHE._retained_regions.clear()
	CACHE._active_region_sessions.clear()
	CACHE._deferred_constructor_paths.clear()
	CACHE._regional_capture_suppressed_paths.clear()
	CACHE._prewarm_complete = false
	CACHE._last_prewarm_report.clear()
	CACHE.hits = 0
	CACHE.misses = 0
	CACHE.captures = 0
	CACHE.cold_builds = 0
	CACHE.cold_build_usec = 0
	CACHE.regional_misses = 0
	CACHE.regional_cold_builds = 0
	CACHE.regional_cold_build_usec = 0

func _load_job_resource(session: Dictionary, job: Dictionary) -> Dictionary:
	var state := CACHE.request_region_job_resource(session, job)
	for _frame in 600:
		if String(state.get("state", "")) != "loading":
			return state
		await process_frame
		state = CACHE.poll_region_job_resource(session, job)
	return {"error": "thread_load_timeout", "retryable": true}

func _jobs_contain(jobs: Array[Dictionary], path: String) -> bool:
	return not _job_for_path(jobs, path).is_empty()

func _job_for_path(jobs: Array[Dictionary], path: String) -> Dictionary:
	for job in jobs:
		if String(job.get("path", "")) == path:
			return job
	return {}

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _has_warmup_view_prefix(prefix: String) -> bool:
	for child in root.get_children():
		if String(child.name).begins_with(prefix):
			return true
	return false
