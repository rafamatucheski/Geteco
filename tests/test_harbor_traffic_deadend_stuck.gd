extends SceneTree

## Regression for a real bug found reproducing the 2026-09-06 gameplay
## recording: ambient traffic is scattered across each lane's progress range
## at load time, so a vehicle could spawn PAST a mandatory turn connector's
## entry_curve_offset -- the only way off a dead-end lane segment. Harbor's
## westgate_drive/forward_01 dead-ends at dock_street (junction_011), reachable
## only via a "requires_connector" left turn whose entry_curve_offset (1731.2)
## sits short of the raw curve length (1800.0), only ~190px before the harbor
## seawall curb. A vehicle already past that offset can never plan the turn
## (JunctionTrafficController._planned_connection rejects any candidate whose
## entry_curve_offset < progress), yet TrafficVehicle._open_lane_end_motion
## used to ask has_lane_transition(path) with no progress argument, so it kept
## reporting "a transition exists" against static lane geometry alone. That
## skipped end-of-lane braking entirely: the vehicle cruised at full desired
## speed into Godot's PathFollow2D progress clamp and sat there forever,
## engine still revving at max desired speed, going nowhere -- easy prey for
## a player to carjack with a dead-end wall only a fraction of a second away.
## Reproduced live: HarborTraffic_27 in HarborPreview.tscn used to spawn
## already wedged at progress==curve length (ModernTrafficFactory's
## _find_clear_ratio walked its 12-attempt forward search straight into the
## junction's own exclusion zone and, finding nothing clear, returned that
## unsafe ratio anyway).
##
## Four independent, deterministic facts, each tied to one part of the fix:
##  1. has_lane_transition(path, progress) must stop reporting a transition
##     once progress has passed every connector's entry offset for that lane.
##  2. A vehicle forced into that exact "already past the only exit" state
##     (a dedicated throwaway probe, not the live ambient one -- see fact 4)
##     brakes to a real stop (zero desired lane speed) instead of fighting a
##     physics clamp it can never get past.
##  3. ModernTrafficFactory no longer hands out that unsafe spawn ratio for
##     HarborTraffic_27's original requested ratio (0.68) on this exact lane,
##     nor any position _junction_spawn_is_clear rejects, even on the
##     exhausted-search fallback path.
##  4. The actual, naturally-spawned HarborTraffic_27 -- never repositioned by
##     this test, only observed -- drives itself off the dead-end lane and
##     onto the turn connector within a normal amount of simulated time.

