extends SceneTree
const OUT = "res://evidence/hud-real-glass-20260928/"
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	for i in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		quit(3)
		return
	world.player.teleport(world.maciota_place.entry_position + Vector3(0, 0, 3))
	world.session.weather.time_of_day = .39
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 10000
	world.session.weather._update()
	for i in 100: await process_frame
	await RenderingServer.frame_post_draw
	var metadata = {"source":"Main.tscn current production render", "hud":world.hud.get_script().resource_path,"no_save":world.production.no_save,"minimap_rect":str(world.hud.minimap.get_global_rect()),"interaction":world.hud.interaction_label.text,"clock":world.hud.clock_label.text}
	FileAccess.open(OUT + "capture.json", FileAccess.WRITE).store_string(JSON.stringify(metadata, "\t"))
	root.get_texture().get_image().save_png(OUT + "current.png")
	paused = true
	for node in root.find_children("*", "CanvasLayer", true, false):
		node.visible = false
	world.diagnostic_label.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "scene.png")
	print("HUD_REAL_CAPTURE_COMPLETE ", JSON.stringify(metadata))
	quit()
