@tool
extends RefCounted
## Opt-in measurement inside the actual native .NET editor main-screen plugin.
## No scene runner or standalone replacement UI participates in this route.
static func summary(values: Array[float]) -> Dictionary:
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

static func property_exists(node: Object, name: String) -> bool:
	for entry: Dictionary in node.get_property_list():
		if str(entry.name) == name: return true
	return false

static func screen_of(reference: WeakRef) -> Variant:
	var plugin = reference.get_ref()
	return plugin.screen if is_instance_valid(plugin) and is_instance_valid(plugin.screen) else null

static func import_busy() -> bool:
	var filesystem := EditorInterface.get_resource_filesystem()
	return filesystem.is_scanning() or (filesystem.has_method("is_importing") and bool(filesystem.call("is_importing")))

static func wait_import_idle(tree: SceneTree, max_usec := 180000000) -> bool:
	var began := Time.get_ticks_usec()
	var idle_since := 0
	while Time.get_ticks_usec()-began < max_usec:
		if import_busy(): idle_since = 0
		elif idle_since == 0: idle_since = Time.get_ticks_usec()
		elif Time.get_ticks_usec()-idle_since >= 2000000: return true
		await tree.process_frame
	return false

static func close(reference: WeakRef, tree: SceneTree, code: int) -> void:
	if import_busy():
		print("WORLD_NATIVE_EDITOR_CLOSE waiting_for_import")
		if not await wait_import_idle(tree):
			push_error("Native measurement cannot close while editor resource import is active (180 s timeout).")
			return
	var screen = screen_of(reference)
	# The plugin's normal exit checks validity before queue_free, so releasing
	# this screen cannot double-free it when the editor closes immediately.
	print("WORLD_NATIVE_EDITOR_CLOSE releasing_screen")
	if is_instance_valid(screen): screen.free()
	print("WORLD_NATIVE_EDITOR_CLOSE screen_released draining_frames")
	for frame in 3: await tree.process_frame
	print("WORLD_NATIVE_EDITOR_CLOSE drained quit_deferred")
	tree.quit.call_deferred(code)

