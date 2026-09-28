extends "res://tests/test_world_editor_live_preview.gd"
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2); return
	var original_hash := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/terminal_preview_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	ui.canvas.center = Vector2(106.25,66.25)
	ui._toggle_live_preview()
	check(await settled(0),"Terminal preview loads")
	if failures: ui.free(); quit(1); return
	var terminal := tagged(ui.live_preview.geometry,"harbor_coach_terminal")
	check(terminal != null,"Actual terminal building is visible")
	if terminal != null:
		check(terminal.global_position.is_equal_approx(Vector3(106.25,0,66.25)),"Terminal production placement preserved")
		check(terminal.find_children("*","MeshInstance3D",true,false).size()>40,"Headhouse, bays and guardhouse geometry exists")
		check(passive(terminal),"Preview architecture cannot start buses or passengers")
	ui.live_preview.focus = Vector3(110,0,63)
	ui.live_preview.view_size = 48
	ui.live_preview._pose()
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/terminal-20260926/preview.png")
	check(DATA.disk_hash()==original_hash,"Preview preserves user's map")
	ui.free()
	print("TERMINAL_PREVIEW ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
