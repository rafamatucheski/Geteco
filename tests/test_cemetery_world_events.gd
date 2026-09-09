extends SceneTree

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var state = root.get_node("CampaignState")
	state.set_campaign_flag(&"harbor_arrival_seen",true)
	state.set_campaign_flag(&"harbor_call_complete",true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	while not world.gameplay_ready: await process_frame
	var events=world.get_node("WorldEvents")
	events.set_process(false)
	var cemetery=world.get_node("Cemetery")
	assert(cemetery.global_position.x<0)
	var query:=PhysicsPointQueryParameters2D.new()
	query.collision_mask=1
	for point in [Vector2(-110,1250),Vector2(-110,2200),cemetery.get_gate_position()]:
		query.position=point
		assert(world.get_world_2d().direct_space_state.intersect_point(query).is_empty(),"New west roads and cemetery gate must be traversable")
	assert(events.start_funeral())
	assert(not events.start_funeral(),"Only one ceremony at a time")
	assert(events.guests.size()==5)
	Engine.time_scale=8
	var guard=0
	while events.funeral_phase!="ceremony" and guard<800:
		await physics_frame
		events._tick_funeral(8.0/60.0)
		guard+=1
	assert(events.funeral_phase=="ceremony")
	for guest in events.guests:
		assert(guest.finished,"Guests really walk to their ceremony positions")
	events._tick_funeral(26)
	assert(events.funeral_phase=="leaving")
	guard=0
	while events.funeral_phase!="idle" and guard<800:
		await physics_frame
		events._tick_funeral(8.0/60.0)
		guard+=1
	assert(events.funeral_phase=="idle" and events.guests.is_empty())
	Engine.time_scale=1
	var wanted=root.get_node("WantedManager")
	var stars=wanted.current_stars
	assert(events.start_incident("robbery"),"NPC robbery dispatches actual pooled cruiser")
	assert(events.unit.target==events.incident)
	assert(wanted.current_stars==stars,"NPC crime must not incriminate player")
	assert(not events.start_incident("fire"),"Incident budget is bounded")
	events.end_incident()
	await physics_frame
	assert(events.start_incident("fire"),"Fire dispatches actual fire engine")
	events.incident.extinguish_fire()
	events._process(.1)
	assert(not is_instance_valid(events.incident),"Extinguished fire resolves event")
	print("CEMETERY_WORLD_EVENTS PASS")
	world.queue_free()
	await process_frame
	quit()
