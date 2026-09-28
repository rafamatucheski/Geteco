extends "res://tests/test_world_editor_live_preview.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	root.size = Vector2i(1440,900)
	ui = UI.new()
	ui.edits_path = "res://.godot/measure_editor_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	ui.canvas.center = Vector2(106.25,66.25)
	ui._toggle_live_preview()
	if not await settled(0): ui.free(); quit(1); return
	var drag := "--drag" in OS.get_cmdline_user_args()
	var origin := Vector2(200,200)
	if drag:
		var edit = ui.live_preview.edit_control
		for id in edit.groups:
			var row: Dictionary = ui.canvas.objects.get(id,{})
			if row.get("type","") == "building" and not row.get("locked",false):
				if DATA.point(row.position).distance_to(ui.canvas.center)>40: continue
				edit.select_id(id)
				origin = ui.live_preview.camera.unproject_position(Vector3(row.position[0],0,row.position[1]))
				edit.begin(origin)
				break
		if not edit.dragging: ui.free(); quit(3); return
	var began := Time.get_ticks_usec()
	var previous := began
	var samples: Array[float] = []
	while Time.get_ticks_usec()-began < 38000000:
		ui.live_preview.yaw = sin(float(Time.get_ticks_usec()-began)/10000000)*.2
		ui.live_preview._pose()
		if drag: ui.live_preview.edit_control.update_drag(origin+Vector2(sin(float(Time.get_ticks_usec()-began)/1000000)*30,0))
		await process_frame
		var now := Time.get_ticks_usec()
		if now-began > 8000000: samples.append((now-previous)/1000.0)
		previous = now
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	for ms in samples:
		total += ms
		if ms>33.3: slow += 1
	var summary := {"fps":samples.size()*1000/total,"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":slow,"frames":samples.size(),"seconds":total/1000}
	var label := "after" if "--after" in OS.get_cmdline_user_args() else "before"
	if drag: label = "drag"
	DirAccess.make_dir_recursive_absolute("res://evidence/editor-3d")
	var file := FileAccess.open("res://evidence/editor-3d/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"summary":summary,"frames_ms":samples,"resolution":root.size,"gpu":RenderingServer.get_video_adapter_name(),"vsync":DisplayServer.window_get_vsync_mode(),"limit":Engine.max_fps}))
	print("EDITOR_PERF ",label," ",summary)
	ui.free()
	quit()
