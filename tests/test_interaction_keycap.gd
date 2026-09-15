extends SceneTree
const CAP = preload("res://ui/InteractionKeycap.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var presentation := preload("res://ui/GameplayPresentation.gd").new()
	world.add_child(presentation)
	await process_frame
	await process_frame
	presentation.set_process(false)
	var input := root.get_node("GameInput")
	input.reset_bindings()
	var label := Label.new()
	label.text = "E"
	label.position = Vector2(140, 100)
	label.size = Vector2(160, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color.YELLOW)
	world.add_child(label)
	presentation._update_hints()
	var cap := label.get_node_or_null("InteractionKeycap")
	check(cap != null, "Dynamically added world prompts receive the shared keycap")
	check(label.text == input.hint("interact"), "Keycap preserves the current input binding")
	input.using_gamepad = true
	presentation._update_hints()
	check(label.text == input.hint("interact"), "Controller glyph replaces keyboard key")
	check(label.get_child_count() == 1, "Repeated refresh reuses the same keycap")
	label.hide()
	check(not cap.is_visible_in_tree(), "Keycap hides together with its interaction target")
	label.show()
	label.text = "Missão concluída"
	presentation._update_hints()
	check(not cap.visible and label.text == "Missão concluída", "Functional text does not receive a keycap")
	check(label.get_theme_font_size("font_size") == 11 and label.get_theme_color("font_color") == Color.YELLOW, "Original typography is restored when a prompt becomes text")
	label.text = "E"
	input.using_gamepad = false
	presentation._update_hints()
	check(cap.visible, "Returning to interaction restores the keycap")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	InputMap.action_erase_events("interact")
	InputMap.action_add_event("interact", ev)
	presentation._update_hints()
	check(label.text == "F", "Rebound key is displayed without hardcoding E")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(880, 320)
		root.content_scale_size = Vector2i(880, 320)
		RenderingServer.set_default_clear_color(Color("101820"))
		for index in 4:
			var sample := Label.new()
			sample.text = ["E", "F", "A", "Enter"][index]
			sample.position = Vector2(60 + index*200, 145)
			sample.size = Vector2(160, 28)
			sample.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			world.add_child(sample)
			CAP.sync(sample, true)
		label.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/interaction-review/keycaps.png")
	world.remove_child(label)
	check(label not in presentation._labels, "Unloaded interaction targets leave the presentation registry")
	label.free()
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
