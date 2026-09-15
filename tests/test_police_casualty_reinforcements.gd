extends SceneTree

var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var wanted := root.get_node("WantedManager")
	wanted.set_process(false)
	var player := CharacterBody2D.new()
	player.add_to_group("player")
	world.add_child(player)
	var bike = preload("res://world/shared/emergency/ModernTrafficFactory.gd").spawn_parked_vehicle(world, "EscapeBike", Vector2(0, 100), 0, "bike_sport", 0)
	bike.set_physics_process(false)
	bike.is_driven_by_player = true
	check(wanted.get_suspect_actor() == bike, "Pursuit tracks the production motorcycle while ridden")
	wanted.ensure_minimum_wanted_level(6)
	await physics_frame
	var pool := root.get_node("EmergencyPool")
	var units: Array = []
	for i in 5:
		var car = pool.get_vehicle("police")
		check(car != null, "Six-star fleet slot available")
		if car == null: quit(1); return
		car.set_physics_process(false)
		car.position = Vector2(200 + i * 120, 100)
		car.target = bike
		wanted._configure_dispatch(car)
		units.append(car)
	check(pool.get_vehicle("police") == null, "Live fleet retains its bounded capacity")
	for i in 2:
		var car = units[i]
		car._deploy_officers_duo()
		for officer in car._police_crew:
			officer.set_physics_process(false)
			# Real damage/death path, including the officer-down crime report.
			officer.take_damage(10000, true)
		check(not wanted._is_active_pursuit_unit(car), "Eliminated crew no longer consumes an active-response slot")
		check(not wanted.report_visual_contact(car), "Empty car cannot act as an invisible police observer")
	check(wanted.current_stars == 6, "Four officer deaths preserve six stars")
	check(pool.get_vehicle("police") == null and units[0].visible and units[1].visible, "Nearby empty cars stay on the ground instead of disappearing")
	var empty_position: Vector2 = units[0].position
	units[0]._physics_process(.1)
	check(units[0].position == empty_position, "Eliminated crew never drives its car away")
	bike.position = Vector2(5000, 100)
	wanted._sensor_timer = 1000.0
	wanted.police_spawn_timer = 1000.0
	wanted._process(49.0)
	check(wanted.current_stars == 6 and wanted.is_searching(), "Six-star search survives the old 48-second sudden cancellation")
	var lane := Path2D.new()
	lane.curve = Curve2D.new()
	lane.curve.add_point(Vector2(-1600, 100))
	lane.curve.add_point(Vector2(2000, 100))
	lane.add_to_group("unified_traffic_lane")
	world.add_child(lane)
	wanted._dispatch_police()
	check(wanted.deployed_this_pursuit == 6, "Real dispatch replaces a defeated crew after motorcycle escape")
	check(pool._pool.police.size() == 7, "Replacement does not grow the vehicle pool")
	check(units[0].has_police_response_crew() and not units[0]._police_crew_on_foot, "Replacement starts with its own crew state")
	for unit in units: unit.set_physics_process(false)
	var partial = units[2]
	partial.target = bike
	partial._deploy_officers_duo()
	var survivor = partial._police_crew[0]
	var casualty = partial._police_crew[1]
	survivor.set_physics_process(false)
	casualty.set_physics_process(false)
	casualty.take_damage(10000, true)
	check(not partial._all_surviving_police_boarded(), "A casualty does not invent an onboard driver")
	survivor.position = partial.get_crew_door_point(survivor.crew_side, survivor.crew_longitudinal)
	survivor._board_service_vehicle()
	check(not partial._all_surviving_police_boarded(), "Boarding animation must actually finish")
	await create_timer(.6).timeout
	partial.scene_timeout = 2.0
	partial._physics_process(.1)
	check(not partial._police_crew_on_foot and partial._police_available_seats == 1, "Boarded survivor can resume pursuit without resurrecting the dead partner")
	wanted.time_hidden = wanted.get_escape_duration() - .1
	wanted.police_spawn_timer = 1000.0
	wanted._process(.2)
	check(wanted.current_stars == 0, "Sustained genuine loss of contact still permits escape")
	wanted.dismiss_all_police()
	world.queue_free()
	await process_frame
	print("POLICE_CASUALTY_REINFORCEMENTS failures=", failures)
	quit(1 if failures else 0)
