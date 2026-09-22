extends SceneTree
## Run with --no-save --skip-arrival. Roda do mouse com despacho real de entrada, como na V1:
## a pé troca de arma nos dois sentidos e não mexe na câmera; dirigindo sintoniza a rádio.
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func _wheel(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = Vector2(640, 360)
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for frame in 900:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "production session ready")
	if not failures.is_empty():
		quit(1)
		return
	var state = world.session.state
	for letter in "dukenuke":
		var key := InputEventKey.new()
		key.keycode = letter.to_upper().unicode_at(0)
		key.physical_keycode = key.keycode
		key.unicode = letter.unicode_at(0)
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame
		key = key.duplicate()
		key.pressed = false
		Input.parse_input_event(key)
		await process_frame
	check(state.owns_weapon("pistol"), "arsenal cheat grants weapons")
	state.equip_weapon("fists")
	await process_frame

	# A pé: roda para cima avança, para baixo volta; o enquadramento não muda.
	var size_before: float = world.camera.target_size
	await _wheel(MOUSE_BUTTON_WHEEL_UP)
	var after_up: String = world.gameplay.equipped()
	check(after_up != "fists", "wheel up selects the next weapon (got %s)" % after_up)
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(world.gameplay.equipped() == "fists", "wheel down returns to the previous weapon (got %s)" % world.gameplay.equipped())
	check(is_equal_approx(world.camera.target_size, size_before), "wheel never zooms the camera")

	# Dirigindo: a estação do carro liga ao entrar, a roda sintoniza e a arma não muda.
	var car: CharacterBody3D = world.driving.car
	var entered := false
	for side in [-1, 1]:
		var approach: Vector3 = car.to_global(Vector3(side * (car.half_width + 0.65), 0.04, 0.15))
		if not world.session.position_clear(approach): continue
		world.player.teleport(approach)
		await physics_frame
		if world.driving.interact():
			entered = true
			break
	check(entered, "enters the starting car")
	if entered:
		for frame in 90:
			await process_frame
			if not world.driving.is_body_transition_active(): break
		await process_frame
		var audio = world.production.world_audio
		check(audio.radio_index == 0 and audio.radio.playing, "entering a car turns on its station (PORTO FM)")
		var weapon_before: String = world.gameplay.equipped()
		await _wheel(MOUSE_BUTTON_WHEEL_UP)
		check(audio.radio_index == 1 and audio.radio.playing, "wheel up tunes the next station (got %d)" % audio.radio_index)
		check(audio.radio_notice != null and audio.radio_notice.visible and audio.radio_notice.text.begins_with("PORTO NOITE"), "station name is shown")
		await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
		await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
		check(audio.radio_index == -1 and not audio.radio.playing, "wheel down reaches the off slot")
		check(world.gameplay.equipped() == weapon_before, "wheel in the car never changes weapon")
		check(is_equal_approx(world.camera.target_size, world.camera._last_auto_size), "wheel in the car keeps automatic framing")
		await _wheel(MOUSE_BUTTON_WHEEL_UP)
		check(audio.radio_index == 0, "wheel up wraps from off to the first station")
		check(car.get_meta(&"radio_index", -99) == 0, "the car remembers its station")
	print("MOUSE_WHEEL_WEAPON_RADIO ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)
