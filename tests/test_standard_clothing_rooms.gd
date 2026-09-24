extends "res://tests/test_projected_interior_contract.gd"

func walk_to(actor: CharacterBody2D, target: Vector2) -> bool:
	for step in 240:
		var motion := target - actor.global_position
		if motion.length() < 1: return true
		if actor.move_and_collide(motion.limit_length(4)) != null: return false
		await physics_frame
	return false

func run() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	artifact_dir = "res://docs/measurements/interior-standard-0920/"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var saves := root.get_node("SaveManager")
	saves._save_dir = "user://standard-clothing-validation/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	var mountain = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(mountain)
	current_scene = mountain
	world = mountain
	while not mountain.region_ready or not mountain.interior_manager.region_ready: await process_frame
	var player: CharacterBody2D = mountain.player_instance
	player.set_physics_process(false)
	var manager = mountain.interior_manager
	var layouts := {}
	# Boutique Alpina now occupies its facade; its walking transition and compact
	# floor are covered by test_boutique_inline.gd instead of this portal flow.
	for id in [&"mountain_outfitters", &"mountain_village_outfitters"]:
		var door: BuildingEntrance
		var count := 0
		for candidate in manager._exterior_doors:
			if manager._exterior_doors[candidate].interior_id == id:
				door = candidate
				count += 1
		check(count == 1, "Unique shop access " + String(id))
		player.global_position = door.global_position + Vector2(0, 24)
		for frame in 4: await physics_frame
		check(door.request_interaction(player), "Real shop entry " + String(id))
		await create_timer(.35).timeout
		cabin = manager._interiors[id]
		check(player.global_position.distance_to(cabin.spawn_point.global_position) < 1, "Clear shop spawn " + String(id))
		check(player.model_root.get_viewport() == cabin.viewport_3d, "Shop shares actor depth " + String(id))
		var signature := str(preload("res://systems/interiors/InteriorSolidProjection.gd").mesh_bounds(cabin.room_model))
		check(not layouts.has(signature), "Distinct shop layout " + String(id))
		layouts[signature] = true
		if DisplayServer.get_name() != "headless":
			for frame in 20: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(artifact_dir + String(id) + "-standard.png")
		var reward = cabin.get_node("ShopCash")
		var money: int = player.money
		check(await walk_to(player, reward.global_position), "Shop reward route " + String(id))
		for frame in 4: await physics_frame
		check(reward.collected and player.money == money + reward.amount, "Shop cash contact " + String(id))
		check(await walk_to(player, cabin.to_global(cabin.project_floor(Vector2(0, 1.5)))), "Return to shop aisle " + String(id))
		check(await walk_to(player, cabin.to_global(cabin.project_floor(Vector2(0, -2)))), "Main shop aisle " + String(id))
		check(await walk_to(player, cabin.to_global(cabin._counter_point)), "Approach checkout " + String(id))
		var interact := InputEventAction.new()
		interact.action = "interact"
		interact.pressed = true
		cabin._unhandled_input(interact)
		check(cabin.shop.is_active, "Checkout interaction opens store " + String(id))
		player.money = 5000
		var already_owned: bool = player.owned_outfits.get("dante_arctic", false)
		cabin.shop._select_outfit("dante_arctic")
		cabin.shop._on_action_pressed()
		check(player.current_outfit_id == "dante_arctic" and player.money == (5000 if already_owned else 3200), "Winter purchase preserves pricing " + String(id))
		cabin.shop.close_store()
		var helper = manager._actor_scale_helpers[player]
		if DisplayServer.get_name() != "headless": await check_depth_occlusion(player, helper)
		helper.set_process(true)
		var npc := preload("res://characters/AnimatedPedestrian3D.gd").new()
		mountain.add_child(npc)
		npc.set_physics_process(false)
		npc.global_position = cabin.spawn_point.global_position
		var npc_helper := PRESENTATION.new()
		mountain.add_child(npc_helper)
		npc_helper.configure(npc, cabin.camera_3d, cabin.sprite_3d)
		for pair in [[player, helper], [npc, npc_helper]]:
			var actor: CharacterBody2D = pair[0]
			var presentation: Node = pair[1]
			for shape in cabin.walls_body.get_children():
				var rect: Rect2 = shape.get_meta("model_floor_rect")
				for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]:
					actor.global_position = cabin.to_global(cabin.project_floor(rect.get_center() + direction * (rect.size * .5 + Vector2.ONE)))
					presentation._update_scale()
					await physics_frame
					var target: Vector2 = cabin.to_global(cabin.project_floor(rect.get_center()))
					check(actor.move_and_collide(target - actor.global_position) != null and actor.global_position.distance_to(target) > 1, "Shop solid " + String(shape.name))
		if DisplayServer.get_name() != "headless": await check_depth_occlusion(npc, npc_helper)
		npc_helper.restore()
		npc_helper.queue_free()
		npc.queue_free()
		player.global_position = cabin.spawn_point.global_position
		check(await walk_to(player, cabin.exit_door.global_position + Vector2(0, -18)), "Shop exit route " + String(id))
		for frame in 4: await physics_frame
		check(cabin.exit_door.request_interaction(player), "Real shop exit " + String(id))
		await create_timer(.35).timeout
		check(player.global_position.distance_to(manager._exterior_doors[door].return_pos) < 1, "Correct shop facade return " + String(id))
		check(cabin.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Empty shop stops rendering " + String(id))
	print("STANDARD_CLOTHING failures=", failures, " distinct_layouts=", layouts.size())
	mountain.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
