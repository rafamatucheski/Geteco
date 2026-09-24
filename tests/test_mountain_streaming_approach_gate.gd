extends SceneTree

const CONTINUOUS_WORLD := preload("res://world/harbor/ContinuousWorld.gd")
const DRIVE_SPEED := 600.0
const WALK_SPEED := 200.0
const STEP_SECONDS := 0.1

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stream := CONTINUOUS_WORLD.new()
	var seam: Vector2 = stream.MOUNTAIN_SEAM_POSITION
	var maximum_gate_distance: float = (
		stream.MOUNTAIN_DIRECT_PRELOAD_DISTANCE
		+ stream.MOUNTAIN_MAX_LOOKAHEAD_DISTANCE
	)

	var route_endpoint := seam - Vector2(7770.0, 0.0)
	var far_approach: Dictionary = stream.mountain_load_decision(
		route_endpoint,
		Vector2(DRIVE_SPEED, 0.0)
	)
	_check(not bool(far_approach.should_load), "normal Harbor route remains outside mountain construction at 7,770 px")
	_check(is_equal_approx(float(far_approach.trigger_distance), maximum_gate_distance), "lookahead remains capped at the authored 6,800 px maximum")

	var unrelated_north := seam + Vector2(-5000.0, -5000.0)
	var north_decision: Dictionary = stream.mountain_load_decision(unrelated_north, Vector2(0.0, -DRIVE_SPEED))
	_check(not bool(north_decision.should_load), "north-Harbor movement away from the seam no longer starts Mountain")

	var perpendicular := seam - Vector2(6500.0, 0.0)
	var perpendicular_decision: Dictionary = stream.mountain_load_decision(perpendicular, Vector2(0.0, DRIVE_SPEED))
	var away_decision: Dictionary = stream.mountain_load_decision(perpendicular, Vector2(-DRIVE_SPEED, 0.0))
	_check(not bool(perpendicular_decision.should_load), "perpendicular driving outside direct proximity does not spend Mountain work")
	_check(not bool(away_decision.should_load), "driving away from Mountain does not activate lookahead")

	var drive_trace := _continuous_approach(stream, seam, 8000.0, DRIVE_SPEED)
	_check(bool(drive_trace.triggered), "continuous driving approach starts Mountain before the seam")
	_check(float(drive_trace.trigger_distance) <= maximum_gate_distance + 0.01, "continuous driving never triggers beyond the capped gate")
	_check(float(drive_trace.lead_seconds) >= 10.0, "driving trigger leaves at least ten seconds of physical travel at 600 px/s")

	var walk_trace := _continuous_approach(stream, seam, 6500.0, WALK_SPEED)
	_check(bool(walk_trace.triggered), "continuous walking approach starts Mountain before the seam")
	_check(float(walk_trace.lead_seconds) >= 20.0, "walking trigger leaves at least twenty seconds of physical travel")

	var stopped_near: Dictionary = stream.mountain_load_decision(
		seam - Vector2(stream.MOUNTAIN_DIRECT_PRELOAD_DISTANCE - 1.0, 0.0),
		Vector2.ZERO
	)
	_check(bool(stopped_near.should_load), "stationary arrival inside direct proximity still prepares Mountain")
	var pending_restore: Dictionary = stream.mountain_load_decision(
		seam - Vector2(12000.0, 0.0),
		Vector2.ZERO,
		"mountain"
	)
	_check(bool(pending_restore.should_load) and String(pending_restore.reason) == "pending_region", "Mountain save/arrival request bypasses the physical gate")

	print("MOUNTAIN_STREAMING_APPROACH_GATE ", JSON.stringify({
		"failures": failures,
		"route_endpoint": far_approach,
		"maximum_gate_distance": maximum_gate_distance,
		"drive_trace": drive_trace,
		"walk_trace": walk_trace,
		"pending_restore": pending_restore,
	}))
	stream.free()
	quit(1 if not failures.is_empty() else 0)


func _continuous_approach(stream: Node, seam: Vector2, start_distance: float, speed: float) -> Dictionary:
	# The sample advances along a continuous physical trajectory. It never writes
	# an actor transform and therefore cannot accidentally validate teleport flow.
	var point := seam - Vector2(start_distance, 0.0)
	var velocity := Vector2(speed, 0.0)
	var elapsed := 0.0
	var samples := 0
	while point.x < seam.x and samples < 2000:
		var decision: Dictionary = stream.mountain_load_decision(point, velocity)
		if bool(decision.should_load):
			return {
				"triggered": true,
				"samples": samples,
				"elapsed_seconds": elapsed,
				"trigger_distance": float(decision.distance),
				"gate_distance": float(decision.trigger_distance),
				"lead_seconds": float(decision.estimated_lead_seconds),
				"reason": String(decision.reason),
			}
		point += velocity * STEP_SECONDS
		elapsed += STEP_SECONDS
		samples += 1
	return {
		"triggered": false,
		"samples": samples,
		"elapsed_seconds": elapsed,
		"trigger_distance": point.distance_to(seam),
		"gate_distance": 0.0,
		"lead_seconds": 0.0,
		"reason": "seam_reached_before_trigger",
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
