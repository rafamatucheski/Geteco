extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 900:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.session.weather != null: break
	check(world.session != null and world.session.ready_for_play,"Main must reach playable state")
	if not failures.is_empty(): quit(1); return
	check(world.production.no_save,"Diagnostic must not use player save")
	check(world.camera.current and world.player.is_inside_tree(),"Camera and player must be present")
	check(world.production.region.get_child_count()>0,"Map must have loaded geometry")
	for frame in 30: await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/startup-world-fixed.png")
	for menu in ["show_inventory","show_journal","show_map","show_settings","show_controls"]:
		world.session.call(menu)
		await process_frame
		check(world.session.panel.visible and world.session.column.get_child_count()>0,menu+" must display content")
		world.session.close_menu()
	world.session.show_inventory()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/startup-menu-fixed.png")
	world.session.close_menu()
	world.queue_free()
	await create_timer(.2).timeout
	print("STARTUP_UI ","PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)
