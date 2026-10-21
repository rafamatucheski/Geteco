extends SceneTree
const DATA := preload("res://world/editing/WorldEditData.gd")
const CANVAS := preload("res://addons/geteco_world_editor/WorldMapCanvas.gd")
class EditorProbe:
	extends "res://addons/geteco_world_editor/WorldEditor.gd"
	var captured := {}
	func _commit(row: Dictionary) -> void: captured = row
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var official := DATA.disk_hash()
	var editor := EditorProbe.new()
	editor.canvas = CANVAS.new()
	editor.add_child(editor.canvas)
	var source := {"id":"piece/cobra/cobra_footpath/0","type":"piece","source_record":"test","position":[40,100],"rotation":37.0,"outline":[[-2,-1],[2,-1],[2,1],[-2,1]],"stretch":[1.7,.6],"height_stretch":1.25,"lift":.8}
	editor.canvas.objects[source.id] = source
	editor.canvas.selected_id = source.id
	editor._duplicate()
	var copy: Dictionary = editor.captured
	check(not copy.is_empty() and copy.id!=source.id and copy.clone_of==source.id,"Ctrl+D creates a new identity with the original geometry source")
	check(copy.position==[43.0,103.0],"Ctrl+D offsets the new piece")
	for key in ["rotation","outline","stretch","height_stretch","lift"]: check(copy.get(key)==source[key],"Ctrl+D preserves edited "+key)
	check(DATA.validate_entity(copy).is_empty(),"Duplicated edited contour satisfies the persistent piece contract")
	if copy.has("outline"):
		copy.outline[0][0] = -99
		check(source.outline[0][0]==-2,"Editing the duplicate's contour does not mutate the original")
	editor.free()
	check(DATA.disk_hash()==official,"Duplication regression never writes the official document")
	print("WORLD_EDITOR_DUPLICATE_SHAPE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
