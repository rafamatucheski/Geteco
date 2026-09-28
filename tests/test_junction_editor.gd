extends "res://tests/test_world_editor_live_preview.gd"
func crossing_vertices(node: Node, result: Array) -> void:
	if node is MeshInstance3D and str(node.name).begins_with("HarborCrosswalk"):
		for surface in node.mesh.get_surface_count():
			for vertex in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]: result.append(node.global_transform*vertex)
	for child in node.get_children(): crossing_vertices(child,result)

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	var official := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/junction_test_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var editor = ui.junction_editor
	editor.set_enabled(true)
	check(editor.layouts.size()>5,"Editor exposes actual Harbor junctions")
	for junction in editor.layouts:
		for i in junction.entries.size():
			if junction.entries[i].enabled and junction.entries[i].max_offset>=3 and not str(junction.entries[i].road_id).contains("cobra"):
				editor.selected=junction.id; editor.entry_index=i; break
		if not editor.selected.is_empty(): break
	if editor.entry().is_empty(): check(false,"An editable junction is available"); ui.free(); quit(1); return
	var selected: String = editor.selected
	var index: int = editor.entry_index
	var key: String = editor.entry().key
	var road_id: String = editor.source_row(editor.entry()).id
	ui.canvas.center = editor.current().position
	ui._set_view_mode(1)
	ui._select("")
	if not await settled(0): ui.free(); quit(1); return
	var control = ui.live_preview.edit_control
	var at: Vector2 = editor.project(editor.entry().position,true)
	var event := InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=at
	control.input_event(event)
	check(editor.dragging,"3D approach handle starts drag")
	var history: int = ui.history.size()
	var revision: int = ui.live_preview.revision
	var motion := InputEventMouseMotion.new()
	motion.position=editor.project(editor.entry().position+editor.entry().direction*2.0,true)
	control.input_event(motion)
	check(ui.history.size()==history and ui.live_preview.revision==revision,"Drag preview does not rebuild or save per mouse motion")
	check(editor.proposed>1.8 and editor.proposed<2.2,"3D drag follows road direction in metres")
	event.pressed=false
	control.input_event(event)
	check(ui.history.size()==history+1,"Releasing drag creates one undo action")
	check(ui.document.regions.harbor[road_id].crossing_entries[key].offset>1.8,"3D gesture persists per-entry offset")
	if not await settled(revision): ui.free(); quit(1); return
	ui.undo()
	check(not ui.document.regions.harbor.get(road_id,{}).get("crossing_entries",{}).has(key),"Undo removes only authored approach adjustment")
	ui.redo()
	check(ui.document.regions.harbor[road_id].crossing_entries[key].offset>1.8,"Redo restores approach")
	editor.change("mode","off")
	check(not editor.entry().enabled,"Per-entry selector removes zebra")
	editor.change("mode","on")
	check(editor.entry().enabled,"Per-entry selector restores zebra")
	check(ui.save(),"Per-entry overrides save successfully")
	var loaded := DATA.read_document(ui.edits_path)
	check(loaded.error.is_empty() and loaded.document.regions.harbor[road_id].crossing_entries[key].mode=="on","Save reload retains entry settings")
	Engine.set_meta("geteco_world_edit_document",loaded.document)
	var runtime := preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	runtime.prepare_data()
	var matched := false
	for junction in runtime.harbor_road_geometry.crossing_layout:
		for arm in junction.entries:
			if arm.key==key and arm.road_id==str(road_id).trim_prefix("road/"):
				matched = true
				check(arm.position.distance_to(editor.entry().position)<.02,"Editor marker and actual runtime zebra share exact position")
				check(arm.stop_position.distance_to(editor.entry().stop_position)<.02,"Runtime retention line matches editor marker")
	check(matched,"Runtime resolves saved approach identity")
	runtime.free()
	Engine.remove_meta("geteco_world_edit_document")
	editor.restore()
	check(not ui.document.regions.harbor[road_id].crossing_entries.has(key),"Restore entry clears only that override")
	editor.change("offset",1.0)
	ui._set_view_mode(2)
	ui.canvas.center=editor.current().position
	ui.canvas.zoom=8
	at=editor.project(editor.entry().position,false)
	event.pressed=true; event.position=at
	ui.canvas._gui_input(event)
	check(editor.dragging and not editor.drag_3d,"2D handle starts constrained crossing drag")
	motion.position=editor.project(editor.entry().position+editor.entry().direction,true)
	var old_offset: float = editor.entry().offset
	var escape := InputEventKey.new()
	escape.keycode=KEY_ESCAPE; escape.pressed=true
	ui.canvas._gui_input(escape)
	check(not editor.dragging and is_equal_approx(editor.entry().offset,old_offset),"Escape cancels crossing gesture without committing")
	event.pressed=true; event.position=editor.project(editor.entry().position,false)
	ui.canvas._gui_input(event)
	motion.position=editor.project(editor.entry().position+editor.entry().direction,false)
	ui.canvas._gui_input(motion)
	event.pressed=false
	ui.canvas._input(event)
	check(not editor.dragging and editor.entry().offset>old_offset+.8,"Release outside 2D canvas commits one gesture")
	revision=ui.live_preview.applied_revision
	if await settled(revision):
		var vertices: Array = []
		crossing_vertices(ui.live_preview.geometry,vertices)
		var minimum := INF
		var maximum := -INF
		var arm: Dictionary = editor.entry()
		for point in vertices:
			var delta := Vector2(point.x,point.z)-(arm.position as Vector2)
			var along: float = delta.dot(arm.direction)
			if absf(along)<arm.depth*2+2 and absf(delta.cross(arm.direction))<arm.width*.51:
				minimum=minf(minimum,along); maximum=maxf(maximum,along)
		check(is_finite(minimum) and absf((minimum+maximum)*.5)<.15,"Loaded preview mesh is centered on final edited marker")
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://evidence/junction-editor")
		root.get_texture().get_image().save_png("res://evidence/junction-editor/editor.png")
	check(DATA.disk_hash()==official,"Editor integration never writes user's world")
	check(editor.selected==selected and editor.entry_index==index,"Selection survives edits and undo")
	ui.free()
	await process_frame
	print("JUNCTION_EDITOR checks=",checks," failures=",failures)
	quit(1 if failures else 0)
