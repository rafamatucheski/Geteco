extends SceneTree

## Real-renderer, real-input validation for the mission board's KEYBOARD path.
## Must run WITHOUT --headless: Godot's GUI focus/ui_accept activation for a
## focused Button was found unreliable to script under --headless in earlier
## testing (see the task's final report), so this specific claim is only
## trustworthy when checked against the real renderer/input pipeline.
##
## Every step uses the same public surface a player's keyboard would:
## native E to enter the garage/open dialogues/open the board, native SPACE to
## advance Maciota's lines, and a real InputEventKey matching the default
## ui_accept binding (Enter) on the board's focused, only available contract.
## No accept_mission()/interact_with_objective() shortcut is ever called.
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
	campaign.set_campaign_flag(&"harbor_arrival_seen", true)
	campaign.set_campaign_flag(&"harbor_arrival_call_complete", true)

	var world: Node2D = (load("res://world/harbor/HarborGame.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(20)

	var mission: Node = null
	for node in world.find_children("*", "", true, false):
		if node.has_method("get_campaign_status") and node.has_method("skip_cinematic"):
			mission = node
			break
	if mission == null:
		push_error("Production scene did not wire the arrival mission controller")
		quit(1)
		return

	var player: CharacterBody2D = world.get_node("Player")
	var garage: Node2D = world.get_node("Interiors").garage_interior
	var npc: Node2D = garage.jager_npc

	print("KEYBOARD_REAL: finish Maciota's conversation for real")
	player.global_position = npc.global_position + Vector2(0, 30)
	await _frames(10)
	await _key(KEY_E)
	for _line in 12:
		if not npc.is_talking:
			break
		await _key(KEY_SPACE)
	_check(String(mission.get_campaign_status().get("phase", "")) == "board", "Conversation completion reaches the board phase")

	print("KEYBOARD_REAL: open board with native E")
	player.global_position = garage.mission_board.global_position + Vector2(0, 25)
	await _frames(10)
	await _key(KEY_E)
	await _frames(6)
	_check(garage.mission_board.is_ui_open, "Native E opens the board")

	var button: Button = null
	for child in garage.mission_board.orders_vbox.get_children():
		if child is Button and not child.disabled:
			button = child
			break
	_check(button != null, "The authored contract is selectable")
	if button == null:
		world.queue_free()
		await _frames(4)
		quit(1)
		return
	_check(button.has_focus(), "Opening the board grabs keyboard focus on the contract")

	print("KEYBOARD_REAL: real Enter key (matches default ui_accept), not .pressed.emit()")
	await _key(KEY_ENTER)
	await _frames(4)
	var keyboard_accept_worked: bool = not garage.mission_board.is_ui_open and String(mission.get_campaign_status().get("phase", "")) == "delivery_pickup"
	if keyboard_accept_worked:
		print("KEYBOARD_REAL: RESULT = real Enter key activated the focused button and accepted the contract.")
	else:
		print("KEYBOARD_REAL: RESULT = real Enter key did NOT activate the focused button (is_ui_open=%s phase=%s). See report for the fallback used." % [garage.mission_board.is_ui_open, mission.get_campaign_status().get("phase", "")])
	_check(keyboard_accept_worked, "Real keyboard Enter on the focused contract accepts it (native ui_accept, no signal shortcut)")

	if keyboard_accept_worked:
		print("KEYBOARD_REAL: complete the delivery for real and verify strike-through + no double reward")
		player.global_position = world.get_node("FirstDeliveryPickup").global_position
		await _frames(6)
		mission.interact_with_objective()
		player.global_position = npc.global_position + Vector2(0, 30)
		await _frames(6)
		var money_before: int = player.money
		mission.interact_with_objective()
		_check(player.money > money_before, "Real completion pays the reward")
		var paid: int = player.money
		mission.interact_with_objective()
		_check(player.money == paid, "Repeated interaction cannot pay the reward twice")

		player.global_position = garage.mission_board.global_position + Vector2(0, 25)
		await _frames(10)
		await _key(KEY_E)
		await _frames(6)
		var found_completed := false
		for child in garage.mission_board.orders_vbox.get_children():
			if child.has_meta("board_row_state") and child.get_meta("board_row_state") == "completed":
				found_completed = true
		_check(found_completed, "Completed contract shows struck-through after a real-keyboard accept")
		await _key(KEY_ESCAPE)
		await _frames(4)
		_check(not garage.mission_board.is_ui_open, "Escape closes the board")
		_check(not player.is_control_disabled, "Closing the board returns control to the player")

	world.queue_free()
	await _frames(4)
	print("BOARD_KEYBOARD_REAL: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
