extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const MANIFEST := preload("res://cars/VehiclePrewarmManifest.gd")
const COORDINATOR := preload("res://cars/VehicleRegionalPrewarmCoordinator.gd")
const SCHEDULER := preload("res://systems/RuntimeWorkScheduler.gd")

const STEP_SECONDS := 1.0 / 60.0
const APPROACH_SPEED := 300.0

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _test_progressive_return_cancels()
	await _test_progressive_approach_completes()
	quit(0 if failures.is_empty() else 1)

func _test_progressive_return_cancels() -> void:
	_reset_runtime()
	var actor := CharacterBody2D.new()
	root.add_child(actor)
	var coordinator = COORDINATOR.new()
	root.add_child(coordinator)
	coordinator.set_process(false)
	coordinator.motion_source_override = actor
	actor.global_position = coordinator.seam_position - Vector2(6000.0, 0.0)
	actor.velocity = Vector2(APPROACH_SPEED, 0.0)
	actor.global_position += actor.velocity * STEP_SECONDS
	coordinator.observe_motion(actor.global_position, actor.velocity)
	var triggered := coordinator.telemetry_snapshot()
	_check(int(triggered.trigger_count) == 1, "velocity lookahead triggers from a physical approach")

	# Reverse one normal 60 Hz movement step. The coordinator observes the return;
	# it never rewrites the actor position to synthesize cancellation.
	actor.velocity = Vector2(-APPROACH_SPEED, 0.0)
	actor.global_position += actor.velocity * STEP_SECONDS
	coordinator.observe_motion(actor.global_position, actor.velocity)
	for _frame in 8:
		await process_frame
	var cancelled := coordinator.telemetry_snapshot()
	_check(String(cancelled.state) == "cancelled", "turning back beyond hysteresis cancels the session")
	_check(int(cancelled.jobs_executed) == 0, "cancellation before the scheduler grant performs no model work")
	_check(int(cancelled.heavy_reservations) == 0, "cancellation before resource readiness reserves no heavy slot")
	_check(CACHE.region_jobs(&"mountain", self).size() == MANIFEST.model_paths(&"mountain").size(), "cancelled approach does not warm Mountain")
	coordinator.queue_free()
	actor.queue_free()
	await process_frame

