extends SceneTree
var world
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value: failures.append(label); push_error(label)
func run() -> void:
	root.get_node("V2Launch").selected_path = "user://arrival-flow-isolated.json"
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	# Region prewarming alone can exceed the old four-second frame budget.
	var ready_deadline := Time.get_ticks_msec()+30000
	while Time.get_ticks_msec() < ready_deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Arrival flow: world did not finish startup")
		world.free()
		quit(1)
		return
	var session = world.session
	var arrival = session.arrival
	arrival.phase = "new"
	arrival.flags.clear()
	arrival.opening_completed = false
	arrival.start_or_resume(false)
	check(session.weather.time_of_day > .9 and session.weather.weather_state == 1, "new arrival starts on the film's rainy night")
	check(session.state.world_state.time > .9 and session.state.world_state.weather == 1, "opening weather is present in persistent world state")
	arrival.presentation.film.skip()
	for i in 900:
		await physics_frame
		if arrival.phase == "police_visit" or (arrival.phase == "disembark" and not arrival.controls_locked): break
	print("DISEMBARK phase=", arrival.phase, " player=", world.player.global_position)
	check(arrival.phase == "police_visit", "player physically exits ferry onto public quay")
	check(arrival.flags.get("harbor_arrival_seen", false), "arrival flag after completed physical exit")
	check(world.player.visible and not world.player.input_locked, "visible controllable player after arrival")
	check(session.weather.time_of_day > .9 and session.weather.weather_state == 1, "physical disembark preserves the film's night and rain")
	# A resumed checkpoint must not reset the saved clock/weather to the prologue.
	var arrival_time: float = session.weather.time_of_day
	session.weather.time_of_day = .42
	session.weather.weather_state = 3
	arrival.start_or_resume(true)
	check(is_equal_approx(session.weather.time_of_day,.42) and session.weather.weather_state == 3, "resumed arrival preserves existing weather")
	session.weather.time_of_day = arrival_time
	session.weather.weather_state = 1
	session.weather._update()
	check(await session.enter_place("harbor_police", false), "enter original police station")
	world.player.teleport(session.room.interaction_points.service + Vector3.UP * .06)
	for i in 3: await physics_frame
	check(session.interact(), "physical police conversation")
	var spoken := 0
	while session.dialogue_open and spoken < 10:
		spoken += 1
		session._advance_dialogue()
	check(spoken == 5 and arrival.phase == "police_exit", "all five original police lines advance checkpoint")
	check(await session.leave_place(), "leave police physically")
	arrival._physics_process(4.1)
	check(arrival.phase == "phone", "call follows exit and original four second wait")
	check(session.interact(), "answer actual arrival phone")
	spoken = 0
	while session.dialogue_open and spoken < 10:
		spoken += 1
		session._advance_dialogue()
	check(spoken == 4 and arrival.phase == "yard_meeting", "all four original phone lines and yard checkpoint")
	check(preload("res://runtime/Arrival.gd").validate_snapshot(arrival.snapshot()), "physical flow produces valid save")
	check(is_instance_valid(arrival.car) and not arrival.car.is_physics_processing(), "remote encounter waits for streamed ground")
	world.free()
	await process_frame
	print("ARRIVAL_FLOW failures=", failures)
	quit(0 if failures.is_empty() else 1)
