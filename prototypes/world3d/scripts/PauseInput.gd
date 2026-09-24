extends Node
var world: Node3D

func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_ESCAPE: world._toggle_pause()
		KEY_F3: world.diagnostic_label.visible = not world.diagnostic_label.visible
		KEY_BRACKETLEFT:
			if world.diagnostic_label.visible and not get_tree().paused: world.set_population(world.population-24)
		KEY_BRACKETRIGHT:
			if world.diagnostic_label.visible and not get_tree().paused: world.set_population(world.population+24)
