extends "res://tests/test_world_editor_live_preview.gd"

func revision_ready(previous: int) -> bool:
	var deadline := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var panel = ui.live_preview
		if panel.applied_revision > previous and panel.applied_revision == panel.revision and panel.submitted == panel.desired: return true
	return false

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var official := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/interior_invalid_preview_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui._switch_interior("harbor_bank")
	check(await revision_ready(0),"A real bank interior is rendered before testing invalid placement")
	if failures: ui.free(); quit(1); return
	var panel = ui.live_preview
	var spawn: Array = panel.loading_response.interior_spawn
	var row := DATA.new_entity("prop",Vector2(spawn[0],spawn[1]))
	row.id = "new/interior_entrance_blocker"
	row.model = "crate"
	var previous: int = panel.applied_revision
	ui._commit(row)
	check(await revision_ready(previous),"Invalid entrance placement still publishes the latest 3D snapshot")
	check(tagged(panel.geometry,row.id) != null,"The blocking object remains visible and selectable for correction")
	check(not str(panel.loading_response.get("interior_validation_error","")).is_empty(),"The snapshot reports the actual layout validation failure")
	check(ui.save_button.disabled and not ui.save(),"Saving is blocked while the entrance is obstructed")
	check(ui.document.interiors.harbor_bank.has(row.id),"Validation retains the user's unsaved placement")
	previous = panel.applied_revision
	row.deleted = true
	ui._commit(row)
	check(await revision_ready(previous),"Removing the obstruction publishes a corrected snapshot")
	check(str(panel.loading_response.get("interior_validation_error","")).is_empty(),"Correcting the room clears the layout failure")
	check(not ui.save_button.disabled and ui.save(),"The validated correction can be explicitly saved to the isolated test document")
	check(DATA.disk_hash() == official,"The rendered validation flow never changes official game data")
	var test_path: String = ui.edits_path
	var draft_path: String = ui.draft_path
	ui.free()
	for path in [test_path,draft_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("WORLD_EDITOR_INTERIOR_INVALID_PREVIEW checks=",checks," failures=",failures)
	quit(1 if failures else 0)
