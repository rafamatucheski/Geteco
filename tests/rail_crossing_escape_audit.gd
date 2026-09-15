extends SceneTree

## Component-level safety proof. No vehicle or train actor is spawned or moved;
## the test inspects the geometry and state contract of one derived crossing.

const CROSSING_SCRIPT := preload("res://geodata/roads/safety/RailLevelCrossing2D.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var crossing := CROSSING_SCRIPT.new() as RailLevelCrossing2D
	crossing.name = "RailCrossingEscapeAuditFixture"
	crossing.configure({
		"id": "rail_safety_fixture",
		"road_id": "fixture/two_way_road",
		"road_index": 0,
		"road_t": 0.5,
		"rail_t": 0.5,
		"position": Vector2.ZERO,
		"road_tangent": Vector2.RIGHT,
		"rail_tangent": Vector2(0.12, 1.0).normalized(),
		"road_width": 96.0,
		"rail_ballast_width": 54.0,
		"track_gauge": 22.0,
		"lane_controls": [
			{"lane_id": "forward", "offset": 24.0, "direction": 1},
			{"lane_id": "reverse", "offset": -24.0, "direction": -1},
		],
	})
	root.add_child(crossing)
	await process_frame

	var geometry := crossing.get_gate_geometry()
	_check(String(geometry.get("policy", "")) == "incoming_lanes_only", "gate policy is not incoming-lanes-only")
	var barriers: Array = geometry.get("barriers", [])
	_check(barriers.size() == 2, "two-way road must derive exactly two inbound half barriers")
	_check(crossing.get_node_or_null("TrackConflictZone") is Area2D, "track conflict Area2D is missing")

	for lane in crossing.lane_controls:
		var direction := int(lane.direction)
		var expected_entry_x := -float(direction) * crossing.gate_offset
		var exit_point := Vector2(float(direction) * crossing.gate_offset, float(lane.offset))
		var entry_barrier_found := false
		var exit_is_open := true
		for barrier_value in barriers:
			var barrier := barrier_value as Dictionary
			var center: Vector2 = barrier.position
			var size: Vector2 = barrier.size
			if absf(center.x - expected_entry_x) <= 0.01 and absf(center.y - float(lane.offset)) <= 0.01:
				entry_barrier_found = true
			if absf(exit_point.x - center.x) <= size.x * 0.5 and absf(exit_point.y - center.y) <= size.y * 0.5:
				exit_is_open = false
		_check(entry_barrier_found, "incoming lane %s has no derived entry barrier" % lane.lane_id)
		_check(exit_is_open, "outbound escape for lane %s is physically blocked" % lane.lane_id)

	crossing.set_train_approaching(true)
	for lane in crossing.lane_controls:
		var direction := int(lane.direction)
		var lane_y := float(lane.offset)
		var approach := crossing.to_global(Vector2(-float(direction) * (crossing.gate_offset + 40.0), lane_y))
		var committed := crossing.to_global(Vector2(-float(direction) * (crossing.gate_offset - 4.0), lane_y))
		var conflict := crossing.to_global(Vector2(0.0, lane_y))
		var outbound := crossing.to_global(Vector2(float(direction) * (crossing.gate_offset + 40.0), lane_y))
		_check(crossing.should_stop_vehicle_at(approach), "approaching lane %s is not stopped" % lane.lane_id)
		_check(not crossing.should_stop_vehicle_at(committed), "committed lane %s is stopped between gate and rail" % lane.lane_id)
		_check(not crossing.should_stop_vehicle_at(conflict), "lane %s is stopped inside the rail conflict zone" % lane.lane_id)
		_check(not crossing.should_stop_vehicle_at(outbound), "lane %s cannot leave on its outbound side" % lane.lane_id)

	var warning_seconds := crossing.required_warning_seconds()
	var warning_distance := crossing.required_warning_distance(72.0)
	_check(warning_seconds > crossing.transition_seconds + 4.0, "warning does not include vehicle clearance time")
	_check(warning_distance > 500.0, "72 px/s train warning distance is too short for the derived conflict")

	# Advance only this infrastructure component, then prove the collision shapes
	# are active on the two inbound lanes. No gameplay actor is part of this test.
	crossing._process(crossing.transition_seconds + 0.05)
	await process_frame
	await physics_frame
	var active_barriers := 0
	for barrier in get_nodes_in_group("rail_crossing_barrier"):
		if not crossing.is_ancestor_of(barrier):
			continue
		var shape := barrier.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape != null and not shape.disabled:
			active_barriers += 1
	_check(active_barriers == 2, "closed gate did not activate both inbound physical barriers")

	print("RAIL_CROSSING_ESCAPE_AUDIT: barriers=%d conflict_half=%.2f gate_offset=%.2f warning=%.2fs/%.1fpx failures=%d" % [
		barriers.size(), crossing.conflict_half_length, crossing.gate_offset,
		warning_seconds, warning_distance, _failures.size(),
	])
	for failure in _failures:
		push_error("RAIL_CROSSING_ESCAPE_AUDIT: %s" % failure)
	root.remove_child(crossing)
	crossing.free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
