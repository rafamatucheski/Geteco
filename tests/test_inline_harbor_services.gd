extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "inline_harbor_services"
	arm_watchdog(190)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	var manager: HarborInteriorManager = world.get_node("Interiors")
	var police: HarborPoliceInterior = manager.police_interior
	var clinic = manager.clinic_interior
	for spec in [
		{"id":"police","room":police,"facade":world.get_node("District/Police"),"door":world.get_node("District/Police/Entrance")},
		{"id":"clinic","room":clinic,"facade":world.get_node("District/Clinic"),"door":world.get_node("District/Clinic/Entrance")},
	]:
		var id: String = spec.id
		var room = spec.room
		var facade: Node2D = spec.facade
		var door: BuildingEntrance = spec.door
		check(room.get("inline_mode")==true and room.exit_door==null,"Physical room with no teleport exit: "+id)
		check(not manager._door_configs.has(String(door.get_path()).trim_prefix(String(world.get_path())+"/")),"No manager E entrance: "+id)
		check(not door.handle_input_locally and not door.show_entrance_marker and not door.show_interaction_prompt,"No E or orange entry marker: "+id)
		check(room.global_position.distance_to(facade.global_position)<80,"Room occupies its street building: "+id)
		var outside: Vector2 = door.to_global(Vector2(0,60))
		player.global_position = outside
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		player.get_node("Camera").reset_smoothing()
		await physics_frames(40)
		check(door._door_open and room.inline_door_blocker.disabled,"Street door opens with proximity: "+id)
		var walked: bool = await _walk(player,room.spawn_point.global_position,230,9)
		if not walked:
			var probe: KinematicCollision2D = player.move_and_collide((room.spawn_point.global_position-player.global_position).limit_length(18),true)
			print("SERVICE_ENTRY_DIAG id=",id," player=",player.global_position," spawn=",room.spawn_point.global_position," door=",door.open_amount," blocker=",room.inline_door_blocker.disabled," hit=",probe.get_collider().get_path() if probe else "none")
		check(walked,"Walk through physical doorway: "+id)
		await physics_frames(6)
		check(room.contains_point(player.global_position) and room.room_display.visible,"Cutaway appears inside: "+id)
		check(player.get_node("Camera").has_meta("compact_interior") and player.has_meta("interior_actor_presentation"),"Zoom and shared player depth: "+id)
		check(await _station_and_collision_check(player,room,id),"Furniture and interaction route: "+id)
		var front_route: bool = await _walk(player,room.spawn_point.global_position,230,10)
		var exited := false
		if front_route: exited = await _walk(player,outside,230,10)
		if not exited:
			var probe: KinematicCollision2D = player.move_and_collide((outside-player.global_position).limit_length(20),true)
			print("SERVICE_EXIT_DIAG id=",id," player=",player.global_position," spawn=",room.spawn_point.global_position," outside=",outside," front_route=",front_route," door=",door.open_amount," blocker=",room.inline_door_blocker.disabled," hit=",probe.get_collider().get_path() if probe else "none")
		check(exited,"Walk out the same door: "+id)
		await physics_frames(7)
		check(not room.contains_point(player.global_position) and not room.room_display.visible and not player.get_node("Camera").has_meta("compact_interior"),"Roof and camera restore outside: "+id)
	print("INLINE HARBOR SERVICES: %d passed, %d failed" % [passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)

func _station_and_collision_check(player: CharacterBody2D,room,id: String) -> bool:
	if id=="police":
		var police: HarborPoliceInterior = room
		var start: Vector2 = player.global_position
		var desk: Vector2 = police.to_global(police.project_floor(Vector2(.2,.55)))
		var hit: KinematicCollision2D = player.move_and_collide(desk-start)
		var blocked: bool = hit != null and hit.get_collider() is StaticBody2D
		player.global_position = start
		var reward: Area2D = police.get_node("RoomCash")
		var money_before: int = player.money
		var reached: bool = await _walk(player,reward.global_position,180,10)
		await physics_frames(4)
		var collected: bool = reward.collected and player.money>=money_before+reward.amount
		var terminal_approach: Vector2 = police.to_global(police.project_floor(Vector2(-2.05,2.2)))
		var terminal_reached: bool = await _walk(player,terminal_approach,180,11)
		await physics_frames(4)
		var terminal_near: bool = police.is_near_terminal
		return blocked and reached and collected and terminal_reached and terminal_near
	var clinic = room
	var building_solid := clinic.inline_facade.get_node("BuildingSolid") as StaticBody2D
	var ambulance_solid: bool = building_solid.get_child_count()>=4 and (building_solid.get_child(0) as CollisionShape2D).disabled and not (building_solid.get_child(1) as CollisionShape2D).disabled
	var start: Vector2 = player.global_position
	var bed: Vector2 = clinic.to_global(clinic.project_floor(Vector2(-1.85,.25)))
	var hit: KinematicCollision2D = player.move_and_collide(bed-start)
	var blocked: bool = hit != null and hit.get_collider() is StaticBody2D
	player.global_position = start
	player.health = 30
	var pickup_reached: bool = await _walk(player,clinic.health_pickup.global_position,180,10)
	await physics_frames(5)
	var healed: bool = player.health==player.max_health
	var triage_approach: Vector2 = clinic.to_global(clinic.project_floor(Vector2(1.3,-1.9)))
	var triage_reached: bool = await _walk(player,triage_approach,180,10)
	await physics_frames(4)
	return ambulance_solid and blocked and pickup_reached and healed and triage_reached and clinic.is_near_triage

func _walk(actor: CharacterBody2D,target: Vector2,max_frames: int,tolerance: float) -> bool:
	for step in max_frames:
		var direction := target-actor.global_position
		if direction.length()<=tolerance:
			_release_walk()
			return true
		direction=direction.normalized()
		for pair in [["move_right",direction.x],["move_left",-direction.x],["move_down",direction.y],["move_up",-direction.y]]:
			if pair[1]>.15: Input.action_press(pair[0])
			else: Input.action_release(pair[0])
		await physics_frame
	_release_walk()
	return actor.global_position.distance_to(target)<=tolerance

func _release_walk() -> void:
	for action in ["move_left","move_right","move_up","move_down"]: Input.action_release(action)
