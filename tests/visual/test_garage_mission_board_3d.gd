extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		for frame in 3: await physics_frame
func walk(player: CharacterBody2D, point: Vector2) -> bool:
	for frame in 240:
		var offset := point - player.global_position
		for action in ["move_up", "move_down", "move_left", "move_right"]: Input.action_release(action)
		if offset.length() < 2.5: return true
		var strength := clampf(offset.length() / 28.0, .28, .5)
		if absf(offset.x) > 1: Input.action_press("move_right" if offset.x > 0 else "move_left", strength)
		if absf(offset.y) > 1: Input.action_press("move_down" if offset.y > 0 else "move_up", strength)
		await physics_frame
	for action in ["move_up", "move_down", "move_left", "move_right"]: Input.action_release(action)
	return false
func capture(file: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/life-refinement-0911/" + file + ".png")
func run() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	root.get_node("SettingsManager").set_language("pt_BR")
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	var scene := load("res://world/harbor/HarborGame.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for frame in 20: await process_frame
	var player: CharacterBody2D = scene.get_node("Player")
	var garage: Node2D = scene.get_node("Interiors").garage_interior
	var mission: Node = scene.campaign_controller
	player.global_position = garage.spawn_point.global_position
	player.velocity = Vector2.ZERO
	player.set_meta("police_exterior_position", mission.entrance.global_position)
	player.set_meta("harbor_interior", true)
	for frame in 20: await physics_frame
	check(mission.phase == "board", "Real campaign resumes at the mission board objective")
	var path := [Vector3(1.35, 0, 1.50), Vector3(3.05, 0, 1.50), Vector3(3.05, 0, 3.4), Vector3(4.7, 0, 3.4)]
	for point in path:
		var goal: Vector2 = garage.to_global(garage.workshop_point(point))
		check(await walk(player, goal), "Player reaches office route %s with native movement and collisions" % point)
	for frame in 8: await physics_frame
	mission._refresh_objective()
	var board: Node2D = garage.mission_board
	check(player.global_position.distance_to(board.global_position) < 3.0, "Player can stand at the projected board interaction anchor")
	check(garage.showroom.model.get_node("MissionBoard3D").get_child_count() > 5, "Visible workshop owns the native framed board and pinned contracts")
	var board_body: StaticBody2D = garage.showroom.get_node("MissionBoardFeet")
	var panel_point: Vector2 = garage.to_global(garage.workshop_point(Vector3(4.7, 1.38, 2.5)))
	var query := PhysicsPointQueryParameters2D.new()
	query.position = panel_point
	query.collision_mask = 1
	var panel_blocked := false
	for hit in player.get_world_2d().direct_space_state.intersect_point(query):
		if hit.collider == board_body: panel_blocked = true
	check(panel_blocked, "Raised panel projection blocks the spot where the player could stand over the posters")
	var approach := player.global_transform
	approach.origin = panel_point + Vector2(0, -40)
	var collision := KinematicCollision2D.new()
	check(player.test_move(approach, Vector2(0, 40), collision), "Player approaching from behind cannot walk onto the projected panel")
	check(board.get_node("Prompt").visible, "Interaction prompt appears beside the physical board")
	check(player.has_meta("police_exterior_position") and "0 m" in mission._objective_label.text, "Indoor HUD reports the nearby board while retaining the outdoor entrance metadata")
	await capture("garage-mission-board-3d")
	await key(KEY_E)
	check(board.is_ui_open and not garage.jager_npc.is_talking and not garage.diagnostic_active, "Native E opens the actual mission board without opening Maciota or diagnostics")
	await capture("garage-mission-board-open")
	await key(KEY_ESCAPE)
	check(not board.is_ui_open, "Native escape closes the mission board normally")
	print("GARAGE_MISSION_BOARD_3D failures=", failures)
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

