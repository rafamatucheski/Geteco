extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func run() -> void:
	seed(510)
	create_timer(240,true,false,true).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	await process_frame
	while current_scene == null: await process_frame
	while not current_scene.gameplay_ready: await process_frame
	current_scene.get_node("CobraCampaign").set_process(false)
	var player: CharacterBody2D = get_first_node_in_group("player")
	var system: Node2D = current_scene.get_node("UrbanTransit")
	while not system.ready_for_service: await process_frame
	var operations: Node2D = get_first_node_in_group("harbor_terminal_operations")
	check(operations != null,"terminal operations present")
	var buses: Array = system.buses.duplicate()
	buses.append_array(get_nodes_in_group("harbor_transit_bus"))
	buses.append_array(get_nodes_in_group("regional_coach"))
	for service in operations.fleet: buses.append(service.coach)
	check(buses.size() >= 7,"urban, local and four terminal coaches covered")
	for vehicle in get_nodes_in_group("vehicle"):
		check(vehicle.has_method("enter_vehicle"),"motor vehicle exposes boarding: "+str(vehicle.name))
	if OS.get_cmdline_user_args().has("--emergency-only"):
		buses.clear()
		for kind in 5:
			var emergency := preload("res://emergency/EmergencyVehicle.tscn").instantiate() as CharacterBody2D
			emergency.type = mini(kind,3)
			if kind == 4:
				emergency.type = 0
				emergency.police_variant = "motorcycle"
			current_scene.add_child(emergency)
			emergency.activate()
			emergency.set_physics_process(false)
			emergency.global_position = Vector2(4500,-950) + Vector2(0,kind*200)
			buses.append(emergency)
	for original: CharacterBody2D in buses:
		player.is_control_disabled = false
		player.show()
		player.global_position = original.global_position
		player.set_physics_process(false)
		player.try_enter_vehicle()
		var driven: CharacterBody2D
		for vehicle in get_nodes_in_group("vehicle"):
			if vehicle.get("is_driven_by_player") == true: driven = vehicle
		check(driven != null,"theft grants control: "+str(original.name))
		if driven != null: check(driven == original or original.is_queued_for_deletion(),"interaction selects the approached coach")
		if driven == null: continue
		await create_timer(2.8).timeout
		check(driven._driver == player and not player.is_physics_processing(),"boarding transfers player and camera")
		check(driven._detached_from_lane,"taken bus leaves automatic route")
		if driven.is_in_group("urban_bus"):
			check(not system.buses.has(driven) and not system._exchanges.has(driven),"stolen articulated bus removed from timetable")
		else:
			var start := driven.global_position
			Input.action_press("move_down" if driven.is_in_group("harbor_terminal_coach") else "move_up")
			await create_timer(.7).timeout
			Input.action_release("move_down")
			Input.action_release("move_up")
			check(driven.global_position.distance_to(start)>.1,"coach responds to driving input")
		driven.velocity = Vector2.ZERO
		driven.exit_vehicle()
		# Ônibus longo usa o perfil de caminhão (2,15 s + fechamento da porta);
		# um prazo fixo de 2,8 s cortava a saída ainda em andamento.
		var exit_deadline := Time.get_ticks_msec() + 6000
		while driven.is_driven_by_player and Time.get_ticks_msec() < exit_deadline:
			await process_frame
		await create_timer(0.3).timeout
		check(not driven.is_driven_by_player and player.is_physics_processing(),"exit restores walking")
		var parked := driven.global_position
		await create_timer(.3).timeout
		check(driven.global_position.distance_to(parked)<1,"exited bus stays parked")
		player.is_control_disabled = false
		player.global_position = driven.global_position + Vector2(0,40)
		driven.enter_vehicle(player)
		check(driven.is_driven_by_player,"taken bus can be entered again")
		driven.force_exit_vehicle()
		await create_timer(.1).timeout
		check(player.is_physics_processing(),"forced exit cancels boarding safely")
	print("BUS_THEFT failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
