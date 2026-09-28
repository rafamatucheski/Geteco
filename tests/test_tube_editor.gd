extends "res://tests/test_world_editor_live_preview.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	var official := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/tube_editor_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var id := "piece/transit/urban_station_2"
	check(ui.canvas.objects.has(id) and not ui.canvas.objects[id].locked,"Tube is unlocked in existing catalog")
	check(not ui.canvas.objects.has("context/harbor/transit/urban_station_2"),"No duplicate protected tube remains")
	ui._select(id)
	var row: Dictionary = ui.canvas.objects[id].duplicate(true)
	var base: Array = row.position.duplicate()
	row.position[0] -= 2
	row.position[1] += 2
	row.rotation = 5.0
	row.stretch = [1.1,1.1]
	ui._commit(row)
	check(ui.document.regions.harbor.has(id),"Tube properties commit through editor")
	ui.canvas.center = DATA.point(row.position)
	ui._set_view_mode(1)
	if not await settled(0): ui.free(); quit(1); return
	var art := tagged(ui.live_preview.geometry,id)
	check(art != null,"Edited tube appears in 3D")
	if art != null:
		check(art.global_position.is_equal_approx(Vector3(row.position[0],0,row.position[1])),"Preview uses edited tube position")
		check(passive(art),"Tube preview has no active gameplay or collision")
	check(ui.live_preview.edit_control.groups.has(id),"Tube is available to 3D drag controls")
	var revision: int = ui.live_preview.applied_revision
	ui._delete()
	check(id in ui.deleted_ids and not ui.canvas.objects.has(id),"Tube deletion appears in Excluded menu")
	if not await settled(revision): ui.free(); quit(1); return
	check(tagged(ui.live_preview.geometry,id)==null,"Deleted tube disappears from preview")
	ui.undo()
	check(ui.document.regions.harbor[id].rotation==5.0,"Undo deletion restores edited tube")
	revision = ui.live_preview.applied_revision
	if not await settled(revision): ui.free(); quit(1); return
	check(DATA.save_document(ui.document,"",ui.edits_path).is_empty(),"Tube document saves")
	check(DATA.read_document(ui.edits_path).document.regions.harbor[id].stretch==[1.1,1.1],"Tube scale survives reload")
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://evidence/tube-editor")
	root.get_texture().get_image().save_png("res://evidence/tube-editor/editor.png")
	ui._restore_id(id)
	check(ui.canvas.objects[id].position==base and not ui.document.regions.harbor.has(id),"Restore original resets tube transform")
	check(DATA.disk_hash()==official,"Official world is unchanged")
	ui.free()
	print("TUBE_EDITOR ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
