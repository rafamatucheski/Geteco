extends SceneTree
## Exercises the actual menu and DisplayServer (also runnable headless).
## All writes use a temporary settings file, never the player's preferences.
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value:
		failures.append(message)

func settle() -> void:
	await create_timer(0.25).timeout
	for i in 4:
		await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var directory := OS.get_temp_dir()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("out="):
			directory = argument.trim_prefix("out=")
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))

func _run() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	var sm := root.get_node("SettingsManager")
	var original: Dictionary = sm.interface_snapshot()
	var real_path: String = sm._settings_path
	var existed := FileAccess.file_exists(real_path)
	var before := FileAccess.get_file_as_bytes(real_path) if existed else PackedByteArray()
	var temp := OS.get_temp_dir().path_join("geteco_display_%d.cfg" % OS.get_process_id())
	sm._settings_path = temp
	sm.window_mode = 0
	sm.resolution = Vector2i(1280, 720)
	sm.language = "pt_BR"
	sm.apply_all_settings()
	await settle()
	var initial_resolution: Vector2i = sm.resolution
	check(sm.save_settings(), "initial preferences saved to isolated file")
	var menu = load("res://ui/SettingsMenu.tscn").instantiate()
	root.add_child(menu)
	paused = true # Settings and its countdown must work from the pause menu.
	menu._select_tab(1)
	await settle()
	var initial_view := root.get_visible_rect().size
	var stored := FileAccess.get_file_as_bytes(temp)

	menu.opt_window_mode.select(1)
	menu.opt_window_mode.item_selected.emit(1)
	check(sm.window_mode == 0, "mode selection waits for Apply")
	check(menu.opt_resolution.disabled and menu.opt_resolution.get_item_text(0).contains("nativa"), "fullscreen explicitly shows native resolution")
	menu.btn_apply.pressed.emit()
	await settle()
	check(menu._video_seconds > 0 and menu._video_confirmation.visible, "Apply opens timed video confirmation")
	check(FileAccess.get_file_as_bytes(temp) == stored, "unconfirmed changes are not persisted")
	await capture("settings-fullscreen-confirmation-0911")
	check(root.content_scale_size == Vector2i(1280, 720), "fullscreen preserves logical canvas and UI scale")
	check(root.get_visible_rect().size.is_equal_approx(initial_view), "same logical visible area after mode switch")
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "OS actually enters fullscreen")
		check(DisplayServer.window_get_size() == DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()), "fullscreen output matches current monitor")
	menu._video_confirmation.confirmed.emit()
	await settle()
	check(menu.visible and menu._video_seconds == 0, "confirmed Apply stays in Settings")
	check(menu.status_label.text.contains("salvas"), "Apply visibly reports saved preferences")
	await capture("settings-fullscreen-0911")
	var reload = load("res://systems/SettingsManager.gd").new()
	reload._settings_path = temp
	root.add_child(reload)
	check(reload.load_settings() and reload.window_mode == 1 and reload.resolution == initial_resolution, "fresh manager reloads fullscreen and remembered window size")
	reload.free()

	menu.opt_window_mode.select(0)
	menu.opt_window_mode.item_selected.emit(0)
	check(not menu.opt_resolution.disabled, "windowed mode enables size selection")
	var selected: int = menu._resolutions.find(initial_resolution)
	check(menu.opt_resolution.selected == selected, "window size is remembered across fullscreen")
	menu.btn_apply.pressed.emit()
	await settle()
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "OS actually returns to windowed mode")
		check(DisplayServer.window_get_size() == initial_resolution, "window uses the selected physical dimensions")
	menu._video_seconds = 0.01
	await settle()
	check(sm.window_mode == 1 and menu.visible, "timeout reverts mode and keeps Settings open")
	check(not menu._video_confirmation.visible, "timeout closes confirmation")
	menu.btn_back.pressed.emit()
	check(sm.window_mode == 1, "Cancel does not undo previously confirmed Apply")

	menu.show()
	menu._select_tab(1)
	menu.opt_window_mode.select(2)
	menu.opt_window_mode.item_selected.emit(2)
	menu.btn_apply.pressed.emit()
	await settle()
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, "OS enters exclusive fullscreen")
	menu._video_confirmation.confirmed.emit()
	menu.opt_window_mode.select(0)
	menu.opt_window_mode.item_selected.emit(0)
	menu.btn_save.pressed.emit()
	await settle()
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "exclusive fullscreen can return to a bordered window")
	menu._video_confirmation.confirmed.emit()
	check(not menu.visible, "Save and back closes only after confirmation")
	check(sm.load_settings() and sm.window_mode == 0, "windowed mode persists")

	menu.show()
	menu._select_tab(1)
	var next_index: int = 1 if menu._resolutions.size() > 1 and menu.opt_resolution.selected != 1 else 0
	var next_size: Vector2i = menu._resolutions[next_index]
	menu.opt_resolution.select(next_index)
	menu.opt_resolution.item_selected.emit(next_index)
	menu.btn_apply.pressed.emit()
	await settle()
	check(sm.resolution == next_size, "Apply changes window resolution")
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_size() == next_size, "OS window matches new resolution")
	menu._video_confirmation.confirmed.emit()
	check(sm.load_settings() and sm.resolution == next_size, "new resolution survives reload")
	menu.check_vsync.button_pressed = not sm.vsync
	var expected_vsync: bool = menu.check_vsync.button_pressed
	menu.btn_apply.pressed.emit()
	check(menu._video_seconds == 0 and sm.load_settings() and sm.vsync == expected_vsync, "VSync-only Apply saves without video countdown")

	sm.set_language("en")
	check(menu.btn_apply.text == "APPLY", "Apply translates to English")
	menu.opt_window_mode.select(1)
	menu.opt_window_mode.item_selected.emit(1)
	check(menu.opt_resolution.get_item_text(0).contains("native"), "native output translates to English")
	check(menu._video_confirmation.ok_button_text == "Keep", "video confirmation follows language changes")
	menu.btn_apply.pressed.emit()
	await settle()
	menu._video_confirmation.canceled.emit()
	check(sm.window_mode == 0 and menu.visible, "Revert button restores video without leaving Settings")

	# Exercise save failure using a directory path, which cannot be a config file.
	sm._settings_path = OS.get_temp_dir()
	menu.btn_apply.pressed.emit()
	check(menu.visible and menu.status_label.text.contains("Could not save"), "save failure is visible on Video tab and does not close Settings")
	sm._settings_path = temp
	menu.btn_apply.pressed.emit()
	check(menu.status_label.text.contains("saved"), "save can be retried after failure")

	sm.set_language("pt_BR")
	menu.btn_apply.pressed.emit()
	await capture("settings-windowed-0911")
	sm.resolution = sm.fit_window_resolution(Vector2i(1366, 768))
	menu._load_values_from_manager()
	check(menu._resolutions[menu.opt_resolution.selected] == sm.resolution, "saved custom window resolution is displayed exactly")
	menu.btn_defaults.pressed.emit()
	check(menu.opt_window_mode.selected == 0 and menu._window_resolution == initial_resolution, "Defaults stages the default window size")
	check(sm.window_mode == 0 and sm.resolution != initial_resolution, "Defaults waits for Apply before changing video")
	check(FileAccess.file_exists(real_path) == existed, "real settings file existence unchanged")
	check((FileAccess.get_file_as_bytes(real_path) if existed else PackedByteArray()) == before, "real player settings remain byte-for-byte unchanged")
	menu.free()
	paused = false
	sm.restore_snapshot(original)
	sm._settings_path = real_path
	DirAccess.remove_absolute(temp)
	print("DISPLAY SETTINGS: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
