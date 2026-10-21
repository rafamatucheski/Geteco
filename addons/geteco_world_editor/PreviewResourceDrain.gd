@tool
extends Node
## ResourceLoader has no cancellation API. Collect a pending read after it finishes,
## without blocking the editor when its preview panel is closed.
var resource_path := ""
var cleanup_folder := ""
var cleanup_revision := 0

func _process(_delta: float) -> void:
	var state := ResourceLoader.load_threaded_get_status(resource_path)
	if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return
	if state == ResourceLoader.THREAD_LOAD_LOADED:
		ResourceLoader.load_threaded_get(resource_path)
	if not resource_path.is_empty(): DirAccess.remove_absolute(resource_path)
	if cleanup_folder.begins_with("res://.godot/world_live_%d_" % OS.get_process_id()):
		var prefix := "view_%d_" % cleanup_revision
		for filename in DirAccess.get_files_at(cleanup_folder):
			if filename.begins_with(prefix) and (filename.ends_with(".scn") or filename.ends_with(".res")):
				DirAccess.remove_absolute(cleanup_folder+"/"+filename)
	queue_free()
