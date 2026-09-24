extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "inline_harbor_complexes"
	arm_watchdog(240)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	var manager: HarborInteriorManager = world.get_node("Interiors")
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = 2.0/24.0
	var garage = manager.garage_interior
	var fire = manager.fire_station_interior
	var boss = world.get_node("Interiors/InteriorSpaces/PortBossGarage")
	print("COMPLEX_SAFE_SPAWNS maciota=",garage.spawn_point.global_position," fire=",fire.spawn_point.global_position)
	check(garage.inline_mode and fire.inline_mode and boss.inline_mode,"Three physical rooms stay active in the district")
	for spec in [
		{"id":"maciota","room":garage,"door":world.get_node("District/Garage/Entrance")},
		{"id":"fire","room":fire,"door":world.get_node("NorthDistrict/NorthFireStation/Entrance1")},
	]:
		var id: String = spec.id
		var room = spec.room
		var door: BuildingEntrance = spec.door
		check(not door.handle_input_locally and not door.show_entrance_marker and not door.show_interaction_prompt,"No E or marker: "+id)
		var outside: Vector2 = door.to_global(Vector2(0,78))
		player.global_position = outside
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		await physics_frames(45)
		check(door._door_open,"Proximity opens street door: "+id)
		check(await _walk(player,room.spawn_point.global_position,300,13),"Walk into real building: "+id)
		await physics_frames(10)
		if id=="fire" and not (room.contains_point(player.global_position) and room.sprite_3d.visible):
			print("FIRE_CUT_DIAG pos=",player.global_position," contained=",room.contains_point(player.global_position)," sprite=",room.sprite_3d.visible," occupied=",room._inline_occupied," facade_cut=",room.inline_facade.inline_cutaway)
		check(room.contains_point(player.global_position) and room.sprite_3d.visible,"Cutaway and interior art inside: "+id)
		check(player.get_node("Camera").has_meta("compact_interior") and player.has_meta("interior_actor_presentation"),"Zoom and shared actor depth: "+id)
		var solid_body: Node = room.showroom.get_node("WorkshopMeshSolids") if id=="maciota" else room.walls_body
		check(await _solid_blocks(player,solid_body),"Projected furniture/wall physically blocks player: "+id)
		if id=="maciota":
			check(garage.inline_door_blocker.disabled and player.weapons_forbidden(),"Garage door opens and weapon restriction is spatial")
			var personal_manager := world.get_node("PersonalCarManager")
			var personal_car = personal_manager.car
			var was_unlocked: bool = personal_car.unlocked
			personal_car.unlocked = true
			personal_manager._sync_availability()
			await physics_frames(4)
			check(garage.parked_car_presentation != null and not personal_car.sprite.visible and not personal_car.get_node("ContactShadow").visible and personal_car.body_model.get_parent()==garage.showroom.viewport_3d,"Parked Monaliza uses room depth pass")
			personal_car.unlocked = was_unlocked
			personal_manager._sync_availability()
		else:
			check(fire.inline_gate_blockers[1].disabled and fire.bay_trucks.size()==3 and fire.bay_exits.is_empty(),"Three trucks remain and no teleport exits")
		check(await _walk(player,outside,300,14),"Walk back through same door: "+id)
		await physics_frames(8)
		check(not room.contains_point(player.global_position) and not player.get_node("Camera").has_meta("compact_interior"),"Roof and camera restore: "+id)
		if id=="maciota":
			var personal_manager := world.get_node("PersonalCarManager")
			var personal_car = personal_manager.car
			var was_unlocked: bool = personal_car.unlocked
			personal_car.unlocked = true
			personal_manager._sync_availability()
			await physics_frames(4)
			check(not personal_car.sprite.visible and not personal_car.get_node("ContactShadow").visible and garage.parked_car_presentation==null and personal_car.collision_layer!=0,"Closed roof hides parked Monaliza and shadow without disabling collision")
			personal_car.global_position = outside+Vector2(90,0)
			await physics_frames(4)
			check(personal_car.sprite.visible and personal_car.get_node("ContactShadow").visible,"Monaliza street sprite and shadow return outside the garage")
			personal_car.global_position = garage.get_vehicle_bay_position()
			personal_car.unlocked = was_unlocked
			personal_manager._sync_availability()
	for index in 3:
		var door := world.get_node("NorthDistrict/NorthFireStation/Entrance%d" % index) as BuildingEntrance
		check(not door.handle_input_locally and not door.show_entrance_marker,"Fire bay %d has no E/marker" % index)
		player.global_position = door.to_global(Vector2(0,78))
		await physics_frames(45)
		check(await _walk(player,fire.get_spawn_for_bay(index).global_position,300,13),"Fire bay %d is traversable" % index)
		check(fire.contains_point(player.global_position),"Fire bay %d reaches hall" % index)
		check(await _walk(player,door.to_global(Vector2(0,78)),300,14),"Fire bay %d has physical exit" % index)
	var boss_clock := get_first_node_in_group("day_night_manager")
	boss_clock.is_dynamic_time=false
	boss_clock.time_of_day=2.0/24.0
	var bridge = world.get_node("CobraCampaign")
	bridge.ledger.data.day_elapsed = fposmod(2.0/24.0-.35,1.0)*bridge.LEDGER.DAY_SECONDS
	player.global_position = boss.EXTERIOR+Vector2(55,0)
	player.velocity = Vector2.ZERO
	await physics_frames(30)
	print("BOSS_GATE_DIAG hour=",boss.hour()," gate=",boss._gate_open," shutter_disabled=",boss.shutter_shape.disabled," showroom=",boss.showroom!=null," player=",player.global_position," clock_same=",boss_clock==world.weather)
	check(boss.showroom!=null and boss._gate_open and boss.shutter_shape.disabled,"Boss gate opens during schedule")
	var boss_entered: bool=await _walk(player,boss.spawn_point.global_position,330,13)
	if not boss_entered:
		var probe: KinematicCollision2D=player.move_and_collide((boss.spawn_point.global_position-player.global_position).limit_length(20),true)
		print("BOSS_ENTRY_DIAG player=",player.global_position," spawn=",boss.spawn_point.global_position," collider=",probe.get_collider().get_path() if probe else "none")
	check(boss_entered,"Walk through boss garage gate")
	await physics_frames(10)
	check(boss.contains_point(player.global_position) and boss.showroom.sprite_3d.visible and not boss.portal.sprite_3d.visible,"Boss garage roof cuts away")
	check(boss.cars.size()==5 and boss.guards.size()==2 and boss.boss!=null,"Five cars, two guards and Porto Rosso retained")
	check(await _solid_blocks(player,boss.showroom.get_child(boss.showroom.get_child_count()-1)),"Boss room projected wall blocks player")
	print("BOSS_ACTOR_DIAG cam=",player.get_node("Camera").has_meta("compact_interior")," actor=",player.has_meta("interior_actor_presentation")," active=",boss.active," occupants=",boss.actor_presentations.size()," player_visible=",player.visible," room=",boss.contains_point(player.global_position))
	check(player.get_node("Camera").has_meta("compact_interior") and player.has_meta("interior_actor_presentation"),"Boss camera and actor depth")
	check(await _walk(player,boss.EXTERIOR+Vector2(55,0),330,13),"Walk out boss gate")
	await physics_frames(8)
	check(not boss.active and boss.portal.sprite_3d.visible and not player.get_node("Camera").has_meta("compact_interior"),"Boss roof and camera restore")
	var personal_manager := world.get_node("PersonalCarManager")
	var personal_car = personal_manager.car
	personal_car.unlocked = true
	personal_manager._sync_availability()
	player.global_position = garage.spawn_point.global_position
	await physics_frames(15)
	check(garage.parked_car_presentation != null,"Monaliza is in the room pass before boarding")
	personal_car.enter_vehicle(player)
	await physics_frames(100)
	check(personal_car.is_driven_by_player and garage.inline_car_presentation != null and garage.parked_car_presentation == null and not personal_car.sprite.visible,"Boarding transfers Monaliza to driven room pass")
	personal_car.global_position = garage.inline_entrance.global_position+Vector2(180,80)
	personal_car.velocity = Vector2.ZERO
	await physics_frames(12)
	check(garage.inline_car_presentation == null and personal_car.sprite.visible and personal_car.get_node("ContactShadow").visible and personal_car.body_model.get_parent()==personal_car.body_viewport,"Driving out restores Monaliza sprite, shadow and model")
	personal_car.force_exit_vehicle()
	print("INLINE HARBOR COMPLEXES: %d passed, %d failed" % [passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)

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

func _solid_blocks(actor: CharacterBody2D,body: Node) -> bool:
	var shape: CollisionPolygon2D
	for child in body.get_children():
		if child is CollisionPolygon2D and not child.disabled:
			shape=child
			break
	if shape==null: return false
	var center := Vector2.ZERO
	for point in shape.polygon: center+=point
	center=shape.to_global(center/shape.polygon.size())
	var start: Vector2=shape.to_global(shape.polygon[0])
	var end: Vector2=shape.to_global(shape.polygon[1])
	var normal := Vector2((end-start).y,-(end-start).x).normalized()
	var middle := (start+end)*.5
	if normal.dot(middle-center)<0: normal=-normal
	var original := actor.global_position
	actor.global_position=middle+normal*16
	await physics_frames(2)
	var hit: KinematicCollision2D=actor.move_and_collide(-normal*32,true)
	actor.global_position=original
	await physics_frames(3)
	return hit!=null and hit.get_collider()==body
