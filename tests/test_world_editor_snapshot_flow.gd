extends "res://tests/test_world_editor_live_preview.gd"
const SNAPSHOTS := preload("res://world/editing/WorldStaticSnapshots.gd")
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(240).timeout.connect(func(): push_error("SNAPSHOT_FLOW timeout"); quit(3))
	var official := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/snapshot_flow_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	ui._set_view_mode(2)
	check(await settled(0),"Original world loads in the editor")
	if failures: ui.free(); quit(1); return
	ui._select("building/Garage")
	check(ui._copy(),"A special authored building can be copied")
	check(ui.clipboard_row.get("model","") == "static_snapshot","Special building copy is independent static scenery")
	if failures: ui.free(); quit(1); return
	var id: String = ui.clipboard_row.snapshot_id
	var published: String = SNAPSHOTS.PUBLISHED+id+".scn"
	var existed := FileAccess.file_exists(published)
	ui._switch_region("desert")
	ui._paste()
	ui._place("prop",Vector2(-315,-914.2))
	var clone_id: String = ui.canvas.selected_id
	check(ui.document.regions.desert.has(clone_id),"Copy pastes in another map")
	check(not FileAccess.file_exists(ui.edits_path),"Cross-map paste does not save the world")
	check(existed or not FileAccess.file_exists(published),"Cross-map paste does not publish geometry before Save")
	check(await settled(ui.live_preview.applied_revision),"Cross-map scenery loads from staged geometry")
	check(tagged(ui.live_preview.geometry,clone_id) != null,"Copied building is present in the destination's real 3D geometry")
	check(ui.save(),"Explicit Save persists document and geometry")
	check(DATA.read_document(ui.edits_path).document.regions.desert.has(clone_id) and FileAccess.file_exists(published),"Saved cross-map copy survives document reload")
	ui.undo()
	check(not ui.document.regions.desert.has(clone_id),"Undo removes the copy independently")
	ui.redo()
	check(ui.document.regions.desert.has(clone_id),"Redo restores the copy independently")
	check(DATA.disk_hash() == official,"Official world remains untouched")
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://evidence/editor-workspace-20261021/")
	root.get_texture().get_image().save_png("res://evidence/editor-workspace-20261021/snapshot-cross-map.png")
	ui.free()
	for i in 30: await process_frame
	if not existed: DirAccess.remove_absolute(published)
	print("WORLD_SNAPSHOT_FLOW checks=",checks," failures=",failures)
	quit(1 if failures else 0)
