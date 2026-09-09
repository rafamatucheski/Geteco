extends SceneTree

## Regression for the SECOND Cobra roundabout deadlock (bug 4 remains
## partially open until this is fixed): a vehicle that arrives at
## cobra_court_southwest/forward_01 via the connector from
## cobra_approach/forward_01 lands at progress == curve length directly --
## already past entry_curve_offset (450.58) of every remaining real exit at
## junction_039_7400_1700 (radius 71.12, trim_distance ~51.2). It never gets
## a chance to plan its own next move: _planned_connection's
## "already passed" filter (entry_curve_offset < progress - 0.5) rejects
## every candidate, so it is permanently stuck -- reservation granted, signal
## green (unsignalized), nowhere the game will ever let it go. Reproduced
## live as HarborTraffic_00 in a sustained 6-star pursuit (see
## test_harbor_police_multi_dispatch.gd's fixture): stalled 13+ seconds with
## planned=<none>.
##
## A prior attempt at a general fix (widening
## UnifiedRoadNetwork2D._exit_directions_at's endpoint tolerance to match
## _create_lane_connector_path's own trim_distance) caused a real
## vehicle/train collision at Bairro1's rail level crossing
## (rail_level_crossing_runtime_test) and was reverted. This test drives the
## EXACT real connector a live vehicle takes, not a synthetic progress
## assignment, so it stays honest about what actually happens in production.

const PREVIEW_PATH := "res://district/harbor_preview/HarborPreview.tscn"
const DEST_LANE_META_ID := "CobraNeighborhood/cobra_court_southwest/forward_01"
const CONNECTOR_NAME := "connector__39_CobraNeighborhood__cobra_approach__forward_01>CobraNeighborhood__cobra_court_southwest__forward_01"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []

	var packed := load(PREVIEW_PATH) as PackedScene
	var scene := packed.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for i in 5:
		await physics_frame

	var controller = null
	for c in get_nodes_in_group("junction_traffic_controller"):
		if c.has_method("evaluate_lane_motion"):
			controller = c
			break
	if controller == null:
		failures.append("No JunctionTrafficController found")
		_finish(scene, failures)
		return

	var connector: Path2D = null
	for candidate in get_nodes_in_group("unified_lane_connector"):
		if String(candidate.name) == CONNECTOR_NAME:
			connector = candidate
			break
	if connector == null:
		failures.append("Fixture changed: connector %s not found" % CONNECTOR_NAME)
		_finish(scene, failures)
		return

	# Drive a real probe down the exact connector a live vehicle takes, then
	# let complete_lane_transition() finish it onto cobra_court_southwest --
	# the same _finish_connector_transition() path production traffic uses,
	# not a hand-set progress value on the destination lane.
	var probe_follow := PathFollow2D.new()
	probe_follow.loop = false
	connector.add_child(probe_follow)
	probe_follow.progress = connector.curve.get_baked_length()
	var probe := Node2D.new()
	probe.name = "ConnectorOvershootProbe"
	probe_follow.add_child(probe)

	var finished: bool = bool(controller.call("complete_lane_transition", probe, connector, probe_follow))
	if not finished:
		failures.append("complete_lane_transition() did not finish the connector traversal -- fixture or contract changed")
		_finish(scene, failures)
		return

	var landed_path := probe_follow.get_parent() as Path2D
	var landed_lane_id := String(landed_path.get_meta("traffic_lane_id", "")) if landed_path else "?"
	print("LANDED lane=%s progress=%.2f length=%.2f" % [
		landed_lane_id, probe_follow.progress, (landed_path.curve.get_baked_length() if landed_path else -1.0)
	])
	if landed_lane_id != DEST_LANE_META_ID:
		failures.append("Probe landed on an unexpected lane (%s) -- fixture or contract changed" % landed_lane_id)
		_finish(scene, failures)
		return

	# Exhaustively force every visit_count residue, exactly like the
	# self-loop regression test: a real vehicle's route hash could land on
	# any candidate, so this must never depend on which one my synthetic
	# probe's name happens to hash to.
	var saw_any_connection := false
	for visit in 12:
		probe_follow.remove_meta("traffic_planned_connection_id")
		probe_follow.remove_meta("traffic_planned_junction_index")
		probe_follow.set_meta("traffic_route_decision_count", visit)
		var connection = controller.call("_planned_connection", probe, landed_path, probe_follow)
		if connection is Dictionary and not (connection as Dictionary).is_empty():
			saw_any_connection = true
			print("PLANNED visit=%d connection_id=%s" % [visit, str((connection as Dictionary).get("connection_id", "?"))])

	if not saw_any_connection:
		failures.append(
			"A vehicle that just arrived on %s via its real production connector can never plan any next move (progress=%.2f, past every real exit's entry_curve_offset) -- it is permanently stuck exactly like HarborTraffic_00" % [DEST_LANE_META_ID, probe_follow.progress]
		)

	probe_follow.queue_free()
	_finish(scene, failures)

func _finish(scene: Node, failures: Array[String]) -> void:
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("COBRA_CONNECTOR_OVERSHOOT_STUCK: PASS")
		quit(0)
	else:
		for f in failures:
			printerr("  - %s" % f)
		print("COBRA_CONNECTOR_OVERSHOOT_STUCK: FAIL (%d)" % failures.size())
		quit(1)
