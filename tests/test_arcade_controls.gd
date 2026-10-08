extends SceneTree
## Native InputEvent -> InputMap -> real ArcadeScreen and real BlocksGame.
const Screen := preload("res://activities/arcade/ArcadeScreen.gd")
var checks: int = 0
var failures: Array[String] = []
var saved_actions: Dictionary = {}
var adapter: Adapter
var ui: CanvasLayer

class Adapter extends Node:
	var screen: CanvasLayer
	var score_calls: int = 0
	var close_calls: int = 0
	func record_score() -> void:
		score_calls += 1
	func close() -> void:
		close_calls += 1
		screen.dismiss()
	func _input(event: InputEvent) -> void:
		if is_instance_valid(screen) and screen.visible:
			screen.handle_input(event)
			get_viewport().set_input_as_handled()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)

func _binding(action: String, keys: Array, pad: int = -1) -> void:
	if not saved_actions.has(action):
		saved_actions[action] = InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	for code in keys:
		var event := InputEventKey.new()
		event.physical_keycode = int(code)
		InputMap.action_add_event(action, event)
	if pad >= 0:
		var event := InputEventJoypadButton.new()
		event.button_index = pad
		InputMap.action_add_event(action, event)

func _key(code: int, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	ui._process(1.0 / 60.0)

func _pad(button: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	ui._process(1.0 / 60.0)

func _ticks(count: int) -> void:
	for frame in range(count):
		ui._process(1.0 / 60.0)

func _fresh_blocks() -> void:
	ui.open_game("blocks", 0)
	ui.set_process(false)
	ui.start_game()
	ui.game.piece = 2
	ui.game.origin = Vector2i(3, 4)
	ui.game.rotation = 0
	ui._process(1.0 / 60.0)

func _run() -> void:
	# Match the shared default accept/handbrake binding that caused the bug,
	# while moving WASD to IJKL to verify that gameplay follows InputMap.
	_binding("interact", [KEY_E], JOY_BUTTON_X)
	_binding("ui_accept", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], JOY_BUTTON_A)
	_binding("handbrake", [KEY_SPACE], JOY_BUTTON_A)
	_binding("sprint", [KEY_SHIFT])
	_binding("pause_game", [KEY_ESCAPE])
	_binding("ui_cancel", [KEY_ESCAPE], JOY_BUTTON_B)
	for entry in [["move_left", KEY_J], ["move_right", KEY_L], ["move_up", KEY_I], ["move_down", KEY_K], ["ui_left", KEY_LEFT], ["ui_right", KEY_RIGHT], ["ui_up", KEY_UP], ["ui_down", KEY_DOWN]]:
		_binding(str(entry[0]), [entry[1]])
	adapter = Adapter.new()
	root.add_child(adapter)
	ui = Screen.new()
	ui.adapter = adapter
	adapter.screen = ui
	adapter.add_child(ui)
	ui.open_game("blocks", 0)
	ui.set_process(false)
	check(ui.visible and not ui.playing, "Opening a cabinet waits for a start action")
	await _key(KEY_ENTER, true)
	check(ui.playing and not ui.armed, "Enter starts the game but remains unarmed until release")
	check(adapter.score_calls == 1, "Start is dispatched only once through the native input route")
	var start_origin: Vector2i = ui.game.origin
	_ticks(40)
	check(ui.game.rotation == 0 and ui.game.origin == start_origin, "Holding the start key neither rotates nor advances the new game")
	await _key(KEY_ENTER, true, true)
	check(adapter.score_calls == 1 and ui.game.rotation == 0, "Keyboard echo cannot restart or play through the start barrier")
	await _key(KEY_ENTER, false)
	check(ui.armed, "Releasing the start key arms gameplay")
	ui.game.piece = 2
	ui.game.origin = Vector2i(3, 4)
	await _key(KEY_ENTER, true)
	var input: Dictionary = ui.controls_now()
	check(input.action and not input.action_alt, "Enter maps to primary action only")
	check(ui.game.rotation == 1, "A new Enter press rotates the real active piece exactly once")
	_ticks(12)
	check(ui.game.rotation == 1 and adapter.score_calls == 1, "Holding gameplay action does not rotate repeatedly or restart")
	await _key(KEY_ENTER, false)

	_fresh_blocks()
	await _key(KEY_SPACE, true)
	input = ui.controls_now()
	check(Input.is_action_pressed("ui_accept") and Input.is_action_pressed("handbrake"), "Fixture reproduces Space shared by accept and handbrake")
	check(input.action_alt and not input.action, "Space maps to alternative action only despite the shared UI binding")
	check(ui.game.board[17].count(0) == 7 and ui.game.board[16].count(0) == 9, "Space drops the T piece in its original orientation without rotating it")
	var locked_score: int = ui.game.score
	_ticks(12)
	check(ui.game.score == locked_score, "Holding hard drop cannot drop subsequent pieces automatically")
	await _key(KEY_SPACE, false)
	await _key(KEY_KP_ENTER, true)
	input = ui.controls_now()
	check(input.action and not input.action_alt, "Keypad Enter is also primary action only")
	await _key(KEY_KP_ENTER, false)
	await _key(KEY_SHIFT, true)
	input = ui.controls_now()
	check(input.action_alt and not input.action, "Shift remains an independent alternative action")
	await _key(KEY_SHIFT, false)
	await _key(KEY_X, true)
	input = ui.controls_now()
	check(input.action_alt and not input.action, "Physical X remains an independent alternative action")
	await _key(KEY_X, false)
	await _pad(JOY_BUTTON_X, true)
	input = ui.controls_now()
	check(input.action and not input.action_alt, "Gamepad X triggers primary action only")
	await _pad(JOY_BUTTON_X, false)
	await _pad(JOY_BUTTON_A, true)
	input = ui.controls_now()
	check(input.action_alt and not input.action, "Gamepad A triggers alternative action only despite ui_accept")
	await _pad(JOY_BUTTON_A, false)

	_fresh_blocks()
	await _key(KEY_J, true)
	input = ui.controls_now()
	check(input.left and not input.right and ui.game.origin.x == 2, "Remapped J moves left through move_left")
	await _key(KEY_J, false)
	await _key(KEY_L, true)
	check(ui.controls_now().right and ui.game.origin.x == 3, "Remapped L moves right through move_right")
	await _key(KEY_L, false)
	await _key(KEY_I, true)
	check(ui.controls_now().up and ui.game.rotation == 1, "Remapped I reaches the rotate direction")
	await _key(KEY_I, false)
	await _key(KEY_K, true)
	check(ui.controls_now().down, "Remapped K reaches the soft-drop direction")
	await _key(KEY_K, false)
	await _key(KEY_A, true)
	check(not ui.controls_now().left, "The previous WASD binding does not bypass a remapped action")
	await _key(KEY_A, false)
	await _key(KEY_LEFT, true)
	check(ui.controls_now().left, "UI arrow controls remain available alongside remapped movement")
	await _key(KEY_LEFT, false)

	_fresh_blocks()
	await _key(KEY_P, true)
	check(ui.suspended, "P pauses a running game")
	var pause_origin: Vector2i = ui.game.origin
	_ticks(120)
	check(ui.game.origin == pause_origin, "The game does not advance while paused")
	await _key(KEY_P, true, true)
	check(ui.suspended, "P keyboard echo does not toggle pause a second time")
	await _key(KEY_P, false)
	await _key(KEY_J, true)
	await _key(KEY_P, true)
	check(not ui.suspended and not ui.armed, "Resuming with a direction held waits for controls to release")
	_ticks(20)
	check(ui.game.origin == pause_origin, "A held direction cannot leak across the resume barrier")
	await _key(KEY_P, false)
	await _key(KEY_J, false)
	check(ui.armed, "Gameplay rearms once held controls are released after resume")
	await _key(KEY_J, true)
	check(ui.game.origin.x == pause_origin.x - 1, "A new direction press works after resume")
	await _key(KEY_J, false)
	await _key(KEY_ESCAPE, true)
	check(adapter.close_calls == 1 and not ui.visible and not ui.playing, "Escape closes the screen exactly once through the adapter")
	await _key(KEY_ESCAPE, false)

	for action in saved_actions:
		InputMap.action_erase_events(action)
		for event in saved_actions[action]:
			InputMap.action_add_event(action, event)
	adapter.free()
	for failure in failures:
		push_error(failure)
	print("ARCADE CONTROLS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
