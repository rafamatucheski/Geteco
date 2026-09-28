@tool
extends EditorPlugin
var screen: Control
var _owns_focus_mode := false
var _previous_focus_mode := false
var _opened := false
func _enter_tree() -> void:
	screen = preload("res://addons/geteco_world_editor/WorldEditor.gd").new()
	# Main screen is a VBoxContainer: anchors alone do not allocate its height.
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(screen)
	screen.hide()
	screen.map_focus_changed.connect(_map_focus_changed)
func _exit_tree() -> void:
	_restore_editor_panels()
	if is_instance_valid(screen): screen.queue_free()
func _has_main_screen() -> bool: return true
func _get_plugin_name() -> String: return "Mundo"
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("WorldEnvironment", "EditorIcons")
func _make_visible(visible: bool) -> void:
	if is_instance_valid(screen):
		screen.visible = visible
		if visible:
			if not _opened:
				_opened = true
				screen._set_view_mode(1)
			_map_focus_changed(screen.map_expanded)
		else: _restore_editor_panels()

func _map_focus_changed(expanded: bool) -> void:
	if expanded and is_instance_valid(screen) and screen.visible:
		if _owns_focus_mode: return
		_previous_focus_mode = EditorInterface.is_distraction_free_mode_enabled()
		_owns_focus_mode = true
		EditorInterface.set_distraction_free_mode(true)
	else: _restore_editor_panels()

func _restore_editor_panels() -> void:
	if not _owns_focus_mode: return
	_owns_focus_mode = false
	EditorInterface.set_distraction_free_mode(_previous_focus_mode)
