extends "res://tests/test_world_editor_live_preview.gd"
const REGION := preload("res://world/editing/EditableRegion.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
func run() -> void:
	var official := DATA.disk_hash()
	ui = UI.new()
	ui.edits_path = "res://.godot/piece_delete_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	await process_frame
	var id := "piece/neco/Office"
	ui._select(id)
	check(ui.canvas.objects.has(id),"Existing scenery piece selectable")
	ui._delete()
	check(ui.document.regions.harbor.get(id,{}).get("deleted",false),"Delete persists tombstone")
	check(not ui.canvas.objects.has(id) and id in ui.deleted_ids,"Deleted piece disappears and is restorable")
	ui.undo()
	check(ui.canvas.objects.has(id),"Undo restores piece")
	ui.redo()
	check(not ui.canvas.objects.has(id),"Redo removes piece")
	check(DATA.save_document(ui.document,"",ui.edits_path).is_empty(),"Deleted piece saves")
	var saved := DATA.read_document(ui.edits_path)
	check(saved.error.is_empty() and saved.document.regions.harbor[id].deleted,"Deletion survives reload")
	Engine.set_meta("geteco_world_edit_document",saved.document)
	var region := REGION.build_region("harbor")
	region.prepare_data()
	Engine.remove_meta("geteco_world_edit_document")
	var holder := Node3D.new()
	root.add_child(holder)
	for cell in region.records:
		for record in region.records[cell]:
			if record.kind == "salvage": region._build_record(holder,record)
	var office := false
	var barrel := false
	for piece in PIECES.collect(holder):
		office = office or piece.get_meta("world_edit_piece_id") == "neco/Office"
		barrel = barrel or piece.get_meta("world_edit_piece_id") == "neco/Barrel0"
	check(not office and barrel,"Production removes deleted group but retains adjacent objects")
	check(holder.find_children("EditorPiece_neco_Office","Node3D",true,false).is_empty(),"Deleted mesh and collider subtree removed")
	holder.free()
	region.free()
	ui._restore_id(id)
	check(ui.canvas.objects.has(id) and not ui.document.regions.harbor.has(id),"Excluded menu restores original")
	var crossing := ""
	for key in ui.canvas.objects:
		var row: Dictionary = ui.canvas.objects[key]
		if row.type == "piece" and not row.get("locked",false) and row.get("label","") == "Crosswalk Stripes": crossing = key; break
	check(not crossing.is_empty(),"Crosswalk fixture exists")
	if not crossing.is_empty():
		ui._select(crossing)
		ui._delete()
		check(not ui.canvas.objects.has(crossing),"Authored crosswalk can be deleted")
	check(DATA.disk_hash()==official,"Official map untouched")
	ui.free()
	print("PIECE_DELETE ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
