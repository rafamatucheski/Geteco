extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var wanted := root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.reset_crime()
	await physics_frame
	await physics_frame
	var pool := root.get_node("EmergencyPool")
	wanted.current_stars = 1
	var patrol: Node2D = pool.get_vehicle("police")
	var bike: Node2D = pool.get_vehicle("police")
	patrol.configure_police_response(1, 1)
	bike.configure_police_response(1, 2)
	patrol.set_physics_process(false)
	bike.set_physics_process(false)
	assert(patrol.police_variant == "patrol")
	assert(bike.police_variant == "motorcycle")
	assert(bike.visual_3d.motorcycle and bike.visual_3d.doors.is_empty(), "Motorcycle uses real rider model, no car doors")
	assert(bike.get_node("CollisionShape2D").shape.size.y < patrol.get_node("CollisionShape2D").shape.size.y)
	var target := CharacterBody2D.new()
	target.position = Vector2(100, 100)
	scene.add_child(target)
	bike.position = Vector2(0, 100)
	bike.target = target
	bike._begin_response()
	assert(bike.deployed_officers == 1, "One actual officer dismounts motorcycle")
	assert(bike._tactical_doors.is_empty(), "Motorcycle cannot fabricate ballistic cover")
	for officer in bike._police_crew:
		officer.set_physics_process(false)
		officer.queue_free()
	pool.return_vehicle(patrol)
	pool.return_vehicle(bike)
	wanted.current_stars = 5
	assert(wanted.get_max_active_units() == 5, "Maximum pursuit is capped at five vehicles")
	var units: Array[Node2D] = []
	for index in 5:
		var unit: Node2D = pool.get_vehicle("police")
		assert(unit != null, "Five heavy-response cruisers available")
		wanted._configure_dispatch(unit)
		unit.set_physics_process(false)
		assert(unit.police_variant != "motorcycle")
		units.append(unit)
	assert(pool.get_vehicle("police") == null, "Heavy-response fleet is finite at five")
	assert(units.filter(func(unit): return unit.police_variant == "tactical").size() == 1, "Five-car response contains exactly one elite tactical unit")
	assert(units.filter(func(unit): return unit.police_variant == "patrol").size() == 4, "The other four response cars remain standard patrols")
	var first_elite: Node2D = units.filter(func(unit): return unit.police_variant == "tactical")[0]
	first_elite.is_broken = true
	var replacement: Node2D = units.filter(func(unit): return unit.police_variant == "patrol")[0]
	wanted._configure_dispatch(replacement)
	var active_elite := units.filter(func(unit): return wanted._is_active_pursuit_unit(unit) and unit.police_variant == "tactical")
	assert(active_elite == [replacement], "A disabled elite is replaced without creating two active elite units")
	for unit in units: pool.return_vehicle(unit)
	wanted.reset_crime()
	await physics_frame
	print("PASS police response fleet: two low-level motorcycles, five-car maximum, one elite unit")
	quit()
