extends SceneTree
## Production scene; never loads or writes personal saves/preferences.
const OUTPUT := "res://evidence/dialogue-ui-language/integration"
var world
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("BILINGUAL_SESSION ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label); push_error(label)
func settle(count := 4) -> void:
	for index in count: await process_frame
func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT+"/"+label+".png") == OK,"capture "+label)
func has_label(node: Node, source: String) -> bool:
	for child in node.get_children():
		if child is Label and child.text == source: return true
		if has_label(child,source): return true
	return false
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1280,720)
	root.get_node("V2Launch").direct_start_consumed = true
	var settings := root.get_node("V2Settings")
	var original_text: String = settings.text_language
	var original_voice: String = settings.voice_language
	settings.text_language = "en"
	settings.voice_language = "pt_BR"
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path","user://bilingual-session-missing-%d.json" % Time.get_ticks_usec())
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+180000
	while (world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled) and Time.get_ticks_msec()<deadline: await process_frame
	check(world.session != null and world.session.ready_for_play,"Main production session ready")
	if failures.is_empty():
		var session = world.session
		if session.modal: session.close_menu()
		world.player.controlled_automatically = true
		world.player.automatic_direction = Vector3.ZERO
		world.dispatch.router.nearest_edge(world.player.global_position)
		check(world.dispatch.router._native != null,"compiled C# router active")
		await settle(20)
		check(not str(session.objective.text).is_empty(),"authored objective exists in gameplay")
		check(session.state.intro.stage == "meet_maciota", "fresh session uses authored garage objective")
		check(String(TranslationServer.translate(session.objective.text)) == "Talk to Maciota at the garage.","authored garage objective displays English")
		await shot("en-gameplay")
		if world.driving.occupied:
			world.driving.leave()
			await settle(120)
		session.state.economy.grant_item("apple",1)
		session.show_inventory()
		var pocket_items: Array = session.state.economy.grid_snapshot().pockets
		for index in pocket_items.size():
			if pocket_items[index].id == "apple": session.field_inventory.ui._select("pockets",index)
		await settle()
		check(session.field_inventory.ui.visible,"real inventory opens from session")
		check(has_label(session.field_inventory.ui,"INVENTÁRIO"),"real inventory heading exists")
		check(TranslationServer.translate("INVENTÁRIO") == "INVENTORY","real inventory heading resolves English")
		check(TranslationServer.translate("Maçã Vermelha") == "Red Apple","inventory item name resolves English")
		await shot("en-inventory")
		settings.text_language = "pt_BR"
		await settle()
		check(session.field_inventory.ui.visible and TranslationServer.translate("INVENTÁRIO") == "INVENTÁRIO","open inventory switches back to Portuguese")
		check(settings.voice_language == "pt_BR","live text changes preserve voice")
		await shot("pt-inventory")
		session.close_menu()
		session.show_map()
		await settle()
		check(session.modal,"real map opens")
		await shot("pt-map")
		settings.text_language = "en"
		await settle()
		await shot("en-map")
		session.close_menu()
		session.show_settings()
		await settle()
		var menu = world.pause_panel.settings
		check(paused and menu.visible,"settings opens through real pause menu")
		menu._widgets.text_language.item_selected.emit(0)
		menu._widgets.voice_language.item_selected.emit(1)
		await settle()
		check(settings.text_language == "pt_BR" and settings.voice_language == "en","live production menu switches independently")
		await shot("pt-settings-en-voice")
		menu.close()
		check(settings.text_language == "en" and settings.voice_language == "pt_BR","cancel restores both settings in real session")
		world.pause_panel.resume_game()
		await settle()
		check(not paused and not world.pause_panel.visible,"return from menu restores live gameplay")
		await shot("en-gameplay-return")
	paused = false
	settings.text_language = original_text
	settings.voice_language = original_voice
	world.queue_free()
	await settle(3)
	print("BILINGUAL_SESSION_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
