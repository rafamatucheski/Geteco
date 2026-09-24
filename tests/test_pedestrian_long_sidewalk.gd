extends "res://tests/test_pedestrian_route_recovery.gd"

func run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	seed(916)
	root.get_node("WantedManager").set_process(false)
	var props: Array[StaticBody2D] = []
	for x in [100.0,220.0,340.0,460.0]: props.append(obstacle(Vector2(x,0), Vector2(10,10)))
	var person := walker(PackedVector2Array([Vector2.ZERO,Vector2(600,0)]),Vector2(20,0))
	var furthest := 0.0
	var largest_step := 0.0
	for i in 1200:
		var previous := person.position
		await physics_frame
		furthest = maxf(furthest, person.position.x)
		largest_step = maxf(largest_step, person.position.distance_to(previous))
		if person.position.x > 350.0: break
	# The ambient pace is intentionally slower now; crossing the third obstacle
	# still proves progress beyond the navigation helper's local search range.
	check(furthest > 350.0, "Long sidewalk advances through several poles beyond local search range: x=%.2f" % furthest)
	check(largest_step < 1.2, "Long-route progress uses physical movement")
	person.free()
	for prop in props: prop.free()
	await frames(2)
	print("PEDESTRIAN_LONG_SIDEWALK failures=%d" % failures)
	quit(0 if failures == 0 else 1)
