@tool
extends RefCounted
## Static ownership: closing the editor cannot resume a coroutine on a freed UI.
static func run(reference: WeakRef,tree: SceneTree,area: String,signature: String,rows: Array) -> void:
	var editor = reference.get_ref()
	if not _current(editor,area,signature): return
	var key := area+"/"+signature
	if editor.topography_units_installed.get(area,"") == signature or editor.topography_unit_jobs.has(key): return
	var token := Time.get_ticks_usec()
	var generation: int = editor.environment_generation
	editor.topography_unit_jobs[key] = token
	while editor._merging_units:
		await tree.process_frame
		editor = reference.get_ref()
		if not _current(editor,area,signature) or editor.environment_generation != generation:
			_release(editor,key,token)
			return
	await preload("res://addons/geteco_world_editor/WorldEditorUnitIndex.gd").run(reference,tree,area,rows)
	editor = reference.get_ref()
	if _current(editor,area,signature) and editor.environment_generation == generation:
		editor.topography_units_installed[area] = signature
	_release(editor,key,token)

static func _current(editor,area: String,signature: String) -> bool:
	if not is_instance_valid(editor) or not editor.is_inside_tree(): return false
	if not str(editor.active_interior).is_empty() or is_instance_valid(editor.live_preview): return false
	return signature == preload("res://addons/geteco_world_editor/WorldLivePreview.gd").terrain_revision(editor.document,area)

static func _release(editor,key: String,token: int) -> void:
	if is_instance_valid(editor) and int(editor.topography_unit_jobs.get(key,-1)) == token:
		editor.topography_unit_jobs.erase(key)
