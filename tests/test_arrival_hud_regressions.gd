extends SceneTree

var failures: Array[String] = []
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	change_scene_to_file("res://district/harbor_preview/HarborGame.tscn")
	for i in 30: await process_frame
	var world := current_scene
	var arrival: Node = world.get_node("ArrivalMission")
	check(arrival.phase == "arrival" and is_instance_valid(arrival._opening_layer), "Real opening starts")
	# Do not skip, delete the CGI or force the phase. Exercise its real completion signal.
	var deadline := Time.get_ticks_msec() + 90000
	while arrival.phase != "phone" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(arrival.phase == "phone", "Natural opening and bus disembark reach the phone")
	check(not paused, "World pause released naturally")
	check(not is_instance_valid(arrival._opening_layer), "Real CGI layer removed by its fade")
	check(is_instance_valid(world.get_node("ArrivalStop").bus), "Real terminal bus remains available")
	var player: Node2D = world.get_node("Player")
	check(player.visible and player.global_position.distance_to(world.get_node("ArrivalSpawn").global_position) < 3, "Dante visibly disembarked at the authored marker")
	for i in 16:
		if arrival.phase != "phone": break
		arrival.advance_dialogue()
		await process_frame
	var hud: Node = get_first_node_in_group("hud")
	for resolution in [Vector2i(1280,720), Vector2i(1920,1080)]:
		root.size = resolution
		root.content_scale_size = resolution
		hud.show_achievement("GRANA SUJA", "Acumule $2.000 no bolso.")
		for i in 8: await process_frame
		var money_stack: Control = hud.get_node("RootMargin/TopRightPanel")
		check(not money_stack.get_global_rect().intersects(hud.achievement_panel.get_global_rect()), "Achievement clears money, stars and clock at " + str(resolution))
		check(hud.achievement_panel.get_global_rect().end.x <= resolution.x, "Achievement fits screen width")
		check(hud.achievement_panel.size.y < 160, "Achievement stays compact after repeated layout updates")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/arrival-hud-%d.png" % resolution.x)
	print("ARRIVAL_HUD_REGRESSIONS failures=", failures)
	quit(0 if failures.is_empty() else 1)