static func run(reference: WeakRef, tree: SceneTree) -> void:
	var plugin = reference.get_ref()
	if not is_instance_valid(plugin): return
	var began := int(plugin.get_meta("native_measure_start_usec",Time.get_ticks_usec()))
	var official_script = load("res://world/editing/WorldEditData.gd")
	var official: String = official_script.disk_hash()
	var label := "native-editor-final"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=").validate_filename()
	if DisplayServer.get_name() == "headless":
		push_error("Native editor measurement requires an actual rendered editor window.")
		close(reference,tree,2)
		return
	var host := EditorInterface.get_base_control().get_window()
	host.mode = Window.MODE_WINDOWED
	host.size = Vector2i(1440,900)
	host.gui_disable_input = true
	Engine.max_fps = 60
	OS.low_processor_usage_mode = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED,host.get_window_id())
	EditorInterface.set_main_screen_editor("Mundo")
	var loading: Array[float] = []
	var previous := began
	var deadline := began+120000000
	var opened := false
	var ready := false
	while Time.get_ticks_usec() < deadline:
		var screen = screen_of(reference)
		if not is_instance_valid(screen): return
		var initialized: bool = not property_exists(screen,"initialized") or bool(screen.get("initialized"))
		if initialized and not opened:
			screen._set_view_mode(1)
			opened = true
		var panel = screen.live_preview
		if initialized and is_instance_valid(panel) and screen.is_visible_in_tree() and panel.is_visible_in_tree() and panel.applied_revision > 0 and panel.applied_revision == panel.revision and panel.submitted == panel.desired:
			ready = true
			break
		await tree.process_frame
		var now := Time.get_ticks_usec()
		loading.append((now-previous)/1000.0)
		previous = now
	var screen = screen_of(reference)
	if not ready or not is_instance_valid(screen):
		push_error("Native Mundo editor did not finish loading within 120 seconds.")
		close(reference,tree,1)
		return
	var main_screen := EditorInterface.get_editor_main_screen()
	var native_route: bool = Engine.is_editor_hint() and main_screen.is_ancestor_of(screen) and bool(screen.is_visible_in_tree())
	if not native_route:
		push_error("Measurement did not reach the native EditorInterface main-screen route.")
		close(reference,tree,1)
		return
	var panel = screen.live_preview
	var load_ms := (Time.get_ticks_usec()-began)/1000.0
	var import_wait_started := Time.get_ticks_usec()
	print("WORLD_NATIVE_EDITOR_MEASURE waiting_for_resource_filesystem_idle")
	if not await wait_import_idle(tree):
		push_error("Native editor import did not finish within 180 seconds; no FPS result was recorded.")
		close(reference,tree,1)
		return
	var import_wait_usec := Time.get_ticks_usec()-import_wait_started
	var import_interruptions := 0
	var warm: Array[float] = []
	var samples: Array[float] = []
	var smoke := "--smoke" in OS.get_cmdline_user_args()
	var warm_usec := 0 if smoke else 8000000
	var total_usec := 2000000 if smoke else 38000000
	var stable_start := Time.get_ticks_usec()
	previous = stable_start
	while Time.get_ticks_usec()-stable_start < total_usec:
		screen = screen_of(reference)
		if not is_instance_valid(screen) or not is_instance_valid(screen.live_preview): return
		panel = screen.live_preview
		panel.yaw = sin((Time.get_ticks_usec()-stable_start)/10000000.0)*.2
		panel._pose()
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if import_busy():
			import_interruptions += 1
			var wait_began := now
			if not await wait_import_idle(tree,maxi(1,180000000-import_wait_usec)):
				push_error("Resource import interrupted native FPS measurement and exceeded its 180 second budget.")
				close(reference,tree,1)
				return
			import_wait_usec += Time.get_ticks_usec()-wait_began
			warm.clear()
			samples.clear()
			stable_start = Time.get_ticks_usec()
			previous = stable_start
			continue
		if now-stable_start < warm_usec: warm.append((now-previous)/1000.0)
		else: samples.append((now-previous)/1000.0)
		previous = now
	screen = screen_of(reference)
	if not is_instance_valid(screen): return
	panel = screen.live_preview
	var folder := "res://evidence/editor-workspace-20261021/"
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	var screenshot_error := host.get_texture().get_image().save_png(folder+label+".png")
	var report := {"route":"EditorInterface.get_editor_main_screen()/Mundo","native_editor_route":native_route,"editor_hint":Engine.is_editor_hint(),"mono":OS.has_feature("mono"),"screen_path":str(screen.get_path()),"native_main_screen_path":str(main_screen.get_path()),"area":"harbor","whole":false,"view":"3D","engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"size":str(host.size),"vsync":DisplayServer.window_get_vsync_mode(host.get_window_id()),"limit":Engine.max_fps,"low_processor_usage":OS.low_processor_usage_mode,"load_ms":load_ms,"loading":summary(loading),"warmup":summary(warm),"summary":summary(samples),"frames_ms":samples,"loading_ms":loading,"meshes":panel.edit_control.meshes.size(),"groups":panel.edit_control.groups.size(),"render_draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"render_primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"render_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"screenshot_error":screenshot_error,"official_data_unchanged":official_script.disk_hash() == official}
	if property_exists(panel,"lod_metrics"): report.lod = panel.get("lod_metrics")
	report.screen_visible = screen.is_visible_in_tree()
	report.preview_visible = panel.is_visible_in_tree()
	report.preview_size = str(panel.surface.size)
	report.camera_focus = str(panel.focus)
	report.camera_size = panel.view_size
	report.camera_pitch = panel.pitch
	report.filesystem_scanning = EditorInterface.get_resource_filesystem().is_scanning()
	var filesystem := EditorInterface.get_resource_filesystem()
	report.filesystem_importing = filesystem.has_method("is_importing") and bool(filesystem.call("is_importing"))
	report.metric_source = "RenderingServer.frame_post_draw"
	report.mode = "smoke" if smoke else "benchmark"
	report.dotnet = ClassDB.class_exists("CSharpScript")
	report.integration_valid = not import_busy() and not samples.is_empty() and native_route
	report.measurement_valid = not smoke and bool(report.integration_valid)
	report.import_wait_ms = import_wait_usec/1000.0
	report.sample_import_interruptions = import_interruptions
	var file := FileAccess.open(folder+label+".json",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	else: push_error("Could not write the native editor measurement report.")
	print("WORLD_NATIVE_EDITOR_MEASURE ",JSON.stringify({"label":label,"native_editor_route":native_route,"load_ms":load_ms,"summary":report.summary}))
	close(reference,tree,0 if file != null and screenshot_error == OK and bool(report.official_data_unchanged) and bool(report.integration_valid) else 1)
