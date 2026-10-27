extends SceneTree
const STARTUP := preload("res://tests/fixtures/TravelBagScene.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	check(await STARTUP.wait_for_startup(world),"Main must reach playable state after streaming and curtain")
	if not failures.is_empty(): quit(1); return
	check(world.production.no_save,"Diagnostic must not use player save")
	check(world.camera.current and world.player.is_inside_tree(),"Camera and player must be present")
	check(world.production.region.get_child_count()>0,"Map must have loaded geometry")
	for frame in 30: await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/startup-world-fixed.png")
	for menu in ["show_inventory","show_journal","show_map","show_controls"]:
		world.session.call(menu)
		await process_frame
		# Each current view has its own presentation owner; only the journal
		# still uses the legacy session panel.
		match menu:
			"show_inventory":
				var inventory = world.session.field_inventory.ui
				check(inventory.is_visible_in_tree() and inventory.card.get_child_count()>0,menu+" must display inventory content")
			"show_map":
				var map = world.hud.get_node_or_null("MapUI")
				check(is_instance_valid(map) and map.is_visible_in_tree() and is_instance_valid(map.canvas),menu+" must display the map canvas")
			"show_controls":
				var settings = world.pause_panel.settings
				check(world.pause_panel.visible and settings.is_visible_in_tree() and settings._tab==2 and settings._controls_list.get_child_count()>0,menu+" must display control bindings")
			_:
				check(world.session.panel.visible and world.session.column.get_child_count()>0,menu+" must display content")
		if paused: world.pause_panel.resume_game()
		else: world.session.close_menu()
		await process_frame
	# Configurações moraram no painel da sessão; hoje abrem a tela de configurações do
	# menu de pausa (FullSession.show_settings -> PauseMenu.open_settings).
	world.session.show_settings()
	await process_frame
	var pause_menu = world.pause_panel
	check(is_instance_valid(pause_menu) and pause_menu.visible and is_instance_valid(pause_menu.settings) and pause_menu.settings.visible and pause_menu.settings.get_child_count()>0,"show_settings must display content")
	pause_menu.resume_game()
	await process_frame
	world.session.show_inventory()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/startup-menu-fixed.png")
	world.session.close_menu()
	world.queue_free()
	await create_timer(.2).timeout
	print("STARTUP_UI ","PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)
