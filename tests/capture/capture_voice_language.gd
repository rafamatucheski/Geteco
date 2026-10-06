extends SceneTree
const OUTPUT := "res://evidence/dialogue-ui-language/settings-audio.png"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Use Godot .NET renderizado com --no-save.")
		quit(2)
		return
	root.get_node("V2Launch").direct_start_consumed = true
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var menu: Control = load("res://ui/SettingsMenu.tscn").instantiate()
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.open()
	menu._select_tab(1)
	menu._widgets.voice_language.select(1)
	menu._widgets.voice_language.item_selected.emit(1)
	menu._widgets.voice_language.grab_focus()
	for _frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT))
	menu.close()
	menu.queue_free()
	await process_frame
	print("VOICE_LANGUAGE_CAPTURE ", result)
	quit(0 if result == OK else 1)
