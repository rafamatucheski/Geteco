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
	for scenario in ["occupied", "parked", "hidden", "fallen"]:
		var aboard := 1 if scenario == "occupied" else 0
		var player = load("res://characters/Player.gd").new()
		var camera := Camera2D.new()
		camera.name = "Camera"
		player.add_child(camera)
		world.add_child(player)
		player.set_physics_process(false)
		var unit = load("res://cars/traffic/TrafficVehicle.tscn").instantiate()
		unit.position = Vector2(2000 * aboard, 0)
		world.add_child(unit)
		unit.set_physics_process(false)
		unit.apply_archetype("bike_urban", Color.WHITE)
		unit.ensure_presentation()
		if scenario == "parked": unit.configure_as_parked()
		if scenario == "hidden": unit.body_model.rider.hide()
		if scenario == "fallen": unit._rider_fallen = true
		player.position = unit.position + Vector2(0, -65)
		await physics_frame
		unit.enter_vehicle(player)
		check(get_nodes_in_group("pedestrian").filter(func(n): return n is CarjackedDriver).size() == aboard, "%d onboard yields %d riders" % [aboard, aboard])
		var driven: Node = null
		for car in world.get_children():
			if car.get("is_driven_by_player") == true: driven = car
		check(driven != null, "Player controls motorcycle")
		for child in world.get_children(): child.queue_free()
		await process_frame
		await process_frame
	print("MOTORCYCLE_THEFT failures=%d" % failures)
	quit(1 if failures else 0)
