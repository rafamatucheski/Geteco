extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(15.0).timeout.connect(func():
		print("TIMEOUT: test_police_death_departure")
		quit(2)
	)

	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene

	var wanted = root.get_node_or_null("WantedManager")
	assert(wanted != null, "WantedManager must exist")
	wanted.reset_crime()

	await physics_frame
	await physics_frame

	# 1. Spawn a police vehicle and an officer
	var pool = root.get_node_or_null("EmergencyPool")
	var cruiser: Node2D = null
	if pool and pool.has_method("get_vehicle"):
		cruiser = pool.get_vehicle("police")
	if cruiser == null:
		var em_scene = load("res://emergency/EmergencyVehicle.tscn") as PackedScene
		cruiser = em_scene.instantiate()
		scene.add_child(cruiser)

	cruiser.position = Vector2(200, 200)
	cruiser.set("type", 0)
	cruiser.set_meta("police_player_pursuit", true)

	var officer_scene = load("res://police/PoliceOfficer.tscn") as PackedScene
	var officer = officer_scene.instantiate()
	officer.position = Vector2(230, 200)
	officer.service_vehicle = cruiser
	cruiser._police_crew.append(officer)
	cruiser.deployed_officers = 1
	cruiser.is_acting = true
	scene.add_child(officer)

	# Mock dummy suspect (player)
	var dummy_player := Node2D.new()
	dummy_player.position = Vector2(280, 200)
	dummy_player.add_to_group("player")
	dummy_player.set("is_dead", false)
	scene.add_child(dummy_player)

	officer.target = dummy_player
	cruiser.target = dummy_player
	wanted.current_stars = 2

	await physics_frame
	await physics_frame

	# Verify initial pursuit state
	assert(cruiser.get_meta("police_player_pursuit", false) == true, "Cruiser starts in pursuit")
	assert(officer.target == dummy_player, "Officer aims at player")

	# 2. Simulate player death / stand_down_police()
	dummy_player.set("is_dead", true)
	wanted.stand_down_police()

	# Verify: units MUST NOT be removed/queued_for_deletion during the death screen
	assert(is_instance_valid(cruiser) and not cruiser.is_queued_for_deletion(), "Cruiser remains in scene during death")
	assert(is_instance_valid(officer) and not officer.is_queued_for_deletion(), "Officer remains in scene during death")

	# Verify: crime is reset
	assert(wanted.current_stars == 0, "Stars reset to 0 upon death")

	# Verify: officer stopped aiming and initiated return to vehicle
	assert(officer.target == null, "Officer target cleared")
	assert(not officer.is_police_aiming(), "Officer no longer aims weapon")
	assert(officer.returning_to_service_vehicle == true, "Officer is returning to service vehicle")

	# Verify: cruiser stopped pursuit and requested recall
	assert(cruiser.target == null, "Cruiser target cleared")
	assert(cruiser.get_meta("police_player_pursuit", false) == false, "Pursuit metadata removed from cruiser")
	assert(cruiser._police_recall_requested == true, "Cruiser recall requested")

	# 3. Simulate passage of time during death screen (~10 physics frames)
	for i in range(10):
		await physics_frame

	# Units must still be valid and alive during this timeframe
	assert(is_instance_valid(cruiser) and not cruiser.is_queued_for_deletion(), "Cruiser still active in scene")
	assert(is_instance_valid(officer) and not officer.is_queued_for_deletion(), "Officer still active in scene")

	# 4. Simulate hospital respawn / dismiss_all_police()
	wanted.dismiss_all_police()

	# Give a frame for deferred deletion / deactivation
	await physics_frame
	await physics_frame

	# Verify: officer is freed
	assert(not is_instance_valid(officer) or officer.is_queued_for_deletion(), "Officer is cleanly removed upon hospital respawn")

	# Clean up scene
	scene.queue_free()
	print("TEST PASSED: test_police_death_departure successfully verified smooth departure and respawn cleanup!")
	quit(0)
