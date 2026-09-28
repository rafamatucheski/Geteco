extends SceneTree
const OUT := "res://evidence/ui-refactor-20260928/acceptance/"
func _initialize() -> void: run.call_deferred()
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size=Vector2i(1280,720); root.content_scale_size=root.size
	# Inspect the menu itself with no pending real session/save preview.
	root.get_node("V2Launch").direct_start_consumed=true
	var menu=load("res://ui/MainMenu.tscn").instantiate(); root.add_child(menu)
	if is_instance_valid(menu.sky): menu.sky.set_process(false)
	await create_timer(2).timeout
	await shot("main-menu")
	menu._open_settings(); await create_timer(.25).timeout
	await shot("settings")
	menu.settings.close()
	var pause=load("res://ui/PauseMenu.tscn").instantiate(); pause.layer=127; root.add_child(pause)
	pause.show(); await create_timer(.25).timeout
	await shot("pause")
	pause.queue_free(); menu.queue_free(); await process_frame
	print("CONTEXTUAL_MENUS_CAPTURE complete")
	quit()
