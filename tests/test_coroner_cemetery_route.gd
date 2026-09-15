extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	Engine.max_fps = 0
	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	for flag in [&"harbor_arrival_seen",&"harbor_arrival_call_complete",&"harbor_maciota_met",&"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 120: await physics_frame
	paused = false
	var unit := preload("res://EmergencyVehicle.tscn").instantiate()
	unit.type = 3
	unit.position = Vector2(1880,1962)
	unit.rotation = PI
	current_scene.add_child(unit)
	unit.activate()
	if OS.get_cmdline_user_args().has("yard"):
		unit.position = Vector2(1985,1455)
		unit.rotation = 0
		unit.set_meta("depot_departure_pending",true)
		unit.set_meta("depot_departure_waypoints",preload("res://world/harbor/HarborLocalStreets.gd").medical_departure(unit.position))
	unit.is_heading_to_cemetery = true
	unit._coroner_stage = "cemetery"
	unit._cemetery_target_position = get_first_node_in_group("cemetery").get_coroner_stop_position()
	for frame in 9000:
		await physics_frame
		if frame%300 == 0:
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = unit.get_node("CollisionShape2D").shape
			query.transform = unit.get_node("CollisionShape2D").global_transform
			query.motion = unit.transform.x*35
			query.collision_mask = unit.EMERGENCY_COLLISION_MASK
			query.exclude = [unit.get_rid()]
			query.margin = 2.0
			var hits := []
			for hit in unit.get_world_2d().direct_space_state.intersect_shape(query,8): hits.append(str(hit.collider.get_path()))
			print("ROUTE ",frame," pos=",unit.position," rot=",unit.rotation," waypoint=",unit._get_road_guidance_target(unit._cemetery_target_position)," clearance=",unit._forward_clearance()," hits=",hits," rest=",unit.get_world_2d().direct_space_state.get_rest_info(query))
		if unit._coroner_stage == "waiting_plot":
			print("CORONER_ROUTE PASS reached cemetery without cargo")
			quit(0)
			return
	print("CORONER_ROUTE FAIL")
	quit(1)
