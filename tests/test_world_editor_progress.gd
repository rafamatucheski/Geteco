extends SceneTree
const PANEL := preload("res://addons/geteco_world_editor/WorldLivePreview.gd")
const CONTEXT := preload("res://addons/geteco_world_editor/WorldSessionContext.gd")
var failures := 0
var checks := 0
class EditStub extends Control:
	var synchronizing := false
	var index_revision := 0
	func cancel() -> void: pass

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func run() -> void:
	var panel := PANEL.new()
	root.add_child(panel)
	panel.folder = "res://.godot/world_live_%d_progress_test" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(panel.folder)
	panel.revision = 3
	panel.request_started = Time.get_ticks_msec()
	var file := FileAccess.open(panel.folder+"/progress.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"revision":2,"phase":"Cena antiga","done":9,"total":10,"updated":10}))
	file.close()
	panel._read_progress()
	check(not panel.message.text.contains("Cena antiga"),"Progress from superseded requests is ignored")
	file = FileAccess.open(panel.folder+"/progress.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"revision":3,"phase":"Construindo trechos","done":4,"total":12,"updated":20}))
	file.close()
	panel._read_progress()
	check(panel.message.text.contains("4/12"),"Loading names the stage and number of completed cells")
	check(panel.last_progress_at > 0,"An active worker refreshes the inactivity deadline")
	check(panel.message.tooltip_text.contains("worker.log"),"Full diagnostic log is discoverable")
	var progress_before := panel.message.text
	file = FileAccess.open(panel.folder+"/progress.json",FileAccess.WRITE)
	file.store_string("{\"revision\":")
	file.close()
	panel._read_progress()
	check(panel.message.text == progress_before,"Transient incomplete IPC reads preserve the visible progress")
	check(panel.last_protocol_error.contains("progress.json"),"Persistent IPC corruption remains diagnosable without error spam")
	file = FileAccess.open(panel.folder+"/worker.log",FileAccess.WRITE)
	file.store_string("SCRIPT ERROR: Parse Error: Invalid declaration\n at: test_source.gd:42\n")
	file.close()
	panel._announce("A prévia encerrou.","error")
	check(panel.message.text.contains("test_source.gd:42"),"Worker failure exposes the script and source line")
	check(CONTEXT.preview_in_range(Vector3.ZERO,Vector3(5000,0,5000),90,-1),"Full-map request includes distant session scenery")
	check(not CONTEXT.preview_in_range(Vector3.ZERO,Vector3(5000,0,5000),90,0),"Nearby preview keeps distant scenery unloaded")
	check(CONTEXT.preview_in_range(Vector3.ZERO,Vector3(250,0,0),90,3),"Expanded preview includes scenery within loaded cells")
	panel.surface.size = Vector2(1200,600)
	panel._fit_bounds([0,-10,0,1500,200,1000])
	check(panel.focus.is_equal_approx(Vector3(750,90,500)),"Whole-map framing centers the authored three-dimensional bounds")
	check(panel.view_size >= 750,"Whole-map framing accounts for viewport aspect and authored extent")
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh = BoxMesh.new()
	batch.multimesh.instance_count = 1
	batch.set_meta("preview_instance_transforms",[Transform3D.IDENTITY])
	batch.set_meta("preview_instance_colors",[Color.RED])
	panel.scene_root.add_child(batch)
	panel._restore_instance_transforms(batch)
	check(not batch.multimesh.use_colors,"Restoring preview batches preserves the authored color-usage flag")
	check(not batch.has_meta("preview_instance_colors"),"Unused color metadata is collected without issuing invalid RenderingServer calls")
	panel.geometry = Node3D.new()
	panel.scene_root.add_child(panel.geometry)
	var unsaved := preload("res://world/editing/WorldEditData.gd").empty_document()
	unsaved.regions.harbor["new/progress"] = preload("res://world/editing/WorldEditData.gd").new_entity("tree",Vector2.ZERO)
	panel.desired = {"document":unsaved.duplicate(true),"focus":[0,0],"area":"harbor","radius":0,"refresh":0}
	panel.submitted = panel.desired.duplicate(true)
	panel.retry()
	check(panel.desired.get("document",{}) == unsaved,"Retry retains all unsaved requested edits")
	check(panel.submitted.is_empty() and not panel.timer.is_stopped(),"Retry schedules a fresh request after an error")
	panel.cancel_loading()
	check(panel.timer.is_stopped() and panel.desired.is_empty(),"Cancellation stops pending work until another request")
	check(is_instance_valid(panel.geometry),"Cancellation preserves the currently visible geometry")
	check(unsaved.regions.harbor.has("new/progress"),"Cancellation preserves the editing document")
	panel.reach = 3
	panel.request(unsaved,Vector2.ZERO,"harbor")
	panel.submitted = panel.desired.duplicate(true)
	panel.revision = 11
	var pending: Dictionary = panel.desired.duplicate(true)
	var debounce_before: int = panel.ready_at
	for index in 50: panel.request(unsaved,Vector2(index*20,index*10),"harbor")
	check(panel.desired == pending and panel.submitted == pending and panel.revision == 11,"Fifty focus changes during full-map loading never restart identical geometry work")
	check(panel.ready_at == debounce_before and panel.focus.x == 980,"Camera panning stays responsive without postponing full-map loading")
	panel.refresh()
	panel.request(unsaved,Vector2(980,490),"harbor")
	check(panel.desired.refresh != pending.refresh,"An explicit refresh still supersedes full-map work")
	var changed_document: Dictionary = unsaved.duplicate(true)
	changed_document.regions.harbor["new/progress"].position = [10,20]
	panel.request(changed_document,Vector2(980,490),"harbor")
	check(panel.desired.document == changed_document,"Actual document changes still update the full-map request")
	panel.cancel_loading()
	panel.request_topography(unsaved,Vector2.ZERO,"harbor")
	pending = panel.desired.duplicate(true)
	debounce_before = panel.ready_at
	for index in 50: panel.request_topography(unsaved,Vector2(index*20,index*10),"harbor")
	check(panel.desired == pending and panel.ready_at == debounce_before,"Background full-region topography also ignores camera-only request changes")
	panel.cancel_loading()
	panel.edit_control = EditStub.new()
	panel.add_child(panel.edit_control)
	var refresh_before: int = panel.refresh_count
	panel.after_commit({}, {"id":"terrain/test","type":"terrain"})
	panel.after_commit({}, {"id":"terrain/test","type":"terrain","deleted":true})
	check(panel.refresh_count == refresh_before+2,"Both terrain edits and terrain deletion rebuild the actual surface")
	panel.free()
	DirAccess.remove_absolute("res://.godot/world_live_%d_progress_test/progress.json" % OS.get_process_id())
	DirAccess.remove_absolute("res://.godot/world_live_%d_progress_test/worker.log" % OS.get_process_id())
	print("WORLD_EDITOR_PROGRESS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
