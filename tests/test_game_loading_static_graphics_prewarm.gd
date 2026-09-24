extends SceneTree

const GAME_LOADING := preload("res://ui/GameLoading.gd")
const STATIC_VIEW := preload("res://world/mountain_pass/MountainStaticModelView.gd")

class LoadingProbe extends Control:
	var stages: Array[Dictionary] = []
	func set_stage(value: float, label: String) -> void:
		stages.append({"value": value, "label": label})

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("GAME_LOADING_STATIC_PREWARM: " + message)

func _run() -> void:
	STATIC_VIEW.reset_global_graphics_prewarm_for_tests()
	var loading := GAME_LOADING.new()
	root.add_child(loading)
	var probe := LoadingProbe.new()
	loading.add_child(probe)
	loading.screen = probe
	paused = true
	var result: Dictionary = await loading._prepare_static_model_graphics()
	_check(paused, "prewarm must not release the paused gameplay tree")
	_check(bool(result.get("world_paused", false)), "telemetry must record that gameplay stayed paused")
	_check(bool(result.get("loading_visible", false)), "loading presentation must remain visible")
	_check(probe.stages.size() == 1, "loading must expose exactly one presentation-prewarm stage")
	_check(float(loading.phase_times_ms.get("static_graphics_backend", -1.0)) >= 0.0,
		"loading must record backend cost")
	_check(String(result.get("scope", "")) == "loading_global",
		"telemetry must separate the global loading cost from model costs")
	_check(String(result.get("charged_to", "")) == "loading",
		"bootstrap cost must be charged to loading")
	_check(not bool(result.get("vehicle_model_cost_included", true)),
		"bootstrap telemetry must not be folded into a vehicle model measurement")
	if DisplayServer.get_name() == "headless":
		_check(bool(result.get("skipped_headless", false)), "headless must skip GPU work explicitly")
		_check(not bool(result.get("ready", true)), "headless skip must not claim a warmed GPU")
	else:
		_check(bool(result.get("ready", false)), "rendered loading prewarm must complete")
		_check(not bool(result.get("timed_out", true)), "rendered loading prewarm must not time out")
	var second: Dictionary = await STATIC_VIEW.prewarm_graphics_backend(self, 3000)
	if DisplayServer.get_name() != "headless":
		_check(bool(second.get("reused", false)), "second rendered call must reuse the global bootstrap")
		_check(int(second.get("attempts", 0)) == 1, "idempotent call must not create a second bootstrap")
		_check(bool(result.get("temporary_viewport_released", false)),
			"global prewarm viewport must be released before loading continues")
	_check(root.find_child("MountainStaticGraphicsPrewarm", true, false) == null,
		"global prewarm must not leave a persistent viewport host")

	# Timeout is sticky inside one loading attempt, so controls remain paused and
	# no retry loop is possible. Only a later loading session may retry once.
	STATIC_VIEW.reset_global_graphics_prewarm_for_tests()
	var failed_session := loading.start_static_graphics_prewarm_session()
	STATIC_VIEW.force_global_graphics_prewarm_timeout_for_tests(failed_session)
	var timed_out: Dictionary = await loading._prepare_static_model_graphics()
	_check(bool(timed_out.get("timed_out", false)), "timeout must remain recorded in the same loading session")
	_check(bool(timed_out.get("retry_deferred_to_next_loading", false)),
		"same loading session must defer retry instead of looping")
	_check(paused, "recording a timeout must not release gameplay controls")
	_check(float(loading.phase_times_ms.get("static_graphics_backend_timeout", 0.0)) == 1.0,
		"loading telemetry must expose the pending timeout before controls are released")
	_check(float(loading.phase_times_ms.get("static_graphics_backend_pending", 0.0)) == 1.0,
		"loading must retain an explicit pending marker for the next loading")
	var attempts_after_timeout := int(timed_out.get("attempts", 0))
	var same_session: Dictionary = await loading._prepare_static_model_graphics()
	_check(int(same_session.get("attempts", -1)) == attempts_after_timeout,
		"same loading session must not start another attempt")
	var retry_session := loading.start_static_graphics_prewarm_session()
	var retry: Dictionary = await loading._prepare_static_model_graphics()
	_check(retry_session != failed_session, "new loading must receive a distinct retry session")
	_check(not bool(retry.get("timed_out", true)), "new loading session must clear the previous terminal timeout")
	_check(int(retry.get("loading_session", -1)) == retry_session,
		"retry telemetry must identify the new loading session")
	var phase_snapshot: Dictionary = loading.phase_times_ms.duplicate(true)
	paused = false
	loading.queue_free()
	await process_frame
	print("GAME_LOADING_STATIC_PREWARM result=", result,
		" second=", second, " timeout=", timed_out,
		" same_session=", same_session, " retry=", retry,
		" phase_times_ms=", phase_snapshot,
		" failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
