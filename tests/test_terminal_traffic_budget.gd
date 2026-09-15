extends "res://tests/test_reserved_traffic_budget.gd"

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var car := actor(world, Vector2(5000, 5000))
	var pedestrian := actor(world, Vector2(5100, 5100), true)
	var distant := actor(world, Vector2(8000, 8000))
	var coach := Node2D.new()
	coach.add_to_group("harbor_terminal_coach")
	coach.position = Vector2(12000, 12000)
	world.add_child(coach)
	var life := preload("res://world/harbor/HarborLife.gd").new()
	world.add_child(life)
	life.set_process(false)
	life.vehicles.assign([car, distant])
	life.walkers.assign([pedestrian])
	var stream := QuietStream.new()
	world.add_child(stream)
	for budget in [life, stream]:
		coach.position = Vector2(12000, 12000)
		for body in [car, pedestrian, distant]:
			body.set_process(true)
			body.set_physics_process(true)
		var method := "_budget_population" if budget == life else "_budget_traffic"
		budget.call(method, Vector2.ZERO)
		check(not car.can_process() and not pedestrian.can_process(), "Off-camera population initially sleeps")
		coach.position = Vector2(5050, 5050)
		budget.call(method, Vector2.ZERO)
		check(car.can_process() and car.is_processing() and car.is_physics_processing(), "Approaching terminal coach wakes traffic on its off-camera journey")
		check(pedestrian.can_process(), "Pedestrians around the off-camera coach can finish crossing")
		check(not distant.can_process(), "Unrelated distant population retains its simulation budget")
		coach.position = Vector2(12000, 12000)
		budget.call(method, Vector2.ZERO)
		check(not car.can_process() and not pedestrian.can_process(), "Population can sleep again after the coach leaves")
		# Each owner is a separate fixture; restore before testing the other owner.
		if budget == life: life._population_activity.restore_all()
		else: stream.population_activity.restore_all()
	print("TERMINAL_TRAFFIC_BUDGET failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
