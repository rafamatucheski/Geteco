extends SceneTree

## Targeted coverage for PT-BR/English language selection: persisted setting
## (independent of campaign saves), TranslationServer wiring, and switching
## language mid-session without disrupting an in-progress Harbor campaign.
##
## ISOLATION: this Godot 4.7.2 build has no --user-data-dir CLI flag, so this
## test redirects the running SettingsManager instance's own _settings_path
## (a plain instance property, set reflectively via sm.set(...), not a source
## change to SettingsManager.gd) to a throwaway temp file before ever calling
## save_settings()/load_settings(). The player's real user://settings.cfg is
## never opened for writing here, and its content is diffed before/after to
## prove that. See test_language_applied_before_first_screen.gd for the same
## pattern applied to the "no PT-BR flash" check.
##
## Run standalone with:
##   "<godot>" --headless --path D:\geteco\game --script res://tests/test_language_settings.gd
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func _frames(count: int = 4) -> void:
	for _i in count:
		await physics_frame


func _run() -> void:
	var sm := root.get_node("SettingsManager")
	var real_path := ProjectSettings.globalize_path("user://settings.cfg")
	var real_existed_before := FileAccess.file_exists(real_path)
	var real_before := FileAccess.get_file_as_string(real_path) if real_existed_before else ""
	var temp_dir := OS.get_temp_dir().path_join("harbor_lang_isolated_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var temp_path := temp_dir.path_join("settings.cfg")
	sm.set("_settings_path", temp_path)

	print("LANGUAGE: persisted setting is independent from campaign saves")
	sm.set_language("en")
	_check(TranslationServer.get_locale() == "en", "set_language applies the locale to TranslationServer immediately")
	_check(tr("BOARD_TITLE_MACIOTA") == "SERVICE BOARD · MACIOTA", "English translation resolves for the mission board title")

	_check(sm.save_settings(), "Settings (including language) save without error, to the isolated path")
	_check(FileAccess.file_exists(temp_path), "The isolated settings.cfg was actually written, not user://")
	sm.language = "pt_BR"  # Simulate a fresh process before load_settings runs.
	_check(sm.load_settings(), "Settings reload without error from the isolated path")
	_check(sm.language == "en", "Persisted language survives a save/load roundtrip in the isolated settings.cfg")

	sm.set_language("pt_BR")
	_check(tr("BOARD_TITLE_MACIOTA") == "QUADRO DE SERVIÇOS · MACIOTA", "Portuguese translation resolves again after switching back")

	sm.set_language("xx_INVALID")
	_check(sm.language == "pt_BR", "An unsupported locale is rejected, keeping the last valid language")

	print("LANGUAGE: switching mid-campaign does not disrupt the Harbor flow")
	var campaign := root.get_node("CampaignState")
	var saves := root.get_node("SaveManager")
	campaign.reset_campaign()
	saves.clear_pending_save()
	# Flags must exist BEFORE the scene's own _start_gameplay() runs its single
	# start_or_resume() call (same shortcut test_harbor_campaign_flow.gd uses
	# for save/load coverage) — calling start_or_resume() a second time here
	# would double up on _lock_player() from the arrival phase already begun.
	campaign.set_campaign_flag(&"harbor_arrival_seen", true)
	campaign.set_campaign_flag(&"harbor_arrival_call_complete", true)
	campaign.set_campaign_flag(&"harbor_maciota_met", true)
	var packed := load("res://district/harbor_preview/HarborGame.tscn") as PackedScene
	var world: Node2D = packed.instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(12)

	var mission: Node = null
	for node in world.find_children("*", "", true, false):
		if node.has_method("get_campaign_status") and node.has_method("skip_cinematic"):
			mission = node
			break
	_check(mission != null, "Production scene wires the arrival mission controller")
	if mission == null:
		world.queue_free()
		await _frames(2)
		quit(1)
		return
	_check(String(mission.get_campaign_status().get("phase", "")) == "board", "Flag-driven resume reaches the board objective")

	var garage: Node2D = world.get_node("Interiors").garage_interior
	var player: CharacterBody2D = world.get_node("Player")
	player.global_position = garage.mission_board.global_position + Vector2(0, 25)
	await _frames(6)
	garage.mission_board.open_chalkboard()
	await _frames(2)
	# Opening the board is itself a modal that locks control (by design, same
	# as Maciota's own dialogue) — capture that baseline so the language
	# switch itself can be checked for NOT changing it either way.
	var control_locked_before_switch: bool = player.is_control_disabled

	sm.set_language("en")
	await _frames(2)
	var saw_english_title := false
	for child in garage.mission_board.orders_vbox.get_children():
		if child is Button and String(child.text).begins_with("First Run"):
			saw_english_title = true
	_check(saw_english_title, "Switching language while the board is open re-renders its authored mission text")
	_check(garage.mission_board.is_ui_open, "Switching language does not close the open board")
	_check(String(mission.get_campaign_status().get("phase", "")) == "board", "Switching language does not disturb the campaign phase")
	_check(player.is_control_disabled == control_locked_before_switch, "Switching language does not change the player's control-lock state")

	garage.mission_board.close_chalkboard()

	world.queue_free()
	await _frames(4)

	var real_after_exists := FileAccess.file_exists(real_path)
	var real_after := FileAccess.get_file_as_string(real_path) if real_after_exists else ""
	_check(real_after_exists == real_existed_before, "The player's real user://settings.cfg existence is unchanged")
	_check(real_after == real_before, "The player's real user://settings.cfg is byte-for-byte unchanged after this test")
	var dir := DirAccess.open(temp_dir)
	if dir:
		dir.remove("settings.cfg")
	DirAccess.remove_absolute(temp_dir)

	print("LANGUAGE SETTINGS: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
