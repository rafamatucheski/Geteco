extends SceneTree
## Input migration contracts only. Does not write settings or start a game session.
var failures: Array[String] = []
var checks := 0
var controls: Node

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("EQUIPMENT_WHEEL_BINDINGS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func wheel(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event

func pad(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event

func bound(action: String, event: InputEvent) -> bool:
	return InputMap.event_is_action(event, action)

func run() -> void:
	controls = root.get_node("GameInput")
	controls.reset_bindings()
	check(bound("weapon_wheel", key(KEY_Q)), "Q opens the hold wheel by default")
	check(not bound("weapon_next", key(KEY_Q)), "Q no longer immediately cycles a weapon")
	check(bound("interact", key(KEY_E)), "E remains the interaction reused to change wheel page")
	check(bound("weapon_next", wheel(MOUSE_BUTTON_WHEEL_UP)) and bound("weapon_previous", wheel(MOUSE_BUTTON_WHEEL_DOWN)), "mouse wheel retains both immediate weapon directions")
	check(bound("weapon_next", pad(JOY_BUTTON_RIGHT_SHOULDER)) and bound("weapon_previous", pad(JOY_BUTTON_LEFT_SHOULDER)), "controller shoulder buttons retain immediate weapon cycling")
	check(bound("weapon_wheel", pad(JOY_BUTTON_LEFT_SHOULDER)), "L1/LB opens the wheel while its older navigation contexts stay available")

	# Q belongs to separate on-foot and mounted-skate contexts in either remap order.
	check(controls.rebind_slot("weapon_wheel", 0, key(KEY_Q)).ok and bound("skate_flip", key(KEY_Q)), "rebinding the wheel preserves kickflip")
	check(controls.rebind_slot("skate_flip", 0, key(KEY_Q)).ok and bound("weapon_wheel", key(KEY_Q)), "rebinding kickflip preserves the wheel")
	controls.reset_bindings()
	var defaults: Dictionary = controls.export_bindings()
	var pad_defaults: Dictionary = controls.export_gamepad_bindings()

	# This is the historical serialized shape, not generated from the new defaults.
	var legacy := {"weapon_next": [{"key": KEY_Q}, {"mouse": MOUSE_BUTTON_WHEEL_UP}], "weapon_previous": [{"mouse": MOUSE_BUTTON_WHEEL_DOWN}]}
	var original := legacy.duplicate(true)
	controls.import_bindings(legacy)
	check(bound("weapon_wheel", key(KEY_Q)) and not bound("weapon_next", key(KEY_Q)), "legacy Q moves from next weapon to hold wheel")
	check(bound("weapon_next", wheel(MOUSE_BUTTON_WHEEL_UP)) and bound("weapon_previous", wheel(MOUSE_BUTTON_WHEEL_DOWN)), "migration retains legacy mouse-wheel alternatives")
	check(legacy == original, "migration does not mutate the caller's saved settings")
	check(controls.export_gamepad_bindings() == pad_defaults, "keyboard migration leaves controller mappings unchanged")
	var migrated: Dictionary = controls.export_bindings()
	controls.reset_bindings()
	controls.import_bindings(JSON.parse_string(JSON.stringify(migrated)))
	check(controls.export_bindings() == migrated, "migrated settings round-trip without another migration")

	controls.reset_bindings()
	controls.import_bindings({"weapon_next": [{"key": KEY_P}, {"mouse": MOUSE_BUTTON_WHEEL_UP}]})
	check(bound("weapon_next", key(KEY_P)) and bound("weapon_next", wheel(MOUSE_BUTTON_WHEEL_UP)) and not bound("weapon_next", key(KEY_Q)), "legacy customized next-weapon binding is preserved")
	controls.reset_bindings()
	controls.import_bindings({"weapon_next": [{"key": KEY_Q}, {"key": KEY_P}, {"mouse": MOUSE_BUTTON_WHEEL_UP}]})
	check(bound("weapon_wheel", key(KEY_Q)) and bound("weapon_next", key(KEY_P)) and bound("weapon_next", wheel(MOUSE_BUTTON_WHEEL_UP)) and not bound("weapon_next", key(KEY_Q)), "legacy migration removes only Q from custom alternatives")
	controls.reset_bindings()
	controls.import_bindings({"interact": [{"key": KEY_Q}], "weapon_next": [{"mouse": MOUSE_BUTTON_WHEEL_UP}], "skate_flip": []})
	check(bound("interact", key(KEY_Q)) and controls.keyboard_events("weapon_wheel").is_empty() and bound("weapon_next", wheel(MOUSE_BUTTON_WHEEL_UP)), "new wheel does not steal Q from a legacy customized interaction")
	var preserved_custom_q: Dictionary = controls.export_bindings()
	controls.reset_bindings()
	controls.import_bindings(preserved_custom_q)
	check(bound("interact", key(KEY_Q)) and controls.keyboard_events("weapon_wheel").is_empty(), "legacy custom Q remains protected after settings round-trip")

	var customized := defaults.duplicate(true)
	customized.weapon_wheel = [{"key": KEY_Y}]
	customized.weapon_next = [{"key": KEY_Q}, {"mouse": MOUSE_BUTTON_WHEEL_UP}]
	controls.reset_bindings()
	controls.import_bindings(customized)
	check(controls.export_bindings() == customized and bound("weapon_wheel", key(KEY_Y)) and bound("weapon_next", key(KEY_Q)), "explicit modern wheel and next-weapon customizations survive import")
	customized.weapon_wheel = []
	controls.reset_bindings()
	controls.import_bindings(customized)
	check(controls.keyboard_events("weapon_wheel").is_empty() and bound("weapon_next", key(KEY_Q)), "an explicitly unbound wheel is not restored during import")
	controls.reset_bindings()
	var legacy_pad: Dictionary = controls.export_gamepad_bindings()
	legacy_pad.weapon_wheel = []
	controls.import_gamepad_bindings(legacy_pad, 2)
	check(bound("weapon_wheel", pad(JOY_BUTTON_LEFT_SHOULDER)) and bound("weapon_previous", pad(JOY_BUTTON_LEFT_SHOULDER)), "old standard controller gains wheel without losing menu previous action")
	check(controls.rebind_gamepad("radio_previous", pad(JOY_BUTTON_LEFT_SHOULDER)).ok and bound("weapon_wheel", pad(JOY_BUTTON_LEFT_SHOULDER)), "radio customization preserves contextual wheel hold")
	check(controls.rebind_gamepad("weapon_wheel", pad(JOY_BUTTON_LEFT_SHOULDER)).ok and bound("skate_shove", pad(JOY_BUTTON_LEFT_SHOULDER)) and bound("weapon_previous", pad(JOY_BUTTON_LEFT_SHOULDER)), "rebinding wheel preserves skate and older menu controls")
	controls.reset_bindings()
	legacy_pad.weapon_previous = [{"button": JOY_BUTTON_PADDLE1}]
	controls.import_gamepad_bindings(legacy_pad, 2)
	check(controls.gamepad_events("weapon_wheel").is_empty() and bound("weapon_previous", pad(JOY_BUTTON_PADDLE1)), "custom older previous-weapon control is not reinterpreted")
	legacy_pad.weapon_previous = [{"button": JOY_BUTTON_LEFT_SHOULDER}]
	legacy_pad.interact = [{"button": JOY_BUTTON_LEFT_SHOULDER}]
	controls.reset_bindings()
	controls.import_gamepad_bindings(legacy_pad, 2)
	check(controls.gamepad_events("weapon_wheel").is_empty() and bound("interact", pad(JOY_BUTTON_LEFT_SHOULDER)), "migration does not steal a custom interaction button")
	legacy_pad.weapon_wheel = [{"button": JOY_BUTTON_PADDLE2}]
	controls.reset_bindings()
	controls.import_gamepad_bindings(legacy_pad, 2)
	check(bound("weapon_wheel", pad(JOY_BUTTON_PADDLE2)), "an older explicit wheel binding is preserved")
	controls.reset_bindings()
	var modern_pad: Dictionary = controls.export_gamepad_bindings()
	modern_pad.weapon_wheel = []
	controls.import_gamepad_bindings(modern_pad, 3)
	check(controls.gamepad_events("weapon_wheel").is_empty(), "current explicit wheel unbinding remains empty")
	controls.reset_bindings()
	for failure in failures: push_error(failure)
	print("EQUIPMENT_WHEEL_BINDINGS_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
