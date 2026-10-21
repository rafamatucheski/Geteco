extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const SNAPSHOTS := preload("res://world/editing/WorldStaticSnapshots.gd")
class EditStub:
	extends RefCounted
	var groups: Dictionary = {}
class PreviewStub:
	extends Control
	var edit_control = EditStub.new()
	var focus := Vector3.ZERO
	var folder := ""
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	var official := DATA.disk_hash()
	var ui := UI.new()
	var path := "res://.godot/workflow_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()]
	ui.edits_path = path
	ui.draft_path = path+".draft"
	root.add_child(ui)
	await process_frame
	check(ui.initialized and ui.activity_log.size() >= 3,"Startup exposes initialization phases")
	var coarse := {"id":"piece/fixture","type":"piece","position":[0,0],"size":[4,6],"parts":[[0,0,4,6,1,"ffffff"]]}
	var moved := coarse.duplicate(true)
	check(ui._overlay_piece(moved,coarse,{"id":"piece/fixture","type":"piece","position":[10,20],"rotation":0}),"Coarse rectangular catalog piece accepts movement")
	check(moved.parts[0].size() == 7 and is_equal_approx(moved.parts[0][0],10) and is_equal_approx(moved.parts[0][1],20),"Coarse geometry gains a valid transformed outline without script error")
	var tree := DATA.new_entity("tree",Vector2(50,110))
	ui._commit(tree)
	check(not FileAccess.file_exists(path),"Editing never saves the world implicitly")
	check(FileAccess.file_exists(ui.draft_path),"Unpublished edits have a recoverable draft")
	check(ui.save_button.text.ends_with("*"),"Unsaved state stays visible when sidebars are narrow")
	var pending: Dictionary = ui.document.duplicate(true)
	ui.document = DATA.empty_document()
	ui.edits_path = path+".other"
	ui._restore_draft()
	check(ui.document == DATA.empty_document(),"Draft never leaks into a different world file")
	ui.edits_path = path
	ui._restore_draft()
	check(ui.document.regions.harbor.has(tree.id) and ui.document.regions.harbor.size() == pending.regions.harbor.size() and DATA.point(ui.document.regions.harbor[tree.id].position).is_equal_approx(Vector2(50,110)) and ui.restored_draft,"Same-world draft is restored without publishing")
	var source := "piece/neco/Office"
	check(ui.canvas.objects.has(source),"Native scenery fixture exists")
	if ui.canvas.objects.has(source):
		ui._select(source)
		check(ui._copy(),"Native scenery can be copied with the normal clipboard")
		ui._paste()
		var before_crossing: Dictionary = ui.document.duplicate(true)
		ui._place("piece",Vector2(850,-450))
		check(ui.document == before_crossing and not ui.placement_template.is_empty(),"Unsupported cross-map native paste reports a clear error without consuming clipboard or edits")
		ui._place("piece",Vector2(-45,35))
		var id: String = ui.canvas.selected_id
		check(id.begins_with("piece/clone/") and ui.document.regions.harbor.has(id),"Paste creates a persistent independent scenery identity")
		if ui.document.regions.harbor.has(id):
			check(ui.document.regions.harbor[id].clone_of == source,"Scenery copy retains source for runtime rebuild")
		ui.undo()
		check(not ui.document.regions.harbor.has(id),"Undo removes pasted scenery")
		ui.redo()
		check(ui.document.regions.harbor.has(id),"Redo restores pasted scenery")
	var paving_id := ""
	for row in ui.canvas.objects.values():
		if row.get("paving",false): paving_id = str(row.id); break
	check(not paving_id.is_empty(),"Existing pavement fixture available")
	if not paving_id.is_empty():
		ui._select(paving_id)
		check(ui._copy(),"Existing pavement can be copied as an independent floor")
		var floor_copy := ui._clone_at(ui.clipboard_row,Vector2(65,115))
		check(not floor_copy.has("paving") and DATA.validate_entity(floor_copy).is_empty(),"Copied pavement sheds native identity and remains valid ground")
	if ui.canvas.objects.has(source):
		var fixture := Node3D.new()
		root.add_child(fixture)
		fixture.position = DATA.xyz(ui.canvas.objects[source].position)
		fixture.position.y = 12.0
		fixture.set_meta("world_snapshot_ground_height",12.0)
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		fixture.add_child(mesh)
		var preview := PreviewStub.new()
		preview.focus.y = 99.0
		preview.edit_control.groups[source] = [fixture]
		root.add_child(preview)
		ui.canvas.selected_id = source
		ui.live_preview = preview
		var captured_ok := ui._copy()
		ui.live_preview = null
		preview.free()
		fixture.free()
		check(captured_ok and ui.clipboard_row.model == "static_snapshot", "Loaded native selection uses static geometry clipboard")
		if captured_ok:
			var snapshot_id: String = ui.clipboard_row.snapshot_id
			var geometry := SNAPSHOTS.instantiate(ui.clipboard_row)
			root.add_child(geometry)
			var meshes := geometry.find_children("*","MeshInstance3D",true,false)
			check(not meshes.is_empty() and is_zero_approx(meshes[0].global_position.y),"Copy uses the object's ground height rather than the camera focus height")
			geometry.free()
			check(FileAccess.file_exists(SNAPSHOTS.STAGING+snapshot_id+".scn"),"Copy stages geometry without publishing the world")
			ui._paste()
			ui._place("prop",Vector2(850,-450))
			var snapshot_row_id: String = ui.canvas.selected_id
			check(ui.document.regions.mountain.has(snapshot_row_id) and ui.document.regions.mountain[snapshot_row_id].snapshot_id == snapshot_id,"Captured geometry pastes into another map with its resource identity")
			ui._select(snapshot_row_id)
			ui._set_value("scale",1.5)
			check(is_equal_approx(ui.document.regions.mountain[snapshot_row_id].scale,1.5),"Snapshot inspector supports independent scaling without procedural model lookup")
			check(ui._copy() and ui.clipboard_row.snapshot_id == snapshot_id,"Recopying an authored snapshot retains its geometry")
			ui.undo()
			ui.undo()
	check(ui.save(),"Explicit Save publishes the draft")
	check(DATA.read_document(path).document.regions.harbor.has(tree.id),"Published world survives disk reload")
	check(ui.save_state.text == "Mundo salvo" and not ui.save_button.text.ends_with("*"),"Explicit save clears dirty status")
	ui._select(tree.id)
	ui._set_array("position",0,52.0)
	var external := DATA.empty_document()
	check(DATA.save_document(external,DATA.disk_hash(path),path).is_empty(),"Concurrent-writer fixture updated")
	var external_hash := DATA.disk_hash(path)
	check(not ui.save(),"Concurrent external update blocks overwriting")
	check(DATA.disk_hash(path) == external_hash and ui.document.regions.harbor[tree.id].position[0] == 52.0,"Save conflict preserves both external data and editor changes")
	check(ui.activity_log[-1].contains("ERROR"),"Save conflict is visible in activity logs")
	ui.activity_log.clear()
	for i in UI.LOG_LIMIT: ui.activity_log.append("old")
	ui._report("Newest message")
	check(ui.activity_log.size() == UI.LOG_LIMIT and ui.activity_log[-1].contains("Newest message"),"Activity log has a fixed memory limit and retains newest entry")
	var old_cache := DATA.disk_hash(UI.CACHE_PATH)
	ui.worker_pid = 2147483000
	ui.worker_output = path+".missing_catalog"
	ui.worker_log = path+".catalog.log"
	ui._poll_worker()
	check(DATA.disk_hash(UI.CACHE_PATH) == old_cache and ui.status.text.contains("falhou"),"Failed catalogue generation cannot report an old cache as success")
	check(ui.activity_log[-1].contains(ui.worker_log.get_file()),"Catalogue failure exposes the worker log path")
	var auxiliary := FileAccess.open(ui.worker_log,FileAccess.WRITE)
	auxiliary.store_string("SCRIPT ERROR: diagnostic fixture")
	auxiliary.close()
	check(ui._collect_logs().contains("SCRIPT ERROR: diagnostic fixture"),"Logs panel reads actual script diagnostics from the auxiliary process")
	var terrain_log := PreviewStub.new()
	terrain_log.folder = path+".topography"
	DirAccess.make_dir_recursive_absolute(terrain_log.folder)
	ui.add_child(terrain_log)
	ui.topography_loader = terrain_log
	var terrain_diagnostic := FileAccess.open(terrain_log.folder+"/worker.log",FileAccess.WRITE)
	terrain_diagnostic.store_string("SCRIPT ERROR: hidden topography diagnostic fixture")
	terrain_diagnostic.close()
	check(ui._collect_logs().contains("SCRIPT ERROR: hidden topography diagnostic fixture"),"Logs panel reads the terrain worker even when no 3D preview is visible")
	ui.draft_path = path+"/unwritable/draft.json"
	check(not ui._write_draft() and ui.activity_log[-1].contains("ERROR"),"Draft write failures are visible rather than silently discarded")
	check(DATA.disk_hash() == official,"Official map remains untouched")
	ui.free()
	var closing := UI.new()
	closing.edits_path = path+".closing"
	closing.draft_path = path+".closing.draft"
	closing.deferred_bootstrap = true
	root.add_child(closing)
	closing.queue_free()
	for i in 5: await process_frame
	check(not is_instance_valid(closing),"Closing during deferred startup releases the editor without resuming a freed instance")
	await process_frame
	print("WORLD_EDITOR_WORKFLOW checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
