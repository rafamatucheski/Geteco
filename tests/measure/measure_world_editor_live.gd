extends "res://tests/measure/measure.gd"
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var ui = preload("res://addons/geteco_world_editor/WorldEditor.gd").new()
	ui.edits_path = "res://.godot/live_measure_unused.json"
	ui.draft_path = "res://.godot/live_measure_unused_draft.json"
	root.size = Vector2i(1440,900)
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if "--infill" in OS.get_cmdline_user_args():
		var row := preload("res://world/editing/WorldEditData.gd").new_entity("building",Vector2(5,95))
		row.model = "urban_infill"
		row.size = [6,9]
		row.height = 12
		ui._commit(row)
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=")
	if "--live" in OS.get_cmdline_user_args():
		ui._toggle_live_preview()
		for i in 3600:
			await process_frame
			if ui.live_preview.applied_revision > 0: break
		if ui.live_preview.applied_revision <= 0: quit(1); return
	var measured: Array[float] = []
	var warm: Array[float] = []
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec()-start < 38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if now-start < 8000000: warm.append((now-last)/1000.0)
		else: measured.append((now-last)/1000.0)
		last = now
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info().string,"size":str(root.size),"variant":variant,"summary":stats(measured),"warmup":stats(warm),"frames_ms":measured,"warmup_ms":warm}
	var file := FileAccess.open("res://evidence/world-editor-live-"+variant+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	print("LIVE_EDITOR_MEASURE ",JSON.stringify(report.summary))
	ui.free()
	quit()
