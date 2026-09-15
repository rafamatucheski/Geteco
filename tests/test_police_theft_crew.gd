extends SceneTree

var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("PresentationBudget").set_process(false)
	var wanted := root.get_node("WantedManager")
	wanted.set_process(false)
	for scenario in [[2, false], [1, false], [0, false], [1, true], [0, true]]:
		wanted.reset_crime()
		var aboard: int = scenario[0]
		var player = load("res://Player.gd").new()
		var camera := Camera2D.new()
		camera.name = "Camera"
		player.add_child(camera)
		world.add_child(player)
		player.set_physics_process(false)
		var unit = load("res://emergency/EmergencyVehicle.tscn").instantiate()
		unit.type = 0
		if scenario[1]: unit.police_variant = "motorcycle"
		unit.position = Vector2(2000 * aboard, 0)
		world.add_child(unit)
		unit.set_physics_process(false)
		if aboard != 2:
			unit._police_crew_on_foot = true
			unit.returned_officers = aboard
		player.position = unit.position + Vector2(0, -65)
		await physics_frame
		unit.enter_vehicle(player)
		check(get_nodes_in_group("police_officer").size() == aboard, "%d onboard yields %d officers" % [aboard, aboard])
		var driven: Node = null
		for car in world.get_children():
			if car.get("is_driven_by_player") == true: driven = car
		check(driven != null, "Player controls stolen police vehicle")
		var notice_found := false
		for label in root.find_children("*","Label",true,false):
			if "VIATURA ROUBADA" in label.text: notice_found = true
		check(not notice_found,"police car/motorcycle theft does not show the red notice")
		check(wanted.current_stars == 1,"police car/motorcycle theft still adds one wanted star")
		for npc in get_nodes_in_group("pedestrian"):
			check(not npc is CarjackedDriver, "No generic civilian is created")
		var positions: Array[Vector2] = []
		for officer in get_nodes_in_group("police_officer"):
			for point in positions: check(point.distance_to(officer.position) >= 16, "Medics exit separately")
			positions.append(officer.position)
			check(officer.get_script() == load("res://police/PoliceOfficer.gd"), "Real police officer is used")
		if driven != null:
			while driven.has_meta("vehicle_boarding"): await process_frame
			driven.force_exit_vehicle()
		for child in world.get_children(): child.queue_free()
		await process_frame
		await process_frame
	print("POLICE_THEFT failures=%d" % failures)
	quit(1 if failures else 0)
