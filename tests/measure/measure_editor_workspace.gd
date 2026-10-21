extends "res://tests/test_world_editor_live_preview.gd"
## Rendered editor, isolated draft. Reports first-load hitches separately from 30 s orbit.
## --area=harbor|mountain|desert --whole --label=<unique name>
func summary(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var stalled := 0
	for value in values:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: stalled += 1
	return {"frames":values.size(),"seconds":total/1000.0,"fps":values.size()*1000.0/total,"p50_ms":sorted[int((sorted.size()-1)*.5)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted.back(),"over_33_3_ms":slow,"over_66_7_ms":stalled}

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var area := "harbor"
	var label := "current"
	var whole := "--whole" in OS.get_cmdline_user_args()
	var two_d := "--two-d" in OS.get_cmdline_user_args()
	var motocross := "--motocross" in OS.get_cmdline_user_args()
	var terrain_edited := "--terrain-edited" in OS.get_cmdline_user_args()
	var topography := "--topography" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--area="): area = arg.trim_prefix("--area=")
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=").validate_filename()
	if area not in ["harbor","mountain","desert"]: quit(2); return
	var official := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	root.gui_disable_input = true
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var began := Time.get_ticks_usec()
	ui = UI.new()
	ui.edits_path = "res://.godot/workspace_measure_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path + ".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui._switch_region(area)
	if motocross:
		ui.canvas.center = Vector2(-185,-116)
		ui.canvas.zoom = 3.0
		if terrain_edited:
			var brush := preload("res://world/editing/WorldTerrainEdits.gd").new_brush(Vector2(-185,-116),"motocross")
			brush.radius = 22.0
			brush.height = 4.0
			brush.surface = "sand"
			ui._commit(brush)
	ui._set_view_mode(0 if two_d else 2)
	var panel = ui.live_preview
	if motocross and not two_d:
		panel.request(ui.document,Vector2(-185,-116),"harbor")
	if two_d and not motocross: ui._fit_world()
	if topography: ui._queue_topography()
	if whole and not two_d:
		panel.reach_menu.select(3)
		panel.reach_menu.item_selected.emit(3)
	var loading: Array[float] = []
	var previous := began
	var deadline := began + 480000000
	while not two_d and panel.applied_revision == 0 and Time.get_ticks_usec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		loading.append((now-previous)/1000.0)
		previous = now
		if panel.worker_pid > 0 and not OS.is_process_running(panel.worker_pid): break
	if two_d:
		if topography:
			while ui.canvas.terrain_topography_tiles().is_empty() and Time.get_ticks_usec() < deadline:
				await process_frame
				var now := Time.get_ticks_usec()
				loading.append((now-previous)/1000.0)
				previous = now
			check(not ui.canvas.terrain_topography_tiles().is_empty(),"Terrain relief loads automatically in the actual 2D editor")
		else:
			await process_frame
			loading.append((Time.get_ticks_usec()-began)/1000.0)
	check(two_d or panel.applied_revision > 0,"Rendered workspace finishes loading "+area)
	if failures: ui.free(); quit(1); return
	var load_ms := (Time.get_ticks_usec()-began)/1000.0
	var warm: Array[float] = []
	var samples: Array[float] = []
	var stable_start := Time.get_ticks_usec()
	var initial_center: Vector2 = ui.canvas.center
	previous = stable_start
	while Time.get_ticks_usec()-stable_start < 38000000:
		if two_d:
			ui.canvas.center = initial_center+Vector2(sin((Time.get_ticks_usec()-stable_start)/10000000.0)*120,0)
			ui.canvas.queue_redraw()
		else:
			panel.yaw = sin((Time.get_ticks_usec()-stable_start)/10000000.0)*.2
			panel._pose()
		await process_frame
		var now := Time.get_ticks_usec()
		if now-stable_start < 8000000: warm.append((now-previous)/1000.0)
		else: samples.append((now-previous)/1000.0)
		previous = now
	var folder := "res://evidence/editor-workspace-20261021/"
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+label+"-"+area+".png")
	var terrain_probe: Array = []
	if topography:
		var probe := Vector2(-185,-116)
		var probe_index := 0
		for tile: Dictionary in ui.canvas.terrain_topography_tiles():
			var bounds: Rect2 = tile.bounds
			if not bounds.has_point(probe): continue
			var image := (tile.texture as Texture2D).get_image()
			var tile_path := folder+label+"-"+area+"-terrain-%d.png" % probe_index
			image.save_png(tile_path)
			var at := (probe-bounds.position)/bounds.size*Vector2(image.get_size())
			var pixel := Vector2i(at).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE)
			terrain_probe.append({"file":tile_path,"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"pixel":[pixel.x,pixel.y],"color":image.get_pixelv(pixel).to_html(),"source_ids":tile.get("source_ids",[])})
			probe_index += 1
	var report := {"area":area,"whole":whole,"two_d":two_d,"motocross":motocross,"terrain_edited":terrain_edited,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"size":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"limit":Engine.max_fps,"load_ms":load_ms,"loading":summary(loading),"warmup":summary(warm),"summary":summary(samples),"frames_ms":samples,"loading_ms":loading,"meshes":0 if two_d else panel.edit_control.meshes.size(),"groups":0 if two_d else panel.edit_control.groups.size()}
	var file := FileAccess.open(folder+label+"-"+area+".json",FileAccess.WRITE)
	report["overview_record_count"] = ui.canvas.get("overview_record_count")
	report["overview_rebuild_ms"] = ui.canvas.get("overview_rebuild_ms")
	report["overview_command_count"] = ui.canvas.get("overview_command_count")
	report["render_draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	report["render_primitives"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	report["render_objects"] = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	if topography:
		report["terrain_probe"] = terrain_probe
		report["legacy_course_replaced"] = ui.canvas._terrain_owner_replaced("context/harbor/motocross_course/123")
		report["legacy_woodland_replaced"] = ui.canvas._terrain_owner_replaced("context/harbor/session/vertice_woodland")
	if not two_d: report["lod"] = panel.get("lod_metrics")
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("EDITOR_WORKSPACE ",area," whole=",whole," load_ms=",load_ms," ",JSON.stringify(report.summary))
	check(DATA.disk_hash() == official,"Measurement never saves official map")
	ui.free()
	quit(1 if failures else 0)
