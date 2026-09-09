extends SceneTree
var failures := 0
var capture := false
func _init() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
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
	var original_scale: Vector2 = actor.sprite_3d_display.scale
	var original_position: Vector2 = actor.sprite_3d_display.position
	var manager = scene.interior_manager
	var bunker = manager.bunker_interior
	var entrance = scene.get_node("MountainExpedition/IceWolvesStronghold/StationZeroEntrance")
	check(bunker.model.get_child_count() > 150, "authored bunker geometry built")
	check(bunker.walls_body.get_child_count() >= 20, "projected collision footprints built")
	check(not bunker.active and not bunker.room_camera.enabled, "empty bunker sleeps")
	check(manager.cabin_interior.exit_door.destination_requested.get_connections().size() == 1, "existing cabin exit now bound")
	check(manager.ammunation_interior.exit_door.destination_requested.get_connections().size() == 1, "existing gun shop exit now bound")
	actor.global_position = entrance.global_position + Vector2(0, 24)
	await settle()
	check(entrance.request_interaction(actor), "real exterior sensor accepts interaction")
	await create_timer(0.35).timeout
	check(actor.global_position.distance_to(bunker.spawn_point.global_position) < 1, "entrance arrives at bunker spawn")
	check(actor.get_meta("mountain_interior_id", "") == &"mountain_bunker", "interior identity tracks shelter")
	check(actor.sprite_3d_display.scale.x * actor.viewport_3d.size.x > original_scale.x * 128 * 1.5, "human scale matches bunker furnishings")
	check(bunker.active and root.get_camera_2d() == bunker.room_camera, "bunker activates framed camera")
	check(scene.storm_manager.sheltered and not scene.storm_manager.visible, "no precipitation in bunker")
	var query := PhysicsPointQueryParameters2D.new()
	query.position = bunker.global_position + bunker.project_floor(Vector2(0, -4.2))
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	check(not scene.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "command desk physically blocks player")
	query.position = bunker.global_position + bunker.project_floor(Vector2(0, 0))
	check(scene.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "central approach remains clear")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	actor.global_position = bunker.global_position + bunker.console_position
	bunker._unhandled_key_input(key)
	check(bunker.note_open and bunker.note_text.text.contains("CANAL 07"), "radio gives local narrative")
	bunker._unhandled_key_input(key)
	check(not bunker.note_open, "radio note closes")
	actor.global_position = bunker.global_position + bunker.route_position
	bunker._unhandled_key_input(key)
	check(bunker.note_open and bunker.note_text.text.contains("MAPA"), "route map gives desert foreshadowing")
	bunker._unhandled_key_input(key)
	# Sweep the real player capsule along the circulation route, not only points.
	var route := [Vector2(0, 4.3), Vector2(0, 1.2), Vector2(6.6, 1.2), Vector2(6.6, -3.15), Vector2(6.6, 1.2), Vector2(-5.4, 1.2), Vector2(-5.4, -3), Vector2(-5.4, 1.2), Vector2(0, 1.2), Vector2(0, -3)]
	actor.global_position = bunker.global_position + bunker.project_floor(route[0])
	for i in range(1, route.size()):
		var destination: Vector2 = bunker.global_position + bunker.project_floor(route[i])
		var collision: KinematicCollision2D = actor.move_and_collide(destination - actor.global_position)
		check(collision == null, "walkable route segment " + str(i))
	if capture:
		actor.global_position = bunker.global_position + bunker.project_floor(Vector2(0, 1))
		await settle()
		for i in 15:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/mountain-bunker-interior.png")
	actor.global_position = bunker.exit_door.global_position + Vector2(0, -25)
	await settle()
	check(bunker.exit_door.request_interaction(actor), "real interior sensor accepts exit")
	await create_timer(0.35).timeout
	check(actor.global_position.distance_to(Vector2(6500, -2790)) < 1, "exit returns to safe forecourt")
	check(not actor.has_meta("mountain_interior") and not bunker.active, "exit clears shelter and deactivates bunker")
	check(actor.sprite_3d_display.scale.is_equal_approx(original_scale) and actor.sprite_3d_display.position.is_equal_approx(original_position), "exterior restores original player proportions")
	check(root.get_camera_2d() == scene.main_camera, "exterior restores player camera")
	check(scene.storm_manager.visible, "snow resumes on exterior")
	check(scene.has_node("HarborReturnCrossing"), "district has official Harbor return")
	scene.queue_free()
	await process_frame
	print("BUNKER FAILURES: ", failures)
	quit(failures)
