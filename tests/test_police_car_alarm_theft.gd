extends SceneTree

var failures: Array[String] = []
var world: Node2D
var player: CharacterBody2D
var wanted: Node

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func solve(car: Node) -> void:
	var lock = car._vehicle_lockpick
	for pin in 3:
		lock.angle = lock.target_angle
		var event: InputEvent
		if pin == 1:
			event = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
		else:
			event = InputEventKey.new()
			event.keycode = KEY_SPACE
		event.pressed = true
		lock._input(event)

func leave(car: Node) -> void:
	while car.has_meta("vehicle_boarding"): await process_frame
	car.exit_vehicle()
	while car.has_meta("vehicle_boarding"): await process_frame
	player.set_physics_process(false)

func run() -> void:
	create_timer(65).timeout.connect(func(): quit(2))
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("PresentationBudget").set_process(false)
	wanted = root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.reset_crime()
	player = CharacterBody2D.new()
	player.set_script(load("res://characters/Player.gd"))
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)

	var parking = load("res://world/harbor/HarborPatrolParking.gd").new()
	world.add_child(parking)
	var car = parking.get_node("PatrolParked1")
	player.global_position = car.global_position + Vector2(30, 0)
	car.enter_vehicle(player)
	check(not car.is_driven_by_player and car._vehicle_lockpick.active, "Precinct cruiser requires lockpick before boarding")
	check(player.visible and player.is_control_disabled and wanted.current_stars == 0, "Lockpick leaves actor outside, blocks controls and creates no crime")
	var first_lock = car._vehicle_lockpick
	car.enter_vehicle(player)
	check(car._vehicle_lockpick == first_lock, "Repeated interaction cannot duplicate lockpick")
	first_lock.angle = first_lock.target_angle + PI
	first_lock.attempt()
	check(not car.is_driven_by_player and player.visible and not player.is_control_disabled, "Wrong timing denies entry and restores controls")
	check(car.is_alarm_active and car.alarm_audio.playing and wanted.current_stars == 0, "Failure sounds alarm without wanted stars")
	check(car.alarm_timer >= 10 and car.alarm_timer <= 15, "Police alarm duration is 10 to 15 seconds")
	var initial_time: float = car.alarm_timer
	car.start_theft_alarm()
	check(car.alarm_timer <= initial_time, "Repeated alarm trigger cannot extend timeout")
	car.enter_vehicle(player)
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	car._vehicle_lockpick._input(cancel)
	check(car._vehicle_lockpick == null and not player.is_control_disabled and wanted.current_stars == 0, "Escape closes lockpick and keeps failure local")
	car.enter_vehicle(player)
	Input.action_press("fire")
	car._vehicle_lockpick.finish(false)
	check(player.is_control_disabled, "Failed click cannot leak into weapon fire")
	Input.action_release("fire")
	await process_frame
	await process_frame
	check(not player.is_control_disabled, "Releasing failed click restores controls")
	car.enter_vehicle(player)
	solve(car)
	check(car.is_driven_by_player and car.was_stolen_from_police, "Keyboard and mouse solve the lock and begin boarding")
	check(wanted.current_stars == 1 and wanted.crime_points == wanted.STAR_THRESHOLDS[1], "Successful theft creates exactly one wanted star")
	check(not car.is_alarm_active and not car.alarm_audio.playing, "Successful unlock silences previous alarm")
	await leave(car)
	car.enter_vehicle(player)
	check(car._vehicle_lockpick == null and wanted.current_stars == 1, "Reentering stolen cruiser does not repeat lock or crime")
	await leave(car)

	var standby = load("res://emergency/EmergencyStandbyPoint.gd").new()
	standby.position = Vector2(500, 500)
	world.add_child(standby)
	await process_frame
	var standby_car = standby.parked_car
	player.global_position = standby_car.global_position + Vector2(30, 0)
	standby_car.enter_vehicle(player)
	check(standby_car._vehicle_lockpick != null and standby.available, "Standby cruiser is also locked and remains available until theft")
	solve(standby_car)
	check(wanted.current_stars == 2 and not standby.available, "Second cruiser adds one star and notifies its standby point")
	await leave(standby_car)
	standby._spawn_standby_car()
	await process_frame
	check(is_instance_valid(standby_car) and standby.parked_car != standby_car, "Replacing standby stock preserves the stolen cruiser")

	var other = parking.get_node("PatrolParked2")
	player.global_position = other.global_position + Vector2(30, 0)
	other.enter_vehicle(player)
	player.is_arrested = true
	other._vehicle_lockpick.finish(true)
	check(not other.is_driven_by_player and not player.is_control_disabled, "Arrest during lockpick cannot grant entry or leave controls stuck")
	player.is_arrested = false
	other.enter_vehicle(player)
	other.queue_free()
	await process_frame
	check(not player.is_control_disabled, "Removing vehicle closes modal and restores actor controls")

	var alarms: Array[Node] = []
	for archetype in ["sedan_classic", "bike_urban"]:
		var equipped := 0
		for i in 16:
			var sample = ModernTrafficFactory.spawn_parked_vehicle(world, "%s%d" % [archetype,i], Vector2(1000+i*120,1000), 0, archetype, 0)
			if sample.has_theft_alarm: equipped += 1
			var original: bool = sample.has_theft_alarm
			sample.configure_as_parked()
			check(sample.has_theft_alarm == original, "Parked alarm selection stays stable")
			sample.free()
		check(equipped > 0 and equipped < 16, archetype + " has a mix of alarm-equipped and ordinary parked vehicles")
		var parked = ModernTrafficFactory.spawn_parked_vehicle(world, archetype, Vector2(3000,1000), 0, archetype, 0)
		parked.has_theft_alarm = true
		player.global_position = parked.global_position + Vector2(0,30)
		parked.enter_vehicle(player)
		check(parked.is_driven_by_player and parked.is_alarm_active and parked.alarm_audio.playing, archetype + " alarm sounds on theft")
		check(parked.alarm_timer >= 10 and parked.alarm_timer <= 15, archetype + " alarm lasts 10 to 15 seconds")
		check(wanted.current_stars == 2, "Civilian alarm does not add police stars")
		await leave(parked)
		# One timer runs on a sleeping abandoned car; the other on a broken bike.
		if parked.is_motorcycle: parked.is_broken = true
		else: parked.set_physics_process(false)
		alarms.append(parked)

	var quiet = ModernTrafficFactory.spawn_parked_vehicle(world, "QuietCar", Vector2(3400,1000), 0, "sedan_classic", 0)
	quiet.has_theft_alarm = false
	player.global_position = quiet.global_position + Vector2(0,30)
	quiet.enter_vehicle(player)
	check(quiet.is_driven_by_player and not quiet.is_alarm_active, "Vehicle without alarm boards normally and quietly")
	await leave(quiet)
	await create_timer(15.2).timeout
	for parked in alarms:
		check(not parked.is_alarm_active and not parked.alarm_audio.playing and parked.alarm_timer == 0, "Alarm expires naturally even on a sleeping or broken vehicle")
		parked.is_broken = false
		player.global_position = parked.global_position + Vector2(0,30)
		parked.enter_vehicle(player)
		check(not parked.is_alarm_active, "Returning to a previously stolen civilian vehicle does not restart alarm")
		await leave(parked)
	print("VEHICLE SECURITY FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)
