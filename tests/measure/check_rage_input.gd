extends "res://tests/measure/measure_katana_session.gd"
## --no-save --skip-arrival --only-rage --skip-temporal
var feedback := ""
func phase(_label: String, _use_rage := false) -> void:
	gameplay.message.connect(func(value: String): feedback=value)
	var focus := Button.new()
	focus.text = "Input regression fixture"
	focus.gui_input.connect(func(event: InputEvent):
		if event.is_action_pressed("rage"): focus.accept_event())
	root.add_child(focus)
	focus.grab_focus()
	await frames(3)
	gameplay.rage.restore(0)
	await press_v()
	check(not gameplay.rage.active and feedback.contains("0%"),"V reports empty meter with GUI focus")
	gameplay.rage.restore(100)
	await press_v()
	check(gameplay.rage.active,"V activates full RAGE before focused GUI consumes key")
	gameplay.rage.cancel("input_test")
	gameplay.rage.restore(100)
	state.equip_weapon("fists")
	feedback = ""
	await press_v()
	check(not gameplay.rage.active and feedback.contains("katana"),"V explains equipped-weapon restriction")
	state.equip_weapon("katana")
	focus.queue_free()
	await frames(2)

func press_v() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_V
	key.pressed = true
	Input.parse_input_event(key)
	await frames(2)
	key = InputEventKey.new()
	key.physical_keycode = KEY_V
	key.pressed = false
	Input.parse_input_event(key)
	await frames(2)
