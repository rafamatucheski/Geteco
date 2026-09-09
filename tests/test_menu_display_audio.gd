extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var sm = root.get_node("SettingsManager")
	sm._settings_path = OS.get_temp_dir().path_join("geteco_display_test_%d.cfg" % Time.get_ticks_usec())
	sm.window_mode = 0
	sm.resolution = Vector2i(1280,720)
	sm.apply_display_settings()
	sm.save_settings()
	var menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.btn_settings.pressed.emit()
	await process_frame
	var settings = menu._settings_instance
	settings.opt_resolution.select(1)
	settings.opt_resolution.item_selected.emit(1)
	assert(sm.resolution == Vector2i(1280,720), "Video selection waits for Apply")
	settings.btn_save.pressed.emit()
	await create_timer(.4).timeout
	assert(sm.resolution == Vector2i(1600,900))
	if DisplayServer.get_name() != "headless":
		assert(DisplayServer.window_get_size() == Vector2i(1600,900), "Apply changes actual OS window size")
	menu.btn_settings.pressed.emit()
	assert(settings.opt_resolution.selected == 1, "Reopening displays applied resolution")
	settings.opt_resolution.select(2)
	settings.btn_back.pressed.emit()
	assert(sm.resolution == Vector2i(1600,900), "Cancel preserves saved resolution")
	menu.btn_settings.pressed.emit()
	settings.opt_window_mode.select(1)
	settings.opt_resolution.select(0)
	settings.btn_save.pressed.emit()
	await create_timer(.4).timeout
	assert(root.content_scale_size == Vector2i(1280,720))
	assert(root.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT, "Fullscreen applies render resolution")
	var audio = load("res://ui/MenuAudio.gd")
	assert(audio.get_music_stream().get_length() > 19.9)
	assert(audio.get_music_stream().loop_mode == AudioStreamWAV.LOOP_FORWARD)
	menu.btn_load_game.grab_focus()
	await process_frame
	await process_frame
	assert(root.get_node("__MenuHoverPlayer").stream == audio.get_hover_stream())
	menu.btn_settings.pressed.emit()
	await process_frame
	await process_frame
	assert(root.get_node("__MenuClickPlayer").stream == audio.get_click_stream())
	sm.window_mode=0
	sm.resolution=Vector2i(1280,720)
	sm.apply_display_settings()
	print("MENU_DISPLAY_AUDIO PASS: window resize, fullscreen render size, apply, cancel, reopen, navigation, confirmation, music")
	menu.queue_free()
	await process_frame
	quit()
