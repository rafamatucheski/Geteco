extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "fuel_inline"
	arm_watchdog(210)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	var manager: Node2D = world.get_node("Interiors")
	var room: Node2D = manager.get_node("InteriorSpaces/FuelInterior")
	var door: BuildingEntrance = room.entrance
	var bank: Node2D = manager.get_node("InteriorSpaces/BankInterior")
	var camera: Camera2D = player.get_node("Camera")
	check(room.inline_mode and not room.is_bank and room.global_position.distance_to(door.global_position) < 100, "Fuel floor is inside its exterior lot")
	check(room.exit_door == null and room.inline_floor_polygon.size() == 4, "No off-map fuel exit")
	check(not door.show_entrance_marker and not door.show_interaction_prompt and not door.handle_input_locally, "No marker or E prompt at fuel entrance")
	check(not manager._door_configs.has("District/NorthFrontage4/RobberyEntrance"), "Fuel has no teleport binding")
	check(bank.is_bank and bank.inline_mode and bank.exit_door == null and not manager._door_configs.has("District/NorthFrontage0/RobberyEntrance"), "Bank now shares the physical inline entrance contract")
	for name in ["RearWall","SideWall-1","SideWall1","FrontWall-1","FrontWall1","WallStock-1","WallStock1","Cooler","Counter","CoffeeStation","DoorLeaves"]:
		check(room.get_node_or_null(name) is StaticBody2D, "Projected fuel solid: "+name)
	var outside := door.to_global(Vector2(0,71))
	player.global_position = outside
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	await physics_frames(45)
	check(not room.actor_inside() and room.inline_store.roof.visible, "Roof remains on outside")
	check(door.open_amount > .9, "Sliding leaves open on approach")
	var before := player.global_position
	await press_key(KEY_E)
	check(player.global_position.distance_to(before) < 2 and not room.actor_inside(), "E outside does not enter")
	await shot("before")
	var inside := room.to_global(room.project_floor(Vector2(0,1.5)))
	var entered := await walk_to_fuel(player,inside,220,9)
	if not entered:
		var probe: KinematicCollision2D = player.move_and_collide(Vector2(0,-24),true)
		print("FUEL_ENTRY_DIAG player=",player.global_position," door_local=",door.to_local(player.global_position)," target=",inside," room_local=",room.to_local(player.global_position)," door_amount=",room._inline_door_amount," blocker_disabled=",room.inline_door_blocker.disabled," blocker=",probe.get_collider().get_path() if probe else "none"," exterior_solid=",world.get_node("District/NorthFrontage4").get_node_or_null("BuildingSolid"))
	check(entered, "Player crosses doorway by walking")
	await physics_frames(8)
	check(room.actor_inside() and not room.inline_store.roof.visible and camera.has_meta("compact_interior"), "Roof cuts away and camera zooms inside")
	check(player.global_position.distance_to(door.global_position)<110, "Player stays in physical building")
	await shot("inside")
	await check_actor_depth(room, room.actor_scale, "Player")
	var reward: Area2D = room.get_node("RoomCash")
	var start_money: int = player.money
	check(await walk_to_fuel(player,reward.global_position,150,8), "Central aisle reaches floor reward")
	await physics_frames(5)
	check(reward.collected and player.money >= start_money+350, "Cash reward collects on contact")
	check(player.serialize().world_pickups_collected.has(reward.pickup_id), "Reward persists in player save data")
	var shelf_start := room.to_global(room.project_floor(Vector2(-2.55,0)))
	player.global_position = shelf_start
	player.velocity = Vector2.ZERO
	await physics_frames(3)
	check(not await walk_to_fuel(player,room.to_global(room.project_floor(Vector2(-3.8,0))),65,7), "Shelf blocks the player body")
	var visitor := preload("res://characters/AnimatedPedestrian3D.gd").new() as CharacterBody2D
	world.add_child(visitor)
	visitor.set_physics_process(false)
	visitor.global_position = room.to_global(room.project_floor(Vector2(0,-.3)))
	await physics_frames(3)
	var hit := visitor.move_and_collide(room.to_global(room.project_floor(Vector2(1.7,-1.7)))-visitor.global_position)
	check(hit != null and hit.get_collider().name == "Counter", "Real NPC collides with checkout counter")
	visitor.global_position = room.to_global(room.project_floor(Vector2(0,.2)))
	var visitor_presentation := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
	world.add_child(visitor_presentation)
	visitor_presentation.configure(visitor,room.room_camera,room.room_display)
	await physics_frames(4)
	await check_actor_depth(room,visitor_presentation,"NPC")
	visitor_presentation.restore()
	visitor_presentation.queue_free()
	visitor.queue_free()
	player.global_position = room.to_global(room.project_floor(Vector2(0,.35)))
	player.velocity = Vector2.ZERO
	await physics_frames(5)
	var clerk: Node2D = room.civilians[0]
	check(room.contains_point(clerk.global_position) and not _point_solid(clerk.global_position), "Cashier stands on free floor")
	room.cashier_resists = false
	player.active_weapon_id = "pistol"
	player.weapon_aim_active = true
	start_money = player.money
	room._tick_cashier(3.2,clerk.global_position)
	check(room.cash_paid and player.money >= start_money+180 and room._taken("register"), "Existing robbery pays cashier once")
	start_money = player.money
	room._tick_cashier(4.0,clerk.global_position)
	check(player.money == start_money, "Cashier cannot pay twice")
	var saved_position: Array = player.serialize().position
	check(Vector2(saved_position[0],saved_position[1]).distance_to(player.global_position)<1, "Save records physical shop position")
	player.active_weapon_id = "fists"
	player.weapon_aim_active = false
	player.global_position = room.to_global(room.project_floor(Vector2(0,1.6)))
	player.velocity = Vector2.ZERO
	await physics_frames(5)
	check(await walk_to_fuel(player,outside,160,11), "Player exits through same door by walking")
	await physics_frames(8)
	check(not room.actor_inside() and room.inline_store.roof.visible and not camera.has_meta("compact_interior"), "Roof and exterior camera restore")
	check(room.view.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "Empty shop suspends continuous 3D rendering")
	await shot("after")
	print("FUEL INLINE: %d passed, %d failed" % [passed_count,failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)

func _point_solid(point: Vector2) -> bool:
	var probe := PhysicsPointQueryParameters2D.new()
	probe.position = point
	probe.collision_mask = 1
	return not current_scene.get_world_2d().direct_space_state.intersect_point(probe,16).is_empty()

func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	var folder := OS.get_temp_dir().path_join("geteco-fuel-cutaway-0922")
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("test-"+name+".png"))

