extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/urban-ride-0911/"+label+".png")
func run() -> void:
	seed(510)
	create_timer(240,true,false,true).timeout.connect(func(): print("FAIL timeout"); quit(2))
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
	system._update_schedule()
	var bus: CharacterBody2D = system.buses[0]
	var ride: CanvasLayer = system.player_ride
	var player: CharacterBody2D = current_scene.get_node("Player")
	player.is_control_disabled = false
	player.is_in_dialogue = false
	player.global_position = system.stops[0].boarding_position()
	player.camera.make_current()
	player.camera.reset_smoothing()
	# Keep ambient traffic out of the deterministic journey, preserving signals and collisions.
	current_scene.get_node("Life")._traffic_target = 0
	for car in get_nodes_in_group("ambient_traffic"):
		if not car.is_in_group("urban_bus") and not car.is_in_group("urban_bus_section") and not car.is_in_group("harbor_transit_bus"): car.queue_free()
	await create_timer(0.8).timeout
	for weather in [0,1,2,0]:
		system.clock.set_weather(weather)
		system.clock._update_lighting()
		await process_frame
		check(bus.is_night_or_storm == (weather>0),"bus weather lights state %d"%weather)
		check(bus.headlight.visible == (weather>0) and bus.second_headlight.visible == (weather>0),"both front beams state %d"%weather)
		for part in bus.sections:
			check(not part.headlight.visible,"trailer does not project a forward beam")
			check(part.body_model.materials.taillight.emission_enabled == (weather>0),"trailer running lamps state %d"%weather)
	system.clock.set_weather(1)
	system.clock._update_lighting()
	await capture("01-rain-boarding")
	var layer_before := player.collision_layer
	var mask_before := player.collision_mask
	for invalid in [Vector2(123,45),Vector2(123,-45),Vector2(-170,8),Vector2(185,8),Vector2(50,8)]:
		player.global_position = system.stops[0].to_global(invalid)
		check(ride.nearby_bus(player)==null,"no boarding from outside door %s"%invalid)
	player.global_position = system.stops[0].boarding_position()
	player.try_enter_vehicle()
	check(ride.actor == player and ride.bus == bus,"E interaction boards from station platform")
	check(not player.visible and not player.is_physics_processing() and player.collision_layer == 0,"passenger cannot walk or collide inside bus")
	check(not bus.is_driven_by_player and bus.get_parent() is PathFollow2D,"passenger preserves scheduled lane driving")
	Engine.time_scale = 3.0
	while bus.dwelling or bus.doors > 0: await physics_frame
	check(not ride.exit_at_stop(),"cannot exit moving bus")
	var began := Time.get_ticks_msec()
	while bus.current_stop == 0 and Time.get_ticks_msec()-began < 65000: await physics_frame
	check(bus.current_stop == 1,"passenger reaches next stop along real route")
	check(ride.actor == player,"arrival does not force player out")
	while bus.dwelling: await physics_frame
	check(ride.actor == player,"can stay aboard beyond first stop")
	ride._activate()
	check(ride.stop_requested,"button requests next stop while moving")
	ride.continue_button.pressed.emit()
	check(not ride.stop_requested,"continue button cancels stop request")
	ride.action.pressed.emit()
	check(ride.stop_requested,"can request stop again with visible button")
	await capture("02-stop-requested")
	began = Time.get_ticks_msec()
	while not ride.can_exit() and Time.get_ticks_msec()-began < 65000: await physics_frame
	check(bus.current_stop == 2 and ride.can_exit(),"requested stop opens doors for exit")
	await create_timer(9).timeout
	check(bus.dwelling and ride.holds_stop(bus),"requested bus waits for player's exit button")
	check(player.global_position.distance_to(bus.global_position)<3,"player and camera follow ride across junction handoffs")
	await capture("03-exit-button")
	var blocked_exit := StaticBody2D.new()
	blocked_exit.collision_layer = 1
	var blocker_shape := CollisionShape2D.new()
	blocker_shape.shape = RectangleShape2D.new()
	blocker_shape.shape.size = Vector2(360,90)
	blocked_exit.add_child(blocker_shape)
	system.stops[2].add_child(blocked_exit)
	blocked_exit.position = Vector2(10,0)
	await physics_frame
	check(not ride.exit_at_stop() and ride.actor == player,"blocked platform keeps passenger safely aboard")
	blocked_exit.queue_free()
	await physics_frame
	check(ride.exit_at_stop(),"exit button puts player on clear platform")
	check(player.visible and player.is_physics_processing() and not player.is_control_disabled,"exit restores visible controllable player")
	check(player.collision_layer==layer_before and player.collision_mask==mask_before,"exit restores original collisions")
	check(player.global_position.distance_to(system.stops[2].platform_exit())<110,"exit stays at requested station")
	await capture("04-disembarked")
	check(not ride.holds_stop(bus),"exit releases bus to continue passenger service")
	player.global_position = system.stops[2].boarding_position()
	check(ride.board(bus,player),"can board again")
	system.clock.time_of_day = 2.0/24
	system._update_schedule()
	check(ride.holds_stop(bus),"service closure preserves safe player exit")
	check(ride.exit_at_stop(),"can exit when service closes")
	check(not ride.board(bus,player),"closed service rejects new boarding")
	Engine.time_scale = 1
	print("URBAN PLAYER RIDE FAILURES: ",failures)
	quit(0 if failures.is_empty() else 1)
