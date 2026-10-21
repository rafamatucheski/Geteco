extends SceneTree
var world
var failures: Array[String] = []
func _initialize() -> void:
	# Este teste confere a abertura: o runner a pula por padrão (Arrival.skip_opening).
	OS.set_environment("GETECO_SKIP_OPENING", "0")
	# O prólogo jogável (BlitzScene) tem teste próprio: aqui cai direto no filme da balsa.
	OS.set_environment("GETECO_SKIP_PROLOGUE", "1")
	run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value: failures.append(label); push_error(label)
func run() -> void:
	root.get_node("V2Launch").selected_path = "user://arrival-flow-isolated.json"
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	# A cold .NET/Main launch took 48 s in the integrated story validation;
	# use the same finite wall-clock startup window as other current fixtures.
	var ready_deadline := Time.get_ticks_msec()+80000
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
	var security = session.urban_operations.security
	var arrival_crimes: Array = []
	world.gameplay.crime_reported.connect(func(points: int): arrival_crimes.append({"points":points,"phase":arrival.phase,"position":world.player.global_position}))
	arrival.phase = "new"
	arrival.flags.clear()
	arrival.opening_completed = false
	arrival.start_or_resume(false)
	check(session.weather.time_of_day > .9 and session.weather.weather_state == 1, "new arrival starts on the film's rainy night")
	check(session.state.world_state.time > .9 and session.state.world_state.weather == 1, "opening weather is present in persistent world state")
	arrival.presentation.film.skip()
	for i in 900:
		await physics_frame
		if arrival.phase == "terminal_meeting" or (arrival.phase == "disembark" and not arrival.controls_locked): break
	print("DISEMBARK phase=", arrival.phase, " player=", world.player.global_position)
	check(arrival.phase == "terminal_meeting", "player physically exits ferry and goes directly to Maciota's street encounter")
	check(arrival.flags.get("harbor_arrival_seen", false), "arrival flag after completed physical exit")
	check(world.player.visible and not world.player.input_locked, "visible controllable player after arrival")
	check(session.weather.time_of_day > .9 and session.weather.weather_state == 1, "physical disembark preserves the film's night and rain")
	check(arrival_crimes.is_empty() and not security.alerted and world.gameplay.stars == 0, "scripted spawn and disembark never report trespassing: %s" % str(arrival_crimes))
	if "--capture-arrival" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/arrival-port-fix-20261010.png")
	# A resumed checkpoint must not reset the saved clock/weather to the prologue.
	var arrival_time: float = session.weather.time_of_day
	session.weather.time_of_day = .42
	session.weather.weather_state = 3
	arrival.start_or_resume(true)
	check(is_equal_approx(session.weather.time_of_day,.42) and session.weather.weather_state == 3, "resumed arrival preserves existing weather")
	session.weather.time_of_day = arrival_time
	session.weather.weather_state = 1
	session.weather._update()
	check(not arrival.flags.has("harbor_police_briefed"), "new arrival never requires the police briefing")
	check(is_instance_valid(arrival.car) and is_instance_valid(arrival.maciota), "Maciota and the black M8 already wait at the street exit")
	session.controller.region.set_focus(arrival.PARK)
	for i in 600:
		await physics_frame
		if session.controller.region.is_streaming_idle(): break
	world.player.teleport(arrival.maciota.global_position + Vector3(0,.1,2))
	for i in 5: await physics_frame
	if not session.dialogue_open: arrival.perform("arrival_meeting")
	var spoken := 0
	while session.dialogue_open and spoken < 10:
		spoken += 1
		session._advance_dialogue()
	check(spoken == 5 and arrival.phase == "tour_board", "recognition, police photograph and invitation advance to passenger boarding")
	check(arrival.flags.get("harbor_arrival_contact_met",false), "terminal meeting persists independently of the old police/phone chain")
	check(preload("res://runtime/Arrival.gd").validate_snapshot(arrival.snapshot()), "physical flow produces valid save")
	world.free()
	await process_frame
	print("ARRIVAL_FLOW failures=", failures)
	quit(0 if failures.is_empty() else 1)
