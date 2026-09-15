extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1
func run() -> void:
	var saves := root.get_node("SaveManager")
	saves._save_dir = OS.get_temp_dir().path_join("geteco_delete_%d" % OS.get_process_id()) + "/"
	saves._save_directory_ready = false
	var path: String = saves.get_slot_path("slot_01")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"save_version": 1, "timestamp": 1}))
	file.close()
	change_scene_to_file("res://ui/MainMenu.tscn")
	await process_frame
	await process_frame
	var menu := current_scene
	check(menu.btn_continue.visible, "Continue available with save")
	menu._on_btn_load_game_pressed()
	var remove: Button
	for row in menu.slot_list_container.get_children():
		for child in row.get_children():
			if child.get_meta("delete_slot", "") == "slot_01": remove = child
	check(remove != null, "Delete action available")
	remove.pressed.emit()
	var dialog: ConfirmationDialog
	for child in menu.get_children():
		if child is ConfirmationDialog: dialog = child
	check(FileAccess.file_exists(path), "Prompt does not delete before confirmation")
	dialog.canceled.emit()
	await process_frame
	check(FileAccess.file_exists(path), "Cancel preserves save")
	remove.pressed.emit()
	for child in menu.get_children():
		if child is ConfirmationDialog: dialog = child
	dialog.confirmed.emit()
	await process_frame
	check(not FileAccess.file_exists(path), "Confirmation removes selected save")
	check(not menu.btn_continue.visible and menu.latest_save.is_empty(), "Continue refreshes after last save deleted")
	check(not saves.delete_save("../outside").success, "Reject traversal")
	file = FileAccess.open(saves.get_slot_path("autosave"), FileAccess.WRITE)
	file.store_string("broken")
	file.close()
	check(saves.delete_save("autosave").success, "Corrupt autosave can be removed")
	quit(1 if failures else 0)
