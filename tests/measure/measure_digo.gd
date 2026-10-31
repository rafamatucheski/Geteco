extends "res://tests/measure/measure_motocross.gd"
## A/B no mapa renderizado completo, câmera idêntica no paddock e amostras de 30 s.
## --without-digo remove só o NPC/carro desta tarefa depois que o streaming termina.
var without_digo := false

func run() -> void:
	without_digo = "--without-digo" in OS.get_cmdline_user_args()
	seed(1993)
	paddock_focus = true
	await super.run()
	started = 0
	if without_digo:
		# Mantém válida a referência do gerenciador para impedir que o carro do A/B renasça.
		for group in ["digo_instructor","digo_car","digo_amarok"]:
			for actor in get_nodes_in_group(group):
				actor.hide()
				actor.process_mode = Node.PROCESS_MODE_DISABLED
				for sound in actor.find_children("*","AudioStreamPlayer3D",true,false): sound.stop()
	for i in 120: await physics_frame
	started = Time.get_ticks_usec()
	previous = started

func finish() -> void:
	DirAccess.make_dir_recursive_absolute("res://evidence/digo")
	var report := {"label":label,"without_digo":without_digo,"scene":"Main.tscn / motocross paddock",
		"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"engine":Engine.get_version_info().string,"resolution":str(root.size),
		"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,
		"population":world.people.size(),"summary":stats(samples),"warmup":stats(cold),
		"intervals_ms":samples,"warmup_ms":cold,"cpu":stats(cpu),"physics":stats(physics),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"digo_count":get_nodes_in_group("digo_instructor").size(),"gol_count":get_nodes_in_group("digo_car").size(),"amarok_count":get_nodes_in_group("digo_amarok").size(),
		"note":"Diagnostic A/B; external user editor/game may be running. Teleported to paddock; does not validate traversal."}
	var path := "res://evidence/digo/"+label
	var file := FileAccess.open(path+".json",FileAccess.WRITE)
	if file == null: push_error("Digo report path not writable"); quit(2); return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("DIGO_BENCHMARK ",JSON.stringify(report.summary))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path+"-gameplay.png")
	if not without_digo:
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 8
		world.add_child(camera)
		var car = world.session.motocross.get("digo_car")
		if is_instance_valid(car):
			camera.global_position = car.to_global(Vector3(-5,2.7,-6))
			camera.look_at(car.global_position+Vector3.UP*.75)
			camera.make_current()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(path+"-gol.png")
		var amarok = world.session.motocross.get("digo_amarok")
		if is_instance_valid(amarok):
			camera.size = 9
			camera.global_position = amarok.to_global(Vector3(-6,3,-7))
			camera.look_at(amarok.global_position+Vector3.UP*.9)
			camera.make_current()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(path+"-amarok.png")
		var instructors := get_nodes_in_group("digo_instructor")
		if not instructors.is_empty():
			camera.size = 3.3
			camera.global_position = instructors[0].global_position+Vector3(2,1.9,4)
			camera.look_at(instructors[0].global_position+Vector3.UP*.9)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(path+"-digo.png")
	world.queue_free()
	await process_frame
	quit()