const PREVIEW_PATH := "res://world/harbor/HarborPreview.tscn"
const DEADEND_LANE_PATH := "RoadNetwork/GeneratedLanePaths/RoadLayout__westgate_drive__forward_01"
const ORIGINAL_REQUESTED_RATIO := 0.68 # matches HarborLife._spawn_traffic's index=27 formula
const LIVE_VEHICLE_NAME := "HarborTraffic_27"

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

	var path := scene.get_node_or_null(DEADEND_LANE_PATH) as Path2D
	var controller = null
	for c in get_nodes_in_group("junction_traffic_controller"):
		if c.has_method("evaluate_lane_motion"):
			controller = c
			break
	if path == null or controller == null:
		failures.append("Fixture changed: expected lane %s and a JunctionTrafficController" % DEADEND_LANE_PATH)
		_finish(scene, failures)
		return

	# Grab the live, naturally-spawned vehicle now, before anything else in
	# this test runs -- fact 4 only ever reads its state, never sets it.
	var live_vehicle: Node = null
	for v in get_nodes_in_group("vehicle"):
		if v.name == LIVE_VEHICLE_NAME:
			live_vehicle = v
			break
	if live_vehicle == null:
		failures.append("%s not found in HarborPreview.tscn (fixture changed?)" % LIVE_VEHICLE_NAME)

	# --- Fact 1: has_lane_transition is progress-aware. ---
	var length: float = path.curve.get_baked_length()
	if not bool(controller.call("has_lane_transition", path, 0.0)):
		failures.append("has_lane_transition(path, 0.0) should still see the reachable turn near progress=0")
	if bool(controller.call("has_lane_transition", path, length)):
		failures.append("has_lane_transition(path, length) must be false once progress has passed every connector's entry offset -- a vehicle there is at a genuine dead end")

	# --- Fact 2: a *dedicated* probe forced into that state brakes for real.
	# Spawned well before the junction's exclusion zone so its own placement
	# is safe; only its progress is then forced, independent of live traffic.
	var probe := ModernTrafficFactory.spawn_moving_vehicle(path, "DeadEndBrakeProbe", "sedan_classic", 0.2, 90.0, 0)
	if probe == null:
		failures.append("Could not spawn a dedicated probe on %s" % DEADEND_LANE_PATH)
	else:
		var follow := probe.get_parent() as PathFollow2D
		follow.progress = length
		for i in 200:
			await physics_frame
		var lane_speed: float = float(probe.get("_lane_motion_speed"))
		print("DEADEND_PROBE lane_speed=%.2f pos=%s progress=%.2f" % [lane_speed, str(probe.global_position), follow.progress])
		if lane_speed > 1.0:
			failures.append(
				"A vehicle placed at the dead end (progress==length) still desires lane_speed=%.2f -- it is fighting the physics clamp instead of having braked to a real stop" % lane_speed
			)
		probe.queue_free()

	# --- Fact 3: spawn placement no longer hands out an unsafe ratio, even
	# on the exhausted-search fallback path. ---
	var safe_ratio: float = ModernTrafficFactory._find_clear_ratio(path, ORIGINAL_REQUESTED_RATIO)
	var safe_progress := safe_ratio * length
	var still_safe: bool = bool(controller.call("is_lane_spawn_position_safe", path, safe_progress, 76.0))
	print("SPAWN_RATIO requested=%.2f resolved=%.4f progress=%.2f safe=%s" % [ORIGINAL_REQUESTED_RATIO, safe_ratio, safe_progress, str(still_safe)])
	if not still_safe:
		failures.append(
			"_find_clear_ratio(westgate_drive/forward_01, %.2f) returned ratio=%.4f (progress=%.2f), which is_lane_spawn_position_safe rejects -- ambient traffic can spawn stuck at the dead end again" % [ORIGINAL_REQUESTED_RATIO, safe_ratio, safe_progress]
		)

	# --- Fact 4: the real, untouched ambient vehicle actually gets off the
	# dead-end lane and onto the turn connector on its own. ---
	if live_vehicle != null:
		var completed_transition := false
		var last_parent_path := ""
		for i in 900: # up to 15s of simulated time
			await physics_frame
			if not is_instance_valid(live_vehicle):
				break
			var follow := live_vehicle.get_parent() as PathFollow2D
			if follow == null:
				break
			var parent_path := String(follow.get_parent().get_path())
			if parent_path != last_parent_path:
				print("LIVE_VEHICLE t=%d parent=%s progress=%.2f" % [i, parent_path, follow.progress])
				last_parent_path = parent_path
			if follow.get_parent() != path:
				completed_transition = true
				break
		if not completed_transition:
			failures.append(
				"%s (never repositioned by this test) did not leave %s within 15s of real simulation -- it is still stuck at the dead end, not just spawned safely" % [LIVE_VEHICLE_NAME, DEADEND_LANE_PATH]
			)
		else:
			print("LIVE_VEHICLE_RESULT %s reached parent=%s pos=%s" % [LIVE_VEHICLE_NAME, last_parent_path, str(live_vehicle.global_position)])

	_finish(scene, failures)

func _finish(scene: Node, failures: Array[String]) -> void:
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("HARBOR_TRAFFIC_DEADEND_STUCK: PASS")
		quit(0)
	else:
		for f in failures:
			printerr("  - %s" % f)
		print("HARBOR_TRAFFIC_DEADEND_STUCK: FAIL (%d)" % failures.size())
		quit(1)
