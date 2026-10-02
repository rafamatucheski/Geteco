extends SceneTree
const Game := preload("res://gameplay/urban_v1/TruckersVillageHorseshoes.gd")
var checks := 0
var failures: Array[String] = []
var outcomes: Array[int] = []
var throws: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _action(action: StringName, pressed := true) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _run() -> void:
	check(Game.is_hit(0.7), "The center of the visible target scores a hit")
	check(Game.is_hit(0.62) and Game.is_hit(0.78), "Both visible target boundaries are inclusive")
	check(not Game.is_hit(0.619) and not Game.is_hit(0.781), "Throws just beyond the target miss")
	check(not Game.is_hit(-1.0) and not Game.is_hit(2.0), "Out-of-range strengths cannot score")
	check(not Game.is_hit(NAN) and not Game.is_hit(INF), "Non-finite strengths cannot score")
	var game := Game.new()
	root.add_child(game)
	game.finished.connect(func(result: int): outcomes.append(result))
	game.throw_released.connect(func(value: float, hit: bool): throws.append({"strength": value, "hit": hit}))
	check(not game.active and not game.is_processing() and not game.is_processing_input(), "Closed UI has no frame or input processing")
	Input.action_press("interact")
	check(game.open_game(), "A closed game opens with a fresh free round")
	check(not game.open_game(), "Opening an active round cannot reset it")
	game._input(_action("interact"))
	game.step(0.2)
	check(game.attempts == 0 and throws.is_empty() and game.strength == 0.0, "Holding the opening action never releases an accidental throw")
	Input.action_release("interact")
	game.step(0.7 / Game.SWEEP_SPEED)
	check(is_equal_approx(game.strength, 0.7), "The visible meter advances to the target deterministically")
	game._input(_action("interact"))
	check(game.attempts == 1 and game.hits == 1 and throws.size() == 1 and throws[0].hit, "The remappable interaction action releases one scored throw")
	game._input(_action("interact"))
	game._input(_action("ui_accept"))
	game.step(Game.THROW_SECONDS - 0.1)
	check(game.attempts == 1 and throws.size() == 1 and outcomes.is_empty(), "Rapid actions cannot skip the flight cooldown")
	game.step(0.11)
	check(game.active and game.strength == 0.0, "A completed flight resets the meter for the next attempt")
	game._input(_action("ui_accept"))
	check(game.attempts == 2 and game.hits == 1 and throws.size() == 2 and not throws[1].hit, "Menu accept also launches and a short throw misses")
	game.step(Game.THROW_SECONDS + 0.01)
	game.step(0.7 / Game.SWEEP_SPEED)
	game._throw_button.pressed.emit()
	check(game.attempts == 3 and game.hits == 2 and outcomes.is_empty(), "Mouse button uses the same scoring and waits for the last flight")
	game.step(Game.THROW_SECONDS + 0.01)
	check(outcomes == [2] and not game.active and not game.visible, "Three completed throws emit one final hit count and close the panel")
	game.step(3.0)
	game.cancel_game()
	check(not game.try_throw() and outcomes == [2] and throws.size() == 3, "Closed rounds cannot emit extra throws or outcomes")
	check(not game.is_processing() and not game.is_processing_input(), "Completion disables frame and input processing")
	check(game.open_game() and game.hits == 0 and game.attempts == 0, "A later round starts fresh")
	game._input(_action("ui_cancel"))
	check(outcomes == [2, -1] and not game.active, "Cancel is distinct from a completed round with zero hits")
	game.open_game()
	game.step(0.01)
	game._cancel_button.grab_focus()
	game._input(_action("ui_accept"))
	check(outcomes == [2, -1, -1] and not game.active, "Gamepad accept activates the focused exit button")
	game.open_game()
	game.step(NAN)
	game.step(-1.0)
	check(game.strength == 0.0 and game.attempts == 0, "Invalid deltas do not corrupt the round")
	game.cancel_game()
	var original_events := InputMap.action_get_events("interact")
	InputMap.action_erase_events("interact")
	var remapped := InputEventKey.new()
	remapped.physical_keycode = KEY_P
	InputMap.action_add_event("interact", remapped)
	game._refresh_controls()
	check(game._throw_button.text.contains("P"), "The launch hint follows the remapped interaction key")
	game.open_game()
	game.step(0.01)
	game.strength = 0.7
	remapped.pressed = true
	game._input(remapped)
	check(game.attempts == 1 and game.hits == 1, "A remapped physical key launches through the action map")
	game.step(Game.THROW_SECONDS + 0.01)
	remapped.echo = true
	game._input(remapped)
	check(game.attempts == 1, "Keyboard autorepeat cannot launch another throw")
	game.cancel_game()
	InputMap.action_erase_events("interact")
	for event in original_events:
		InputMap.action_add_event("interact", event)
	game.queue_free()
	print("TRUCKERS_VILLAGE_HORSESHOES: ", checks, " checks; failures=", failures.size())
	quit(1 if not failures.is_empty() else 0)
