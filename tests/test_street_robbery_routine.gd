extends SceneTree

class TestWorld extends Node2D:
	var gameplay_ready := true

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var state = root.get_node("CampaignState")
	state.set_campaign_flag(&"harbor_arrival_seen",true)
	state.set_campaign_flag(&"harbor_call_complete",true)
	var isolated := OS.get_cmdline_user_args().has("--isolated")
	var world = TestWorld.new() if isolated else load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	if isolated:
		var director = load("res://world/harbor/events/HarborWorldEvents.gd").new()
		director.name = "WorldEvents"
		world.add_child(director)
	while not world.gameplay_ready: await process_frame
	var events = world.get_node("WorldEvents")
	events.set_process(false)
	var wanted = root.get_node("WantedManager")
	wanted.set_process(false)
	var starting_stars: int = wanted.current_stars
	assert(events.start_incident("robbery"))
	var incident = events.street_incident
	var suspect_start: Vector2 = incident.suspect.global_position
	var officer_start: Vector2 = incident.officer.global_position
	assert(not incident.reported and incident.officer.target==null)
	assert(not events.start_incident("fire"),"One bounded city incident")
	assert(incident.site.hotspot and incident.site.point.x>7000,"Actual Cobra neighborhood")
	assert(incident.suspect.model.bag.get_child_count()>=6,"Detailed 3D satchel")
	assert(incident.victim.model.phone.get_child_count()==2,"Victim uses a real 3D phone")
	var phases: Array[String] = []
	Engine.time_scale = 4
	for frame in 1900:
		await physics_frame
		incident.tick(4.0/60.0)
		if not phases.has(incident.phase):
			phases.append(incident.phase)
			print("STREET_PHASE ",incident.phase," age=",incident.age," suspect=",incident.suspect.global_position," officer=",incident.officer.global_position)
		if incident.phase=="calling":
			assert(not incident.reported and incident.officer.target==null,"Phone call delays response")
			assert(incident.victim.model.gesture=="call")
		if incident.phase=="pursuit":
			assert(incident.officer.target==incident.suspect,"Officer targets the NPC, never player")
		assert(wanted.current_stars==starting_stars,"Ambient crime does not incriminate player")
		if incident.phase=="leaving": break
	assert(phases.has("confrontation") and phases.has("handover") and phases.has("calling") and phases.has("pursuit"),"Real approach, theft, report, pursuit")
	assert(incident.officer.global_position.distance_to(officer_start)>250,"Officer actually walks to the incident")
	assert(incident.suspect.global_position.distance_to(suspect_start)>130,"Suspect physically flees")
	assert(incident.outcome=="arrested","Officer warns and completes a real sight-checked arrest")
	assert(incident.suspect.arrested)
	assert(not incident.victim.model.carrying_bag and incident.suspect.model.carrying_bag,"Seized property leaves with suspect instead of teleporting")
	incident.tick(3.1)
	assert(incident.officer.target==null and incident.officer.walking_home,"Patrol leaves without acquiring player")
	events.end_incident()
	await physics_frame
	assert(events.robbery_cooldown>=180,"Cooldown survives completion")
	# Busy/unsafe local state prevents an automatic encounter near the camera.
	assert(events.start_street_robbery(load("res://world/harbor/events/HarborStreetRobbery.gd").SITES[2]))
	assert(events.calm_area_cooldown>=480,"Downtown gets substantially longer quiet periods")
	incident = events.street_incident
	incident.officer.queue_free()
	await physics_frame
	incident.tick(.1)
	incident.tick(3.1)
	assert(incident.phase=="leaving" and incident.outcome=="interrupted","Police dismissal safely ends local event")
	events.end_incident()
	Engine.time_scale = 1
	print("STREET_ROBBERY_ROUTINE PASS")
	world.queue_free()
	await process_frame
	quit()
