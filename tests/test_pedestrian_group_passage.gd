extends "res://tests/test_pedestrian_route_recovery.gd"

func run() -> void:
	create_timer(25.0).timeout.connect(func(): quit(2))
	seed(914)
	root.get_node("WantedManager").set_process(false)
	var route := PackedVector2Array([Vector2.ZERO, Vector2(500, 0)])
	var reverse := route.duplicate()
	reverse.reverse()
	var leader := walker(route, Vector2(60, 0))
	var follower := walker(route, Vector2(25, 0))
	var opposing := walker(reverse, Vector2(240, 0))
	var post := obstacle(Vector2(145, 0), Vector2(10, 10))
	var min_gap := INF
	var largest_step := 0.0
	var passed := false
	for i in 840:
		var before := [leader.position, follower.position, opposing.position]
		await physics_frame
		var people := [leader, follower, opposing]
		if OS.get_cmdline_user_args().has("--debug") and i % 120 == 0:
			for p in people:
				print("GROUP ", i, " ", p.position, " state=", p.locomotion_state, " target=", p.walk_target, " path=", p.movement_navigation.path.slice(0, 2), " side=", p._person_detour_direction(p.walk_dir), " stuck=", p.stuck_timer)
		for j in 3:
			largest_step = maxf(largest_step, people[j].position.distance_to(before[j]))
			for k in range(j + 1, 3): min_gap = minf(min_gap, people[j].position.distance_to(people[k].position))
		if follower.position.x > 190.0 and leader.position.x > 190.0 and opposing.position.x < 100.0:
			passed = true
			break
	check(passed, "Group passes pole and opposing walker: %s / %s / %s" % [leader.position, follower.position, opposing.position])
	check(min_gap >= 23.0, "Group never overlaps physical personal space")
	check(largest_step < 1.2, "Group manoeuvres without teleporting")
	leader.free()
	follower.free()
	opposing.free()
	post.free()
	await frames(2)
	print("PEDESTRIAN_GROUP_PASSAGE failures=%d" % failures)
	quit(0 if failures == 0 else 1)
