extends "res://tests/test_cobra_journal_rest_real.gd"

## Run the integration author's real-input test without saving its PT/EN
## switches over the player's settings. No production UI behavior is replaced.
func _run() -> void:
	var settings := root.get_node("SettingsManager")
	var directory := OS.get_temp_dir().path_join("harbor_journal_qa_%d" % OS.get_process_id())
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Cannot create isolated journal settings directory")
		quit(1)
		return
	settings.set("_settings_path", directory.path_join("settings.cfg"))
	print("JOURNAL_QA isolated_settings=", settings.get("_settings_path"))
	await super._run()
