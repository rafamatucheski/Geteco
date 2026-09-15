extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen",&"harbor_arrival_call_complete",&"harbor_maciota_met",&"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 30: await process_frame
	while not current_scene.gameplay_ready: await process_frame
	var system: Node2D = current_scene.get_node("UrbanTransit")
	while not system.ready_for_service: await process_frame
	current_scene.get_node("CobraCampaign").set_process(false)
	system.clock.is_dynamic_time = false
	system.clock.time_of_day = 0.5
	system.clock._update_lighting()
	await create_timer(18).timeout
	for person in system.passengers:
		var hit := KinematicCollision2D.new()
		var blocked: bool = person.test_move(person.global_transform,person.global_position.direction_to(person.destination)*5,hit)
		print("COMMUTER ",person.name," stop=",person.stop.stop_id," state=",person.transit_state," local=",person.stop.to_local(person.global_position)," target=",person.stop.to_local(person.destination)," blocker=",hit.get_collider().get_path() if blocked else "none")
	quit()
