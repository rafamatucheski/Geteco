extends SceneTree

## Real-renderer, real-input validation for CobraCampaignBridge's journal [J]
## and rest UI — mouse AND keyboard both exercised in this one run (unlike
## the board tests, no headless-vs-real distinction is being probed here,
## just real GUI events either way). Fixture only sets up initial progress
## (documented at each step); every claim about a click/keypress "working"
## goes through a real InputEvent, never pressed.emit()/bridge._selected()/
## bridge.rest() called as a bare function (the two _direct_ bridge.rest()/
## bridge.can_rest() calls below are read-only probes of internal state for
## comparison, not how the ACTION is performed — the action is always the
## real button click or J/Enter/Escape key).

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


func _click_at(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await _frames(4)
	var down := InputEventMouseButton.new()
	down.position = pos
	down.global_position = pos
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventMouseButton.new()
	up.position = pos
	up.global_position = pos
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(4)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var campaign := root.get_node("CampaignState")
	var saves := root.get_node("SaveManager")
	campaign.reset_campaign()
	saves.clear_pending_save()
	# Fixture: reach "onboarding done" (primeiro_giro complete) instantly.
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_started", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)

	var world: Node2D = (load("res://district/harbor_preview/HarborGame.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(20)

	var bridge: CanvasLayer = world.get_node_or_null("CobraCampaign")
	_check(bridge != null, "CobraCampaignBridge is wired into the production scene")
	if bridge == null:
		world.queue_free(); await _frames(4); quit(1); return

	var player: CharacterBody2D = world.get_node("Player")
	var garage: Node2D = bridge.garage
	var pause_menu: CanvasLayer = world.get_node_or_null("PauseMenu")
	_check(pause_menu != null, "Production scene has a PauseMenu to check against")

	print("JOURNAL: mouse click on the on-screen Diário button opens it")
	player.global_position = garage.jager_npc.global_position + Vector2(0, 45)
	await _frames(8)
	_check(bridge._journal_button.visible, "Diário button is visible once onboarding is done")
	await _click_at(bridge._journal_button.get_global_rect().get_center())
	_check(bridge._journal.visible, "A real mouse click on Diário opens the journal")
	_check(player.is_control_disabled, "Opening the journal locks player movement")

	print("JOURNAL: J also closes it; focus lands on an enabled control")
	await _key(KEY_J)
	_check(not bridge._journal.visible, "J closes the open journal")
	_check(not player.is_control_disabled, "Closing the journal restores movement")

	await _key(KEY_J)
	_check(bridge._journal.visible, "J also opens the journal")
	_check(bridge._rest_button.has_focus(), "Opening the journal grabs keyboard focus on an enabled control")
	Input.action_press("ui_down")
	await _frames(4)
	Input.action_release("ui_down")
	_check(bridge._close_button.has_focus() or bridge._rest_button.has_focus(), "ui_down moves focus among the journal's real controls without losing it")

	print("JOURNAL: Escape closes only the journal, not the pause menu")
	await _key(KEY_ESCAPE)
	_check(not bridge._journal.visible, "Escape closes the journal")
	_check(not paused, "Escape does not leave the world paused")
	_check(not pause_menu.visible, "Escape does not simultaneously open the pause menu")

	print("REST: blocked far from the garage shows a clear reason (PT then EN)")
	player.global_position = garage.jager_npc.global_position + Vector2(400, 0)
	await _frames(8)
	await _key(KEY_J)
	_check(bridge._rest_button.disabled, "Rest is disabled far from Maciota")
	_check(bridge._rest_reason.visible and not bridge._rest_reason.text.is_empty(), "A reason is shown instead of a bare grey button (PT: %s)" % bridge._rest_reason.text)
	var sm := root.get_node("SettingsManager")
	sm.set_language("en")
	await _frames(4)
	_check(bridge._rest_reason.visible and not bridge._rest_reason.text.is_empty(), "The reason is also shown in English: %s" % bridge._rest_reason.text)
	sm.set_language("pt_BR")
	await _frames(4)
	await _key(KEY_J)

	print("REST: blocked during an active mission shows a reason")
	bridge.ledger.data.active_id = "cobra_contact"  # fixture: simulate "mission in progress", documented
	player.global_position = garage.jager_npc.global_position + Vector2(0, 45)
	await _frames(8)
	await _key(KEY_J)
	_check(bridge._rest_button.disabled, "Rest is disabled while a mission is active")
	_check(bridge._rest_reason.visible and not bridge._rest_reason.text.is_empty(), "Reason shown for an active mission: %s" % bridge._rest_reason.text)
	await _key(KEY_J)
	bridge.ledger.data.active_id = ""  # fixture cleanup

	print("REST: blocked during a police pursuit shows a reason")
	var wanted := root.get_node_or_null("/root/WantedManager")
	if wanted:
		wanted.current_stars = 2  # fixture: simulate an active pursuit, documented
	await _key(KEY_J)
	_check(wanted == null or bridge._rest_button.disabled, "Rest is disabled during a pursuit")
	_check(wanted == null or (bridge._rest_reason.visible and not bridge._rest_reason.text.is_empty()), "Reason shown for an active pursuit: %s" % bridge._rest_reason.text)
	await _key(KEY_J)
	if wanted:
		wanted.current_stars = 0  # fixture cleanup

	print("REST: real click, fade completes, controls return, day advances, no auto-accept")
	await _key(KEY_J)
	_check(not bridge._rest_button.disabled, "Rest is available again near Maciota with no mission/pursuit")
	var day_before: int = bridge.ledger.data.day
	await _click_at(bridge._rest_button.get_global_rect().get_center())
	_check(bridge._fade.visible, "Rest starts a real fade transition")
	await create_timer(1.5).timeout
	_check(not bridge._fade.visible, "Fade completes on its own")
	_check(not player.is_control_disabled, "Controls return once the fade finishes")
	_check(int(bridge.ledger.data.day) == day_before + 1, "Resting advances exactly one game day")
	_check(bridge.runtime.active_id.is_empty(), "Resting never auto-accepts a mission")

	print("REST/DIALOGUE: an open dialogue blocks player movement")
	player.global_position = garage.mission_board.global_position + Vector2(0, 25)
	await _frames(10)
	await _key(KEY_E)
	var contact_button: Button = null
	for child in bridge.board.orders_vbox.get_children():
		if child is Button and not child.disabled:
			contact_button = child
			break
	if contact_button != null:
		contact_button.grab_focus()
		await _key(KEY_ENTER)
	_check(bridge._dialog.visible, "Accepting opens the real briefing dialogue")
	var pos_before := player.global_position
	Input.action_press("ui_up")
	await _frames(20)
	Input.action_release("ui_up")
	_check(player.global_position.distance_to(pos_before) < 0.1, "The player cannot move while the briefing dialogue is open")
	await _key(KEY_ENTER)
	_check(not bridge._dialog.visible, "Dialogue closes normally afterward")

	print("CLEANUP: leaving the scene does not leave the tree paused")
	await _key(KEY_J)
	_check(paused, "Journal reopened for the cleanup check pauses the tree as designed")
	world.queue_free()
	await _frames(6)
	_check(not paused, "Freeing the scene while a modal was open does not leave the next scene paused")

	print("COBRA_JOURNAL_REST_REAL: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
