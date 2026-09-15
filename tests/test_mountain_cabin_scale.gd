extends SceneTree
var failures := 0
func _init() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value:
		failures += 1
func settle() -> void:
	for i in 4:
		await physics_frame
func run() -> void:
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/mountain-rebuild-0913/saves-cabin/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	# Match streaming: camera/physics setup happens after the engine's first frame.
	await process_frame
	var scene = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await settle()
	var actor = scene.player_instance
	actor.set_physics_process(false)
	var manager = scene.interior_manager
	var cabin = manager.cabin_interior
	var entrance: BuildingEntrance
	for door in manager._exterior_doors:
		if manager._exterior_doors[door]["interior_id"] == &"mountain_cabin":
			entrance = door
			break
	check(entrance != null, "cabin exterior found")
	actor.global_position = entrance.global_position + Vector2(0, 24)
	await settle()
	check(entrance.request_interaction(actor), "real cabin entrance accepts player")
	await create_timer(0.35).timeout
	check(actor.global_position.distance_to(cabin.spawn_point.global_position) < 1, "projected cabin spawn")
	check(actor.sprite_3d_display.scale.x * actor.viewport_3d.size.x > 62, "cabin human scale calibrated")
	for pickup in cabin._active_weapon_stations:
		var floor_point := Vector2(pickup.model.position.x, pickup.model.position.z)
		check(pickup.position.distance_to(cabin.project_floor(floor_point)) < 0.01, "streamed pickup matches visible floor position: " + pickup.weapon_id)
	for route_to_wall in [
		[Vector2(0, 3.5), Vector2(0, 6)],
		[Vector2(-6.3, 0), Vector2(-8, 0)],
		[Vector2(6.2, 2), Vector2(8, 2)],
		[Vector2(3, -3), Vector2(3, -6)],
	]:
		actor.global_position = cabin.to_global(cabin.project_floor(route_to_wall[0]))
		var hit = actor.move_and_collide(cabin.to_global(cabin.project_floor(route_to_wall[1])) - actor.global_position)
		check(hit != null and hit.get_collider() == cabin.walls_body, "streamed cabin perimeter blocks walking into blackout")
	actor.global_position = cabin.spawn_point.global_position
	var clip_hit = actor.move_and_collide(Vector2(0, 500))
	var visible_bottom: float = cabin.to_global(cabin.sprite_3d.position + Vector2(0, cabin.viewport_3d.size.y * cabin.sprite_3d.scale.y * 0.5)).y
	check(clip_hit != null and actor.global_position.y < visible_bottom, "clipped front of floor blocks access to black area")
	for pickup in cabin._active_weapon_stations:
		actor.global_position = cabin.to_global(cabin.project_floor(Vector2(pickup.model.position.x, pickup.model.position.z)))
		await settle()
		check(pickup.collected and not pickup.model.visible, "visible weapon collects through physics: " + pickup.weapon_id)
	actor.global_position = cabin.spawn_point.global_position
	check(cabin.viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "occupied cabin animates effects")
	var effect = cabin.cabin_3d_world.get_node("LivingHearth")
	var previous: float = effect.clock
	await create_timer(0.15).timeout
	check(effect.clock > previous and effect.flames.size() == 5 and effect.wisps.size() == 7, "subtle fire and wisps animate")
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = 1
	query.position = cabin.global_position + cabin.project_floor(Vector2(0, -1.2))
	query.exclude = [actor.get_rid()]
	check(not scene.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "coffee table has projected collision")
	var route := [Vector2(0, 3), Vector2(0, 0.3), Vector2(1.2, 0.3), Vector2(1.2, -2.4)]
	actor.global_position = cabin.global_position + cabin.project_floor(route[0])
	for i in range(1, route.size()):
		var destination: Vector2 = cabin.global_position + cabin.project_floor(route[i])
		var collision: KinematicCollision2D = actor.move_and_collide(destination - actor.global_position)
		check(collision == null, "cabin circulation segment " + str(i))
		await settle()
	if "--capture" in OS.get_cmdline_user_args():
		actor.global_position = cabin.global_position + cabin.project_floor(Vector2(0, 0.4))
		scene.main_camera.reset_smoothing()
		await settle()
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/mountain-cabin-human-scale.png")
	actor.global_position = cabin.exit_door.global_position + Vector2(0, -25)
	await settle()
	check(cabin.exit_door.request_interaction(actor), "real cabin exit works")
	await create_timer(0.35).timeout
	check(not actor.has_meta("mountain_interior") and is_equal_approx(actor.sprite_3d_display.scale.x, 0.34), "exterior scale and shelter restored")
	check(cabin.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "empty cabin stops rendering")
	previous = effect.clock
	await create_timer(0.1).timeout
	check(is_equal_approx(effect.clock, previous), "empty cabin suspends effects")
	# Enter again and exercise the actual respawn path that bypasses the door.
	actor.global_position = entrance.global_position + Vector2(0, 24)
	await create_timer(0.8).timeout
	await settle()
	check(entrance.request_interaction(actor), "cabin reentry accepts player")
	await create_timer(0.35).timeout
	var presentation = actor.get_meta("interior_actor_presentation")
	actor.global_position += Vector2(8,0)
	await settle()
	check(presentation.anchor.global_position.distance_to(presentation.floor_position(actor.global_position))<.01,"reentered cabin keeps the animated rig following Dante")
	actor._respawn_at_hospital()
	actor.set_physics_process(false)
	await settle()
	var recovery: Node2D = scene.get_node("MountainExpedition/SnowOutfitters/MountainRecoverySpawn")
	check(actor.global_position.distance_to(recovery.global_position) < 1, "mountain recovery stays at the relocated shelter inside isolated region")
	check(not actor.has_meta("mountain_interior") and actor.viewport_3d.size == Vector2i(128, 128), "respawn restores exterior presentation")
	# A save from the old layout can place Dante inside a now-solid armchair.
	actor.global_position = cabin.to_global(cabin.project_floor(Vector2(2.2, -1.2)))
	scene.restore_region_interior(actor, {"interior": "mountain_cabin", "exterior_return": [7350, 730]})
	await settle()
	check(actor.model_root.get_viewport() == cabin.viewport_3d and not actor.sprite_3d_display.visible, "save restore uses shared interior depth")
	check(actor.global_position.distance_to(cabin.spawn_point.global_position) < .01, "invalid old save is recovered onto the clear spawn")
	manager._on_exit_requested(null, actor, &"", null, &"", &"mountain_cabin")
	await settle()
	check(actor.model_root.get_viewport() == actor.viewport_3d and actor.sprite_3d_display.visible, "exit after save restore returns the original rig")
	scene.queue_free()
	await process_frame
	print("CABIN SCALE FAILURES: ", failures)
	quit(failures)
