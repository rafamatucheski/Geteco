extends "res://tests/test_vehicle_doors.gd"
## A nearby door must not send Dante around the nose/rear of the entire car.
func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	actor = ACTOR.new()
	actor.is_player = true
	stage.add_child(actor)
	actor.set_physics_process(false)
	await process_frame
	for id in ["sport_coupe", "sedan_classic", "arctic_jeep", "cargo_flatbed_truck"]:
		var car := spawn(id, .9)
		car.finish_doors()
		for side in car.boarding_sides():
			var layout: Dictionary = car.door_layout(side)
			for offset in [-.7, 0.0, .7]:
				actor.global_position = car.to_global(Vector3(float(side) * (car.half_width + .55), .04, layout.hinge.z + offset))
				var transition = BOARDING.new()
				stage.add_child(transition)
				transition.begin_entry(stage, car, actor, side)
				transition._motion.kill()
				transition.set_process(false)
				check(not transition._door_started, id + ": door stays closed until the short approach is clear")
				var direct: float = actor.global_position.distance_to(transition._stand_world)
				print("ENTRY_ROUTE ", id, " side=", side, " offset=", offset, " direct=", direct, " path=", transition._path_length, " duration=", transition.duration)
				check(transition._path_length <= direct + .15, id + ": nearby same-side door uses the short approach")
				check(transition.duration <= direct / 2.3 + .3 + .32 + float(transition.BODY_SECONDS.get(car.boarding_class(), 1.5)) + transition.CLOSE_SECONDS, id + ": entry time matches local approach, not a lap around the car")
				for sample in 21:
					transition.progress = transition._approach * float(sample) / 21.0
					transition._apply()
					var point: Vector3 = car.to_local(actor.global_position)
					check(absf(point.x) >= car.half_width + BODY_RADIUS, id + ": approach keeps the body outside the hull")
				transition.abort("test_done")
				await process_frame
				car.animate_driver_door(side, false, 0.0)
				actor.global_position = car.to_global(Vector3(float(side) * (car.half_width + .55), .04, layout.hinge.z + offset))
				var reversal = BOARDING.new()
				stage.add_child(reversal)
				reversal.begin_entry(stage, car, actor, side)
				reversal._motion.kill()
				reversal.set_process(false)
				reversal.progress = reversal._approach * .25
				reversal._apply()
				check(reversal.reverse_entry_to_exit(), id + ": early entry can be reversed")
				reversal._motion.kill()
				reversal._apply()
				check(not reversal._door_started, id + ": early reversal cannot open the door into the approach path")
				reversal.abort("test_done")
				await process_frame
				car.animate_driver_door(side, false, 0.0)
		car.queue_free()
		await process_frame
	await late_reversal()
	print("VEHICLE_ENTRY_SHORT_PATH checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func late_reversal() -> void:
	var car := spawn("sedan_classic", .9)
	car.finish_doors()
	actor.global_position = car.driver_door_anchor(-1)
	var transition = BOARDING.new()
	stage.add_child(transition)
	transition.begin_entry(stage, car, actor, -1)
	transition._motion.kill()
	transition.set_process(false)
	transition.progress = .8
	transition._apply()
	car.animate_driver_door(-1, true, 0.0)
	check(transition.reverse_entry_to_exit(), "open-door entry admits late cancellation")
	var returned := false
	var moved_with_open_leaf := false
	for step in 400:
		await process_frame
		if not is_instance_valid(transition) or not transition.active: break
		transition._apply()
		if transition.progress < transition._approach - .001:
			returned = true
			if absf(car.door_presentation.hinges[-1].rotation.y) > .01: moved_with_open_leaf = true
	check(returned, "late cancellation retraces the approach")
	check(not moved_with_open_leaf, "late cancellation closes the leaf before walking back past it")
	check(not is_instance_valid(transition) or not transition.active, "late cancellation finishes and releases its presentation")
	car.queue_free()
	await process_frame
