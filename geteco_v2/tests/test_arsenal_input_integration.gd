extends SceneTree
## Run with --no-save --skip-arrival. Uses real input dispatch and production session.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	var world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 600:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("ARSENAL: production session did not become ready")
		quit(1)
		return
	for letter in "dukenuke":
		var event := InputEventKey.new()
		event.keycode = letter.to_upper().unicode_at(0)
		event.physical_keycode = event.keycode
		event.unicode = letter.unicode_at(0)
		event.pressed = true
		Input.parse_input_event(event)
		await process_frame
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		await process_frame
	if not world.session.state.economy.cheat_all_weapons or not world.session.state.owns_weapon("pistol"):
		push_error("ARSENAL: typing did not grant weapons")
		quit(1)
		return
	print("ARSENAL_INPUT_PASS: real input granted weapons")
	quit(0)
