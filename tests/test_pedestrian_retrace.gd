extends "res://tests/test_pedestrian_route_recovery.gd"

func run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	seed(917)
	root.get_node("WantedManager").set_process(false)
	var post := obstacle(Vector2(300,0), Vector2(10,10))
	var wall := obstacle(Vector2(350,0), Vector2(30,100))
	var person := walker(PackedVector2Array([Vector2.ZERO,Vector2(600,0)]),Vector2(321,0))
	var escaped := false
	var max_side := 0.0
	for i in 660:
		await physics_frame
		if OS.get_cmdline_user_args().has("--debug") and i % 60 == 0:
			print("RETRACE ", i, " ", person.position, " target=",person.walk_target," path=",person.movement_navigation.path," pending=",person.movement_navigation._search_pending," stuck=",person.stuck_timer)
		max_side = maxf(max_side, absf(person.position.y))
		if person.position.x < 275.0:
			escaped = true
			break
	check(escaped, "Blocked walker replans a retreat around the pole behind it: %s" % person.position)
	check(max_side > 16.0 and max_side <= 28.1, "Retreat follows a physical detour inside the sidewalk")
	person.free()
	post.free()
	wall.free()
	await frames(2)
	print("PEDESTRIAN_RETRACE failures=%d" % failures)
	quit(0 if failures == 0 else 1)
