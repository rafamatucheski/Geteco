extends SceneTree

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(20).timeout.connect(func(): printerr("POLICE_PARKED_WITHOUT_CREW TIMEOUT"); quit(2))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var wanted := root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.current_stars = 2
	await physics_frame
	var car = root.get_node("EmergencyPool").get_vehicle("police")
	car.set_physics_process(false)
	car.position = Vector2(500, 500)
	var target := Node2D.new()
	target.set_meta("ambient_crime", true)
	scene.add_child(target)
	target.position = Vector2(1800, 500)
	car.target = target
	car._deploy_officers_duo()
	var crew: Array = car._police_crew.duplicate()
	for officer in crew: officer.set_physics_process(false)
	var parked: Transform2D = car.global_transform
	for frame in 1000:
		# Repeated external return/reverse orders may never bypass occupancy.
		car.is_returning_to_base = true
		car.is_acting = false
		car.is_reversing = true
		car.velocity = Vector2(100, 0)
		car.current_speed = 100.0
		car._physics_process(.1)
		assert(car.global_transform.is_equal_approx(parked), "Car moved without its crew")
	assert(car._police_crew_on_foot and car.returned_officers == 0, "Timeout cannot invent a driver")
	car.on_officer_embarked(crew[0])
	assert(car.returned_officers == 0, "Visible officer is not boarded")
	for officer in crew:
		officer.position = car.get_crew_door_point(officer.crew_side, officer.crew_longitudinal)
		officer._board_service_vehicle()
	await create_timer(.6).timeout
	assert(car.returned_officers == crew.size(), "Real boarding releases both seats")
	car.on_officer_embarked(target)
	assert(car.returned_officers == crew.size(), "Unassigned actor cannot invent occupants")
	car._physics_process(.1)
	assert(not car._police_crew_on_foot, "Completed boarding releases driving lock")
	# A subsequent deployment losing the entire team remains parked indefinitely.
	car._deploy_officers_duo()
	for officer in car._police_crew:
		officer.set_physics_process(false)
		officer.is_dead = true
	for frame in 300:
		car.is_returning_to_base = true
		car._physics_process(.1)
		assert(car.global_transform.is_equal_approx(parked), "Dead crew cannot drive the car home")
	assert(car._police_crew_on_foot)
	car._deactivate()
	scene.queue_free()
	await process_frame
	print("POLICE_PARKED_WITHOUT_CREW PASS")
	quit()
