extends SceneTree
var failures:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	if not value: failures+=1;push_error(label)
func run()->void:
	root.get_node("CampaignState").reset_campaign()
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen",true)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_phone_answered",true)
	root.get_node("SaveManager").clear_pending_save()
	var world=load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	for frame in 12:await process_frame
	var service=get_first_node_in_group("regional_coach_service")
	while service==null or service.access_lane==null:
		await process_frame
		service=get_first_node_in_group("regional_coach_service")
	service.set_process(false)
	service.coach.set_process(false)
	service._plan_city(service.outbound_lane,service.outbound_lane.curve.get_baked_length())
	var lane:Path2D
	for candidate in get_nodes_in_group("unified_lane_connector"):
		if String(candidate.get_meta("traffic_connection_id","")).begins_with("22:RoadLayout/island_esplanade/reverse_01>"):lane=candidate
	var coach=service.coach
	var follow:PathFollow2D=coach.get_parent()
	follow.reparent(lane,false)
	follow.progress=124.63200378418
	coach.position=Vector2.ZERO
	coach.rotation=0.0
	var actor:=CharacterBody2D.new()
	actor.collision_layer=4
	actor.collision_mask=0
	actor.add_to_group("pedestrian")
	var shape:=CollisionShape2D.new()
	shape.shape=CircleShape2D.new()
	shape.shape.radius=11.0
	actor.add_child(shape)
	world.add_child(actor)
	actor.global_position=Vector2(4810,-1182)
	await physics_frame
	await physics_frame
	check(not coach._lane_pedestrian_blocks(follow,actor,false),"Pedestrian on the published sidewalk stays outside the real turning corridor")
	actor.global_position=Vector2(4780,-1130)
	check(coach._lane_pedestrian_blocks(follow,actor,false),"Pedestrian in the outgoing road still stops the coach")
	actor.global_position=lane.to_global(lane.curve.sample_baked(follow.progress+10,true))
	check(coach._lane_pedestrian_blocks(follow,actor,false),"Pedestrian immediately inside the turn still stops the coach")
	actor.global_position=Vector2(4810,-1182)
	actor.velocity=Vector2(0,90)
	check(coach._lane_pedestrian_blocks(follow,actor,false),"Pedestrian walking toward the road is anticipated")
	actor.velocity=Vector2.ZERO
	for fixture in [
		["HarborTraffic_53","6:RoadLayout/foundry_avenue/forward_01>",69.506134,Vector2(2286.582,477.1404)],
		["HarborTraffic_32","12:RoadLayout/warehouse_way/forward_01>",93.402344,Vector2(2107.895,1335.259)]
	]:
		var ambient: Node2D
		for candidate in get_nodes_in_group("vehicle"):
			if String(candidate.name)==fixture[0]:ambient=candidate
		var turn:Path2D
		for candidate in get_nodes_in_group("unified_lane_connector"):
			if String(candidate.get_meta("traffic_connection_id","")).begins_with(fixture[1]):turn=candidate
		check(ambient!=null and turn!=null,"Production ambient car and authored turn are available")
		if ambient==null or turn==null:continue
		ambient.set_process(false)
		ambient.set_physics_process(false)
		var ambient_follow:PathFollow2D=ambient.get_parent()
		ambient_follow.reparent(turn,false)
		ambient_follow.progress=fixture[2]
		ambient.position=Vector2.ZERO
		ambient.rotation=0.0
		actor.global_position=fixture[3]
		check(not ambient._lane_pedestrian_blocks(ambient_follow,actor,false),"Ambient car ignores sidewalk resident outside turn "+fixture[1])
		turn.set_meta("curved_pedestrian_corridor",false)
		check(ambient._lane_pedestrian_blocks(ambient_follow,actor,false),"Non-opt-in maps retain the original pedestrian rule")
		turn.set_meta("curved_pedestrian_corridor",true)
		actor.global_position=turn.to_global(turn.curve.sample_baked(ambient_follow.progress+10,true))
		check(ambient._lane_pedestrian_blocks(ambient_follow,actor,false),"Ambient car still yields to a pedestrian inside its turn")
	actor.global_position=coach.to_global(Vector2(100,-17))
	actor.add_to_group("player")
	await physics_frame
	await physics_frame
	for ray_name in ["FrontRay","FrontRayL","FrontRayR"]:coach.get_node(ray_name).force_raycast_update()
	check(coach._get_lane_obstruction(follow).hard,"Player remains an unconditional sensor blocker")
	print("REGIONAL_PEDESTRIAN_TURN failures=",failures)
	world.queue_free()
	for frame in 4:await process_frame
	quit(0 if failures==0 else 1)
