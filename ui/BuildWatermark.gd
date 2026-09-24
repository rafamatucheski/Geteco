extends CanvasLayer

# Marca d'água de build: fica acima de toda a interface (menu, HUD, pausa) para que
# capturas e vídeos desta fase sempre saiam identificados como alpha.

const LAYER := 128


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var label := Label.new()
	label.text = "Alpha build · work in progress · v%s%s" % [
		str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		_commit_suffix(),
	]
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(12, 8)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	label.add_theme_constant_override("outline_size", 3)
	add_child(label)


# Em desenvolvimento o .git está ao lado do projeto; num export ele não existe e o
# sufixo simplesmente some.
func _commit_suffix() -> String:
	var git_dir := ProjectSettings.globalize_path("res://.git")
	var head := FileAccess.get_file_as_string(git_dir.path_join("HEAD")).strip_edges()
	if head.begins_with("ref: "):
		head = FileAccess.get_file_as_string(git_dir.path_join(head.substr(5))).strip_edges()
	return " (%s)" % head.left(7) if head.length() >= 7 else ""
