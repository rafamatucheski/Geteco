extends SceneTree
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->void:
	print("PASS " if value else "FAIL ",message)
	if not value:failures.append(message)
func place(actor:Node2D,lane:Path2D,offset:float)->void:
	var follow:PathFollow2D=actor.get_parent()
	follow.reparent(lane,false)
	follow.loop=false
	follow.progress=offset
	follow.remove_meta("traffic_planned_connection_id")
	follow.remove_meta("traffic_planned_junction_index")
	actor.position=Vector2.ZERO
	actor.rotation=0
	actor._lane_motion_speed=0
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
	while service.access_lane==null:await process_frame
	var coach=service.coach
	var local_bus:Node2D
	var car:Node2D
	for candidate in get_nodes_in_group("vehicle"):
		if candidate.name=="HarborLocalBus":local_bus=candidate
		if candidate.name=="HarborTraffic_12":car=candidate
	var foundry:Path2D
	var union:Path2D
	var connector:Path2D
	for lane in get_nodes_in_group("unified_traffic_lane"):
		var id=String(lane.get_meta("traffic_lane_id",""))
		if id=="RoadLayout/foundry_avenue/reverse_01":foundry=lane
		if id=="RoadLayout/union_avenue/forward_01":union=lane
	for lane in get_nodes_in_group("unified_lane_connector"):
		if String(lane.get_meta("traffic_connection_id",""))=="5:RoadLayout/foundry_avenue/reverse_01>RoadLayout/union_avenue/forward_01":connector=lane
	check(car!=null and local_bus!=null and connector!=null,"Original city actors and canonical connector5 exist")
	if not failures.is_empty():quit(1);return
	var authority=world.get_node("Life").traffic_controller
	# Let a pre-existing ambient reservation finish before arranging this
	# diagnostic. Never steal its reservation or delete its vehicle.
	var reservation_wait=Time.get_ticks_msec()
	while int(authority._states[5].reservation_owner)!=0 and Time.get_ticks_msec()-reservation_wait<120000:
		await process_frame
	check(int(authority._states[5].reservation_owner)==0,"Existing ambient reservation clears naturally before the fixture")
	if not failures.is_empty():quit(1);return
	for actor in [coach,local_bus,car]:authority.release_vehicle(actor.get_instance_id())
	place(coach,foundry,4629.1181640625)
	# Begin just before the recorded contact, so fixture placement cannot
	# embed two physical hulls before the first real movement step.
	place(local_bus,connector,8.0)
	place(car,union,93.9203338623047)
	for bus in [coach,local_bus]:
		bus.dwelling=false
		bus.doors=0
	coach.stop_lane=service.harbor_lane
	coach.stop_offset=service.harbor_offset
	coach.stop_armed=true
	service.state="returning"
	service._plan_city(service.harbor_lane,service.harbor_offset)
	authority._states[5].phase_index=0
	authority._states[5].stage=authority.JunctionStage.GREEN
	authority._synchronize_crossing_consumers()
	check(authority.try_reserve_junction(5,local_bus.get_instance_id(),3,"RoadLayout/foundry_avenue/reverse_01",local_bus),"Local bus holds the real junction5 reservation")
	authority.notify_vehicle_entered(5,local_bus.get_instance_id())
	authority._set_stage(5,authority.JunctionStage.ALL_RED)
	Engine.physics_ticks_per_second=480
	Engine.max_physics_steps_per_frame=16
	Engine.time_scale=8
	for frame in 8:await physics_frame
	print("REAL5_INITIAL car=",car.global_position," zone=",car._traffic_control_zone_motion(union,car.get_parent())," owner=",authority._states[5].reservation_owner)
	for crossing in get_nodes_in_group("road_crossing_area"):
		if String(crossing.crossing_id).contains("junction_005") and String(crossing.road_id).contains("union"):
			print("REAL5_CROSSING data=",crossing.get_crossing_data()," property=",crossing.road_index," meta=",crossing.get_meta("road_index",-1)," can_clear=",authority.can_clear_crossing(car,crossing.junction_id,crossing)," shape=",car.get_node("Collision").shape)
			for ref in crossing._pedestrians_inside.values():
				var npc=ref.get_ref()
				if npc!=null:print("REAL5_CROSSING_NPC=",npc.get_path()," position=",npc.global_position," can=",npc.can_process())
	var begin=Time.get_ticks_msec()
	var trace=begin
	var cleared_car=false
	var cleared_bus=false
	var cleared_coach=false
	while Time.get_ticks_msec()-begin<120000 and not(cleared_car and cleared_bus and cleared_coach):
		await process_frame
		if Time.get_ticks_msec()-trace>5000:
			trace=Time.get_ticks_msec()
			print("REAL5_PROGRESS car=",car.global_position," bus=",local_bus.global_position," coach=",coach.global_position," car_zone=",car._traffic_control_zone_motion(car.get_parent().get_parent(),car.get_parent()))
		cleared_car=cleared_car or car.global_position.y>610
		cleared_bus=cleared_bus or(local_bus.get_parent().get_parent()==union and local_bus.global_position.y>610)
		cleared_coach=cleared_coach or(coach.get_parent().get_parent()==union and coach.global_position.y>610)
	check(cleared_car,"The existing exit-lane car physically clears the far crossing")
	check(cleared_bus,"The original local bus physically clears connector5 behind the car")
	check(cleared_coach,"The regional coach follows through junction5 without removing traffic")
	print("REAL5_RESULT failures=",failures," car=",car.global_position," bus=",local_bus.global_position," coach=",coach.global_position)
	Engine.time_scale=1
	world.queue_free()
	for frame in 4:await process_frame
	quit(0 if failures.is_empty() else 1)
