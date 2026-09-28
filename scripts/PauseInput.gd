extends Node
var world: Node3D

func _unhandled_input(event: InputEvent) -> void:
	if world.has_meta("menu_preview"): return
	if world.session != null:
		var arrival = world.session.get("arrival")
		if arrival != null and arrival.phase == "opening": return
	if (event.is_action_pressed("pause_game") or (world.pause_panel.visible and event.is_action_pressed("ui_cancel"))) and not event.is_echo():
		world._toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if event is not InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_F3: world.diagnostic_label.visible = not world.diagnostic_label.visible
		KEY_BRACKETLEFT:
			if world.diagnostic_label.visible and not get_tree().paused: world.set_population(world.population-24)
		KEY_BRACKETRIGHT:
			if world.diagnostic_label.visible and not get_tree().paused: world.set_population(world.population+24)
