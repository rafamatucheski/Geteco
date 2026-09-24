extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "ammunation_inline"
	arm_watchdog(240)
	isolate_saves(_tag)
	skip_onboarding_flags()
	var world := await boot_harbor(15)
	while not world.gameplay_ready:
		await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	var manager: Node2D = world.get_node("Interiors")
	var room: Node2D = manager.ammunation_interior
	var facade: Node2D = world.get_node("District/NorthFrontage2/AmmunationBranchFacade")
	var door: BuildingEntrance = world.get_node("District/NorthFrontage2/AmmunationEntrance")
	var camera: Camera2D = player.get_node("Camera")
	check(room.inline_mode and room.global_position.distance_to(facade.global_position) < 1.0, "Sales floor occupies the exterior building")
	check(room.exit_door == null and room.floor_polygon.size() == 4, "In-place floor has no portal exit")
	check(facade.get_node("DoorLeaves") != null, "Only the door opening is gated")
	var outside := room.to_global(room.floor_point(Vector2(0,3.55)))
	player.global_position = outside
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	camera.reset_smoothing()
	await physics_frames(8)
	check(not room.contains_point(player.global_position) and not room.room_sprite.visible, "Street keeps roof on before entry")
	check(not door.show_entrance_marker and not door.get_node("EntranceMarker").visible, "Harbor Ammu-Nation has no orange entrance marker")
	check(not door.handle_input_locally and not manager._door_configs.has("District/NorthFrontage2/AmmunationEntrance"), "Entry has no E action or teleport destination")
	var before_e := player.global_position
	await press_key(KEY_E)
	await physics_frames(4)
	check(player.global_position.distance_to(before_e) < 2.0 and not room._occupied, "E outside does not enter the shop")
	await _shot("before")
	var inside := room.to_global(room.floor_point(Vector2(0,1.6)))
	check(await walk_to(player, inside, 180, 9), "Player crosses doorway by walking")
	await physics_frames(8)
	check(room.contains_point(player.global_position) and room.room_sprite.visible and not facade.sprite_3d.visible, "Roof hides and cutaway appears inside")
	check(player.global_position.distance_to(door.global_position) < 140 and camera.has_meta("compact_interior"), "No distant teleport; camera zooms on building")
	await _shot("inside")
	check(await walk_to(player, room.to_global(room.merchant_point), 180, 9), "Clear central aisle reaches the clerk")
	check(room.merchant_prompt.text.is_empty() and not room.merchant_prompt.visible, "No floating buy message over Harbor clerk")
	await press_key(KEY_E)
	check(room.active and player.is_in_dialogue, "Existing catalog opens at counter")
	await press_key(KEY_ESCAPE)
	check(not room.active and not player.is_in_dialogue, "Catalog closes and movement resumes")
	player.global_position = room.to_global(room.floor_point(Vector2(0,.12)))
	player.velocity = Vector2.ZERO
	await physics_frames(4)
	check(not await walk_to(player, room.to_global(room.floor_point(Vector2(0,-1.62))), 65, 8), "Counter blocks player")
	player.global_position = room.to_global(room.floor_point(Vector2(2.55,.25)))
	player.velocity = Vector2.ZERO
	await physics_frames(4)
	check(not await walk_to(player, room.to_global(room.floor_point(Vector2(3.85,.25))), 65, 8), "Side stock blocks player")
	for solid_name in ["RearWall", "LeftWall", "RightWall", "LeftFront", "RightFront", "ServiceCounter", "StaffOnly", "LeftStock", "RightStock"]:
		check(room.get_node_or_null(solid_name) is StaticBody2D, "Visible solid has projected collision: " + solid_name)
	var visitor := preload("res://characters/AnimatedPedestrian3D.gd").new()
	world.add_child(visitor)
	visitor.set_physics_process(false)
	visitor.global_position = room.to_global(room.floor_point(Vector2(0,.2)))
	var visitor_helper := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
	world.add_child(visitor_helper)
	visitor_helper.configure(visitor, room.camera, room.room_sprite)
	await physics_frames(4)
	await _shot("npc-front")
	var visitor_hit := visitor.move_and_collide(room.to_global(room.floor_point(Vector2(0,-1.7))) - visitor.global_position)
	check(visitor_hit != null and visitor_hit.get_collider().name in ["ServiceCounter", "StaffOnly"], "Real pedestrian collides with counter")
	await _check_occlusion(room, visitor, visitor_helper)
	visitor_helper.restore()
	visitor_helper.queue_free()
	visitor.queue_free()
	player.global_position = room.to_global(room.floor_point(Vector2(0,1.55)))
	player.velocity = Vector2.ZERO
	await physics_frames(8)
	check(await walk_to(player, outside, 180, 10), "Player exits through same door by walking")
	await physics_frames(8)
	check(not room._occupied and facade.sprite_3d.visible and not camera.has_meta("compact_interior"), "Roof and exterior camera restore")
	check(room.room_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Empty Harbor shop stops 3D rendering")
	var mountain := preload("res://world/mountain_pass/MountainInteriorManager.gd").new()
	mountain.position = Vector2(60000,0)
	world.add_child(mountain)
	while not mountain.region_ready:
		await process_frame
	var mountain_facade := preload("res://world/mountain_pass/MountainGunShopFacade.gd").new()
	mountain_facade.position = Vector2(48000,10000)
	world.add_child(mountain_facade)
	mountain_facade.install_entrance(mountain)
	var mountain_room: Node2D = mountain.ammunation_interior
	check(mountain_room.inline_mode and mountain_room.global_position.distance_to(mountain_facade.global_position) < 1.0, "Mountain floor occupies its own building")
	check(not mountain_facade.entrance.show_entrance_marker and not mountain_facade.entrance.get_node("EntranceMarker").visible, "Mountain Ammu-Nation has no orange entrance marker")
	check(not mountain_facade.entrance.handle_input_locally, "Mountain entry has no E action")
	# This isolated mountain fixture sits outside Harbor's playable perimeter.
	# Production MountainPass has its own world boundary instead.
	player.set_meta("police_exterior_position", mountain_facade.global_position)
	player.global_position = mountain_room.to_global(mountain_room.floor_point(Vector2(0,3.6)))
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	camera.reset_smoothing()
	await physics_frames(8)
	check(await walk_to(player, mountain_room.to_global(mountain_room.floor_point(Vector2(0,1.55))), 200, 9), "Mountain entrance is walkable without E")
	await physics_frames(8)
	check(mountain_room._occupied and mountain_room.room_sprite.visible and not mountain_facade.sprite_3d.visible, "Mountain roof cuts away")
	await _shot("mountain-inside")
	check(await walk_to(player, mountain_room.to_global(mountain_room.merchant_point), 180, 9), "Mountain clerk reachable")
	check(mountain_room.merchant_prompt.text.is_empty() and not mountain_room.merchant_prompt.visible, "No floating buy message over mountain clerk")
	await press_key(KEY_E)
	check(mountain_room.active, "Mountain catalog remains usable")
	await press_key(KEY_ESCAPE)
	check(await walk_to(player, mountain_room.to_global(mountain_room.floor_point(Vector2(0,3.6))), 200, 10), "Mountain exit is walkable")
	await physics_frames(8)
	check(not mountain_room._occupied and mountain_facade.sprite_3d.visible and not camera.has_meta("compact_interior"), "Mountain roof and exterior camera restore")
	check(mountain_room.room_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Empty mountain shop stops 3D rendering")
	print("AMMUNATION INLINE: %d passed, %d failed" % [passed_count, failures.size()])
	world.queue_free()
	await process_frame
	cleanup_isolated_saves()
	quit(0 if failures.is_empty() else 1)

func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var dir := OS.get_temp_dir().path_join("geteco-ammunation-cutaway-0922")
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join("test-%s.png" % label))

func _check_occlusion(room: Node2D, visitor: Node2D, helper: Node) -> void:
	if DisplayServer.get_name() == "headless": return
	visitor.global_position = room.to_global(room.floor_point(Vector2(0,.3)))
	helper._update_scale()
	helper.set_process(false)
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4,4,.2)
	panel.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("427766")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = material
	room.room_view.add_child(panel)
	panel.position = helper.anchor.position + Vector3.UP + (room.camera.position - helper.anchor.position).normalized() * 1.5
	panel.look_at(room.camera.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	var with_actor: Image = room.room_view.get_texture().get_image()
	helper.anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var without_actor: Image = room.room_view.get_texture().get_image()
	var pixel: Vector2 = room.camera.unproject_position(helper.anchor.position + Vector3.UP * .9)
	var hidden_difference := _changed_pixels(with_actor, without_actor, pixel)
	check(hidden_difference == 0, "Opaque fixture occludes the real pedestrian")
	panel.hide()
	helper.anchor.show()
	await process_frame
	await RenderingServer.frame_post_draw
	with_actor = room.room_view.get_texture().get_image()
	helper.anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	without_actor = room.room_view.get_texture().get_image()
	var visible_difference := _changed_pixels(with_actor, without_actor, pixel)
	check(visible_difference > 100, "Visible pedestrian is positive depth control")
	print("AMMUNATION DEPTH hidden=%d visible=%d" % [hidden_difference, visible_difference])
	panel.queue_free()
	helper.anchor.show()
	helper.set_process(true)

func _changed_pixels(a: Image, b: Image, center: Vector2) -> int:
	var changed := 0
	for y in range(maxi(0, int(center.y)-25), mini(a.get_height(), int(center.y)+25)):
		for x in range(maxi(0, int(center.x)-20), mini(a.get_width(), int(center.x)+20)):
			if a.get_pixel(x,y) != b.get_pixel(x,y): changed += 1
	return changed

func release_movement() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)

func walk_to(actor: CharacterBody2D, target: Vector2, max_frames: int = 240, tolerance: float = 10.0) -> bool:
	for _i in max_frames:
		var delta := target - actor.global_position
		if delta.length() <= tolerance:
			release_movement()
			return true
		var direction := delta.normalized()
		for pair in [["move_right", direction.x], ["move_left", -direction.x], ["move_down", direction.y], ["move_up", -direction.y]]:
			if pair[1] > .15: Input.action_press(pair[0])
			else: Input.action_release(pair[0])
		await physics_frame
		Input.action_release("move_left")
		Input.action_release("move_right")
		Input.action_release("move_up")
		Input.action_release("move_down")
	return actor.global_position.distance_to(target) <= tolerance
