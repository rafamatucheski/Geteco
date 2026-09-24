extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const EXTERNAL_PATHS: Array[String] = [
	"res://police/PoliceMotorcycleModel.gd",
	"res://world/harbor/HarborContainerTruckModel.gd",
	"res://world/harbor/PortForkliftModel.gd",
]
const RESCUE_PUMPER_PATH := "res://prototypes/living_cast/models/RescuePumperModel.gd"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path in EXTERNAL_PATHS:
		_test_external_model_warms_without_cache(path)
	_test_rescue_pumper_explicit_operational_opt_out()
	print("VEHICLE_REGIONAL_OPERATIONAL_CACHE_SAFETY failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)


func _test_external_model_warms_without_cache(path: String) -> void:
	_reset_path(path)
	var session := _isolated_session(path)
	var result := _advance_until_terminal(session, path)
	_check(not result.has("error"), "%s operational warmup does not reject Node references" % path)
	_check(bool(result.get("complete", false)), "%s operational warmup completes" % path)
	_check(bool(result.get("preparation", {}).get("operational_only", false)), "%s is explicitly operational-only" % path)
	_check(not CACHE._models.has(path), "%s never publishes a geometry cache entry" % path)
	_check(not CACHE._prepared.has(path), "%s never publishes a false prepared-cache marker" % path)
	_check(CACHE._operationally_warmed_paths.has(path), "%s records only its presentation warm marker" % path)
	_check((session.get("report", {}).get("failed_models", []) as Array).is_empty(), "%s produces no cache-safety failure" % path)
	_check(CACHE.region_session_jobs(session).is_empty(), "%s does not repeat inside the same regional session" % path)
	var report := CACHE.finish_region_session(session, false)
	_check(bool(report.get("completed", false)), "%s operational-only session completes without affecting cache readiness" % path)
	_check(int(report.get("models_prepared", -1)) == 0, "%s is not counted as a prepared cache model" % path)
	_check((report.get("operational_models_warmed", []) as Array).has(path), "%s is attributed as an operational presentation warmup" % path)


func _test_rescue_pumper_explicit_operational_opt_out() -> void:
	var path := RESCUE_PUMPER_PATH
	_reset_path(path)
	var script := load(path) as Script
	var live := script.new() as Node3D
	_check(live != null and bool(live.call("vehicle_geometry_cache_operational_only")), "RescuePumper explicitly opts out of geometry restore")
	if live == null:
		return
	_check(live.get("water_turret") is Node3D and live.get("water_muzzle") is Marker3D, "RescuePumper normal construction retains live water-cannon references")
	var unsafe_references := CACHE._unsafe_operational_node_reference_properties(live)
	_check(unsafe_references.has("water_turret") and unsafe_references.has("water_muzzle"), "RescuePumper opt-out protects the known operational references")
	_check(not CACHE._models.has(path) and not CACHE._prepared.has(path), "RescuePumper normal construction cannot publish geometry cache")
	live.free()

	var session := _isolated_session(path)
	var result := _advance_until_terminal(session, path)
	_check(not result.has("error") and bool(result.get("complete", false)), "RescuePumper operational prewarm completes without coordinator backoff")
	_check(bool(result.get("preparation", {}).get("operational_only", false)), "RescuePumper staged prewarm stays operational-only")
	_check(String(result.get("preparation", {}).get("operational_reason", "")) == "explicit_model_opt_out", "RescuePumper reports its explicit cache opt-out")
	_check(not CACHE._models.has(path), "RescuePumper never publishes _models")
	_check(not CACHE._prepared.has(path), "RescuePumper never publishes _prepared")
	_check(CACHE._operationally_warmed_paths.has(path), "RescuePumper publishes only the separate operational warm marker")
	_check(not CACHE._regional_capture_suppressed_paths.has(path), "RescuePumper completion releases nested capture suppression")
	_check((session.get("report", {}).get("failed_models", []) as Array).is_empty(), "RescuePumper does not create a retryable regional failure")
	var readiness := CACHE.region_cache_readiness(&"harbor", self)
	_check(not (readiness.get("missing_supported_paths", []) as Array).has(path), "RescuePumper no longer blocks Harbor readiness after operational warmup")
	_check((readiness.get("operational_ready_paths", []) as Array).has(path), "Harbor readiness identifies RescuePumper as operationally warm")
	var report := CACHE.finish_region_session(session, false)
	_check(bool(report.get("completed", false)), "RescuePumper-only session completes")
	var second_session := _isolated_session(path)
	_check(CACHE.region_session_jobs(second_session).is_empty(), "second RescuePumper session is idempotent")
	var second_result := CACHE.advance_region_job(second_session, {"path": path, "region": &"harbor"}, script)
	_check(bool(second_result.get("already_warmed_operationally", false)), "second RescuePumper request reuses the operational warm marker")
	CACHE.finish_region_session(second_session, false)


func _advance_until_terminal(session: Dictionary, path: String) -> Dictionary:
	var script := load(path) as Script
	var job := {"path": path, "region": &"harbor"}
	var result := {"complete": false}
	for _stage_index in 24:
		result = CACHE.advance_region_job(session, job, script)
		if result.has("error") or bool(result.get("complete", false)):
			break
	return result


func _isolated_session(path: String) -> Dictionary:
	var warmup_view := SubViewport.new()
	root.add_child(warmup_view)
	return {
		"id": -1,
		"valid": true,
		"active": true,
		"region": &"harbor",
		"paths": [path],
		"started_usec": Time.get_ticks_usec(),
		"misses_before": CACHE.misses,
		"cold_builds_before": CACHE.cold_builds,
		"cold_build_usec_before": CACHE.cold_build_usec,
		"regional_misses_before": CACHE.regional_misses,
		"regional_cold_builds_before": CACHE.regional_cold_builds,
		"regional_cold_build_usec_before": CACHE.regional_cold_build_usec,
		"warmup_view": warmup_view,
		"loaded_resources": {path: load(path)},
		"resource_states": {},
		"job_states": {},
		"report": {
			"requested_models": 1,
			"models_prepared": 0,
			"cache_misses": 0,
			"failed_models": [],
			"uncached_models": [],
			"operational_models_warmed": [],
			"stage_steps": [],
			"stage_steps_dropped": 0,
			"stage_steps_executed": 0,
			"stage_totals_usec": {},
			"max_stage_usec": 0,
			"max_stage": "",
			"max_stage_path": "",
			"over_budget_stages": [],
			"memory_before_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
			"model_timings": [],
			"max_model_usec": 0,
			"max_model_path": "",
		},
	}


func _reset_path(path: String) -> void:
	CACHE._models.erase(path)
	CACHE._prepared.erase(path)
	CACHE._operationally_warmed_paths.erase(path)
	CACHE._miss_started_usec.erase(path)
	CACHE._deferred_constructor_paths.erase(path)
	CACHE._regional_capture_suppressed_paths.erase(path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
