extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await process_frame
func key(code: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await process_frame
func click(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.position = point
	e.global_position = point
	e.button_index = button
	e.pressed = true
	root.push_input(e,true)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	root.push_input(e,true)
	await process_frame
func run() -> void:
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/map-gps/test-saves/"
	create_timer(150).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	if "early" in OS.get_cmdline_user_args():
		while current_scene == null or current_scene.get_node_or_null("Minimap") == null or current_scene.get_node("Minimap").full_map == null:
			await process_frame
	else:
		await create_timer(15).timeout
	var map: Node = current_scene.get_node("Minimap")
	var ui: Node = map.full_map
	var player: Node2D = current_scene.get_node("Player")
	player.global_position = Vector2(715,1800)
	player.is_control_disabled = false
	player.is_in_dialogue = false
	map.refresh()
	if not "early" in OS.get_cmdline_user_args():
		while map._route_building: await process_frame
	var mission: Vector2 = map.objective_target
	await key(KEY_M)
	check(ui.screen.visible and paused,"M opens map and pauses gameplay")
	var before: Vector2 = player.global_position
	await key(KEY_W)
	await frames(3)
	check(player.global_position.is_equal_approx(before),"movement cannot move player while map is open")
	var target := Vector2(2200,1050)
	ui.zoom = 0.2
	ui.view_center = target
	ui.surface.queue_redraw()
	await click(ui.surface.global_position+ui.project(target))
	check(map.has_waypoint and map.waypoint.distance_to(target)<2,"click places GPS at the matching world coordinate")
	if map._route_building:
		check(ui.status.text.contains("Calculando"),"early destination reports pending route")
		while map._route_building: await process_frame
	print("GPS_DEBUG center=",map.center," target=",map.waypoint," route=",map.waypoint_route.size())
	check(map.waypoint_route.size()>1,"GPS uses connected street route")
	check(map.objective_target == mission,"personal GPS preserves mission objective")
	var old_zoom: float = ui.zoom
	await click(ui.surface.global_position+ui.surface.size*0.5,MOUSE_BUTTON_WHEEL_UP)
	check(ui.zoom > old_zoom,"mouse wheel zooms map")
	var view_before: Vector2 = ui.view_center
	var destination_before: Vector2 = map.waypoint
	var mouse := InputEventMouseButton.new()
	mouse.position = ui.surface.global_position+ui.surface.size*0.5
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	root.push_input(mouse,true)
	var motion := InputEventMouseMotion.new()
	motion.position = mouse.position+Vector2(60,20)
	motion.relative = Vector2(60,20)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,true)
	mouse.position = motion.position
	mouse.pressed = false
	root.push_input(mouse,true)
	await process_frame
	check(not ui.view_center.is_equal_approx(view_before) and map.waypoint == destination_before,"drag pans without replacing GPS destination")
	await key(KEY_ESCAPE)
	check(not ui.screen.visible and not paused,"Escape closes map without opening pause menu")
	map.refresh()
	check(map.has_waypoint and map.caption.text.begins_with("GPS"),"destination and distance remain on minimap after closing")
	await key(KEY_M)
	check(ui.screen.visible and map.has_waypoint,"reopening retains destination")
	if DisplayServer.get_name() != "headless":
		ui.zoom = 0.08
		ui.view_center = Vector2(2600,800)
		root.mode = Window.MODE_WINDOWED
		for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
			root.size = resolution
			await frames(3)
			ui.surface.queue_redraw()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/map-gps/map-%d.png" % resolution.x)
	await click(ui.surface.global_position+Vector2(50,50),MOUSE_BUTTON_RIGHT)
	check(not map.has_waypoint and map.waypoint_route.is_empty(),"right click clears waypoint and GPS route")
	await key(KEY_M)
	check(not paused and not ui.screen.visible,"M also closes map")
	map.set_waypoint(Vector2.ZERO)
	check(map.has_waypoint,"world origin is a valid waypoint")
	map.set_waypoint(Vector2(90000,90000))
	check(map.waypoint_route.is_empty(),"off-network target does not invent a drivable route")
	map.set_waypoint(map.center)
	map.refresh()
	check(not map.has_waypoint,"arrival clears the personal GPS")
	var manager: Node = current_scene.get_node("PersonalCarManager")
	manager.introduction_seen = true
	var car: Node2D = manager.car
	car.unlocked = true
	car.show()
	car.global_position = Vector2(2200,1050)
	car.enter_vehicle(player)
	while car.has_meta("vehicle_boarding"): await process_frame
	map.refresh()
	check(map.center.distance_to(car.global_position)<1,"GPS origin follows the controlled car")
	await key(KEY_M)
	check(ui.screen.visible and paused,"driver can open map")
	await key(KEY_M)
	check(not paused and car.is_driven_by_player,"closing map preserves vehicle control")
	player.is_in_dialogue = true
	await key(KEY_M)
	check(not paused and not ui.screen.visible,"dialogue blocks opening map")
	player.is_in_dialogue = false
	paused = true
	await key(KEY_M)
	check(paused and not ui.screen.visible,"map cannot steal another menu's pause")
	paused = false
	print("MAP_GPS_RESULT failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
