extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var path := Path2D.new()
	path.curve = Curve2D.new()
	# A reversed curve keeps +Y on the driver's right and -Y toward the road
	# centre. This reproduces Foundry Avenue's reverse_01 lane convention.
	path.curve.add_point(Vector2(700.0, 0.0))
	path.curve.add_point(Vector2.ZERO)
	path.set_meta("traffic_lane_offset", -30.0)
	path.set_meta("traffic_direction", -1)
	world.add_child(path)
	var car = ModernTrafficFactory.spawn_moving_vehicle(path, "ReverseLaneProbe", "utility_truck", 0.5, 90.0, 0.0)
	_check(car != null, "Reverse-lane traffic fixture spawns")
	if car != null:
		car.set_process(false)
		car.set_physics_process(false)
		var lateral_radius: float = float(car.collision.shape.get_rect().size.y) * absf(car.collision.scale.y) * 0.5 + absf(car.collision.position.y)
		_check(car._traffic_avoidance_candidate_within_lane(path, -16.0), "Reverse lane may recover toward its outside road edge")
		_check(not car._traffic_avoidance_candidate_within_lane(path, 16.0), "Reverse lane cannot move the full truck hull across the road centre")
		_check(16.0 + lateral_radius > 30.0, "Fixture reproduces a centre-line intrusion if the inward side were accepted")
	path.remove_meta("traffic_lane_offset")
	path.remove_meta("traffic_direction")
	if car != null:
		_check(car._traffic_avoidance_candidate_within_lane(path, -16.0), "Legacy paths without lane metadata preserve bounded recovery")
	print("TRAFFIC_LANE_AVOIDANCE_BOUNDARY failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
