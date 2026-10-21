extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const INDEX := preload("res://addons/geteco_world_editor/WorldEditorUnitIndex.gd")
var checks := 0
var failures := 0
var completed := false

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func observe(editor: WeakRef, rows: Array) -> void:
	await INDEX.run(editor,self,"harbor",rows)
	completed = true

func run() -> void:
	var ui := UI.new()
	ui.edits_path = "res://.godot/cancel_index_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.live_preview = preload("res://addons/geteco_world_editor/WorldLivePreview.gd").new()
	ui.add_child(ui.live_preview)
	ui.live_preview.editor_owner = ui
	ui.live_preview.hide()
	var original_document: Dictionary = ui.document.duplicate(true)
	var original_ids: Array = ui.canvas.objects.keys()
	var rows: Array = []
	for i in 50000:
		rows.append({"id":"piece/cancel_index/%d" % i,"type":"piece","position":[i%100,i/100],"size":[1,1],"parts":[],"auto":true,"source_record":"cancel_fixture"})
	observe(weakref(ui),rows)
	check(ui._merging_units and not completed,"The large unit merge reaches a cancellable frame boundary")
	var generation: int = ui.unit_index_generation
	var canvas_generation: int = ui.canvas.context_index_revision
	ui.live_preview.cancel_loading()
	check(ui.unit_index_generation > generation,"Cancelling invalidates the pending unit merge")
	check(ui.canvas.context_index_revision > canvas_generation,"Cancelling invalidates any pending context selection index")
	check(not ui._merging_units,"Cancelling immediately releases the editing gate")
	for i in 4: await process_frame
	check(completed,"Cancelled merge resolves without finishing the remaining rows")
	var original_present := true
	for id in original_ids:
		if not ui.canvas.objects.has(id): original_present = false
	check(original_present,"Cancellation retains the previously available catalog")
	check(ui.document == original_document,"Cancelling indexing does not change the editing document")
	completed = false
	observe(weakref(ui),[{"id":"piece/cancel_retry","type":"piece","position":[0,0],"size":[1,1],"parts":[],"auto":true,"source_record":"cancel_fixture"}])
	for i in 120:
		if completed: break
		await process_frame
	check(completed and not ui._merging_units and ui.canvas.objects.has("piece/cancel_retry"),"A new merge completes after cancellation")
	ui.free()
	print("WORLD_EDITOR_CANCEL_INDEX checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
