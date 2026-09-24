extends "res://tests/test_projected_interior_contract.gd"

class RoomProbe extends Node2D:
	var source: Node2D
	var viewport_3d: SubViewport
	var camera_3d: Camera3D
	func project_floor(point: Vector2) -> Vector2:
		# Keep the positive depth control in a clear aisle between parked trucks.
		if source.name == "FireStationInterior" and point == Vector2(0,.4): point = Vector2(3.4,5)
		if source.has_method("project_floor"): return source.project_floor(point)
		return source.showroom.position + source.showroom.project_floor(point)

func walk_to(actor: CharacterBody2D, target: Vector2) -> bool:
	for step in 240:
		var motion := target - actor.global_position
		if motion.length() < 1: return true
		if actor.move_and_collide(motion.limit_length(4)) != null: return false
		await physics_frame
	return false

func run() -> void:
	create_timer(600).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	artifact_dir = "res://docs/measurements/interior-standard-0920/"
	var saves := root.get_node("SaveManager")
	saves._save_dir = "user://standard-harbor-validation/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_call_complete", true)
	var city = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(city)
	current_scene = city
	world = city
	while not city.gameplay_ready: await process_frame
	for frame in 8: await process_frame
	var player: CharacterBody2D = city.get_node("Player")
	player.set_physics_process(false)
	var manager = city.get_node("Interiors")
	var swept := 0
	var seen := {}
	for path in manager._door_configs:
		var config: Dictionary = manager._door_configs[path]
		var room = config.interior
		if String(room.name) not in ["PoliceInterior", "ClinicInterior", "CemeteryKeeperInterior", "ClothingRoom0", "AmmunationInterior", "FuelInterior", "BankInterior", "FireStationInterior", "GarageInterior"]: continue
		if not OS.get_cmdline_user_args().is_empty() and String(room.name) not in OS.get_cmdline_user_args(): continue
		if seen.has(room): continue
		seen[room] = true
		var entrance = city.get_node(path)
		var authored_positions := {}
		for resident in room.find_children("*", "CharacterBody2D", true, false):
			if not resident.is_in_group("vehicle"): authored_positions[resident] = resident.global_position
		manager._on_exterior_destination_requested(entrance, player, config.id, null, &"", room, config.spawn)
		for resident in authored_positions:
			if resident.has_meta("interior_actor_presentation"):
				check(resident.global_position.distance_to(authored_positions[resident]) < .1, "Authored resident spawn is clear " + String(resident.name))
		await create_timer(1).timeout
		check(room.contains_point(player.global_position), "Actual entry " + String(room.name))
		check(player.has_meta("interior_actor_presentation"), "Live actor presentation " + String(room.name))
		if not player.has_meta("interior_actor_presentation"): continue
		var helper = player.get_meta("interior_actor_presentation")
		var probe := RoomProbe.new()
		probe.source = room
		probe.viewport_3d = helper.room_viewport
		probe.camera_3d = helper.room_camera
		city.add_child(probe)
		probe.global_position = room.global_position
		cabin = probe
		check(player.model_root.get_viewport() == probe.viewport_3d, "Player shares room depth " + String(room.name))
		check(probe.viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Continuous occupied room " + String(room.name))
		for resident in room._resident_presentations:
			check(room._resident_presentations[resident].room_viewport == probe.viewport_3d, "Resident shares room depth " + String(resident.name))
		for frame in 15: await process_frame
		if String(room.name) in ["GarageInterior", "FireStationInterior"]:
			# Vehicle boarding releases this adapter. Once pedestrian control has
			# returned, the occupied room must recover the shared depth presentation.
			helper.restore()
			for frame in 3: await process_frame
			check(player.has_meta("interior_actor_presentation"), "Pedestrian depth rebinds after adapter release " + String(room.name))
			if player.has_meta("interior_actor_presentation"): helper = player.get_meta("interior_actor_presentation")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(artifact_dir + String(room.name) + "-standard.png")
		var reward = room.get_node_or_null("RoomCash")
		if reward == null: reward = room.get_node_or_null("ShopCash")
		if reward != null:
			var before: int = player.money
			check(await walk_to(player, reward.global_position), "Walk to cash " + String(room.name))
			for frame in 4: await physics_frame
			check(reward.collected and player.money == before + reward.amount, "Cash collected by walking " + String(room.name))
		if String(room.name) == "ClinicInterior":
			player.health = 30
			check(await walk_to(player, room.to_global(room.project_floor(Vector2(0,-1)))), "Hospital central aisle")
			check(await walk_to(player, room.health_pickup.global_position), "Hospital health route")
			for frame in 5: await physics_frame
			check(player.health == player.max_health, "Hospital restores health by contact")
		if String(room.name) == "ClothingRoom0":
			check(not room.shop.preview_3d.rig.has_meta("interior_actor_presentation"), "Fitting preview is not a room resident")
			check(await walk_to(player, room.to_global(room.project_floor(Vector2(0,0)))), "Union aisle")
			check(await walk_to(player, room.to_global(room._counter_point)), "Union checkout route")
			var event := InputEventAction.new()
			event.action = "interact"
			event.pressed = true
			room._unhandled_input(event)
			check(room.shop.is_active, "Union checkout opens")
			room.shop.close_store()
		var visitor := preload("res://characters/AnimatedPedestrian3D.gd").new()
		# Sweeps intentionally cross both sides of the perimeter. Keep automatic
		# doorway transfers and proximity presentation teardown out of this phase;
		# the actual entry/exit and interaction phase remains enabled above/below.
		manager.set_physics_process(false)
		room.set_process(false)
		var room_physics_was_active: bool = room.is_physics_processing()
		room.set_physics_process(false)
		var passage: Node = room.get_node_or_null("BankPassage")
		if passage: passage.set_physics_process(false)
		city.set_process(false)
		city.add_child(visitor)
		visitor.set_physics_process(false)
		visitor.global_position = room.spawn_point.global_position
		var visitor_helper := PRESENTATION.new()
		city.add_child(visitor_helper)
		visitor_helper.configure(visitor, helper.room_camera, helper.room_display)
		var shapes: Array = room.find_children("*", "CollisionPolygon2D", true, false)
		shapes.append_array(room.find_children("*", "CollisionShape2D", true, false))
		for pair in [[player, helper], [visitor, visitor_helper]]:
			var actor: CharacterBody2D = pair[0]
			var presentation: Node = pair[1]
			var other: Node2D = visitor if actor == player else player
			other.global_position = room.spawn_point.global_position
			for shape in shapes:
				if not is_instance_valid(shape):
					push_error("Room collision unexpectedly removed during sweep")
					quit(2)
					return
				if not shape.get_parent() is StaticBody2D or shape.disabled: continue
				if (shape.get_parent().collision_layer & 1) == 0: continue
				var bounds := Rect2()
				if shape is CollisionPolygon2D:
					if shape.polygon.is_empty(): continue
					bounds = Rect2(shape.polygon[0], Vector2.ZERO)
					for point in shape.polygon: bounds = bounds.expand(point)
				elif shape.shape is RectangleShape2D:
					bounds = Rect2(-shape.shape.size * .5, shape.shape.size)
				else: continue
				for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
					actor.global_position = shape.to_global(bounds.get_center() + direction * (bounds.size * .5 + Vector2.ONE * 24))
					presentation._update_scale()
					# Closely packed desks have overlapping envelopes. A sweep must
					# start clear, not use depenetration from another piece of furniture.
					var query := PhysicsShapeQueryParameters2D.new()
					query.shape = presentation.collider.shape
					query.collision_mask = 1
					query.exclude = [actor.get_rid()]
					for attempt in 24:
						query.transform = presentation.collider.global_transform
						if actor.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): break
						actor.global_position += direction.normalized()*16
						presentation._update_scale()
					await physics_frame
					var target: Vector2 = shape.to_global(bounds.get_center())
					var hit := actor.move_and_collide(target - actor.global_position)
					var blocked := hit != null and actor.global_position.distance_to(target) > 1
					check(blocked, "Solid " + String(room.name) + "/" + String(shape.name))
					if not blocked: print("SWEEP_DETAIL bounds=",bounds," direction=",direction," hit=",hit!=null," distance=",actor.global_position.distance_to(target)," mask=",actor.collision_mask)
					swept += 1
			await check_depth_occlusion(actor, presentation)
			presentation.set_process(true)
		visitor_helper.restore()
		visitor_helper.queue_free()
		visitor.queue_free()
		player.global_position = room.spawn_point.global_position
		room.set_process(true)
		room.set_physics_process(room_physics_was_active)
		if passage: passage.set_physics_process(true)
		manager.set_physics_process(true)
		city.set_process(true)
		manager._on_exit_door_requested(room.exit_door, player, &"", null, &"", config.id)
		await create_timer(.5).timeout
		check(not player.has_meta("harbor_interior"), "Actual exit " + String(room.name))
		check(probe.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Empty room suspended " + String(room.name))
		print("HARBOR_ROOM_CHECKED room=", room.name, " cumulative_failures=", failures, " cumulative_sweeps=", swept)
		probe.queue_free()
	print("STANDARD_HARBOR failures=", failures, " swept=", swept)
	city.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
