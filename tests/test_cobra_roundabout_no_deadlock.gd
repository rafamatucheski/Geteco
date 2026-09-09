extends SceneTree

## Regression for a real deadlock found reproducing the 2026-09-06 gameplay
## recording ("fila praticamente parada na entrada dos Cobras"): ambient
## traffic at the Cobra roundabout entrance (junction_039_7400_1700, where
## cobra_approach meets the cobra_court_* quarter-arc roads) could stall
## forever, reservation granted, signal green (unsignalized junction), engine
## desiring full speed, with nowhere the game would ever let it go.
##
## Root cause: the connection-graph builder pairs a "continue straight, no
## connector needed" candidate between a lane and itself whenever that lane's
## own road_progress is registered against the same junction on both ends of
## the pairing search (a quirk of a lane whose OWN endpoint IS the junction --
## e.g. cobra_court_southwest/forward_01 ends exactly at junction 39). A
## genuine "same lane continues through this junction" entry always has
## *different* road_progress on either side (the junction sits partway along
## a longer, unbroken lane); one with identical from/to road_progress on its
## own lane is a graph artefact with nowhere to advance to.
## JunctionTrafficController._planned_connection's hash-based route selector
## picked this bogus option roughly 1-in-N visits (N = candidate count,
## alongside the junction's real, connector-requiring exits), and
## complete_lane_transition treats requires_connector=false as "nothing to
## do, just keep going on this same Path2D" -- except the Path2D was already
## fully consumed (progress == curve length). Reproduced live: 20+ seconds of
## simulated time was not enough for HarborTraffic_05 to recover on its own
## before the fix; the fix (JunctionTrafficController.gd:
## _planned_connection excludes a same-lane candidate whose to_road_progress
## equals its own from_road_progress) lets it recover in well under a second.
##
## A second, narrower deadlock was also found (a vehicle entering
## cobra_court_southwest via the cobra_approach connector lands at
## progress==length directly, past its own outgoing entry_curve_offset, with
## no plan possible at all) but is NOT fixed here: the general fix attempted
## for it (widening UnifiedRoadNetwork2D._exit_directions_at's endpoint
## tolerance to match _create_lane_connector_path's trim_distance) caused a
## real vehicle/train collision at Bairro1's rail level crossing
## (rail_level_crossing_runtime_test) and was reverted. See the delivery
## notes for this bug; that second case is a known, reproduced, understood,
## but currently unfixed limitation, not something this test claims to cover.

const PREVIEW_PATH := "res://district/harbor_preview/HarborPreview.tscn"
const JUNCTION_39_POSITION := Vector2(7400.0, 1700.0)
const WATCH_RADIUS := 260.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []

	var packed := load(PREVIEW_PATH) as PackedScene
	var scene := packed.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for i in 90:
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

	# --- Direct contract check: the bogus self-referencing candidate must
	# never be selectable, at the point a real vehicle actually decides --
	# i.e. before its own entry_curve_offset for leaving this junction, the
	# same way HarborTraffic_05 always encountered it live. (A vehicle probed
	# only *after* that point, e.g. one arriving fresh via a connector that
	# itself lands past it, is a separate, narrower, still-open issue -- see
	# the file-level notes above; this test does not claim to cover it.) ---
	var lane_path := scene.get_node_or_null(
		"RoadNetwork/GeneratedLanePaths/CobraNeighborhood__cobra_court_southwest__forward_01"
	) as Path2D
	if lane_path == null:
		failures.append("Fixture changed: cobra_court_southwest/forward_01 not found")
	else:
		var probe_follow := PathFollow2D.new()
		probe_follow.loop = false
		lane_path.add_child(probe_follow)
		probe_follow.progress = 400.0 # short of the real 450.58 entry_curve_offset
		var probe := Node2D.new()
		probe.name = "PlannedConnectionProbe"
		probe_follow.add_child(probe)
		var own_lane_id := String(lane_path.get_meta("traffic_lane_id", ""))
		var saw_any_connection := false
		var saw_self_loop := false
		# _planned_connection's route choice is a hash of vehicle name, lane,
		# junction and visit count -- exhaustively force every visit_count
		# residue so this cannot pass by luck of which candidate the hash
		# happens to land on for one arbitrary probe name (candidates.size()
		# is 2 fixed / 3 unfixed, so 12 visits covers every outcome either
		# way with margin).
		for visit in 12:
			probe_follow.remove_meta("traffic_planned_connection_id")
			probe_follow.remove_meta("traffic_planned_junction_index")
			probe_follow.set_meta("traffic_route_decision_count", visit)
			var connection = controller.call("_planned_connection", probe, lane_path, probe_follow)
			if connection is Dictionary and not (connection as Dictionary).is_empty():
				saw_any_connection = true
				if String((connection as Dictionary).get("to_lane_id", "")) == own_lane_id:
					saw_self_loop = true
					print("PLANNED_CONNECTION_SELF_LOOP visit=%d connection=%s" % [visit, str(connection)])
		if not saw_any_connection:
			failures.append("No connection could ever be planned approaching the junction normally -- fixture or contract changed")
		if saw_self_loop:
			failures.append(
				"_planned_connection selected a self-referencing candidate (to_lane_id == from lane) on at least one visit_count -- this is exactly the bug that stranded HarborTraffic_05"
			)
		else:
			print("PLANNED_CONNECTION_NEVER_SELF_LOOP across 12 forced visit_counts")
		probe_follow.queue_free()

	# --- Live simulation: observational only. A vehicle that already had a
	# real plan cached before reaching this junction (the fixed path) must
	# recover quickly; a vehicle arriving fresh via the still-open connector
	# case may legitimately stall here. This is printed for visibility, not
	# asserted, so it does not mask the documented, reproduced, open issue as
	# a false pass. ---
	var last_pos: Dictionary = {}
	var stopped_since: Dictionary = {}
	for t in 900: # 15s of simulated real time
		await physics_frame
		if t % 60 != 0:
			continue
		for v in get_nodes_in_group("vehicle"):
			if not is_instance_valid(v):
				continue
			if v.global_position.distance_to(JUNCTION_39_POSITION) >= WATCH_RADIUS:
				continue
			var vid := v.get_instance_id()
			var moved := 10000.0
			if last_pos.has(vid):
				moved = (last_pos[vid] as Vector2).distance_to(v.global_position)
			last_pos[vid] = v.global_position
			stopped_since[vid] = 0.0 if moved >= 2.0 else float(stopped_since.get(vid, 0.0)) + 1.0
			if float(stopped_since[vid]) > 0.0:
				print("OBSERVED_STALL vehicle=%s seconds=%.0f" % [v.name, stopped_since[vid]])

	_finish(scene, failures)

func _finish(scene: Node, failures: Array[String]) -> void:
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("COBRA_ROUNDABOUT_NO_DEADLOCK: PASS")
		quit(0)
	else:
		for f in failures:
			printerr("  - %s" % f)
		print("COBRA_ROUNDABOUT_NO_DEADLOCK: FAIL (%d)" % failures.size())
		quit(1)
