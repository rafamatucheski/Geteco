extends SceneTree

## Verifies the saved language is already active before the main menu's own
## _ready() sets any text — i.e. no frame where Portuguese defaults are still
## showing while English is the saved preference.
##
## ISOLATION: this Godot 4.7.2 build has no --user-data-dir CLI flag (checked
## via `godot --help`), so isolation is done one level down: the running
## SettingsManager instance's own _settings_path is redirected to a throwaway
## temp file via sm.set("_settings_path", ...) — a plain instance property,
## set reflectively from this test script, NOT a change to SettingsManager.gd
## itself. The real user://settings.cfg is never opened for writing by this
## test, and its content is snapshotted before and re-checked byte-for-byte
## after, so a regression here would fail loudly instead of silently
## corrupting the player's real preferences.
##
## Run standalone with:
##   "<godot>" --headless --path D:\geteco\game --script res://tests/test_language_applied_before_first_screen.gd
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var sm := root.get_node("SettingsManager")

	# Snapshot the REAL file (read-only) so we can prove afterward it was
	# never touched — no assumption made here about what language it holds.
	var real_path := ProjectSettings.globalize_path("user://settings.cfg")
	var real_existed_before := FileAccess.file_exists(real_path)
	var real_before := FileAccess.get_file_as_string(real_path) if real_existed_before else ""

	var temp_dir := OS.get_temp_dir().path_join("harbor_lang_isolated_%d" % Time.get_ticks_usec())
	_check(DirAccess.make_dir_recursive_absolute(temp_dir) == OK, "Isolated temp directory is created for this run only")
	var temp_path := temp_dir.path_join("settings.cfg")
	sm.set("_settings_path", temp_path)

	sm.set_language("en")
	_check(sm.save_settings(), "English language persists to the isolated settings.cfg")
	_check(FileAccess.file_exists(temp_path), "Isolated settings.cfg was actually written at the temp path, not user://")

	# Simulate a fresh process reading that file back (still the isolated path
	# — TranslationServer is forced to pt_BR first so the check below can only
	# pass if load_settings()+apply actually re-read "en" from disk).
	TranslationServer.set_locale("pt_BR")
	sm.language = "pt_BR"
	_check(sm.load_settings(), "Settings reload without error from the isolated path")
	sm.apply_language_settings()
	_check(TranslationServer.get_locale() == "en", "Locale is English again immediately after reloading the isolated file, before any scene loads")

	var menu: Control = (load("res://ui/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	# No 'await process_frame' before this check: _ready() already ran
	# synchronously as part of add_child() above, so this is the true "first
	# possible frame" state, not a later corrected one.
	var btn_new_game: Button = menu.get_node("%BtnNewGame")
	var btn_quit: Button = menu.get_node("%BtnQuit")
	_check(btn_new_game.text == "NEW GAME", "New Game button already reads English text before any frame is drawn (got: %s)" % btn_new_game.text)
	_check(btn_quit.text == "QUIT GAME", "Quit button already reads English text before any frame is drawn (got: %s)" % btn_quit.text)
	menu.queue_free()

	var real_after_exists := FileAccess.file_exists(real_path)
	var real_after := FileAccess.get_file_as_string(real_path) if real_after_exists else ""
	_check(real_after_exists == real_existed_before, "The player's real user://settings.cfg existence is unchanged (not created, not deleted)")
	_check(real_after == real_before, "The player's real user://settings.cfg is byte-for-byte unchanged after this test")

	# Clean up the throwaway directory only — never the real one.
	var dir := DirAccess.open(temp_dir)
	if dir:
		dir.remove("settings.cfg")
	DirAccess.remove_absolute(temp_dir)

	print("LANGUAGE_BEFORE_FIRST_SCREEN: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
