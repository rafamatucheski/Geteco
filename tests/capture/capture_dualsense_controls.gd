extends SceneTree
## SettingsMenu real em 1280x720. Só padrões em memória; nunca salva preferências.
const OUTPUT := "res://evidence/dualsense-20261002/"
const FILE_NAMES := ["00-on-foot", "01-combat", "02-vehicle", "03-skate", "04-ski", "05-motocross", "06-camera", "07-menus-map"]
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func shot(file_name: String) -> void:
	for _frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + file_name + ".png"))
	if result != OK: failures.append("capture %s (%d)" % [file_name, result])
	print("DUALSENSE_CAPTURE ", file_name, " ", result)

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Use Godot .NET renderizado com --no-save.")
		quit(2)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if directory_error != OK:
		push_error("Não foi possível criar a pasta de capturas (%d)." % directory_error)
		quit(2)
		return
	root.get_node("V2Launch").direct_start_consumed = true
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var menu: Control = load("res://ui/SettingsMenu.tscn").instantiate()
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	menu.open()
	var controls := root.get_node("GameInput")
	controls.reset_bindings()
	controls.set_controller_layout(1)
	menu._select_tab(2)
	for index in FILE_NAMES.size():
		menu._context_choice.select(index)
		menu._context_choice.item_selected.emit(index)
		menu._pages[2].scroll_vertical = 0
		await shot(FILE_NAMES[index])
	for button in menu._controls_list.find_children("*", "Button", true, false):
		if button.get_meta("binding_key", "") == "skate_flip:pad":
			button.grab_focus()
			break
	await shot("08-bindings-skate")
	menu.close()
	menu.queue_free()
	await process_frame
	print("DUALSENSE_CAPTURE ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)
