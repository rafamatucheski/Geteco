extends "res://tests/test_bus_driver_session.gd"
## Reaproveita o cenário real de linha/porta/passageiro/pagamento com toques crus na tela.

func button(action: String) -> void:
	var touch = world.find_child("AndroidControls",true,false)
	check(touch != null,"Android touch overlay is present")
	if touch == null: return
	touch.extra = true
	touch._refresh()
	check(touch.buttons.has(action),"touch action is reachable: "+action)
	if not touch.buttons.has(action): return
	var event := InputEventScreenTouch.new()
	event.index = 88
	event.position = touch.buttons[action].rect.get_center()
	event.pressed = true
	root.push_input(event,true)
	await process_frame
	await process_frame
	event = InputEventScreenTouch.new()
	event.index = 88
	event.pressed = false
	root.push_input(event,true)
	await process_frame
	await process_frame
