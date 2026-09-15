extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("POLICE_EXIT ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count := 4) -> void:
	for i in count: await physics_frame
func run() -> void:
	create_timer(145.0,true,false,true).timeout.connect(func() -> void:
		push_error("Story arrival test exceeded its deadline")
		quit(1))
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	campaign.set_campaign_flag(&"harbor_arrival_seen",true)
	root.get_node("SaveManager").clear_pending_save()
	root.get_node("SaveManager").set("_save_dir",OS.get_temp_dir().path_join("story_police_exit_test")+"/")
	var scene: Node2D = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var deadline := Time.get_ticks_msec()+60000
	while not scene.gameplay_ready and Time.get_ticks_msec()<deadline: await process_frame
	await frames(10)
	var mission: Node = scene.campaign_controller
	var intro: Node = mission.story_arrival
	var player: CharacterBody2D = scene.get_node("Player")
	check(mission.phase == "police_visit","arrival starts at police, no call")
	check(not mission.accept_mission("primeiro_giro"),"board remains locked")
	var entrance: Node2D = scene.get_node("District/Police/Entrance")
	player.global_position = entrance.get_node("OutsideReturn").global_position
	await frames(5)
	check(entrance.request_interaction(player), "real police entrance accepts interaction")
	await create_timer(.9).timeout
	check(intro.police.contains_point(player.global_position), "real door enters police station")
	player.global_position = intro.police.sergeant_npc.global_position+Vector2(0,60)
	await frames()
	check(mission.interact_with_objective(),"police conversation interact")
	check(mission.phase == "story_dialogue","police dialogue opens")
	for i in 5: mission.advance_dialogue()
	check(mission.phase == "police_exit","police must be exited before call")
	check(campaign.has_campaign_flag(&"harbor_police_briefed"),"police checkpoint persisted")
	# Dialogue is advanced instantly here; allow the real entry cooldown to finish.
	await create_timer(scene.get_node("Interiors").transition_cooldown).timeout
	var returned_ids: Array[StringName] = []
	scene.get_node("Interiors").actor_returned_to_exterior.connect(func(_actor: Node2D, id: StringName) -> void: returned_ids.append(id))
	player.global_position = intro.police.exit_door.global_position
	await frames(5)
	check(intro.police.exit_door.request_interaction(player), "real exit door accepts interaction")
	await create_timer(.9).timeout
	check(not intro.police.contains_point(player.global_position), "player returned to city")
	check(returned_ids == [&"police"], "exit signal identifies police interior")
	check(mission.target == Vector2.ZERO, "exit clears distant interior target")
	check(not mission._objective_label.text.contains(" m"), "waiting objective has no bogus distance")
	check(mission.phase == "arrival_wait", "real exit advances mission without reload")
	mission.start_or_resume()
	check(mission.phase == "arrival_wait", "briefed save outside resumes at phone wait")
	mission._phone_wait = 0
	check(mission.phase == "arrival_wait","call starts only after exit")
	mission._process(3.0)
	check(mission.phase == "arrival_wait","pause for Dante reaction")
	mission._process(1.1)
	check(mission.phase == "phone","phone rings after four seconds")
	print("POLICE_EXIT_RESULT ", "PASS" if failures.is_empty() else str(failures))
	scene.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)
