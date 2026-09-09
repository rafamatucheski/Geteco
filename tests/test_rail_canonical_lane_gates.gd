extends SceneTree
func _initialize():
	call_deferred("run")
var failures := 0
func check(ok: bool, msg: String):
	if not ok:
		failures += 1
		push_error(msg)
func run():
	var world = load("res://legacy/Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 30: await physics_frame
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var crossing = get_nodes_in_group("rail_level_crossing")[0]
	crossing.set_train_approaching(true)
	var lanes_checked := 0
	var barriers_checked := 0
	for path in get_nodes_in_group("unified_traffic_lane"):
		if String(path.get_meta("traffic_road_id", "")) != String(crossing.road_id): continue
		lanes_checked += 1
		var center: float = path.curve.get_closest_offset(path.to_local(crossing.global_position))
		var probe = load("res://world/shared/traffic/TrafficVehicle.gd").new()
		var follow = PathFollow2D.new()
		follow.loop = false
		path.add_child(follow)
		follow.add_child(probe)
		# Physical gate must cover this actual lane at its incoming side.
		for gate in crossing.get_gate_geometry().barriers:
			if String(gate.lane_id).get_file() != String(path.get_meta("traffic_lane_id", "")).get_file():
				continue
			barriers_checked += 1
			var gate_world: Vector2 = crossing.to_global(gate.position)
			var nearest: Vector2 = path.to_global(path.curve.get_closest_point(path.to_local(gate_world)))
			check(nearest.distance_to(gate_world) < float(gate.size.y) * 0.5, "Physical barrier covers the canonical lane")
		for offset in [-210, -180]:
			follow.progress = center + offset
			check(crossing.should_stop_vehicle_at(probe.global_position, probe), "Closed gate must stop approaching canonical lane " + str(path.name))
			var motion: Dictionary = probe._traffic_control_zone_motion(path, follow)
			check(is_finite(float(motion.allowed_advance)), "Approach receives bounded braking distance")
		follow.progress = center
		check(not crossing.should_stop_vehicle_at(probe.global_position, probe), "Vehicle on track retains escape")
		follow.progress = center + 180.0
		check(not crossing.should_stop_vehicle_at(probe.global_position, probe), "Outgoing lane stays open")
		crossing.set_train_approaching(false)
		crossing._process(2.0)
		follow.progress = center - 180.0
		check(not crossing.should_stop_vehicle_at(probe.global_position, probe), "Open gate permits entry")
		crossing.set_train_approaching(true)
		follow.queue_free()
	check(lanes_checked == 2 and barriers_checked == 2, "Both canonical lanes and their barriers were exercised")
	print("RAIL_CANONICAL_LANES failures=%d" % failures)
	quit(1 if failures else 0)

