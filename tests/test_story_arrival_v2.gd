extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("STORY_V2 ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count := 4) -> void:
	for i in count: await physics_frame

func wait_for_boarding(intro: Node) -> void:
	# Boarding now walks around the actual hull and includes reaching, seating
	# and door closure. Wait for that behavior instead of the old 1.6s snap.
	var deadline := Time.get_ticks_msec()+12000
	while intro.transition_busy and Time.get_ticks_msec()<deadline: await physics_frame
	check(not intro.transition_busy,"boarding finishes within its bounded sequence")
func run() -> void:
	create_timer(145.0,true,false,true).timeout.connect(func() -> void:
		push_error("Story arrival test exceeded its deadline")
		quit(1))
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	campaign.set_campaign_flag(&"harbor_arrival_seen",true)
	root.get_node("SaveManager").clear_pending_save()
	root.get_node("SaveManager").set("_save_dir",OS.get_temp_dir().path_join("story_arrival_v2_test")+"/")
	var scene: Node2D = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var deadline := Time.get_ticks_msec()+60000
	while (not scene.gameplay_ready or not scene.world_build_ready) and Time.get_ticks_msec()<deadline: await process_frame
	await frames(10)
	var mission: Node = scene.campaign_controller
	var intro: Node = mission.story_arrival
	var player: CharacterBody2D = scene.get_node("Player")
	check(mission.phase == "police_visit","arrival starts at police, no call")
	check(not mission.accept_mission("primeiro_giro"),"board remains locked")
	var police_door: Node2D = scene.get_node("District/Police/Entrance")
	player.global_position = police_door.get_node("OutsideReturn").global_position
	await frames(4)
	police_door.request_interaction(player)
	await create_timer(.9).timeout
	player.global_position = intro.police.sergeant_npc.global_position+Vector2(0,60)
	await frames()
	var interacted: bool = mission.interact_with_objective()
	check(interacted,"police conversation interact")
	if not interacted:
		print("POLICE_INTERACTION position=",player.global_position," target=",intro.police.sergeant_npc.global_position," inside=",intro.police.contains_point(player.global_position)," controls=",player.is_control_disabled," visible=",player.visible)
		quit(1)
		return
	check(mission.phase == "story_dialogue","police dialogue opens")
	for i in 5: mission.advance_dialogue()
	check(mission.phase == "police_exit","police must be exited before call")
	check(campaign.has_campaign_flag(&"harbor_police_briefed"),"police checkpoint persisted")
	player.global_position = scene.get_node("District/Police/Entrance").global_position+Vector2(0,65)
	intro._returned(player,&"police")
	check(mission.phase == "arrival_wait","call starts only after exit")
	mission._process(3.0)
	check(mission.phase == "arrival_wait","pause for Dante reaction")
	mission._process(1.1)
	check(mission.phase == "phone","phone rings after four seconds")
	for i in 5: mission.advance_dialogue()
	check(mission.phase == "yard_meeting","call points to scrapyard")
	check(not mission.garage.jager_npc.visible,"no duplicate Maciota in garage")
	while not scene.get_node("RoadLighting").ready_for_audit: await process_frame
	player.global_position = intro.maciota.global_position+Vector2(0,30)
	await frames()
	check(mission.interact_with_objective(),"Maciota introduces himself")
	for i in 3: mission.advance_dialogue()
	await wait_for_boarding(intro)
	check(mission.phase == "city_tour","boarding starts passenger tour")
	check(not player.visible and player.is_control_disabled,"Dante is seated, not driving")
	check(intro.car.model.occupants[0].visible and intro.car.model.occupants[1].visible,"both occupants present")
	check(player.model_root.get_viewport() == player.viewport_3d and intro.maciota.model_root.get_viewport() == intro.maciota.viewport_3d,"boarding restores both production rigs to their own viewports")
	check(intro.tour_route.size()>20,"real lane route generated")
	var route_file := FileAccess.open("res://docs/measurements/story-arrival-route.json",FileAccess.WRITE)
	var coords: Array = []
	for p in intro.tour_route: coords.append([p.x,p.y])
	route_file.store_string(JSON.stringify(coords))
	route_file.close()
	# Check static clearance along the entire route with the actual car hull.
	var hits: Array = []
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = intro.car.shape.shape
	query.collision_mask = 1
	query.exclude = [intro.car.get_rid(), player.get_rid()]
	for i in range(1,intro.tour_route.size()):
		var at: Vector2 = intro.tour_route[i]
		var angle: float = (at-intro.tour_route[i-1]).angle()
		query.transform = Transform2D(angle,at)
		var obstacles := scene.get_world_2d().direct_space_state.intersect_shape(query,5)
		for hit in obstacles:
			if hits.size()<12: hits.append({"at":str(at),"node":str(hit.collider.get_path())})
	check(hits.is_empty(),"tour route static hull clearance: "+str(hits))
	# Block every passenger-side exit without touching the parked car. A
	# cancellation must wait, never place Dante in that solid or through the car.
	intro.car.set_physics_process(false)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var blocker := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(120,74)
	blocker.shape = rectangle
	wall.add_child(blocker)
	scene.add_child(wall)
	wall.global_position = intro.car.seat(1)+Vector2.from_angle(intro.car.heading+PI*.5)*30
	wall.rotation = intro.car.heading
	await frames(2)
	intro.cancel_ride()
	check(intro.riding and not player.visible and player.is_control_disabled,"blocked passenger exit keeps Dante seated safely")
	wall.queue_free()
	var exit_deadline := Time.get_ticks_msec()+1000
	while intro.riding and Time.get_ticks_msec()<exit_deadline: await process_frame
	check(not intro.riding and player.visible and not player.is_control_disabled,"pending cancellation completes once the exit becomes clear")
	intro.car.set_physics_process(true)
	# Abort/reboard restores physical player state without granting completion.
	intro.cancel_ride()
	check(player.visible and not player.is_control_disabled and player.collision_layer!=0,"cancel restores actor and controls")
	check(not campaign.has_campaign_flag(&"harbor_city_tour_complete"),"cancel does not complete tour")
	intro._board()
	await wait_for_boarding(intro)
	check(mission.phase == "city_tour","tour can resume after cancel")
	intro.car.set_meta("test_audit",true)
	# Drive in the real physics loop, with live traffic sharing the same clock.
	Engine.time_scale = 3.0
	deadline = Time.get_ticks_msec()+100000
	var next_drive_report := Time.get_ticks_msec()+10000
	while intro.car.driving and Time.get_ticks_msec()<deadline:
		await physics_frame
		if Time.get_ticks_msec() >= next_drive_report:
			print("STORY_DRIVE position=",intro.car.global_position," heading=",intro.car.heading," cursor=",intro.car.cursor," reason=",intro.car.pass_reason," obstacle=",intro.car.last_obstacle)
			next_drive_report += 10000
	Engine.time_scale = 1.0
	check(not intro.car.driving,"tour reaches garage physically: "+str(intro.car.global_position)+" blocker="+intro.car.last_obstacle)
	check(campaign.has_campaign_flag(&"harbor_city_tour_complete"),"tour completion persists")
	check(mission.phase == "meet_maciota" and player.visible,"garage conversation follows ride")
	check(not campaign.has_campaign_flag(&"harbor_delivery_complete"),"Monaliza not rewarded early")
	var saved: Dictionary = campaign.to_save_data()
	check(campaign.restore_from_save(saved),"campaign state round-trip")
	check(campaign.has_campaign_flag(&"harbor_city_tour_complete") and campaign.has_campaign_flag(&"harbor_police_briefed"),"arrival checkpoints survive reload")
	mission.start_or_resume()
	check(mission.phase == "meet_maciota","resuming completed tour does not replay police/call")
	var garage: Node2D = mission.garage
	var door: Node2D = mission.entrance
	player.global_position = door.get_node("OutsideReturn").global_position
	await frames(5)
	door.request_interaction(player)
	await create_timer(.9).timeout
	check(garage.contains_point(player.global_position),"real exterior door enters garage")
	player.global_position = garage.jager_npc.interact_area.global_position
	await frames(5)
	garage.jager_npc._open_dialogue()
	check(garage.jager_npc.conversation_keys[0] == "MACIOTA_V2_GARAGE_1","garage opens with offer of help for favors")
	for i in 10:
		if garage.jager_npc.is_talking: garage.jager_npc._advance_dialogue()
	check(mission.phase == "board" and garage.mission_board.interaction_enabled,"completed conversation unlocks existing first favor")
	check(campaign.has_campaign_flag(&"harbor_maciota_met"),"contact checkpoint persisted")
	mission.start_or_resume()
	check(mission.phase == "board","progressed save keeps the board")
	print("STORY_V2_RESULT ","PASS" if failures.is_empty() else failures)
	scene.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)
