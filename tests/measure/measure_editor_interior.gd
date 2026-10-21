extends "res://tests/measure/measure_editor_workspace.gd"
## Actual editor room preview: 8 s warm-up, then 30 s of rendered camera movement.
## --interior=harbor_bank|maciota|<PlaceCatalog id> --floor=0 --label=<name>
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var id := "harbor_bank"
	var floor_index := 0
	var label := "current"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--interior="): id = arg.trim_prefix("--interior=")
		if arg.begins_with("--floor="): floor_index = arg.trim_prefix("--floor=").to_int()
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=").validate_filename()
	var definition := preload("res://addons/geteco_world_editor/WorldInteriorCatalog.gd").definition(id)
	if definition.is_empty() or floor_index < 0 or floor_index > int(definition.get("floor_count",0)):
		push_error("Unknown interior or storey: "+id+"/"+str(floor_index))
		quit(2)
		return
	var official := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	root.gui_disable_input = true
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var began := Time.get_ticks_usec()
	var previous := began
	var loading: Array[float] = []
	ui = UI.new()
	ui.deferred_bootstrap = true
	ui.edits_path = "res://.godot/interior_measure_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var deadline := began+180000000
	while not ui.initialized and Time.get_ticks_usec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		loading.append((now-previous)/1000.0)
		previous = now
	check(ui.initialized,"Editor bootstrap completes before measuring an interior")
	if failures: ui.free(); quit(1); return
	ui._switch_interior(id)
	if floor_index > 0:
		ui.interior_floor_selector.value = floor_index
	var panel = ui.live_preview
	check(is_instance_valid(panel),"Interior selection opens the real 3D editor")
	if failures: ui.free(); quit(1); return
	while (panel.applied_revision == 0 or panel.built_interior != id or panel.built_floor != floor_index) and Time.get_ticks_usec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		loading.append((now-previous)/1000.0)
		previous = now
		if panel.worker_pid > 0 and not OS.is_process_running(panel.worker_pid): break
	check(panel.applied_revision > 0 and panel.built_interior == id and panel.built_floor == floor_index,"Requested production room and storey finish loading")
	if failures: ui.free(); quit(1); return
	var load_ms := (Time.get_ticks_usec()-began)/1000.0
	var warm: Array[float] = []
	var samples: Array[float] = []
	var stable_started := Time.get_ticks_usec()
	previous = stable_started
	while Time.get_ticks_usec()-stable_started < 38000000:
		panel.yaw = sin((Time.get_ticks_usec()-stable_started)/10000000.0)*.15
		panel._pose()
		await process_frame
		var now := Time.get_ticks_usec()
		if now-stable_started < 8000000: warm.append((now-previous)/1000.0)
		else: samples.append((now-previous)/1000.0)
		previous = now
	var folder := "res://evidence/editor-workspace-20261021/"
	DirAccess.make_dir_recursive_absolute(folder)
	var name := label+"-interior-"+id.validate_filename()+"-floor%d" % floor_index
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+name+".png")
	var report := {"scope":"editor_interior_preview","interior":id,"floor":floor_index,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"size":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"limit":Engine.max_fps,"load_ms":load_ms,"loading":summary(loading),"warmup":summary(warm),"summary":summary(samples),"frames_ms":samples,"loading_ms":loading,"meshes":panel.edit_control.meshes.size(),"groups":panel.edit_control.groups.size(),"assembly":panel.assembly_metrics,"manifest_reads":panel.manifest_read_count}
	var file := FileAccess.open(folder+name+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("EDITOR_INTERIOR_MEASURE ",id," floor=",floor_index," load_ms=",load_ms," ",JSON.stringify(report.summary))
	check(DATA.disk_hash() == official,"Measuring the editor preserves official game data")
	ui.free()
	quit(1 if failures else 0)
