extends SceneTree
func _initialize() -> void: run.call_deferred()

func run() -> void:
	Engine.max_fps = 0
	seed(914)
	root.get_node("SaveManager").clear_pending_save()
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		state.set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 120: await physics_frame
	paused = false
	var world := current_scene
	world.get_node("Player").global_position = Vector2(1700,1800)
	world.weather.time_of_day = .45
	world.weather.set_weather(0)
	world.weather.is_dynamic_time = false
	var victim := preload("res://AnimatedPedestrian3D.gd").new()
	victim.name = "CoronerHarborVictim"
	victim.position = Vector2(1800,1760)
	world.add_child(victim)
	await physics_frame
	var floor_query := PhysicsShapeQueryParameters2D.new()
	floor_query.shape = CircleShape2D.new()
	floor_query.shape.radius = 6
	floor_query.transform = Transform2D(0,victim.global_position)
	floor_query.collision_mask = 3
	floor_query.exclude = [victim.get_rid()]
	var spawn_hits := victim.get_world_2d().direct_space_state.intersect_shape(floor_query,8)
	for hit in spawn_hits: print("VICTIM_SPAWN_BLOCKED ",hit.collider.get_path())
	if not spawn_hits.is_empty(): quit(3); return
	victim._die()
	root.get_node("NPCMedicalCare").witness_called(victim)
	var care := root.get_node("CoronerCare")
	var key: String = care.identity(victim)
	var completed := false
	for frame in 18000:
		await physics_frame
		if frame%600==0:
			var units := []
			for unit in get_nodes_in_group("emergency_vehicle"):
				if unit.type==3 and unit.visible:
					var crew_states := []
					for crew in unit._response_crew:
						if is_instance_valid(crew):
							var ray := PhysicsRayQueryParameters2D.create(crew.global_position,victim.global_position,3,[crew.get_rid()])
							var obstruction: Dictionary = crew.get_world_2d().direct_space_state.intersect_ray(ray)
							crew_states.append({"position":str(crew.global_position),"state":crew.state,"route_index":crew._access_index,"route":crew._access_route,"stuck":crew.stuck_timer,"physics":crew.is_physics_processing(),"sight":str(obstruction.collider.get_path()) if not obstruction.is_empty() else "clear","path":crew.movement_navigation.path})
					units.append({"position":str(unit.global_position),"stage":unit._coroner_stage,"acting":unit.is_acting,
						"departure":unit.get_meta("depot_departure_pending",false),"return":unit.is_returning_to_base,
						"parking_rejections":unit._ambulance_approach.rejections,"parking_wait":unit._ambulance_approach._access_wait,
						"speed":unit.current_speed,"walk_pending":unit._ambulance_approach._walk_pending,"crew":crew_states})
			print("HARBOR_CORONER ",frame," ",care.records().get(key)," units=",units)
		if care.records().get(key,{}).get("phase")=="buried":
			completed = true
			break
	print("CORONER_HARBOR ","PASS" if completed else "FAIL")
	world.queue_free()
	for i in 3: await process_frame
	quit(0 if completed else 1)
