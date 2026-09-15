extends SceneTree

class Suspect extends CharacterBody2D:
	var is_dead := false
	var is_control_disabled := false
	var fire_cooldown := 0.0
	var arrests := 0
	func arrest_and_respawn() -> void: arrests += 1

class EscapeCar extends CharacterBody2D:
	var is_driven_by_player := true

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): printerr("POLICE_FAIR_ARREST TIMEOUT"); quit(2))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	root.get_node("WantedManager").set_process(false)
	var actor := Suspect.new()
	actor.add_to_group("player")
	scene.add_child(actor)
	var officer = load("res://police/PoliceOfficer.tscn").instantiate()
	scene.add_child(officer)
	officer.set_physics_process(false)
	officer.position = Vector2(-25, 0)
	officer.target = actor
	await physics_frame
	officer._arrest_player()
	assert(actor.arrests == 0, "No arrest without warning")
	officer.arrest_warning_given = true
	officer.arrest_warning_elapsed = 3.1
	officer.arrest_timer = 2.1
	actor.velocity = Vector2(30, 0)
	assert(not officer._can_arrest_target(), "Moving suspect cannot be instantly arrested")
	actor.velocity = Vector2.ZERO
	actor.set_meta("police_exterior_position", Vector2.ZERO)
	assert(not officer._can_arrest_target(), "No arrest inside another interior")
	actor.remove_meta("police_exterior_position")
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(5, 80)
	shape.shape = rect
	wall.add_child(shape)
	wall.position = Vector2(-12, 0)
	scene.add_child(wall)
	await physics_frame
	assert(not officer._can_arrest_target(), "No arrest through walls")
	wall.queue_free()
	await physics_frame
	await physics_frame
	var car := Node2D.new()
	car.add_to_group("vehicle")
	scene.add_child(car)
	officer.target = car
	officer._arrest_player()
	assert(actor.arrests == 0, "A nearby car must never arrest a remote player")
	officer.target = actor
	actor.fire_cooldown = 0.2
	assert(not officer._can_arrest_target(), "Shooting blocks arrest even before the officer's next AI update")
	actor.fire_cooldown = 0.0
	assert(officer._can_arrest_target(), "Warned stationary suspect in reach may surrender")
	officer._arrest_player()
	assert(actor.arrests == 1)
	# Real cruiser/crew callback path: fleeing in a car recalls the officers,
	# they board at their own doors, and the same unit resumes pursuit.
	root.get_node("WantedManager").report_crime(15)
	var cruiser = root.get_node("EmergencyPool").get_vehicle("police")
	cruiser.set_physics_process(false)
	cruiser.position = Vector2(-100, 0)
	cruiser.target = actor
	cruiser.is_acting = true
	cruiser.officer_deployed = true
	cruiser.set_meta("police_player_pursuit", true)
	cruiser._deploy_officers_duo()
	var escape := EscapeCar.new()
	escape.add_to_group("vehicle")
	escape.position = Vector2(100, 0)
	scene.add_child(escape)
	root.get_node("WantedManager").report_visual_contact(cruiser)
	cruiser._physics_process(0.3)
	for crew in get_nodes_in_group("police_officer"):
		if crew.service_vehicle == cruiser:
			assert(not crew.returning_to_service_vehicle, "A stopped car does not recall the crew")
	escape.velocity = Vector2(120, 0)
	cruiser._physics_process(1.6)
	for crew in get_nodes_in_group("police_officer"):
		if crew.service_vehicle == cruiser:
			assert(crew.returning_to_service_vehicle)
			crew.global_position = cruiser.get_crew_door_point(crew.crew_side, crew.crew_longitudinal)
	await create_timer(0.7).timeout
	assert(cruiser.returned_officers == 2, "Both officers must board")
	cruiser._physics_process(0.1)
	assert(not cruiser.is_acting and not cruiser.is_returning_to_base, "Resume pursuit instead of returning to base")
	var npc := Suspect.new()
	npc.set_meta("ambient_crime",true)
	scene.add_child(npc)
	npc.position=officer.position+Vector2(15,0)
	officer.target=npc
	officer.arrest_warning_given=true
	officer.arrest_warning_elapsed=3.1
	officer.arrest_timer=2.1
	officer.response_aggression=0
	officer._arrest_player()
	assert(npc.arrests==1 and actor.arrests==1,"Ambient arrest affects the suspect, never Dante")
	root.get_node("WantedManager").dismiss_all_police()
	scene.queue_free()
	await process_frame
	print("POLICE_FAIR_ARREST PASS")
	quit()
