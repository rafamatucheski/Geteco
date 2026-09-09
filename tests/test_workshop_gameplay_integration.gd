extends SceneTree

var failures: Array[String] = []
var player: Node2D
var garage: Node2D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func walk(point: Vector3) -> void:
	var target: Vector2 = garage.to_global(garage.workshop_point(point))
	for i in 240:
		var delta := target - player.global_position
		if delta.length() < 2.5: break
		for action in ["ui_left", "ui_right", "ui_up", "ui_down"]: Input.action_release(action)
		var direction := delta.normalized()
		Input.action_press("ui_right" if direction.x > 0 else "ui_left", absf(direction.x))
		Input.action_press("ui_down" if direction.y > 0 else "ui_up", absf(direction.y))
		await physics_frame
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]: Input.action_release(action)
	await physics_frame
	check(player.global_position.distance_to(target) < 4, "Dante walks to " + str(point) + " actual=" + str(garage.to_local(player.global_position)))

func run() -> void:
	create_timer(100).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 30: await process_frame
	var world := current_scene
	var interiors: Node = world.get_node("Interiors")
	garage = interiors.garage_interior
	player = world.get_node("Player")
	var entrance: Node = world.get_node("District/Garage/Entrance")
	interiors._on_exterior_destination_requested(entrance, player, &"", null, &"", garage, garage.spawn_point)
	for i in 4: await physics_frame
	check(not garage.has_node("Floor") and not garage.has_node("MissionBoardZone"), "Legacy 2D room removed")
	check(garage.showroom.viewport_3d.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "Static workshop does not redraw every frame")
	check(player.get_node("Camera").has_meta("compact_interior"), "Gameplay camera frames compact workshop")
	var camera: Camera2D = player.get_node("Camera")
	var screen := camera.get_viewport_rect().size
	var previous_zoom := minf(screen.x / garage.room_size.x, screen.y / garage.room_size.y) * 0.88
	check(is_equal_approx(camera.zoom.x, previous_zoom * 1.2), "Workshop camera is exactly 20 percent closer")
	check(garage.diagnostic_area.position.distance_to(garage.workshop_point(garage.showroom.model.get_interaction_points().workbench)) < 0.01, "Diagnostic interaction follows the repositioned bench")
	await walk(Vector3(1.35, 0, 1.5))
	check(not garage.jager_npc.is_player_nearby, "Glass partition cannot trigger Maciota dialogue")
	await walk(Vector3(3.2, 0, 1.5))
	await walk(Vector3(5.5, 0, 1.5))
	await walk(Vector3(5.5, 0, -0.2))
	await walk(Vector3(4.5, 0, -0.2))
	check(garage.jager_npc.is_player_nearby, "Real actor reaches Maciota desk interaction")
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.keycode = KEY_E
	interact.pressed = true
	Input.parse_input_event(interact)
	Input.flush_buffered_events()
	await process_frame
	interact = interact.duplicate()
	interact.pressed = false
	Input.parse_input_event(interact)
	Input.flush_buffered_events()
	await process_frame
	check(garage.jager_npc.is_talking, "E starts the actual Maciota conversation")
	garage.jager_npc._close_dialogue()
	if DisplayServer.get_name() != "headless":
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/workshop-integrated-review.png")
	await walk(Vector3(5.5, 0, -0.2))
	await walk(Vector3(5.5, 0, 1.5))
	await walk(Vector3(1.35, 0, 1.5))
	await walk(Vector3(1.35, 0, 3.55))
	await walk(Vector3(1.35, 0, 1.5))
	await walk(Vector3(5.25, 0, 1.5))
	await walk(Vector3(5.25, 0, 3.55))
	check(not garage.diagnostic_active and not garage.jager_npc.is_player_nearby, "Mission board approach does not trigger other stations")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/workshop-board-review.png")
	await walk(Vector3(5.25, 0, 1.5))
	await walk(Vector3(1.35, 0, 1.5))
	await walk(Vector3(1.35, 0, 3.55))
	interiors._on_exit_door_requested(garage.exit_door, player, &"", null, &"", &"harbor/District/Garage/Entrance")
	check(not player.get_node("Camera").has_meta("compact_interior"), "Exterior camera restored on exit")
	check(player.global_position.distance_to(garage.global_position) > 1500, "Pedestrian returns to Harbor")
	player.remove_meta("westgate_layout_checked")
	player.global_position = garage.to_global(Vector2(-245, -160))
	garage.restore_legacy_visitor(player)
	check(player.global_position.distance_to(garage.spawn_point.global_position) < 1, "Old lounge save returns to accessible new entrance")
	print("WORKSHOP_GAMEPLAY failures=", failures)
	quit(0 if failures.is_empty() else 1)
