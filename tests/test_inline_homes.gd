extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "inline_homes"
	arm_watchdog(180)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	var homes: ResidenceManager = world.get_node("ResidencePrototype")
	player.money = 200000
	for id in ["westgate_garden","quayside_house","canal_north"]:
		var property: ResidenceProperty = homes.properties[id]
		var room: ResidenceInterior = homes.residence_interiors[id]
		check(room.inline_mode and room.exit_door == null and room.global_position.distance_to(property.global_position)<1,"Physical home: "+id)
		check(property.get_node_or_null("HouseFootprint")==null and room.inline_floor_polygon.size()==4,"Shell collision replaces placeholder: "+id)
		check(room.art.station_points.size()==4 and not room.art.station_points.has("exit"),"Functional stations without E exit: "+id)
		check(homes.purchase_home(id).affordable,"Purchase remains functional: "+id)
		var outside := room.to_global(room.project_floor(Vector2(0,3.1)))+Vector2(0,46)
		player.global_position = outside
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
		player.get_node("Camera").reset_smoothing()
		await physics_frames(42)
		for frame in 300:
			if property.sprite_3d.visible: break
			await process_frame
		if room.contains_point(player.global_position) or not property.sprite_3d.visible:
			print("HOME_OUTSIDE_DIAG id=",id," actor=",player.global_position," local=",room.to_local(player.global_position)," polygon=",room.inline_floor_polygon," sprite=",property.sprite_3d.visible," occupied=",room._inline_occupied," property_visible=",property.visible)
		check(not room.contains_point(player.global_position) and property.sprite_3d.visible,"Roof present outside: "+id)
		check(room._inline_door_amount>.9 and room.inline_door_blocker.disabled,"Door opens by proximity: "+id)
		check(homes._find_action(player).get("kind","")!="enter","No E entrance action: "+id)
		check(homes._find_action(player).get("kind","")!="enter","Entrance key has no home transfer: "+id)
		var crossed: bool = await _walk(player,room.spawn_point.global_position,180,9)
		if not crossed:
			var probe: KinematicCollision2D = player.move_and_collide((room.spawn_point.global_position-player.global_position).limit_length(24),true)
			print("HOME_ENTRY_DIAG id=",id," actor=",player.global_position," target=",room.spawn_point.global_position," local=",room.to_local(player.global_position)," door=",room._inline_door_amount," blocker=",room.inline_door_blocker.disabled," control=",player.is_control_disabled," collider=",probe.get_collider().get_path() if probe else "none")
		check(crossed,"Walk through door: "+id)
		await physics_frames(7)
		check(room.contains_point(player.global_position) and not property.sprite_3d.visible and room.room_display.visible,"Cutaway appears inside: "+id)
		check(player.get_node("Camera").has_meta("compact_interior") and player.has_meta("interior_actor_presentation"),"Camera zoom and player depth: "+id)
		check(await _reachable_stations(room),"Four stations physically reachable: "+id)
		var reward: Area2D = room.get_node("RoomCash")
		var balance: int = player.money
		check(await _walk(player,reward.global_position,180,10),"Reward reachable: "+id)
		await physics_frames(5)
		check(reward.collected and player.money>=balance+reward.amount,"Reward collected: "+id)
		check(player.serialize().world_pickups_collected.has(reward.pickup_id),"Reward saved: "+id)
		check(await _walk(player,outside,180,11),"Walk out same door: "+id)
		await physics_frames(7)
		check(not room.contains_point(player.global_position) and property.sprite_3d.visible and not player.get_node("Camera").has_meta("compact_interior"),"Roof and camera restore: "+id)
		if OS.get_cmdline_user_args().has("--home-first-only"): break
	var keeper_home: Node2D = world.get_node("Cemetery/KeeperHouse")
	var keeper_room: Node2D = keeper_home.room
	check(keeper_room.inline_mode and keeper_room.exit_door==null and keeper_room.global_position.distance_to(keeper_home.global_position)<1,"Cemetery house occupies physical cottage")
	check(not keeper_home.entrance.handle_input_locally and not keeper_home.entrance.show_interaction_prompt and not keeper_home.entrance.show_entrance_marker,"Cemetery house has no E marker")
	check(keeper_home.get_node_or_null("HouseFootprint")==null,"Cemetery cottage placeholder collision removed")
	var cottage_outside: Vector2 = keeper_home.entrance.global_position+Vector2(0,45)
	player.global_position = cottage_outside
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	player.get_node("Camera").reset_smoothing()
	await physics_frames(40)
	check(keeper_home.entrance._door_open and keeper_room.inline_door_blocker.disabled,"Cemetery door opens on approach")
	check(await _walk(player,keeper_room.spawn_point.global_position,160,9),"Walk into cemetery house")
	await physics_frames(6)
	check(keeper_room.actor_inside() and not keeper_home.sprite_3d.visible and keeper_room.room_display.visible,"Cemetery roof cuts away")
	check(player.has_meta("interior_actor_presentation"),"Player shares cemetery room depth")
	var keeper_reward: Area2D = keeper_room.get_node("RoomCash")
	check(await _walk(player,keeper_reward.global_position,160,9),"Cemetery reward reachable")
	check(await _walk(player,cottage_outside,180,11),"Walk out of cemetery house")
	await physics_frames(6)
	check(not keeper_room.actor_inside() and keeper_home.sprite_3d.visible,"Cemetery roof restores")
	print("INLINE HOMES: %d passed, %d failed" % [passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)

func _walk(actor: CharacterBody2D,target: Vector2,max_frames: int,tolerance: float) -> bool:
	for step in max_frames:
		var direction := target-actor.global_position
		if direction.length() <= tolerance:
			_release_walk()
			return true
		direction = direction.normalized()
		for pair in [["move_right",direction.x],["move_left",-direction.x],["move_down",direction.y],["move_up",-direction.y]]:
			if pair[1]>.15: Input.action_press(pair[0])
			else: Input.action_release(pair[0])
		await physics_frame
	_release_walk()
	return actor.global_position.distance_to(target)<=tolerance

func _release_walk() -> void:
	for action in ["move_left","move_right","move_up","move_down"]: Input.action_release(action)

func _reachable_stations(room: ResidenceInterior) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = 10
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var seen := {Vector2i.ZERO:true}
	var reached := {}
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		var point := room.spawn_point.global_position+Vector2(cell)*12
		for station in room.stations:
			if point.distance_to(room.to_global(station.position))<24: reached[station.kind]=true
		for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = cell+offset
			if seen.has(next): continue
			seen[next]=true
			var candidate := room.spawn_point.global_position+Vector2(next)*12
			if not room.contains_point(candidate): continue
			query.transform = Transform2D(0,candidate)
			if room.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): queue.append(next)
	return reached.size()==4
