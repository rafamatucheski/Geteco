extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 30: await process_frame
	var world := current_scene
	while not world.gameplay_ready: await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	var owned: Node2D = world.get_node("PersonalCarManager").car
	var traffic = ModernTrafficFactory.spawn_parked_vehicle(world,"BoardingTraffic",Vector2(4500,-950),0,"summit_suv",0,Color("3f7589"))
	for car in [owned,traffic]:
		car.global_position = Vector2(4500,-950)
		for side in [-1.0,1.0]:
			car.rotation = 0.75 if side > 0 else -PI/2
			player.global_position = car.to_global(Vector2(-8,side*43))
			player.set_physics_process(false)
			player.is_control_disabled = false
			var approach := player.global_position
			car.enter_vehicle(player)
			check(car._boarding.side == side,"entry follows actor side in rotated car")
			check(player.global_position.distance_to(approach)<1 and player.visible,"actor begins at approached door")
			check(player.is_control_disabled,"boarding blocks pedestrian interactions")
			Input.action_press("move_up")
			var parked: Vector2 = car.global_position
			await create_timer(0.36).timeout
			check(car.global_position.distance_to(parked)<1,"throttle cannot move car during entry")
			check(car._door_3d.door_side == side and car._door_3d.extracted_triangles>0,"correct authored 3D door selected")
			check(car._door_3d.hinge.rotation.y*side>0.5,"selected door swings outward")
			var other: Node3D = car._side_doors.get(-side)
			check(other == null or is_zero_approx(other.hinge.rotation.y),"opposite door stays closed")
			if side > 0:
				while is_instance_valid(car._boarding) and car._boarding.progress < 0.82: await process_frame
				check(car._boarding.phase == "change_seat","passenger entry crosses to driver seat")
			while car.has_meta("vehicle_boarding"): await process_frame
			check(not player.visible and not player.is_control_disabled,"seated driver restores interaction state")
			await create_timer(0.15).timeout
			check(car.global_position.distance_to(parked)<1,"held throttle requires release after boarding")
			Input.action_release("move_up")
			await create_timer(0.25).timeout
			check(is_zero_approx(car._door_3d.hinge.rotation.y),"door closes after entry")
			car.exit_vehicle()
			check(car.camera.is_current(), "vehicle camera stays active throughout exit")
			while car.has_meta("vehicle_boarding"): await process_frame
			check(player.visible and player.is_physics_processing(),"exit restores pedestrian")
			check(player.get_node("Camera").is_current(), "camera returns to pedestrian after exit")
			await create_timer(1.05).timeout
	player.global_position = owned.to_global(Vector2(0,43))
	owned.enter_vehicle(player)
	await create_timer(0.2).timeout
	owned.exit_vehicle()
	while owned.has_meta("vehicle_boarding"): await process_frame
	await create_timer(1.4).timeout
	check(player.visible and player.modulate.a == 1 and not player.is_control_disabled,"interrupted entry cannot hide or lock pedestrian later")
	owned.enter_vehicle(player)
	await create_timer(0.1).timeout
	owned.exit_vehicle()
	owned.force_exit_vehicle()
	await create_timer(1.0).timeout
	check(not owned.is_driven_by_player and not owned.has_meta("vehicle_boarding") and player.visible and not player.is_control_disabled, "lifecycle cleanup cancels pending exit without stale callbacks")
	print("VEHICLE BOARDING FAILURES: ",failures)
	quit(0 if failures.is_empty() else 1)
