extends SceneTree
var label := "baseline"
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func run() -> void:
	create_timer(150).timeout.connect(func(): quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("label="): label=arg.trim_prefix("label=")
	root.get_node("SaveManager").clear_pending_save()
	var state=root.get_node("CampaignState")
	for flag in ["harbor_arrival_seen","harbor_arrival_call_complete","harbor_maciota_met","harbor_delivery_complete"]: state.set_campaign_flag(StringName(flag),true)
	seed(912)
	var world=load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	while not world.gameplay_ready: await process_frame
	var manager=world.get_node("Interiors")
	var room=manager.clinic_interior
	var player=world.get_node("Player")
	var door=world.get_node("District/Clinic/Entrance")
	var car=world.get_node("PlayerCar")
	var car_id=car.get_instance_id()
	var car_position=car.global_position
	var money=player.money
	var original_scale=player.sprite_3d_display.scale
	player.active_weapon_id="fists"
	player.health=35
	player.global_position=door.get_node("OutsideReturn").global_position
	for i in 45: await physics_frame
	check(door.request_interaction(player),"Public door accepts entry")
	await create_timer(1.2).timeout
	check(room.contains_point(player.global_position),"Door enters hospital")
	for i in 90: await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/hospital-interior-0912/"+label+".png")
		if not OS.get_cmdline_user_args().has("skip_measure"):
			var samples: Array[float]=[]
			var start=Time.get_ticks_usec()
			var previous=start
			while Time.get_ticks_usec()-start<30000000:
				await process_frame
				var now=Time.get_ticks_usec()
				samples.append(float(now-previous)/1000.0)
				previous=now
			var elapsed=float(Time.get_ticks_usec()-start)/1000000.0
			samples.sort()
			var result={"fps":samples.size()/elapsed,"p50":samples[int(samples.size()*.5)],"p95":samples[int(samples.size()*.95)],"p99":samples[int(samples.size()*.99)],"max":samples[-1],"over33":samples.filter(func(v):return v>33.3).size(),"over66":samples.filter(func(v):return v>66.7).size(),"frames":samples.size(),"seconds":elapsed,"gpu":RenderingServer.get_video_adapter_name()}
			FileAccess.open("D:/geteco/artifacts/hospital-interior-0912/"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
			print(result)
	if label!="baseline":
		var start_walk=player.global_position
		Input.action_press("move_down")
		for i in 25: await physics_frame
		Input.action_release("move_down")
		check(player.global_position.distance_to(start_walk)>20,"Native movement through entrance aisle")
		player.global_position=room.health_pickup.global_position
		for i in 6: await physics_frame
		check(player.health==player.max_health,"Floating pickup restores health through overlap")
		check(room.health_pickup._is_collected,"Pickup enters cooldown")
	player.global_position=room.exit_door.global_position+Vector2(0,35)
	for i in 30: await physics_frame
	check(room.exit_door.request_interaction(player),"Exit door accepts departure")
	await create_timer(1.2).timeout
	check(player.global_position.distance_to(door.get_node("OutsideReturn").global_position)<5,"Exit returns to public door")
	check(car.get_instance_id()==car_id and car.global_position.distance_to(car_position)<2,"City vehicle and location preserved")
	check(player.money==money,"Money preserved")
	check(player.sprite_3d_display.scale.is_equal_approx(original_scale),"Exterior player scale restored")
	check(not player.has_meta("harbor_interior"),"Exterior mode restored")
	if label!="baseline":
		await create_timer(.5).timeout
		check(door.request_interaction(player),"Public door allows repeat visit")
		await create_timer(1.2).timeout
		check(room.contains_point(player.global_position),"Repeat visit enters same hospital")
		check(room.health_pickup._is_collected,"Leaving and returning does not reset health cooldown")
		player.global_position=room.exit_door.global_position+Vector2(0,35)
		for i in 30: await physics_frame
		check(room.exit_door.request_interaction(player),"Repeat exit remains usable")
		await create_timer(1.2).timeout
		check(not player.has_meta("harbor_interior"),"Second visit restores exterior state")
	print("HOSPITAL_RESULT ",failures)
	quit(0 if failures.is_empty() else 1)
