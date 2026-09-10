extends SceneTree
## Captura de auditoria: não altera o código de jogo nem os saves do jogador.
const OUT := "res://docs/measurements/uiux-0910/"
func _initialize() -> void:
	run.call_deferred()
func frames(n := 6) -> void:
	for i in n: await process_frame
func shot(label: String) -> void:
	await frames()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + label + ".png")
	print("CAPTURE ", label, " viewport=", root.get_visible_rect().size)
func key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await frames(2)
func run() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	var scratch := OS.get_temp_dir().path_join("geteco_uiux_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(scratch.path_join("saves"))
	var settings = root.get_node("SettingsManager")
	settings._settings_path = scratch.path_join("settings.cfg")
	settings.window_mode = 0
	settings.resolution = Vector2i(1280,720)
	settings.apply_display_settings()
	settings.set_language("pt_BR")
	var saves = root.get_node("SaveManager")
	saves._save_dir = scratch.path_join("saves") + "/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	change_scene_to_file("res://ui/MainMenu.tscn")
	await create_timer(1).timeout
	var menu = current_scene
	await shot("01_menu_720")
	menu.btn_load_game.grab_focus()
	await key(KEY_ENTER)
	assert(menu.load_panel.visible)
	await shot("02_load_empty")
	print("LOAD_FOCUS ", root.gui_get_focus_owner().name)
	await key(KEY_ESCAPE)
	print("LOAD_VISIBLE_AFTER_ESCAPE ", menu.load_panel.visible)
	menu._on_close_load_panel_pressed()
	menu._on_btn_settings_pressed()
	await shot("03_settings_audio")
	var options = menu._settings_instance
	options._select_tab(1)
	await shot("04_settings_video")
	settings.set_language("en")
	await shot("05_settings_video_en")
	settings.set_language("pt_BR")
	options._select_tab(2)
	await shot("06_settings_controls")
	await key(KEY_ESCAPE)
	print("SETTINGS_VISIBLE_AFTER_ESCAPE ", options.visible)
	options.hide()
	root.size = Vector2i(1280,800)
	await shot("07_menu_16x10")
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i(1920,1080)
	await shot("13_menu_1080")
	settings.resolution = Vector2i(1280,720)
	settings.apply_display_settings()
	var campaign = root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete"]:
		campaign.set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	await frames(80)
	await shot("08_gameplay_720")
	await key(KEY_ESCAPE)
	await shot("09_pause")
	await key(KEY_ESCAPE)
	var world = current_scene
	var player = world.get_node("Player")
	var garage = world.get_node("Interiors").garage_interior
	player.set_physics_process(false)
	player.global_position = garage.jager_npc.global_position + Vector2(0,30)
	await frames(12)
	garage.jager_npc._open_dialogue()
	assert(garage.jager_npc.dialogue_box.visible)
	await shot("11_dialogue_current")
	garage.jager_npc._close_dialogue()
	# Estado de revisão para capturar as telas desbloqueadas; não é teste da campanha.
	campaign.set_campaign_flag(&"harbor_delivery_complete", true)
	await frames(6)
	garage.mission_board.interaction_enabled = true
	garage.mission_board.open_chalkboard()
	assert(garage.mission_board.is_ui_open)
	await shot("10_board_current")
	garage.mission_board.close_chalkboard()
	player.set_dialogue_active(false)
	world.get_node("CobraCampaign")._toggle_journal()
	assert(world.get_node("CobraCampaign")._journal.visible)
	await shot("12_journal_current")
	world.get_node("CobraCampaign")._toggle_journal()
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i(1920,1080)
	await shot("14_gameplay_1080")
	print("AUDITORIA CAPTURADA")
	quit()
