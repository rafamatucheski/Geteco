extends "res://tests/test_world_editor_live_preview.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	var official := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/edit3d_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	ui._place("building",Vector2(10,110))
	var id: String = ui.canvas.selected_id
	ui.canvas.center = Vector2(10,110)
	ui._set_view_mode(1)
	check(not ui.canvas.visible and ui.live_preview.visible,"3D mode fills map area")
	if not await settled(0): ui.free(); quit(1); return
	var edit = ui.live_preview.edit_control
	check(edit.groups.has(id),"Building is indexed for 3D editing")
	var at: Vector2 = ui.live_preview.camera.unproject_position(Vector3(10,7.5,110))
	check(edit.pick(at)==id,"Visible roof selects building in 3D")
	edit.select_id(id)
	var history: int = ui.history.size()
	var revision: int = ui.live_preview.revision
	edit.mode = 0
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = at
	press.pressed = true
	edit.input_event(press)
	check(edit.dragging,"Drag begins on ready geometry")
	edit.update_drag(at+Vector2(30,0))
	check(ui.history.size()==history and ui.live_preview.revision==revision,"Mouse motion does not save or rebuild world")
	check(edit.candidate.position != edit.original.position,"3D motion changes ground position")
	edit.finish()
	check(ui.history.size()==history+1,"Gesture creates exactly one undo entry")
	check(ui.document.regions.harbor[id].position != [10,110],"Release commits moved building")
	if not await settled(revision): ui.free(); quit(1); return
	var moved: Array = ui.document.regions.harbor[id].position.duplicate()
	edit.mode = 1
	edit.begin(at)
	edit.update_drag(at+Vector2(60,0),true)
	edit.finish()
	check(ui.document.regions.harbor[id].rotation==30,"3D rotation commits with snapping")
	revision = ui.live_preview.applied_revision
	if not await settled(revision): ui.free(); quit(1); return
	edit.mode = 2
	edit.begin(at)
	edit.update_drag(at+Vector2(25,0))
	edit.finish()
	check(ui.document.regions.harbor[id].size[0]>10,"Size gesture enlarges building")
	revision = ui.live_preview.applied_revision
	if not await settled(revision): ui.free(); quit(1); return
	edit.mode = 0
	edit.begin(at)
	edit.update_drag(at+Vector2(40,0))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	edit.input_event(escape)
	check(ui.document.regions.harbor[id].position==moved,"Escape/cancel preserves saved position")
	ui.undo()
	check(ui.document.regions.harbor[id].rotation==30 and ui.document.regions.harbor[id].size[0]==10,"Undo restores previous size")
	ui.redo()
	check(ui.document.regions.harbor[id].size[0]>10,"Redo restores size")
	var payload := {"geteco_asset":true,"item":{"action":"place","row":DATA.new_entity("tree",Vector2.ZERO)}}
	check(edit.can_drop(at,payload),"Library asset accepted by 3D drop target")
	edit.drop(at,payload)
	check(ui.document.regions.harbor[ui.canvas.selected_id].type=="tree","Library drop places real tree")
	var tree_id: String = ui.canvas.selected_id
	ui._set_view_mode(2)
	check(ui.canvas.visible,"Side-by-side keeps both views")
	check(DATA.disk_hash()==official,"3D edits leave official world untouched")
	revision = ui.live_preview.applied_revision
	if await settled(revision):
		edit.select_id(id)
		ui._set_view_mode(1)
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://evidence/editor-3d")
		root.get_texture().get_image().save_png("res://evidence/editor-3d/editing.png")
	edit.select_id(tree_id)
	var delete := InputEventKey.new()
	delete.keycode = KEY_DELETE
	delete.pressed = true
	edit.input_event(delete)
	check(ui.document.regions.harbor[tree_id].deleted,"Delete works from 3D keyboard focus")
	check(DATA.save_document(ui.document,"",ui.edits_path).is_empty(),"3D edits save through shared validation")
	var loaded := DATA.read_document(ui.edits_path)
	# JSON.stringify uses decimal precision; compare persisted measurements,
	# rather than demanding binary-identical floating point dictionaries.
	var restored: Dictionary = loaded.document.regions.harbor[id]
	var expected: Dictionary = ui.document.regions.harbor[id]
	check(loaded.error.is_empty() and DATA.point(restored.position).distance_to(DATA.point(expected.position))<.0001 and DATA.point(restored.size).distance_to(DATA.point(expected.size))<.0001 and is_equal_approx(restored.rotation,expected.rotation) and is_equal_approx(restored.height,expected.height) and loaded.document.regions.harbor[tree_id].deleted,"Saved transforms reload to submillimeter precision with deletion intact")
	ui.free()
	print("EDITOR_3D ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
