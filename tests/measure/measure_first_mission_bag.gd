extends "res://tests/measure/measure_katana_session.gd"

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output_dir = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world); current_scene = world
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	var session = world.session
	preload("res://tests/fixtures/TravelBagScene.gd").complete_through(session,"primeiro_giro")
	session.personal_car.refresh()
	# Mesma mochila conquistada nas duas revisões; a linha de base é anterior ao prêmio da missão.
	if session.state.economy.grid_snapshot().bag == "": session.state.economy.grid_equip_bag("backpack")
	gameplay = world.gameplay
	gameplay.god_mode = true
	var warm := Time.get_ticks_usec()
	while Time.get_ticks_usec()-warm < 8000000: await process_frame
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec()-start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-last)/1000.0); last = now
	var summary := summarize(samples)
	summary.merge({"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"viewport":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps})
	FileAccess.open(output_dir.path_join("measure.json"),FileAccess.WRITE).store_string(JSON.stringify(summary,"\t"))
	session.show_inventory()
	await frames(10)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join("inventory.png"))
	session.field_inventory.close()
	await frames(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join("backpack.png"))
	var detail := Camera3D.new()
	world.add_child(detail)
	var back: Vector3 = world.player.visual.global_basis.z
	detail.look_at_from_position(world.player.global_position+back*2.2+Vector3.UP*1.6,world.player.global_position+Vector3.UP)
	detail.make_current()
	await frames(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join("backpack-detail.png"))
	summary.erase("samples_ms"); print("FIRST_BAG_MEASURE ",summary)
	world.queue_free(); await process_frame
	quit(0)
