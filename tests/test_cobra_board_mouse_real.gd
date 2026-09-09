extends SceneTree

## Real-renderer, real-input validation for the SEVEN-ROW board — MOUSE path
## only, run as its own process (see test_cobra_board_keyboard_real.gd for
## the keyboard path and shared context). Sends actual InputEventMouseButton
## events at each control's on-screen rect, through Godot's real GUI
## mouse-picking — never child.pressed.emit()/bridge._selected().

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

	print("BOARD7_MOUSE: a not-yet-available job cannot be selected by mouse")
	player.global_position = board.global_position + Vector2(0, 25)
	await _frames(10)
	await _key(KEY_E)
	_check(board.is_ui_open, "Native E opens the seven-row board")
	_check(board.orders_vbox.get_child_count() == 7, "Seven rows rendered")
	var locked_row: Control = null
	for child in board.orders_vbox.get_children():
		if child.has_meta("board_row_state") and child.get_meta("board_row_state") == "locked":
			locked_row = child
			break
	_check(locked_row != null, "At least one Cobra job row is locked")
	if locked_row != null:
		# Click squarely inside the locked row's own rect: there is no Button
		# there to receive it (only Labels), so the click must be a no-op.
		await _click_at(locked_row.get_global_rect().get_center())
	_check(board.is_ui_open, "Clicking a locked row does not close/select anything")
	_check(bridge.runtime.active_id.is_empty(), "Clicking a locked row does not start any mission")
	await _click_at(_close_button_pos(board))

	print("BOARD7_MOUSE: real rest (mouse click) unlocks cobra_contact")
	player.global_position = garage.jager_npc.global_position + Vector2(0, 45)
	await _frames(8)
	# Open the journal via a real mouse click on the on-screen "Diário [J]" button.
	await _click_at(bridge._journal_button.get_global_rect().get_center())
	_check(bridge._journal.visible, "Clicking the Diário button opens the journal")
	_check(not bridge._rest_button.disabled, "Rest is available near Maciota with no active job/pursuit")
	await _click_at(bridge._rest_button.get_global_rect().get_center())
	await create_timer(1.5).timeout
	_check(int(bridge.ledger.data.day) == 2, "Real mouse click on Rest actually advanced the day")
	_check(not player.is_control_disabled, "Rest fade returns control to the player")
	_check(bridge.runtime.active_id.is_empty(), "Resting never auto-starts a mission")

	print("BOARD7_MOUSE: accept cobra_contact with a real click, board closes, correct controller starts")
	player.global_position = board.global_position + Vector2(0, 25)
	await _frames(10)
	await _key(KEY_E)
	var contact_button: Button = null
	for child in board.orders_vbox.get_children():
		if child is Button and not child.disabled:
			contact_button = child
			break
	_check(contact_button != null, "Cobra contact's row is now a real, enabled button")
	if contact_button != null:
		await _click_at(contact_button.get_global_rect().get_center())
	_check(not board.is_ui_open, "A real mouse click on the contract closes the board")
	_check(bridge.runtime.active_id == "cobra_contact", "Board selection reaches the Cobra runtime controller (correct id)")
	_check(bridge._dialog.visible, "Accepting opens Maciota's real briefing dialogue (modal)")
	await _click_at(bridge._continue.get_global_rect().get_center())
	_check(not bridge._dialog.visible, "Clicking Continue dismisses the briefing")

	print("BOARD7_MOUSE: complete cobra_contact for real (no double reward)")
	var cash_before: int = player.money
	player.global_position = bridge.runtime.WORKSHOP + Vector2(0, 40)
	await _frames(6)
	await _key(KEY_E)
	_check(bridge._dialog.visible, "Native E at the workshop opens the contact conversation")
	await _click_at(bridge._continue.get_global_rect().get_center())
	await _key(KEY_E)
	_check(bool(bridge.ledger.data.completed.get("cobra_contact", false)), "Cobra contact completes through real world interaction")
	_check(player.money == cash_before + 120, "Reward is paid exactly once")
	while bridge._dialog.visible:
		await _click_at(bridge._continue.get_global_rect().get_center())
	await _key(KEY_E)
	_check(player.money == cash_before + 120, "Repeated interaction after completion does not pay again")

	print("BOARD7_MOUSE: struck-through, still seven rows, no duplicate rows on reopen")
	for _i in 3:
		player.global_position = board.global_position + Vector2(0, 25)
		await _frames(8)
		await _key(KEY_E)
		_check(board.orders_vbox.get_child_count() == 7, "Reopening the board never duplicates rows (got %d)" % board.orders_vbox.get_child_count())
		await _click_at(_close_button_pos(board))

	print("BOARD7_MOUSE: language switch with board open keeps seven rows and a usable close button")
	player.global_position = board.global_position + Vector2(0, 25)
	await _frames(8)
	await _key(KEY_E)
	var sm := root.get_node("SettingsManager")
	sm.set_language("en")
	await _frames(4)
	_check(board.is_ui_open, "Switching language does not close the open board")
	_check(board.orders_vbox.get_child_count() == 7, "Still seven rows after switching to English")
	await _click_at(_close_button_pos(board))
	_check(not board.is_ui_open, "A real mouse click on CLOSE (English) closes the board")
	_check(not player.is_control_disabled, "Closing the board via mouse returns control to the player")
	sm.set_language("pt_BR")

	world.queue_free()
	await _frames(4)
	print("COBRA_BOARD_MOUSE_REAL: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _close_button_pos(board: Node2D) -> Vector2:
	for child in board.panel.find_children("*", "Button", true, false):
		if String(child.text).begins_with("FECHAR") or String(child.text).begins_with("CLOSE"):
			return child.get_global_rect().get_center()
	return Vector2.ZERO
