extends SceneTree
## Cobertura de regressão para strings de menus, HUD e atividades acrescentadas depois do catálogo original.
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	preload("res://runtime/Localization.gd").install()
	var original := TranslationServer.get_locale()
	var settings := root.get_node("V2Settings")
	var original_language: String = settings.text_language
	root.get_node("V2Launch").direct_start_consumed = true
	# Parse production scripts changed at variable-first formatting call sites.
	for path in ["res://activities/arcade/ArcadeScreen.gd", "res://activities/arcade/games/FighterGame.gd", "res://activities/desert_drag/DesertDragResults.gd", "res://activities/desert_drag/DragNightPanel.gd", "res://activities/desert_drag/DragRivalChallengeCatalog.gd", "res://activities/desert_drag/DragRivalChallengeController.gd", "res://activities/desert_drag/DragRivalChallengePanel.gd", "res://gameplay/desert_cars/DesertTuningPanel.gd", "res://gameplay/forge/BladeForgeTalk.gd"]:
		var script: GDScript = load(path)
		check(script != null and script.can_instantiate(), "Production script loads: " + path)
	var pairs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/menu-hud-completion.en.json"))
	pairs.merge(JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/hud-quality.en.json")), true)
	for language in ["en", "pt_BR"]:
		settings.text_language = language
		for source in pairs:
			var expected: String = pairs[source] if language == "en" else source
			var actual := String(TranslationServer.translate(source))
			check(actual == expected, "%s: %s => %s; expected %s" % [language, source, actual, expected])
	var label := Label.new()
	label.text = "APAGAR"
	root.add_child(label)
	settings.text_language = "en"
	await process_frame
	check(label.tr(label.text) == "DELETE", "Open menu follows English locale")
	check(String(TranslationServer.translate("INVESTIGAÇÃO LOCAL  1:02")) == "LOCAL INVESTIGATION  1:02", "Wanted timer translates after formatting")
	check(String(TranslationServer.translate("%d ACERTOS")) % 4 == "4 HITS", "Variable-first arcade message translates before formatting")
	check(String(TranslationServer.translate("Rival challenges")) == "Rival challenges", "English stays English")
	settings.text_language = "pt_BR"
	await process_frame
	check(label.tr(label.text) == "APAGAR", "Open menu returns to Portuguese")
	check(String(TranslationServer.translate("LOCAL INVESTIGATION  1:02")) == "INVESTIGAÇÃO LOCAL  1:02", "Wanted timer returns to Portuguese")
	check(String(TranslationServer.translate("Workshop car")) == "Carro da oficina", "English input returns to Portuguese")
	var menu: Control = load("res://ui/SettingsMenu.tscn").instantiate()
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.hide()
	menu.open()
	for language in ["en", "pt_BR"]:
		settings.text_language = language
		menu._load_widgets()
		await process_frame
		for control in menu.find_children("*", "Control", true, false):
			if control is Label or control is Button:
				var source: String = control.text
				if pairs.has(source):
					check(control.tr(source) == (pairs[source] if language == "en" else source), "Settings control follows locale: " + source)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/localization"))
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://output/localization/settings-" + language + ".png"))
	menu.close()
	menu.queue_free()
	settings.text_language = original_language
	label.queue_free()
	TranslationServer.set_locale(original)
	print("MENU_HUD_LOCALIZATION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
