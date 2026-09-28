extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print("LIVE_HOST ",label," ",ok)
	if not ok: failures += 1; push_error(label)
func run() -> void:
	if not Engine.is_editor_hint(): quit(2); return
	for i in 30: await process_frame
	while EditorInterface.get_resource_filesystem().is_scanning(): await process_frame
	EditorInterface.set_main_screen_editor("Mundo")
	for i in 10: await process_frame
	var ui = EditorInterface.get_editor_main_screen().get_node_or_null("MundoGeteco")
	check(ui != null,"Plugin exists in native editor")
	if ui == null: quit(1); return
	root.size = Vector2i(1600,1000)
	ui._toggle_live_preview()
	var panel = ui.live_preview
	var deadline := Time.get_ticks_msec()+90000
	while panel.applied_revision == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
		if panel.worker_pid > 0 and not OS.is_process_running(panel.worker_pid): break
	check(panel.applied_revision > 0,"Native editor displays generated 3D world")
	if panel.applied_revision > 0:
		check(panel.geometry.get_script() == null,"No gameplay scripts run in editor viewport")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/world-editor-live-host.png")
		EditorInterface.set_main_screen_editor("Script")
		for i in 3: await process_frame
		check(panel.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Changing native tab disables rendering")
		EditorInterface.set_main_screen_editor("Mundo")
		for i in 3: await process_frame
		check(panel.visible and panel.geometry != null,"Returning to tab preserves loaded world")
	var pid: int = panel.worker_pid
	ui._toggle_live_preview()
	check(not OS.is_process_running(pid),"Native editor releases its preview builder")
	check(not is_instance_valid(panel),"Native editor releases the viewport and all geometry immediately")
	for i in 15: await process_frame
	print("LIVE_HOST failures=",failures)
	quit(1 if failures else 0)
