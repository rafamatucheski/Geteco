extends SceneTree

## Real-renderer, real-input validation for the SEVEN-ROW board (arrival +
## primeiro_giro + 5 Cobra jobs) — KEYBOARD path only (see
## test_cobra_board_mouse_real.gd for the separate mouse-only run).
##
## Initial progress up to "primeiro_giro complete" is prepared via campaign
## flags (an explicitly allowed fixture — see task notes), matching the same
## shortcut district/harbor_preview's own test_cobra_campaign_gameplay.gd
## uses. Every action actually being PROVEN (accepting a job, confirming a
## dialogue, resting) goes through native input events: focus + a real Enter
## keypress matching the default ui_accept binding. Never
## child.pressed.emit(), bridge._selected(), or runtime.start_mission().

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
	print(("PASS " if ok else "FAIL ") + message)


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
	root.size = Vector2i(1280, 720)
	var campaign := root.get_node("CampaignState")
	var saves := root.get_node("SaveManager")
	campaign.reset_campaign()
	saves.clear_pending_save()
	# Fixture: reach "primeiro_giro complete" instantly instead of replaying
	# the whole arrival/phone/Maciota/delivery flow (already covered by
	# test_harbor_campaign_flow.gd and test_board_keyboard_real.gd). Every
	# flag here is a REAL flag the production flow itself sets.
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_started", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)

	var world: Node2D = (load("res://district/harbor_preview/HarborGame.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(20)

	var bridge: CanvasLayer = world.get_node_or_null("CobraCampaign")
	_check(bridge != null, "CobraCampaignBridge is wired into the production scene")
	if bridge == null:
		world.queue_free()
		await _frames(4)
		quit(1)
		return

	var player: CharacterBody2D = world.get_node("Player")
	var garage: Node2D = bridge.garage
	var board = bridge.board

	print("BOARD7_KBD: seven fixed rows, arrival+primeiro_giro struck through")
	_check(board.campaign_missions.size() == 7, "Board holds exactly seven fixed rows (got %d)" % board.campaign_missions.size())
	player.global_position = board.global_position + Vector2(0, 25)
	await _frames(10)
	await _key(KEY_E)
	_check(board.is_ui_open, "Native E opens the seven-row board")
	var row_count: int = board.orders_vbox.get_child_count()
	_check(row_count == 7, "Rendered board shows seven rows (got %d)" % row_count)
	var completed_rows := 0
	var locked_rows := 0
	var cobra_contact_row: Control = null
	for child in board.orders_vbox.get_children():
		if child.has_meta("board_row_state") and child.get_meta("board_row_state") == "completed":
			completed_rows += 1
		elif child.has_meta("board_row_state") and child.get_meta("board_row_state") == "locked":
			locked_rows += 1
	_check(completed_rows == 2, "Arrival and Primeiro giro are struck through (got %d completed rows)" % completed_rows)
	_check(locked_rows == 5, "All five Cobra jobs show a locked/blocked row (got %d)" % locked_rows)

	print("BOARD7_KBD: a not-yet-available job cannot be selected by keyboard")
	var any_button := false
	for child in board.orders_vbox.get_children():
		if child is Button and not child.disabled:
			any_button = true
	_check(not any_button, "No selectable button exists while every Cobra job is still locked")
	await _key(KEY_ESCAPE)
	_check(not board.is_ui_open, "Escape closes the board")

	print("BOARD7_KBD: real rest (keyboard) unlocks cobra_contact")
	player.global_position = garage.jager_npc.global_position + Vector2(0, 45)
	await _frames(8)
	await _key(KEY_J)
	_check(bridge._journal.visible, "J opens the journal near Maciota")
	_check(bridge._rest_button.has_focus(), "Opening the journal grabs keyboard focus on the (enabled) rest button")
	await _key(KEY_ENTER)
	await _frames(2)
	await create_timer(1.5).timeout
	_check(int(bridge.ledger.data.day) == 2, "Real keyboard Enter on the focused rest button actually advanced the day")
	_check(not player.is_control_disabled, "Rest fade returns control to the player")
	_check(bridge.runtime.active_id.is_empty(), "Resting never auto-starts a mission")

	print("BOARD7_KBD: cobra_contact is now available; accept it for real")
	player.global_position = board.global_position + Vector2(0, 25)
	await _frames(10)
	await _key(KEY_E)
	_check(board.is_ui_open, "Board reopens with native E")
	var contact_button: Button = null
	for child in board.orders_vbox.get_children():
		if child is Button and not child.disabled:
			contact_button = child
			break
	_check(contact_button != null, "Cobra contact's row is now a real, enabled button")
	if contact_button != null:
		_check(contact_button.has_focus(), "Reopening the board re-grabs focus on the now-available contract")
		await _key(KEY_ENTER)
		await _frames(4)
	_check(not board.is_ui_open, "Accepting via keyboard closes the board")
	_check(bridge.runtime.active_id == "cobra_contact", "Board selection reaches the Cobra runtime controller (correct id)")
	_check(bridge._dialog.visible, "Accepting opens Maciota's real briefing dialogue (modal)")
	await _key(KEY_ENTER)
	_check(not bridge._dialog.visible, "Enter dismisses the briefing")

	print("BOARD7_KBD: no other mission auto-starts once one is accepted")
	player.global_position = board.global_position + Vector2(0, 25)
	await _frames(10)
	await _key(KEY_E)
	var still_only_one_selectable := true
	for child in board.orders_vbox.get_children():
		if child is Button and not child.disabled and String(child.get("text")).length() > 0:
			# cobra_contact itself is now "active" (not "enabled"), so ANY
			# selectable button here would mean a second job auto-started.
			still_only_one_selectable = false
	_check(still_only_one_selectable, "With a job active, nothing else on the board is selectable — nothing auto-started")
	await _key(KEY_ESCAPE)

	print("BOARD7_KBD: complete cobra_contact for real (no double reward)")
	var cash_before: int = player.money
	player.global_position = bridge.runtime.WORKSHOP + Vector2(0, 40)
	await _frames(6)
	await _key(KEY_E)
	_check(bridge._dialog.visible, "Native E at the workshop opens the contact conversation")
	await _key(KEY_ENTER)
	await _key(KEY_E)
	_check(bool(bridge.ledger.data.completed.get("cobra_contact", false)), "Cobra contact completes through real world interaction")
	_check(player.money == cash_before + 120, "Reward is paid exactly once")
	while bridge._dialog.visible:
		await _key(KEY_ENTER)
	await _key(KEY_E)
	_check(player.money == cash_before + 120, "Repeated interaction after completion does not pay again")

	print("BOARD7_KBD: struck-through after completion, board still seven rows, no duplicate rows on reopen")
	for _i in 3:
		player.global_position = board.global_position + Vector2(0, 25)
		await _frames(8)
		await _key(KEY_E)
		_check(board.orders_vbox.get_child_count() == 7, "Reopening the board never duplicates rows (got %d)" % board.orders_vbox.get_child_count())
		await _key(KEY_ESCAPE)
	player.global_position = board.global_position + Vector2(0, 25)
	await _frames(8)
	await _key(KEY_E)
	var completed_after := 0
	for child in board.orders_vbox.get_children():
		if child.has_meta("board_row_state") and child.get_meta("board_row_state") == "completed":
			completed_after += 1
	_check(completed_after == 3, "Arrival + primeiro_giro + cobra_contact are struck through (got %d)" % completed_after)

	print("BOARD7_KBD: language switch with board open keeps seven rows, states and usable focus")
	var sm := root.get_node("SettingsManager")
	sm.set_language("en")
	await _frames(4)
	_check(board.is_ui_open, "Switching language does not close the open board")
	_check(board.orders_vbox.get_child_count() == 7, "Still seven rows after switching to English")
	var locked_row_en: Control = null
	for child in board.orders_vbox.get_children():
		if child.has_meta("board_row_state") and child.get_meta("board_row_state") == "locked":
			locked_row_en = child
			break
	_check(locked_row_en != null, "A locked Cobra row is still present in English")
	sm.set_language("pt_BR")
	await _frames(4)
	await _key(KEY_ESCAPE)

	world.queue_free()
	await _frames(4)
	print("COBRA_BOARD_KEYBOARD_REAL: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
