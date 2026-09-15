extends "res://tests/measure_city_scenarios.gd"
## Production observation, separate from the comparable frame-time benchmark.
## Uses the parent's isolated save directory and finite rendered checkpoint.
var _observed: Dictionary = {}
var _next_observation := 0
var _observe_walkers := false

func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	if OS.get_cmdline_user_args().has("--inspect"): seconds = 1.0 if label == "warmup" else 5.0
	_observe_walkers = label != "warmup"
	await super._sample(output, label, seconds, car)
	if not _observe_walkers: return
	_observe_walkers = false
	var rows: Array = _observed.values()
	var blocked: Array = []
	var moving := 0
	for row in rows:
		if row.distance > 20.0: moving += 1
		if row.no_progress_peak > 8.0: blocked.append(row)
	var report := {"observed":rows.size(), "moving_over_20px":moving,
		"blocked_over_8s":blocked, "walkers":rows}
	FileAccess.open(output.path_join("pedestrians.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CITY_PEDESTRIAN_PROGRESS observed=%d moving=%d blocked=%d" % [rows.size(), moving, blocked.size()])

func _report_render() -> void:
	super._report_render()
	if not _observe_walkers or Time.get_ticks_msec() < _next_observation: return
	_next_observation = Time.get_ticks_msec() + 1000
	for person in get_nodes_in_group("authored_sidewalk_pedestrian"):
		if person.get_meta("proximity_sleeping", false) or not person.can_process() or person.is_dead or person.is_incapacitated or person.is_scared: continue
		var key := str(person.get_path())
		var row: Dictionary = _observed.get(key, {"name":key, "distance":0.0, "no_progress_peak":0.0, "previous":person.global_position})
		row.distance += person.global_position.distance_to(row.previous)
		row.previous = person.global_position
		row.no_progress_peak = maxf(row.no_progress_peak, person.stuck_timer)
		row.state = String(person.locomotion_state)
		row.target = person.walk_target
		row.recoveries = person.recovery_count
		row.segment = person._route_segment
		if person.stuck_timer > (1.0 if OS.get_cmdline_user_args().has("--inspect") else 8.0):
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = person.get_node("CollisionShape2D").shape
			query.transform = person.global_transform
			query.margin = person.safe_margin
			query.collision_mask = 3
			query.exclude = [person.get_rid()]
			var blockers: Array = []
			for hit in person.get_world_2d().direct_space_state.intersect_shape(query, 8): blockers.append(str(hit.collider.get_path()))
			row.blockers = blockers
			row.origin_allowed = person._navigation_point_allowed(person.global_position)
			row.target_allowed = person._navigation_point_allowed(person.walk_target)
			row.corridor = [person._corridor_start, person._corridor_end]
			var collision := KinematicCollision2D.new()
			person.test_move(person.global_transform, Vector2.ZERO, collision, person.safe_margin, true)
			row.contact_recovery = collision.get_travel()
			if OS.get_cmdline_user_args().has("--inspect"):
				row.search = {"pending":person.movement_navigation._search_pending, "open":person.movement_navigation._open.size(), "closed":person.movement_navigation._closed.size(), "step":person.movement_navigation.grid_step, "retry":person.movement_navigation.retry}
				var edges: Array = []
				var raw_nav := preload("res://ResponderNavigation.gd").new()
				for direction in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
					var point: Vector2 = person.global_position + direction * 3.0
					edges.append({"point":point, "allowed":person._navigation_point_allowed(point), "nav_clear":person.movement_navigation.clear_segment(person,person.global_position,point), "raw_clear":raw_nav.clear_segment(person,person.global_position,point)})
				row.edges = edges
		_observed[key] = row
