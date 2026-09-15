extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): printerr("POLICE_PURSUIT_SAFETY TIMEOUT"); quit(2))
	var fixture := Node2D.new()
	root.add_child(fixture)
	current_scene = fixture
	var actor := CharacterBody2D.new()
	actor.add_to_group("player")
	fixture.add_child(actor)
	var wanted = root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.reset_crime()
	await physics_frame
	assert(wanted._find_lane_spawn(actor).is_empty(), "No roads must mean no airborne fallback spawn")
	var lane := Path2D.new()
	lane.curve = Curve2D.new()
	lane.curve.add_point(Vector2(-1600, 0))
	lane.curve.add_point(Vector2(1600, 0))
	lane.add_to_group("unified_traffic_lane")
	fixture.add_child(lane)
	await physics_frame
	var point: Dictionary = wanted._find_lane_spawn(actor)
	assert(not point.is_empty() and absf(point.position.y) < 0.1, "Fallback must lie on an authored lane")
	wanted.report_crime(15)
	wanted._dispatch_police()
	await physics_frame
	var police: Node2D
	for unit in get_nodes_in_group("emergency_vehicle"):
		if unit.visible and unit.type == 0: police = unit
	assert(police != null and absf(police.global_position.y) < 1.0)
	assert(police.siren_audio.playing, "Responding cruiser has siren")
	actor.global_position = Vector2(0, 100)
	police.global_position = Vector2(-100, 100)
	assert(wanted.report_visual_contact(police), "Officer witnesses the suspect before entering")
	actor.set_meta("police_exterior_position", Vector2(0, 100))
	actor.global_position = Vector2(20000, 20000)
	wanted._process(1.1)
	await physics_frame
	await physics_frame
	assert(police.target.global_position == Vector2(0, 100), "Interior pursuit keeps exterior position")
	assert(not police.siren_audio.playing, "Stationary search does not leave siren blaring")
	actor.remove_meta("police_exterior_position")
	actor.global_position = Vector2(40, 0)
	assert(wanted.report_visual_contact(police), "Nearby police visually reacquire the suspect outside")
	await physics_frame
	await physics_frame
	assert(police.target == actor, "Leaving interior reacquires real actor")
	wanted.reset_crime()
	await physics_frame
	await physics_frame
	assert(not police.siren_audio.playing, "Zero stars silences the pursuit immediately")
	# Moving the observer nearby can deploy its crew. They must physically
	# reboard before returning, instead of vanishing in the next two frames.
	var recall_deadline := Time.get_ticks_msec() + 15000
	while police.visible and not police.is_returning_to_base and Time.get_ticks_msec() < recall_deadline:
		await physics_frame
	assert(police.is_returning_to_base or not police.visible, "Zero stars recalls the crew and ends vehicle pursuit")
	wanted.dismiss_all_police()
	fixture.queue_free()
	await process_frame
	print("POLICE_PURSUIT_SAFETY|PASS")
	quit()
