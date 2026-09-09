extends SceneTree

## Targeted coverage for the "walk away mid-conversation" scenario: leaving
## Maciota's proximity before his last line must NOT unlock the board, must
## leave a clear reason visible near it (PT-BR and English), and must NOT
## discard progress — returning and finishing the same conversation for real
## (native E/SPACE, no accept_mission()/notify_maciota_conversation_completed()
## shortcuts) must unlock it normally.
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


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(3)


func _run() -> void:
	var campaign := root.get_node("CampaignState")
	var saves := root.get_node("SaveManager")
	var sm := root.get_node("SettingsManager")
	campaign.reset_campaign()
	saves.clear_pending_save()
	sm.set_language("pt_BR")
	# Flags set BEFORE instantiation so the scene's own single start_or_resume()
	# call (from _start_gameplay) routes straight to meet_maciota — avoids a
	# second start_or_resume() call double-locking the player (see
	# test_language_settings.gd for why that ordering matters).
	campaign.set_campaign_flag(&"harbor_arrival_seen", true)
	campaign.set_campaign_flag(&"harbor_arrival_call_complete", true)

	var packed := load("res://world/harbor/HarborGame.tscn") as PackedScene
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
	_check(String(mission.get_campaign_status().get("phase", "")) == "meet_maciota", "Flag-driven resume reaches the meet_maciota objective")

	var player: CharacterBody2D = world.get_node("Player")
	var garage: Node2D = world.get_node("Interiors").garage_interior
	var npc: Node2D = garage.jager_npc

	print("INTERRUPTED_CONVO: open and partially advance, then walk away")
	player.global_position = npc.global_position + Vector2(0, 30)
	await _frames(8)
	await _key(KEY_E)
	_check(npc.is_talking, "Native E opens Maciota's conversation")
	await _key(KEY_SPACE)
	_check(npc.is_talking, "Conversation still running after one advance (4 authored lines)")
	var dialogue_index_before_leaving: int = npc.dialogue_index
	_check(dialogue_index_before_leaving > 0, "Advancing once actually moved past the first line")

	# Leave the real Area2D radius (no manual _close_dialogue() call) — a
	# genuine "walked away" reproduction, not a scripted shortcut.
	player.global_position = npc.global_position + Vector2(0, 600)
	await _frames(10)
	_check(not npc.is_talking, "Leaving Maciota's proximity closes the dialogue on its own")
	_check(not garage.mission_board.interaction_enabled, "Board stays locked: the interrupted conversation never completed")
	_check(not bool(campaign.has_campaign_flag(&"harbor_maciota_met")), "harbor_maciota_met is not set by an incomplete conversation")
	_check(String(mission.get_campaign_status().get("phase", "")) == "meet_maciota", "Campaign phase does not advance from an interrupted conversation")

	print("INTERRUPTED_CONVO: locked board shows a clear reason, in both languages")
	player.global_position = garage.mission_board.global_position + Vector2(0, 25)
	await _frames(10)
	var locked_label: Label = garage.mission_board.get_node_or_null("LockedPrompt")
	_check(locked_label != null and locked_label.visible, "A locked-reason prompt is shown while standing at the board")
	_check(locked_label != null and locked_label.text.contains("Termine a conversa com Maciota"), "PT-BR locked reason matches the requested wording")
	await _key(KEY_E)
	_check(not garage.mission_board.is_ui_open, "Pressing interact on a locked board does not force it open")

	sm.set_language("en")
	await _frames(2)
	_check(locked_label != null and locked_label.text.contains("Finish talking to Maciota"), "English locked reason matches the requested wording, live")
	sm.set_language("pt_BR")
	await _frames(2)

	print("INTERRUPTED_CONVO: returning resumes (not restarts) and finishes for real")
	player.global_position = npc.global_position + Vector2(0, 30)
	await _frames(8)
	await _key(KEY_E)
	_check(npc.is_talking, "Returning to Maciota reopens the conversation")
	_check(npc.dialogue_index == dialogue_index_before_leaving, "Resumed conversation keeps its previous line instead of restarting from zero")
	for _line in 12:
		if not npc.is_talking:
			break
		await _key(KEY_SPACE)
	_check(not npc.is_talking, "Finishing the resumed conversation has an actual end")
	_check(String(mission.get_campaign_status().get("phase", "")) == "board", "Completing the (resumed) conversation for real reaches the board phase")
	_check(garage.mission_board.interaction_enabled, "Board unlocks from the real completion — no notify_maciota_conversation_completed() shortcut was called")
	_check(bool(campaign.has_campaign_flag(&"harbor_maciota_met")), "harbor_maciota_met flag is set by the real completion")

	player.global_position = garage.mission_board.global_position + Vector2(0, 25)
	await _frames(6)
	await _key(KEY_E)
	_check(garage.mission_board.is_ui_open, "Board opens normally once really unlocked")
	garage.mission_board.close_chalkboard()

	world.queue_free()
	await _frames(4)
	print("INTERRUPTED_CONVERSATION: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
