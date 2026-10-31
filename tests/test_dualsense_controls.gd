extends SceneTree
## Contratos de entrada e migração de configurações. Nunca grava as configurações do jogador.
var failures: Array[String] = []
var checks := 0
var controls: Node

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("DUALSENSE_CONTROLS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func button(index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = true
	return event

func axis(index: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = index
	event.axis_value = value
	return event

func bound(action: String, event: InputEvent) -> bool:
	return InputMap.event_is_action(event, action)

func has_pad(action: String) -> bool:
	return not controls.gamepad_events(action).is_empty()

func run() -> void:
	controls = root.get_node("GameInput")
	controls.reset_bindings()
	controls.set_controller_layout(1)
	check(bound("surrender", button(JOY_BUTTON_B)), "Circle offers surrender on foot")
	check(bound("radio_toggle", button(JOY_BUTTON_DPAD_RIGHT)), "right D-pad toggles vehicle radio")
	check(bound("weapon_flashlight", button(JOY_BUTTON_DPAD_UP)) and bound("weapon_flashlight", button(JOY_BUTTON_MISC1)), "flashlight works with D-pad and original Mic alternative")
	check(has_pad("camera_left") and has_pad("camera_right"), "both camera directions work without keyboard")
	check(bound("skate_ollie", button(JOY_BUTTON_A)) and bound("skate_flip", button(JOY_BUTTON_RIGHT_SHOULDER)) and bound("skate_shove", button(JOY_BUTTON_LEFT_SHOULDER)), "skate offers all three tricks")
	check(bound("tank_fire", button(JOY_BUTTON_B)) and bound("pause_game", button(JOY_BUTTON_START)), "tank cannon and pause remain reachable")

	# Personalizar um dos contextos compartilhados não pode apagar outro em silêncio.
	check(controls.rebind_gamepad("weapon_next", button(JOY_BUTTON_RIGHT_SHOULDER)).ok, "remap next weapon succeeds")
	check(bound("skate_flip", button(JOY_BUTTON_RIGHT_SHOULDER)) and bound("radio_next", button(JOY_BUTTON_RIGHT_SHOULDER)), "next weapon remap preserves kickflip and radio")
	check(controls.rebind_gamepad("radio_previous", button(JOY_BUTTON_LEFT_SHOULDER)).ok, "remap previous radio succeeds")
	check(bound("skate_shove", button(JOY_BUTTON_LEFT_SHOULDER)) and bound("weapon_previous", button(JOY_BUTTON_LEFT_SHOULDER)), "radio remap preserves shove-it and previous weapon")
	check(controls.rebind_gamepad("handbrake", button(JOY_BUTTON_A)).ok and bound("skate_ollie", button(JOY_BUTTON_A)), "vehicle handbrake preserves ollie")
	check(controls.rebind_gamepad("headlights", button(JOY_BUTTON_DPAD_UP)).ok and bound("weapon_flashlight", button(JOY_BUTTON_DPAD_UP)), "vehicle headlights preserve weapon flashlight")
	check(controls.rebind_gamepad("tank_fire", button(JOY_BUTTON_B)).ok and bound("surrender", button(JOY_BUTTON_B)), "tank cannon preserves pedestrian surrender")
	check(controls.rebind_gamepad("accelerate", axis(JOY_AXIS_TRIGGER_RIGHT, 1)).ok and bound("fire", axis(JOY_AXIS_TRIGGER_RIGHT, 1)), "accelerator preserves firearm trigger")
	check(controls.rebind_gamepad("interact", button(JOY_BUTTON_Y)).ok and not has_pad("vehicle_interact"), "actions simultaneously available on foot cannot share Triangle")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	key.pressed = true
	check(controls.rebind_slot("weapon_next", 0, key).ok and bound("skate_flip", key), "keyboard contextual remap preserves skate too")

	controls.reset_bindings()
	var modern: Dictionary = controls.export_gamepad_bindings()
	controls.clear_gamepad("surrender")
	controls.clear_gamepad("camera_left")
	var cleared: Dictionary = controls.export_gamepad_bindings()
	controls.reset_bindings()
	controls.import_gamepad_bindings(cleared)
	check(not has_pad("surrender") and not has_pad("camera_left"), "current explicit unbindings survive import")
	controls.reset_bindings()
	controls.import_gamepad_bindings(modern)
	check(controls.export_gamepad_bindings() == modern, "current binding export round-trips completely")

	# Estas entradas eram emitidas vazias pelos padrões de antes da câmera/rendição.
	var legacy: Dictionary = modern.duplicate(true)
	for action in ["camera_left", "camera_right", "surrender", "radio_toggle"]: legacy[action] = []
	legacy.weapon_flashlight = [{"button": JOY_BUTTON_MISC1}]
	controls.reset_bindings()
	controls.import_gamepad_bindings(legacy, 0)
	check(has_pad("camera_left") and has_pad("camera_right") and bound("surrender", button(JOY_BUTTON_B)) and bound("radio_toggle", button(JOY_BUTTON_DPAD_RIGHT)), "old empty defaults gain newly supported commands")
	check(bound("weapon_flashlight", button(JOY_BUTTON_DPAD_UP)) and bound("weapon_flashlight", button(JOY_BUTTON_MISC1)), "old Mic-only flashlight gains a standard reachable button")

	legacy.camera_left = [{"button": JOY_BUTTON_PADDLE1}]
	legacy.weapon_flashlight = [{"button": JOY_BUTTON_PADDLE2}]
	controls.reset_bindings()
	controls.import_gamepad_bindings(legacy, 0)
	check(bound("camera_left", button(JOY_BUTTON_PADDLE1)) and controls.gamepad_events("camera_left").size() == 1, "legacy customized camera is preserved")
	check(bound("weapon_flashlight", button(JOY_BUTTON_PADDLE2)) and controls.gamepad_events("weapon_flashlight").size() == 1, "legacy customized flashlight is preserved")
	legacy.surrender = []
	legacy.interact = [{"button": JOY_BUTTON_B}]
	controls.reset_bindings()
	controls.import_gamepad_bindings(legacy, 0)
	check(bound("interact", button(JOY_BUTTON_B)) and not bound("surrender", button(JOY_BUTTON_B)), "migration never steals a custom gameplay button")
	check(not controls.rebind_gamepad("fire", button(JOY_BUTTON_START)).ok and bound("pause_game", button(JOY_BUTTON_START)), "Options remains reserved for pause")
	controls.reset_bindings()
	Input.parse_input_event(button(JOY_BUTTON_LEFT_STICK))
	Input.flush_buffered_events()
	var release := button(JOY_BUTTON_LEFT_STICK)
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	check(controls.sprint_toggled, "L3 enables toggle sprint")
	Input.parse_input_event(axis(JOY_AXIS_RIGHT_X, 1))
	Input.flush_buffered_events()
	Input.joy_connection_changed.emit(0, false)
	check(not controls.sprint_toggled and is_zero_approx(controls.camera_rotation()), "disconnect clears sprint and camera movement")
	Input.parse_input_event(axis(JOY_AXIS_RIGHT_X, 0))
	Input.flush_buffered_events()
	for failure in failures: push_error(failure)
	print("DUALSENSE_CONTROLS_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
