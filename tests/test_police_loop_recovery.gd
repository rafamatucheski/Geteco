extends SceneTree

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(35.0).timeout.connect(func(): printerr("POLICE_LOOP_RECOVERY TIMEOUT"); quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var wanted := root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.current_stars = 2
	var lane := Path2D.new()
	lane.curve = Curve2D.new()
	for point in [Vector2(0, 0), Vector2(800, 0), Vector2(800, 600), Vector2(0, 600), Vector2.ZERO]:
		lane.curve.add_point(point)
	lane.set_meta("traffic_lane_loop", true)
	lane.add_to_group("unified_traffic_lane")
	world.add_child(lane)
	var suspect := Node2D.new()
	suspect.position = Vector2(400, -580)
	world.add_child(suspect)
	await physics_frame
	var cruiser := root.get_node("EmergencyPool").get_vehicle("police") as CharacterBody2D
	cruiser.position = Vector2.ZERO
	cruiser.rotation = 0.0
	cruiser.target = suspect
	var previous := cruiser.position
	var biggest_step := 0.0
	var visited_goal := false
	for frame in 480:
		await physics_frame
		biggest_step = maxf(biggest_step, previous.distance_to(cruiser.position))
		previous = cruiser.position
		visited_goal = visited_goal or cruiser.position.distance_to(Vector2(400, 0)) < 35.0
	print("LOOP_OFFROAD|position=", cruiser.position, "|speed=", cruiser.current_speed, "|step=", biggest_step)
	check(visited_goal, "Cruiser physically reaches the road nearest an off-road suspect")
	check(cruiser.position.distance_to(Vector2(400, 0)) < 40.0 and cruiser.current_speed < 1.0, "Off-road suspect does not make the cruiser orbit its road forever")
	check(biggest_step < 12.0, "Ending a loop pursuit never teleports the cruiser")
	# The same vehicle must resume normally when the known point moves ahead.
	suspect.position = Vector2(700, -440)
	for frame in 240: await physics_frame
	check(cruiser.position.distance_to(Vector2(700, 0)) < 40.0, "A stopped regional patrol follows an updated known point on the same loop")
	for frame in 120: await physics_frame
	var crew_outside := 0
	for officer in get_nodes_in_group("police_officer"):
		if officer.service_vehicle == cruiser and not officer.service_disembark_active and officer.global_position.distance_to(cruiser.global_position) > 22.0:
			crew_outside += 1
	check(cruiser.deployed_officers > 0 and crew_outside > 0, "Police physically leave the cruiser to pursue a suspect 440 units off the road")
	cruiser._deactivate()
	wanted.reset_crime()
	world.queue_free()
	await process_frame
	print("POLICE_LOOP_RECOVERY ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
