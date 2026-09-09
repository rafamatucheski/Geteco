extends SceneTree

## Real-renderer, real-input validation for the mission board's MOUSE path —
## run as its OWN process (never in the same run as the keyboard test), so a
## focus/state leftover from one input method can never explain the other's
## result. Sends an actual InputEventMouseButton at the button's on-screen
## rect (Controls under a CanvasLayer are already in screen space), routed
## through Godot's real GUI mouse-picking — never child.pressed.emit().

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
	print("MOUSE_REAL: hovered control after motion = ", root.gui_get_hovered_control())
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

	print("MOUSE_REAL: finish Maciota's conversation for real")
	player.global_position = npc.global_position + Vector2(0, 30)
	await _frames(10)
	await _key(KEY_E)
	for _line in 12:
		if not npc.is_talking:
			break
		await _key(KEY_SPACE)
	_check(String(mission.get_campaign_status().get("phase", "")) == "board", "Conversation completion reaches the board phase")

	print("MOUSE_REAL: open board with native E")
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

	var click_pos: Vector2 = button.get_global_rect().get_center()
	print("MOUSE_REAL: real click at ", click_pos, " (button rect ", button.get_global_rect(), ")")
	await _click_at(click_pos)
	var mouse_accept_worked: bool = not garage.mission_board.is_ui_open and String(mission.get_campaign_status().get("phase", "")) == "delivery_pickup"
	if mouse_accept_worked:
		print("MOUSE_REAL: RESULT = a real mouse click on the contract's screen rect accepted it.")
	else:
		print("MOUSE_REAL: RESULT = a real mouse click did NOT accept the contract (is_ui_open=%s phase=%s)." % [garage.mission_board.is_ui_open, mission.get_campaign_status().get("phase", "")])
	_check(mouse_accept_worked, "A real mouse click on the contract's screen rect accepts it (native GUI picking, no signal shortcut)")

	if mouse_accept_worked:
		player.global_position = world.get_node("FirstDeliveryPickup").global_position
		await _frames(6)
		mission.interact_with_objective()
		player.global_position = npc.global_position + Vector2(0, 30)
		await _frames(6)
		mission.interact_with_objective()
		player.global_position = garage.mission_board.global_position + Vector2(0, 25)
		await _frames(10)
		await _key(KEY_E)
		await _frames(6)
		var close_btn: Button = null
		# Click the visible "FECHAR [ESC]" button for real, exercising the
		# mouse-close path explicitly (Escape-close is already covered by the
		# keyboard-path test).
		for child in garage.mission_board.panel.find_children("*", "Button", true, false):
			if String(child.text).begins_with("FECHAR") or String(child.text).begins_with("CLOSE"):
				close_btn = child
				break
		_check(close_btn != null, "The board's close button is found for a real mouse close")
		if close_btn != null:
			await _click_at(close_btn.get_global_rect().get_center())
			_check(not garage.mission_board.is_ui_open, "A real mouse click on FECHAR/CLOSE closes the board")
			_check(not player.is_control_disabled, "Closing the board via mouse returns control to the player")

	world.queue_free()
	await _frames(4)
	print("BOARD_MOUSE_REAL: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
