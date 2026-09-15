extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func run() -> void:
	create_timer(100).timeout.connect(func(): quit(2))
	var saves = root.get_node("SaveManager")
	saves._save_dir = "D:/geteco/artifacts/tube-access/flow-saves/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	for flag in [&"harbor_arrival_seen",&"harbor_arrival_call_complete",&"harbor_maciota_met",&"harbor_delivery_complete"]: root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 30: await process_frame
	while not current_scene.gameplay_ready: await process_frame
	var system: Node2D = current_scene.get_node("UrbanTransit")
	while not system.ready_for_service: await process_frame
	current_scene.get_node("CobraCampaign").set_process(false)
	system.clock.is_dynamic_time = false
	system.clock.time_of_day = 0.5
	system._update_schedule()
	system.set_physics_process(false)
	var bus = system.buses[0]
	var station = system.stops[0]
	var ride = system.player_ride
	var player = current_scene.get_node("Player")
	player.set_physics_process(false)
	player.is_control_disabled = false
	player.is_in_dialogue = false
	# A real parked service bus opens its doors through its production update.
	var deadline := Time.get_ticks_msec()+5000
	while bus.doors<0.95 and Time.get_ticks_msec()<deadline: await physics_frame
	bus.set_physics_process(false)
	# Park the other real commuters at their authored sidewalk spawns. Freezing
	# them halfway through the ramp would deliberately obstruct the clear-route case.
	for i in system.passengers.size():
		var person = system.passengers[i]
		person.global_position = person.stop.sidewalk_position(i/6)
		person.set_destination(person.global_position,"off_duty")
		person.set_physics_process(false)
	await physics_frame
	await process_frame
	check(station.gate_open,"station gate follows parked bus doors")
	for point in [Vector2(123,45),Vector2(123,-45),Vector2(-170,8),Vector2(185,8),Vector2(50,8)]:
		player.global_position = station.to_global(point)
		check(not ride.board_nearby(player),"reject outside boarding aperture %s"%point)
	player.global_position = station.boarding_position()
	player.try_enter_vehicle()
	check(ride.actor==player,"E boards real parked bus at aperture")
	var obstacle := StaticBody2D.new()
	obstacle.collision_layer = 1
	var collision := CollisionShape2D.new()
	collision.shape = RectangleShape2D.new()
	collision.shape.size = Vector2(360,90)
	obstacle.add_child(collision)
	station.add_child(obstacle)
	await physics_frame
	await physics_frame
	check(not ride.exit_at_stop() and ride.actor==player,"blocked platform prevents exit; no sidewalk teleport")
	obstacle.queue_free()
	await physics_frame
	await physics_frame
	check(ride.exit_at_stop(),"exit to free platform")
	check(Rect2(-150,-25,305,50).has_point(station.to_local(player.global_position)),"player exits inside station")
	check(player.visible and player.collision_mask!=0,"exit restores actor and physical mask")
	player.set_physics_process(false)
	for point in [Vector2(151,8),Vector2(185,8),Vector2(207,8)]:
		var target: Vector2 = station.to_global(point)
		check(player.move_and_collide(target-player.global_position)==null,"walk out through ramp %s"%point)
	player.global_position = station.boarding_position()
	check(ride.board_nearby(player),"reentry through boarding aperture")
	check(ride.exit_at_stop(),"repeat exit")
	player.global_position = station.to_global(Vector2(0,70))
	var npc = system.passengers[0]
	npc.global_position = station.ramp_approach()
	npc.walk_route(PackedVector2Array([station.platform_exit(),station.queue_position(0)]),"arriving")
	deadline = Time.get_ticks_msec()+6000
	while not npc.waypoints.is_empty() and Time.get_ticks_msec()<deadline: await physics_frame
	var contact := KinematicCollision2D.new()
	var blocked: bool = npc.test_move(npc.global_transform,npc.global_position.direction_to(npc.destination)*5,contact)
	print("NPC_ROUTE pose=",station.to_local(npc.global_position)," target=",station.to_local(npc.destination)," waypoints=",npc.waypoints," sleeping=",npc.get_meta("proximity_sleeping",false)," speed=",npc.velocity," blocker=",contact.get_collider().get_path() if blocked else "none")
	check(npc.waypoints.is_empty(),"real NPC walks ramp to queue without crossing solids")
	npc.walk_route(PackedVector2Array([station.platform_exit(),station.ramp_approach()]),"walking_to_activity")
	deadline = Time.get_ticks_msec()+6000
	while not npc.waypoints.is_empty() and Time.get_ticks_msec()<deadline: await physics_frame
	check(npc.waypoints.is_empty(),"real NPC leaves by ramp")
	print("TUBE_BOARDING_FLOW failures=",failures)
	quit(0 if failures.is_empty() else 1)