func _test_progressive_approach_completes() -> void:
	_reset_runtime()
	var actor := CharacterBody2D.new()
	root.add_child(actor)
	var coordinator = COORDINATOR.new()
	root.add_child(coordinator)
	coordinator.set_process(false)
	coordinator.motion_source_override = actor
	actor.global_position = coordinator.seam_position - Vector2(7200.0, 0.0)
	actor.velocity = Vector2(APPROACH_SPEED, 0.0)

	var max_step := 0.0
	var previous := actor.global_position
	# Harbor distante: move continuously for one second and prove that no
	# Mountain model is queued merely because the coordinator exists.
	for _frame in 60:
		actor.global_position += actor.velocity * STEP_SECONDS
		max_step = maxf(max_step, actor.global_position.distance_to(previous))
		previous = actor.global_position
		coordinator.observe_motion(actor.global_position, actor.velocity)
		await process_frame
	_check(int(coordinator.telemetry_snapshot().trigger_count) == 0, "distant Harbor performs zero Mountain prewarm")
	_check(CACHE._prepared.is_empty(), "distant Harbor keeps the regional cache cold")

	var completed_before_crossing := false
	for _frame in 1500:
		actor.global_position += actor.velocity * STEP_SECONDS
		max_step = maxf(max_step, actor.global_position.distance_to(previous))
		previous = actor.global_position
		coordinator.observe_motion(actor.global_position, actor.velocity)
		await process_frame
		var snapshot := coordinator.telemetry_snapshot()
		if String(snapshot.state) == "completed":
			completed_before_crossing = actor.global_position.x < coordinator.seam_position.x
			break
	var telemetry := coordinator.telemetry_snapshot()
	var readiness: Dictionary = telemetry.readiness
	_check(String(telemetry.state) == "completed", "Mountain prewarm completes during progressive approach")
	_check(completed_before_crossing, "all supported Mountain models are ready before the physical crossing")
	_check(int(telemetry.crossed_before_ready) == 0, "route never crosses before cache readiness")
	_check(int(telemetry.max_jobs_in_frame) <= 1, "coordinator executes at most one vehicle job per frame")
	_check(int(telemetry.resource_requests) > 0, "physical approach starts threaded resource requests")
	_check(int(telemetry.resource_ready) == int(telemetry.jobs_executed), "only loaded resources reach heavy execution")
	_check(int(telemetry.heavy_reservations) == int(telemetry.stage_steps_executed), "every heavy reservation advances exactly one resumable stage")
	_check(int(telemetry.stage_steps_executed) >= int(telemetry.jobs_executed), "a completed model is composed from one or more resumable stages")
	_check(int(telemetry.resource_failures) == 0, "physical approach has no threaded resource failures")
	_check(max_step <= APPROACH_SPEED * STEP_SECONDS + 0.01, "fixture uses continuous movement without teleport steps")
	_check(bool(readiness.get("ready", false)), "Mountain runtime cache reports ready")
	_check((readiness.get("missing_supported_paths", []) as Array).is_empty(), "no supported Mountain template remains missing")

	# Creating every supported Mountain model after completion must restore from
	# cache without introducing a gameplay miss or a cold-build completion.
	var misses_before := CACHE.misses
	var cold_before := CACHE.cold_builds
	var fixture := Node3D.new()
	root.add_child(fixture)
	var instantiated := 0
	for path in MANIFEST.model_paths(&"mountain"):
		if not CACHE._supports(path):
			continue
		_check(CACHE._models.has(path), "supported Mountain model has packed template: %s" % path)
		var script := load(path) as Script
		if script == null:
			continue
		var model := script.new() as Node3D
		if model == null:
			continue
		fixture.add_child(model)
		instantiated += 1
		model.free()
	_check(CACHE.misses == misses_before, "supported Mountain models produce zero misses after approach prewarm")
	_check(CACHE.cold_builds == cold_before, "supported Mountain models produce zero cold builds after approach prewarm")

	var mountain_paths := MANIFEST.model_paths(&"mountain")
	var harbor_only_cold := 0
	for path in MANIFEST.model_paths(&"harbor"):
		if not mountain_paths.has(path) and not CACHE._prepared.has(path):
			harbor_only_cold += 1
	_check(harbor_only_cold > 0, "Mountain approach does not prewarm the global/Harbor-only catalog")

	var mountain_report := CACHE.region_telemetry(&"mountain")
	var stage_steps: Array = mountain_report.get("stage_steps", [])
	var over_budget_stages: Array = mountain_report.get("over_budget_stages", [])
	var over_budget_path_stages: Array[String] = []
	for value in over_budget_stages:
		var over_budget_stage := value as Dictionary
		over_budget_path_stages.append("%s::%s" % [
			String(over_budget_stage.get("path", "")),
			String(over_budget_stage.get("stage", "")),
		])
	_check(over_budget_stages.size() == int(telemetry.over_budget_stages), "coordinator and regional report agree on over-budget stage count")
	_check(over_budget_stages.is_empty(), "over-budget regional path/stages: %s" % JSON.stringify(over_budget_path_stages))
	_check(stage_steps.size() == int(telemetry.heavy_reservations), "regional report exposes one ordered stage record per scheduler ticket")
	var ticket_ids := {}
	var previous_stage_frame := -1
	for step_value in stage_steps:
		var step := step_value as Dictionary
		var ticket_id := int(step.get("ticket_id", -1))
		var stage_frame := int(step.get("frame", -1))
		_check(ticket_id > 0 and not ticket_ids.has(ticket_id), "each regional stage keeps its unique scheduler ticket id")
		ticket_ids[ticket_id] = true
		_check(stage_frame > previous_stage_frame, "regional stage telemetry remains ordered with at most one heavy reservation per frame")
		previous_stage_frame = stage_frame
		_check(not String(step.get("path", "")).is_empty() and not String(step.get("stage", "")).is_empty(), "regional stage telemetry identifies model path and stage")
	print("VEHICLE_REGIONAL_APPROACH_OVER_BUDGET ", JSON.stringify(over_budget_stages))
	print("VEHICLE_REGIONAL_APPROACH trigger_distance=%.0f lookahead=%.1f cancel_distance=%.0f requests=%d ready=%d reservations=%d stages=%d over_budget=%d over_budget_path_stages=%s wait_frames=%d jobs=%d max_jobs_frame=%d completion_distance=%.1f supported=%d instantiated=%d max_step=%.2f harbor_only_cold=%d max_model_ms=%.3f max_model=%s failures=%s" % [
		float(telemetry.trigger_distance), float(telemetry.lookahead_seconds), float(telemetry.cancel_distance),
		int(telemetry.resource_requests), int(telemetry.resource_ready), int(telemetry.heavy_reservations), int(telemetry.stage_steps_executed), int(telemetry.over_budget_stages), JSON.stringify(over_budget_path_stages), int(telemetry.resource_wait_frames),
		int(telemetry.jobs_executed), int(telemetry.max_jobs_in_frame), float(telemetry.distance),
		int(readiness.get("supported_models", 0)), instantiated, max_step, harbor_only_cold,
		int(mountain_report.get("max_model_usec", 0)) / 1000.0, String(mountain_report.get("max_model_path", "")), failures,
	])
	fixture.free()
	coordinator.queue_free()
	actor.queue_free()
	await process_frame

func _reset_runtime() -> void:
	SCHEDULER.reset_for_tests()
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

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
