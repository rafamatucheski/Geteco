extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "bank_inline_migration"
	arm_watchdog(140)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready: await process_frame
	var building = world.get_node("District/NorthFrontage0")
	var door: BuildingEntrance = building.get_node("RobberyEntrance")
	var room = world.get_node("Interiors/InteriorSpaces/BankInterior")
	var player = world.get_node("Player") as CharacterBody2D
	player.active_weapon_id = "fists"
	player.set_physics_process(false)
	check(room.inline_mode and room.is_bank, "Bank uses the physical inline room")
	check(not door.show_entrance_marker and not door.show_interaction_prompt and not door.handle_input_locally, "Door has no marker or E entry")
	check(not world.get_node("Interiors")._door_configs.has("District/NorthFrontage0/RobberyEntrance"), "Door has no teleport destination")
	check(building.get_node_or_null("BuildingSolid") == null, "Old whole-building blocker removed")
	var outside := door.to_global(Vector2(0, 25))
	var middle: Vector2 = room.to_global(room.project_floor(Vector2(0, 2.2)))
	player.global_position = outside
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	await physics_frames(50)
	check(door.open_amount > .55 and room.inline_door_blocker.disabled, "Proximity opens physical door")
	check(await walk_bank(player, middle), "Walk through threshold without teleport")
	await physics_frames(5)
	check(room.actor_inside() and player.get_meta("harbor_interior", false), "Bank occupancy activates in place")
	check(building.get_meta("bank_inline_occupied", false) and player.get_node("Camera").has_meta("compact_interior"), "Roof is cut and camera moves close")
	check(room.view.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Occupied room renders its depth view")
	check(player.has_meta("interior_actor_presentation"), "Player shares the bank's 3D depth buffer")
	for person in room.guards + room.civilians:
		check(person.has_meta("interior_actor_presentation"), "Resident shares bank depth: " + String(person.name))
	if DisplayServer.get_name() != "headless":
		await verify_depth(room, player.get_meta("interior_actor_presentation"), "Player")
		await verify_depth(room, room.guards[0].get_meta("interior_actor_presentation"), "Guard")
	var footprint := Rect2(building.global_position - building.footprint * .5, building.footprint)
	check(footprint.has_point(room.to_global(room.project_floor(Vector2(-6.8,-4.8)))) and footprint.has_point(room.to_global(room.project_floor(Vector2(6.8,4.8)))), "Floor fits inside authored bank footprint")
	var counter: Vector2 = room.to_global(room.project_floor(Vector2(-4.5,-1)))
	check(player.move_and_collide(counter - player.global_position) != null, "Player cannot cross teller furniture")
	player.global_position = middle
	player.reset_physics_interpolation()
	var bank_solids := room.get_node_or_null("BankVisualSolids") as StaticBody2D
	check(bank_solids != null and bank_solids.get_child_count() > 6, "Rendered bank walls and furniture project to collision")
	var probe_guard: CharacterBody2D = room.guards[0]
	probe_guard.set_physics_process(false)
	var counter_goal: Vector2 = room.to_global(room.project_floor(Vector2(-4.5,-1.0)))
	check(probe_guard.move_and_collide(counter_goal - probe_guard.global_position) != null, "Real guard cannot pass through the teller counter")
	player.active_weapon_id = "pistol"
	player.weapon_aim_active = true
	room._process(.2)
	check(room.armed_warning and not room.alarm_started, "Drawing a gun warns before the alarm")
	player.set("_respawn_grace_active", true)
	player.weapon_fired.emit()
	check(room.alarm_started and room.shots_fired, "First shot starts bank heist")
	for guard in room.guards: guard.take_damage(1000, true)
	await physics_frames(5)
	check(room.keycard_available, "Guards still drop the security card")
	room.set_process(false)
	player.global_position = room.keycard_position
	room._tick_vault(1.3, true)
	check(room.keycard_taken, "Card can be collected inside physical footprint")
	player.global_position = room.to_global(room.vault_position)
	room._tick_vault(.7, true)
	check(room.lockpick.active, "Vault still requires lockpick interaction")
	room.lockpick.finish(false)
	room._unlock_vault()
	room._process(3.1)
	check(room.vault_open and room.vault_body.collision_layer == 0, "Unlocking opens the vault and its collision")
	var money_before: int = player.money
	var achievements_before: Array = player.unlocked_achievements.duplicate()
	player.global_position = room.to_global(room.loot_positions[0])
	room._tick_vault(1.3, true)
	var achievement_bonus := 0
	for id in player.unlocked_achievements:
		if id not in achievements_before: achievement_bonus += AchievementCatalog.cash_reward(id)
	check(player.money == money_before + 4000 + achievement_bonus, "Vault loot pays the authored amount plus any separate achievement")
	money_before = player.money
	room._tick_vault(1.3, true)
	check(player.money == money_before, "Vault loot cannot duplicate")
	room.set_process(true)
	player.global_position = middle
	player.reset_physics_interpolation()
	check(await walk_bank(player, outside), "Walk back out through the same door")
	await physics_frames(8)
	check(not room.actor_inside() and not player.has_meta("harbor_interior"), "Exit restores exterior state")
	check(not building.get_meta("bank_inline_occupied", false) and not player.get_node("Camera").has_meta("compact_interior"), "Roof and exterior camera return")
	check(room.view.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "Empty bank suspends continuous rendering")
	print("BANK INLINE: %d passed, %d failed" % [passed_count, failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)

func walk_bank(actor: CharacterBody2D, target: Vector2) -> bool:
	for _step in 210:
		var motion := target - actor.global_position
		if motion.length() < 3.0: return true
		var hit := actor.move_and_collide(motion.limit_length(2.4))
		if hit != null:
			print("BANK ROUTE BLOCKED ", hit.get_collider().get_path(), " at=", actor.global_position, " target=", target)
			return false
		await physics_frame
	return false

func verify_depth(room: Node2D, adapter: Node, label: String) -> void:
	adapter._update_scale()
	adapter.set_process(false)
	var anchor: Node3D = adapter.anchor
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4,4,.2)
	panel.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("427766")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = material
	room.view.add_child(panel)
	panel.position = anchor.position + Vector3.UP + (room.room_camera.position-anchor.position).normalized()*1.5
	panel.look_at(room.room_camera.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden_actor: Image = room.view.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden_empty: Image = room.view.get_texture().get_image()
	var pixel: Vector2 = room.room_camera.unproject_position(anchor.position+Vector3.UP*.9)
	check(changed_pixels(hidden_actor,hidden_empty,pixel)==0,label+" is hidden by an opaque wall")
	panel.hide()
	anchor.show()
	await process_frame
	await RenderingServer.frame_post_draw
	var visible_actor: Image = room.view.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var visible_empty: Image = room.view.get_texture().get_image()
	check(changed_pixels(visible_actor,visible_empty,pixel)>100,label+" is visible on open floor")
	panel.queue_free()
	anchor.show()
	adapter.set_process(true)

func changed_pixels(a: Image, b: Image, center: Vector2) -> int:
	var changed := 0
	for y in range(maxi(0,int(center.y)-25),mini(a.get_height(),int(center.y)+25)):
		for x in range(maxi(0,int(center.x)-20),mini(a.get_width(),int(center.x)+20)):
			if a.get_pixel(x,y) != b.get_pixel(x,y): changed += 1
	return changed
