extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const INDEX := preload("res://addons/geteco_world_editor/WorldEditorUnitIndex.gd")
var checks := 0
var failures: Array[String] = []
var completed := false
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func observe(reference: WeakRef,rows: Array) -> void:
	await INDEX.run(reference,self,"harbor",rows)
	completed = true
func run() -> void:
	var ui := UI.new()
	ui.edits_path = "res://.godot/index_lifecycle_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	var rows: Array = []
	for i in 50000:
		rows.append({"id":"piece/index_lifecycle/%d" % i,"type":"piece","position":[i%100,i/100],"size":[1,1],"parts":[],"auto":true,"source_record":"index_fixture"})
	observe(weakref(ui),rows)
	check(ui._merging_units and not completed,"Large index yields while the editor remains responsive")
	ui.free()
	for i in 6: await process_frame
	check(completed,"Closing the editor cancels pending indexing and resolves its awaiter")
	var detached := UI.new()
	var reference: WeakRef = weakref(detached)
	await INDEX.run(reference,self,"harbor",rows)
	check(not detached._merging_units,"Detached editors cannot start indexing")
	detached.free()
	print("WORLD_EDITOR_INDEX_LIFECYCLE checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
