extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var settings = root.get_node("SettingsManager")
	settings._settings_path = OS.get_temp_dir().path_join("geteco_menu_capture.cfg")
	settings.window_mode = 0
	settings.resolution = Vector2i(1280,720)
	settings.apply_display_settings()
	change_scene_to_file("res://ui/MainMenu.tscn")
	await create_timer(1).timeout
	var menu = current_scene
	assert(menu.get_node("SunsetPresentation").buttons.size() == 4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/menu-sunset-720.png")
	menu.btn_load_game.pressed.emit()
	await process_frame
	assert(menu.load_panel.visible)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/menu-sunset-load.png")
	menu._on_close_load_panel_pressed()
	settings.resolution = Vector2i(1920,1080)
	settings.apply_display_settings()
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/menu-sunset-1080.png")
	print("SUNSET MENU PASS: presentation, load modal, 720p and 1080p captures")
	quit()
