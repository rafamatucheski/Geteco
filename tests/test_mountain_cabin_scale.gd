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
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var scene = load("res://district/mountain_pass/MountainPass.tscn").instantiate()
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
	actor._respawn_at_hospital()
	actor.set_physics_process(false)
	await settle()
	check(actor.global_position.distance_to(Vector2(5980, 635)) < 1, "mountain recovery stays inside isolated region")
	check(not actor.has_meta("mountain_interior") and actor.viewport_3d.size == Vector2i(128, 128), "respawn restores exterior presentation")
	scene.queue_free()
	await process_frame
	print("CABIN SCALE FAILURES: ", failures)
	quit(failures)
