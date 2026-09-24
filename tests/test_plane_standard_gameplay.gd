extends "res://tests/test_remaining_mountain_standard.gd"

func run() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	artifact_dir = "res://docs/measurements/interior-standard-0920/"
	var saves := root.get_node("SaveManager")
	saves._save_dir = "user://plane-standard-gameplay/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	world = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.region_ready: await process_frame
	var actor: CharacterBody2D = world.player_instance
	actor.set_physics_process(false)
	var plane = world.find_child("SmugglerCargoPlane",true,false)
	actor.global_position = plane.to_global(plane.project_floor(Vector2(0,10.5)))
	check(await walk_to(actor,plane.to_global(plane.project_floor(Vector2(0,3)))),"Continuous ramp entry")
	await create_timer(.3).timeout
	check(plane.inside and actor.has_meta("interior_actor_presentation"),"Plane integrates the real player into shared depth")
	var helper = actor.get_meta("interior_actor_presentation")
	check(actor.model_root.get_viewport() == plane.viewport_3d,"Plane actor uses aircraft viewport")
	check(plane.viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"Occupied aircraft animates continuously")
	check(helper.anchor.position.y >= .215,"Feet stand on the cargo deck")
	for frame in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(artifact_dir+"plane-standard-final.png")
	var probe := RoomProbe.new()
	probe.source = plane
	probe.viewport_3d = plane.viewport_3d
	probe.camera_3d = plane.camera_3d
	world.add_child(probe)
	probe.global_position = plane.global_position
	cabin = probe
	await check_depth_occlusion(actor,helper)
	helper.set_process(true)
	var visitor := preload("res://characters/AnimatedPedestrian3D.gd").new()
	world.add_child(visitor)
	visitor.set_physics_process(false)
	visitor.global_position = plane.to_global(plane.project_floor(Vector2(0,1)))
	await create_timer(.3).timeout
	check(visitor.has_meta("interior_actor_presentation"),"Aircraft admits walking NPC to shared depth")
	var visitor_helper = visitor.get_meta("interior_actor_presentation")
	actor.global_position = plane.to_global(plane.project_floor(Vector2(0,5)))
	await check_depth_occlusion(visitor,visitor_helper)
	visitor_helper.set_process(true)
	plane.set_process(false)
	world.set_process(false)
	var swept := 0
	for pair in [[actor,helper],[visitor,visitor_helper]]:
		var walker: CharacterBody2D = pair[0]
		var presentation: Node = pair[1]
		var other: Node2D = visitor if walker == actor else actor
		other.global_position = plane.to_global(plane.project_floor(Vector2(0,6)))
		for shape in plane.find_children("*","CollisionPolygon2D",true,false):
			if not shape.get_parent() is StaticBody2D or shape.disabled: continue
			var bounds := Rect2(shape.polygon[0],Vector2.ZERO)
			for point in shape.polygon: bounds = bounds.expand(point)
			for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN,Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
				walker.global_position = shape.to_global(bounds.get_center()+direction*(bounds.size*.5+Vector2.ONE*24))
				presentation._update_scale()
				var query := PhysicsShapeQueryParameters2D.new()
				query.shape = presentation.collider.shape
				query.collision_mask = 1
				query.exclude = [walker.get_rid()]
				for attempt in 24:
					query.transform = presentation.collider.global_transform
					if walker.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): break
					walker.global_position += direction.normalized()*16
					presentation._update_scale()
				await physics_frame
				var target: Vector2 = shape.to_global(bounds.get_center())
				var hit := walker.move_and_collide(target-walker.global_position)
				check(hit != null and walker.global_position.distance_to(target)>1,"Aircraft solid "+String(shape.get_parent().name))
				swept += 1
	actor.global_position = plane.to_global(plane.project_floor(Vector2(0,3)))
	plane.set_process(true)
	world.set_process(true)
	visitor.queue_free()
	check(await walk_to(actor,plane.to_global(plane.project_floor(Vector2(0,-6.4)))),"Walk through both cargo rows")
	var cash_before: int = actor.money
	plane._process(.2)
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	plane._unhandled_input(event)
	check(plane.collected and actor.money == cash_before+1800,"Mapped interaction opens cargo chest")
	var reward = plane.get_node("CargoSMG")
	check(await walk_to(actor,reward.global_position),"SMG can be collected by walking")
	for frame in 6: await physics_frame
	check(reward.collected and actor.weapon_inventory.get("smg",false),"Walk contact grants SMG")
	check(actor.world_pickups_collected.has(reward.pickup_id) and actor.world_pickups_collected.has(plane.PICKUP_ID),"Both aircraft rewards persist")
	check(not plane.claim_treasure(actor) and actor.money == cash_before+1800,"Cargo chest cannot duplicate money")
	check(await walk_to(actor,plane.to_global(plane.project_floor(Vector2(0,-6.4)))),"Leave reward alcove")
	var late_visitor := preload("res://characters/AnimatedPedestrian3D.gd").new()
	world.add_child(late_visitor)
	late_visitor.set_physics_process(false)
	late_visitor.global_position = plane.to_global(plane.project_floor(Vector2(.7,1)))
	check(await walk_to(actor,plane.to_global(plane.project_floor(Vector2(0,11)))),"Continuous ramp exit")
	await create_timer(.3).timeout
	check(not plane.inside and not actor.has_meta("interior_actor_presentation"),"Exit restores external actor presentation")
	check(actor.model_root.get_viewport() == actor.viewport_3d,"Native player viewport restored")
	check(late_visitor.has_meta("interior_actor_presentation") and plane.viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"Remaining NPC keeps shared aircraft presentation active")
	late_visitor.global_position = plane.to_global(plane.project_floor(Vector2(0,11)))
	await create_timer(.3).timeout
	check(not late_visitor.has_meta("interior_actor_presentation"),"Last NPC restores native presentation on exit")
	check(plane.viewport_3d.render_target_update_mode != SubViewport.UPDATE_ALWAYS,"Empty aircraft returns to cached rendering")
	late_visitor.queue_free()
	print("PLANE_STANDARD_GAMEPLAY failures=",failures," swept=",swept)
	quit(0 if failures==0 else 1)
