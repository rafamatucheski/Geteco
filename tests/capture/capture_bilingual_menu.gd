extends SceneTree
const OUTPUT := "res://evidence/dialogue-ui-language"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	root.get_node("V2Launch").direct_start_consumed = true
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var settings := root.get_node("V2Settings")
	var original_text: String = settings.text_language
	var original_voice: String = settings.voice_language
	var menu: Control = load("res://ui/SettingsMenu.tscn").instantiate()
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.open()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var failures := 0
	for text_language in ["pt_BR", "en"]:
		for voice_language in ["pt_BR", "en"]:
			settings.text_language = text_language
			settings.voice_language = voice_language
			menu._load_widgets()
			for tab in [0,1]:
				menu._select_tab(tab)
				for frame in 4: await process_frame
				await RenderingServer.frame_post_draw
				var path := "%s/settings-text-%s-voice-%s-tab-%d.png" % [OUTPUT,text_language,voice_language,tab]
				if root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path)) != OK: failures += 1
	menu.close()
	menu.queue_free()
	settings.text_language = original_text
	settings.voice_language = original_voice
	await process_frame
	print("BILINGUAL_MENU_CAPTURE failures=",failures)
	quit(0 if failures == 0 else 1)