func check_actor_depth(room: Node2D, adapter: Node, label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	var anchor: Node3D = adapter.anchor
	adapter._update_scale()
	adapter.set_process(false)
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4,4,.2)
	panel.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("427766")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = material
	room.view.add_child(panel)
	panel.position = anchor.position + Vector3.UP + (room.room_camera.position-anchor.position).normalized()*1.5
	panel.look_at(room.room_camera.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	var with_actor: Image = room.view.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var without_actor: Image = room.view.get_texture().get_image()
	var pixel: Vector2 = room.room_camera.unproject_position(anchor.position+Vector3.UP*.9)
	check(changed_pixels(with_actor,without_actor,pixel)==0,label+" is hidden by an opaque 3D wall")
	panel.hide()
	anchor.show()
	await process_frame
	await RenderingServer.frame_post_draw
	with_actor = room.view.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	without_actor = room.view.get_texture().get_image()
	check(changed_pixels(with_actor,without_actor,pixel)>100,label+" is visible on open floor")
	panel.queue_free()
	anchor.show()
	adapter.set_process(true)
	await shot(label.to_lower()+"-depth")

func changed_pixels(a: Image, b: Image, center: Vector2) -> int:
	var changed := 0
	for y in range(maxi(0,int(center.y)-25),mini(a.get_height(),int(center.y)+25)):
		for x in range(maxi(0,int(center.x)-20),mini(a.get_width(),int(center.x)+20)):
			if a.get_pixel(x,y) != b.get_pixel(x,y): changed += 1
	return changed

func walk_to_fuel(body: CharacterBody2D, target: Vector2, max_frames: int, tolerance: float) -> bool:
	for step in max_frames:
		var delta := target-body.global_position
		if delta.length() <= tolerance:
			release_fuel_movement()
			return true
		var direction := delta.normalized()
		for pair in [["move_right",direction.x],["move_left",-direction.x],["move_down",direction.y],["move_up",-direction.y]]:
			if pair[1] > .15: Input.action_press(pair[0])
			else: Input.action_release(pair[0])
		await physics_frame
	release_fuel_movement()
	return body.global_position.distance_to(target) <= tolerance

func release_fuel_movement() -> void:
	for action in ["move_left","move_right","move_up","move_down"]: Input.action_release(action)
