extends "res://tests/test_projected_interior_contract.gd"

class RoomProbe extends Node2D:
	var source: Node2D
	var viewport_3d: SubViewport
	var camera_3d: Camera3D
	func project_floor(_point: Vector2) -> Vector2: return source.project_floor(Vector2(0,3))

func walk_to(actor: CharacterBody2D, target: Vector2) -> bool:
	for step in 320:
		var motion := target-actor.global_position
		if motion.length()<1: return true
		var hit := actor.move_and_collide(motion.limit_length(4))
		if hit:
			print("ROUTE_BLOCK ",hit.get_collider().get_path())
			return false
		await physics_frame
	return false

func run() -> void:
	create_timer(420).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	artifact_dir = "res://docs/measurements/interior-standard-0920/"
	var saves := root.get_node("SaveManager")
	saves._save_dir = "user://remaining-mountain-standard/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	world = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.region_ready or not world.interior_manager.region_ready: await process_frame
	var player: CharacterBody2D = world.player_instance
	player.set_physics_process(false)
	var manager = world.interior_manager
	var swept := 0
	var ids := OS.get_cmdline_user_args()
	if ids.is_empty(): ids = PackedStringArray(["lumberjack_shelter","ski_lodge","mountain_bunker","mountain_mystery_cave","ammunation"])
	for room_id in ids:
		var id := StringName(room_id)
		var room = manager.get_interior(id)
		var door: BuildingEntrance
		for candidate in manager._exterior_doors:
			if manager._exterior_doors[candidate].interior_id == id:
				door = candidate
				break
		check(door != null and door.is_inside_tree(),"Live entrance "+room_id)
		if door == null or not door.is_inside_tree(): continue
		player.global_position = door.global_position+Vector2(0,24)
		for frame in 8: await physics_frame
		check(door.request_interaction(player),"Actual entry "+room_id)
		await create_timer(.4).timeout
		check(player.has_meta("interior_actor_presentation"),"Shared depth presentation "+room_id)
		if not player.has_meta("interior_actor_presentation"): continue
		var helper = player.get_meta("interior_actor_presentation")
		if room_id == "mountain_mystery_cave":
			var solid_inventory := preload("res://systems/interiors/InteriorSolidProjection.gd").mesh_bounds(room.room_view.model)
			for solid_id in [&"ExpeditionCot",&"SupplyCase",&"SecretWeaponCase",&"CampPickaxe",&"CampLantern",&"CacheLantern",&"FoodTins",&"Stalagmite0",&"Stalagmite11"]:
				check(solid_inventory.has(solid_id),"Cave visible solid has model-derived footprint "+String(solid_id))
			check(room.walls_body.find_children("CaveContour*","CollisionPolygon2D",false,false).size() == 11,"Cave collision follows the irregular floor boundary")
		check(player.global_position.distance_to(room.spawn_point.global_position)<1,"Valid spawn "+room_id)
		check(helper.room_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"Continuous occupied viewport "+room_id)
		var probe := RoomProbe.new()
		probe.source = room
		probe.viewport_3d = helper.room_viewport
		probe.camera_3d = helper.room_camera
		world.add_child(probe)
		probe.global_position = room.global_position
		cabin = probe
		for frame in 15: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(artifact_dir+room_id+"-standard-final.png")
		for reward in room.get_children():
			if not reward is Area2D or reward.get("pickup_id") == null: continue
			if room_id == "lumberjack_shelter":
				check(await walk_to(player,room.to_global(room.project_floor(Vector2(2,2.2)))),"Logger east aisle")
				check(await walk_to(player,room.to_global(room.project_floor(Vector2(2,-2.7)))),"Logger axe approach")
			elif room_id == "mountain_mystery_cave":
				check(await walk_to(player,room.to_global(room.project_floor(Vector2(0,2.4)))),"Cave central aisle")
				check(await walk_to(player,room.to_global(room.project_floor(Vector2(3.1,2)))),"Cave RPG approach")
			check(await walk_to(player,reward.global_position),"Walk over reward "+room_id)
			for frame in 5: await physics_frame
			check(reward.collected and player.world_pickups_collected.has(reward.pickup_id),"Persistent contact reward "+room_id)
		if room_id == "mountain_bunker":
			for point in [Vector2(0,1.2),Vector2(6.6,1.2),Vector2(6.6,-3.15)]:
				check(await walk_to(player,room.to_global(room.project_floor(point))),"Bunker radio circulation")
			var radio_key := InputEventKey.new()
			radio_key.physical_keycode = KEY_F
			radio_key.pressed = true
			room._unhandled_key_input(radio_key)
			check(room.note_open and room.note_text.text.contains("CANAL 07"),"Bunker radio remains functional")
			room._unhandled_key_input(radio_key)
			check(not room.note_open,"Bunker radio closes")
		if room_id == "ammunation":
			var vendor: Node3D = room.room_view.find_child("VanceMilitaryGunsmith",true,false)
			var bounds := AABB()
			var initialized := false
			for mesh in vendor.find_children("*","MeshInstance3D",true,false):
				for corner in 8:
					var point: Vector3 = mesh.global_transform * mesh.mesh.get_aabb().get_endpoint(corner)
					if initialized: bounds = bounds.expand(point)
					else:
						bounds = AABB(point,Vector3.ZERO)
						initialized = true
			check(bounds.size.y >= 1.75 and bounds.size.y <= 1.85 and bounds.size.x <= .70,"Merchant has human height and shoulder width")
			print("VENDOR_DIMENSIONS ",bounds.size)
			check(await walk_to(player,room.to_global(room.project_floor(Vector2(1.7,.2)))),"Gunshop central aisle")
			check(await walk_to(player,room.to_global(room.merchant_point)),"Gunshop counter route")
			await create_timer(5).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(artifact_dir+"ammunation-human-scale.png")
			var event := InputEventAction.new()
			event.action = &"interact"
			event.pressed = true
			room._unhandled_input(event)
			check(room.active,"Gunshop catalog opens through input action")
			player.money = 1000
			player.armor = 0
			room.selection = room.stock.find("armor")
			room.change_selection(0)
			var achievements_before: Array = player.unlocked_achievements.duplicate()
			room.purchase()
			var achievement_cash := 0
			for achievement in player.unlocked_achievements:
				if achievement not in achievements_before:
					achievement_cash += AchievementCatalog.cash_reward(achievement)
			check(player.armor == 100 and player.money == 500+achievement_cash,"Gunshop purchase charges once and preserves achievement rewards")
			var money_after: int = player.money
			room.purchase()
			check(player.money == money_after,"Full armor cannot be charged twice")
			room.close_catalog()
		# Isolate physical sweeps from region recovery and automatic exit logic.
		manager.set_process(false)
		room.set_process(false)
		world.set_process(false)
		var visitor := preload("res://characters/AnimatedPedestrian3D.gd").new()
		world.add_child(visitor)
		visitor.set_physics_process(false)
		visitor.global_position = room.spawn_point.global_position
		var visitor_helper := PRESENTATION.new()
		world.add_child(visitor_helper)
		visitor_helper.configure(visitor,helper.room_camera,helper.room_display)
		var shapes: Array = room.find_children("*","CollisionPolygon2D",true,false)
		shapes.append_array(room.find_children("*","CollisionShape2D",true,false))
		for pair in [[player,helper],[visitor,visitor_helper]]:
			var actor: CharacterBody2D = pair[0]
			var presentation: Node = pair[1]
			var other: Node2D = visitor if actor == player else player
			other.global_position = room.spawn_point.global_position
			for shape in shapes:
				if not shape.get_parent() is StaticBody2D or shape.disabled: continue
				var bounds := Rect2()
				if shape is CollisionPolygon2D:
					if shape.polygon.is_empty(): continue
					bounds = Rect2(shape.polygon[0],Vector2.ZERO)
					for point in shape.polygon: bounds = bounds.expand(point)
				elif shape.shape is RectangleShape2D: bounds = Rect2(-shape.shape.size*.5,shape.shape.size)
				else: continue
				for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
					actor.global_position = shape.to_global(bounds.get_center()+direction*(bounds.size*.5+Vector2.ONE*24))
					presentation._update_scale()
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
					var hit := actor.move_and_collide(target-actor.global_position)
					check(hit != null and actor.global_position.distance_to(target)>1,"Solid "+room_id+"/"+String(shape.name))
					swept += 1
			await check_depth_occlusion(actor,presentation)
			presentation.set_process(true)
		visitor_helper.restore()
		visitor_helper.queue_free()
		visitor.queue_free()
		player.global_position = room.spawn_point.global_position
		room.set_process(true)
		manager.set_process(true)
		world.set_process(true)
		player.global_position = room.exit_door.global_position+Vector2(0,-18)
		for frame in 5: await physics_frame
		check(room.exit_door.request_interaction(player),"Actual exit "+room_id)
		await create_timer(.4).timeout
		check(not player.has_meta("mountain_interior"),"Restored exterior "+room_id)
		check(probe.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Vacant room suspended "+room_id)
		probe.queue_free()
		print("ROOM_COMPLETE ",room_id," failures=",failures," sweeps=",swept)
	print("MOUNTAIN_STANDARD failures=",failures," swept=",swept)
	quit(0 if failures == 0 else 1)
