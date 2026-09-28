extends SceneTree
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func settle() -> void:
	for i in 15: await process_frame
func run() -> void:
	await settle()
	if not Engine.is_editor_hint():
		push_error("Run with --editor")
		quit(2)
		return
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	EditorInterface.set_main_screen_editor("Mundo")
	await settle()
	var host := EditorInterface.get_editor_main_screen()
	var ui = host.get_node_or_null("MundoGeteco")
	check(ui != null, "World plugin loaded in the actual editor")
	if ui == null:
		quit(1)
		return
	for dimensions in [Vector2i(1280,900), Vector2i(1600,1000)]:
		root.size = dimensions
		await settle()
		print("HOST_SIZE window=", root.size, " host=", host.size, " world=", ui.size, " map=", ui.canvas.size)
		check(ui.visible, "World tab is visible")
		check(absf(ui.size.y-host.size.y) < 2, "World fills available host height " + str(dimensions))
		check(absf(ui.size.x-host.size.x) < 2, "World fills available host width " + str(dimensions))
		check(absf(ui.canvas.get_global_rect().end.y + ui.get_theme_constant("separation") - ui.status.get_global_rect().position.y) < 2, "Map reaches the footer without unused space")
		check(absf(ui.status.get_global_rect().end.y - ui.get_global_rect().end.y) < 2, "Footer reaches bottom of available host")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/world-editor-20260925/host-filled.png")
	var previous := EditorInterface.is_distraction_free_mode_enabled()
	ui.focus_toggle.pressed.emit()
	await settle()
	check(EditorInterface.is_distraction_free_mode_enabled(), "Expand enables editor focus mode")
	check(absf(ui.size.y-host.size.y) < 2, "Expanded world fills host height")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/world-editor-20260925/host-expanded.png")
	EditorInterface.set_main_screen_editor("Script")
	await settle()
	check(EditorInterface.is_distraction_free_mode_enabled() == previous, "Leaving world restores native panels")
	EditorInterface.set_main_screen_editor("Mundo")
	await settle()
	ui.focus_toggle.pressed.emit()
	await settle()
	check(EditorInterface.is_distraction_free_mode_enabled() == previous, "Restore returns previous focus mode")
	print("WORLD_HOST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
