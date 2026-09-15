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
	for aboard in [2, 1, 0]:
		var player = load("res://Player.gd").new()
		var camera := Camera2D.new()
		camera.name = "Camera"
		player.add_child(camera)
		world.add_child(player)
		player.set_physics_process(false)
		var unit = load("res://EmergencyVehicle.tscn").instantiate()
		unit.type = 1
		unit.position = Vector2(2000 * aboard, 0)
		world.add_child(unit)
		unit.set_physics_process(false)
		if aboard != 2:
			unit.deployed_paramedics = 2
			unit.returned_paramedics = aboard
		player.position = unit.position + Vector2(0, -65)
		await physics_frame
		unit.enter_vehicle(player)
		check(get_nodes_in_group("paramedic").size() == aboard, "%d onboard yields %d medics" % [aboard, aboard])
		var driven: Node = null
		for car in world.get_children():
			if car.get("is_driven_by_player") == true: driven = car
		check(driven != null, "Player controls stolen ambulance")
		for npc in get_nodes_in_group("pedestrian"):
			check(not npc is CarjackedDriver, "No generic civilian is created")
		var positions: Array[Vector2] = []
		for medic in get_nodes_in_group("paramedic"):
			for point in positions: check(point.distance_to(medic.position) >= 16, "Medics exit separately")
			positions.append(medic.position)
			check(medic.mat_uniform != null, "Existing paramedic uniform is used")
		for child in world.get_children(): child.queue_free()
		await process_frame
		await process_frame
	print("AMBULANCE_THEFT failures=%d" % failures)
	quit(1 if failures else 0)
