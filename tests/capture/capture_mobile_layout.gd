extends SceneTree
## Render real gameplay at Fold cover/inner aspect ratios, including rotation.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		quit(3)
		return
	world.player.teleport(Vector3(132, .15, 72))
	var touch = world.find_child("AndroidControls", true, false)
	if touch == null:
		quit(4)
		return
	var output := "res://evidence/mobile-20261003"
	DirAccess.make_dir_recursive_absolute(output)
	for extent in [Vector2i(1170, 540), Vector2i(540, 1170), Vector2i(900, 840), Vector2i(840, 900)]:
		root.size = extent
		for i in 12: await process_frame
		for expanded in [false, true]:
			touch.extra = expanded
			touch._refresh()
			await RenderingServer.frame_post_draw
			var label := "%sx%s%s" % [extent.x, extent.y, "-options" if expanded else ""]
			root.get_texture().get_image().save_png(output.path_join(label + ".png"))
			print("MOBILE_LAYOUT ", label, " viewport=", touch.size, " unit=", touch.unit)
	world.queue_free()
	await process_frame
	quit()
