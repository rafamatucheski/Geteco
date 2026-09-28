extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	await process_frame
	print("EDITOR_HOST_AVAILABLE ",Engine.is_editor_hint()," ",EditorInterface.get_editor_main_screen() != null)
	if not Engine.is_editor_hint() or EditorInterface.get_editor_main_screen() == null:
		quit(2)
		return
	var plugin = load("res://addons/geteco_world_editor/plugin.gd").new()
	root.add_child(plugin)
	plugin._make_visible(true)
	var before := EditorInterface.is_distraction_free_mode_enabled()
	plugin.screen.focus_toggle.pressed.emit()
	assert(EditorInterface.is_distraction_free_mode_enabled())
	plugin.screen.focus_toggle.pressed.emit()
	assert(EditorInterface.is_distraction_free_mode_enabled() == before)
	plugin.screen.focus_toggle.pressed.emit()
	plugin._make_visible(false)
	assert(EditorInterface.is_distraction_free_mode_enabled() == before)
	plugin._make_visible(true)
	assert(EditorInterface.is_distraction_free_mode_enabled())
	plugin.free()
	assert(EditorInterface.is_distraction_free_mode_enabled() == before)
	print("WORLD_LAYOUT_HOST passed=5")
	quit()
