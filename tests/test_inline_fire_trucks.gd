extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	_tag = "inline_fire_trucks"
	arm_watchdog(220)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	var fire = world.get_node("Interiors").fire_station_interior
	check(fire.inline_mode and fire.bay_trucks.size()==3 and fire.bay_exits.is_empty(),"Three physical bays have three real trucks and no transfer doors")
	for index in 3:
		var door := world.get_node("NorthDistrict/NorthFireStation/Entrance%d" % index) as BuildingEntrance
		var truck: CharacterBody2D = fire.bay_trucks[index]
		var original := truck.get_instance_id()
		check(not door.handle_input_locally and not door.show_entrance_marker,"Bay %d has no E or marker" % index)
		player.global_position = truck.global_position+Vector2(0,-43)
		player.velocity = Vector2.ZERO
		await physics_frames(8)
		player.try_enter_vehicle()
		for frame in 240:
			await physics_frame
			if truck.is_driven_by_player and not truck.has_meta("vehicle_boarding"): break
		check(truck.is_driven_by_player and not truck.has_meta("vehicle_boarding"),"Board truck %d normally" % index)
		await physics_frames(4)
		Input.action_press("move_up")
		var left := false
		for frame in 530:
			await physics_frame
			if not fire.contains_point(truck.global_position):
				left = true
				break
		Input.action_release("move_up")
		check(left and truck.global_position.distance_to(door.global_position)<230,"Truck %d drives through its own gate" % index)
		check(truck.get_instance_id()==original and not truck.has_meta("interior_vehicle_presentation"),"Truck %d remains same exterior node" % index)
		truck.velocity = Vector2.ZERO
		truck.global_rotation = -PI/2
		truck.global_position = door.global_position+Vector2(0,92)
		await physics_frames(24)
		Input.action_press("move_up")
		var returned := false
		for frame in 530:
			await physics_frame
			if fire.contains_point(truck.global_position):
				returned = true
				break
		Input.action_release("move_up")
		check(returned and fire._inline_occupied,"Truck %d drives back into same physical bay" % index)
		check(truck.get_instance_id()==original and fire.bay_trucks[index]==truck,"Truck %d is never duplicated" % index)
		truck.velocity = Vector2.ZERO
		truck.exit_vehicle()
		for frame in 300:
			await physics_frame
			if player.visible and not player.is_control_disabled: break
		check(player.visible and not player.is_control_disabled,"Disembark truck %d" % index)
	player.health=40
	player.global_position=fire.heal_area.global_position
	await physics_frames(190)
	check(player.health>40 and player.health<=player.max_health,"Fire medical station still heals")
	print("INLINE FIRE TRUCKS: %d passed, %d failed" % [passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)
