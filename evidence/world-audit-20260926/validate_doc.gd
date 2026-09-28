extends SceneTree
## Valida world_edits.json com as mesmas regras do editor.
func _initialize() -> void:
	var loaded = preload("res://world/editing/WorldEditData.gd").read_document()
	print("DOC_ERROR=[", loaded.error, "]")
	quit(0 if str(loaded.error).is_empty() else 1)
