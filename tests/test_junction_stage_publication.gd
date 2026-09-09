extends SceneTree

class CountingController:
	extends "res://world/shared/roads/traffic/JunctionTrafficController.gd"
	var visual_publications := 0
	var crossing_publications := 0
	var published_stages: Array[int] = []
	func _ready() -> void:
		set_process(false)
	func _refresh_signal_visuals() -> void:
		visual_publications += 1
	func _synchronize_crossing_consumers() -> void:
		crossing_publications += 1
		published_stages.clear()
		for state in _states.values():
			published_stages.append(int(state.stage))

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var controller := CountingController.new()
	var source := Node2D.new()
	root.add_child(source)
	controller.graph_source = source
	root.add_child(controller)
	var signals: Array = []
	controller.junction_stage_changed.connect(func(id: StringName, stage: int, roads: Array): signals.append([id, stage, roads]))
	for index in 12:
		controller._states[index] = {
			"junction_id": StringName("junction_%d" % index), "signalized": true,
			"roads": [0, 1], "phases": [[0], [1]], "phase_index": 0,
			"stage": controller.JunctionStage.GREEN, "elapsed": controller.minimum_green_seconds,
			"reservation_owner": 0,
		}
	# Periodic update and twelve simultaneous transitions must coalesce.
	controller._crossing_sync_elapsed = 0.49
	controller._process(0.02)
	check(signals.size() == 12, "Every logical stage change must emit its signal")
	check(controller.visual_publications == 1 and controller.crossing_publications == 1, "Same-tick transitions and periodic update must publish once")
	for stage in controller.published_stages:
		check(stage == controller.JunctionStage.YELLOW, "Consumers must receive final state of every junction")
	controller._process(0.02)
	check(controller.crossing_publications == 1, "Unchanged nonperiodic tick must not publish")
	controller._set_stage(0, controller.JunctionStage.ALL_RED)
	check(controller.crossing_publications == 2 and controller.visual_publications == 2, "Stage change outside process must publish immediately")
	check(controller.published_stages[0] == controller.JunctionStage.ALL_RED, "External change must be visible immediately")
	controller._crossing_sync_elapsed = 0.49
	controller._process(0.02)
	check(controller.crossing_publications == 3, "Periodic publication must remain active without transitions")
	controller.queue_free()
	source.queue_free()
	await process_frame
	print("JUNCTION_STAGE_PUBLICATION_RESULT failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
