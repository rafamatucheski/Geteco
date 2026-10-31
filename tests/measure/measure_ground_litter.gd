extends "res://tests/measure/measure.gd"
## Mesmo Main renderizado, rota, clima e semente para antes/depois. Sem gravar save.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var variant := "before"
	var render_compare := "--render-compare" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	var folder := "res://evidence/ground-litter-20261006/" + variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	seed(6102026)
	if "--without-litter" in OS.get_cmdline_user_args():
		load("res://world/city_look/CityGroundLitter.gd").enabled = false
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	var startup := Time.get_ticks_msec()
	while Time.get_ticks_msec() - startup < 150000:
		await process_frame
		if world.session != null and world.session.ready_for_play and world.people.size() >= world.production.requested_population: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Ground litter benchmark startup incomplete")
		quit(3)
		return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.session.weather.set_process(false)
	world.diagnostic_label.hide()
	var report := {"variant":variant,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"cases":[]}
	if "--alternate" in OS.get_cmdline_user_args():
		if not await _alternate(folder,report):
			quit(4)
			return
		world.queue_free()
		await process_frame
		quit()
		return
	var sites := [{"id":"day","time":.55,"weather":3},{"id":"night-rain","time":.84,"weather":1}]
	if render_compare:
		sites = [{"id":"day-hidden","time":.55,"weather":3,"visible":false},{"id":"day-visible","time":.55,"weather":3,"visible":true},{"id":"night-rain-hidden","time":.84,"weather":1,"visible":false},{"id":"night-rain-visible","time":.84,"weather":1,"visible":true}]
	for site in sites:
		if render_compare:
			load("res://world/city_look/CityGroundLitter.gd").render_visible = site.visible
			for node in world.production.region.find_children("CityGroundLitter","Node3D",true,false): node.visible = site.visible
		world.player.teleport(Vector3(86.7,.08,101.5))
		world.production._update_physical_residency(world.player.position)
		world.production._update_logical_region(world.player.position)
		world.camera.heading = 0
		world.camera.target_size = 26
		world.camera.initialized = false
		world.session.weather.time_of_day = site.time
		world.session.weather.weather_state = site.weather
		world.session.weather.weather_timer = 10000
		world.session.weather._update()
		var warm: Array[float] = []
		var frames: Array[float] = []
		var begin := Time.get_ticks_usec()
		var last := begin
		while Time.get_ticks_usec() - begin < 8000000:
			await process_frame
			var now := Time.get_ticks_usec()
			warm.append((now-last)/1000.0)
			last = now
		begin = last
		while Time.get_ticks_usec() - begin < 30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append((now-last)/1000.0)
			last = now
			var t := (now-begin)/1000000.0
			world.player.automatic_direction = Vector3(0,0,sin(t*.45))
			world.camera.heading = sin(t*.18)*.25
			world.camera.target_size = 26+sin(t*.3)*3
		world.player.automatic_direction = Vector3.ZERO
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+site.id+".png")
		var result := {"id":site.id,"population":world.people.size(),"requested_population":world.production.requested_population,"vehicles":world.production.vehicles.size(),"position":str(world.player.global_position),"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
		var decoration := {"chunks":0,"leaves":0,"papers":0,"build_max_ms":0.0,"build_step_max_ms":0.0,"visible_chunks":0}
		for node in world.production.region.find_children("CityGroundLitter","Node3D",true,false):
			decoration.chunks += 1
			if node.visible: decoration.visible_chunks += 1
			decoration.leaves += int(node.get_meta("leaves"))
			decoration.papers += int(node.get_meta("papers"))
			decoration.build_max_ms = maxf(decoration.build_max_ms,float(node.get_meta("build_ms")))
			decoration.build_step_max_ms = maxf(decoration.build_step_max_ms,float(node.get_meta("build_step_max_ms",node.get_meta("build_ms"))))
		result.decoration = decoration
		result.density_scale = world.production.density_scale
		result.stars = world.gameplay.stars
		report.cases.append(result)
		FileAccess.open(folder+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		print("GROUND_LITTER_BENCHMARK ",site.id," ",JSON.stringify(result.summary))
		print("GROUND_LITTER_COUNTS ",JSON.stringify(decoration))
	if variant != "before" and "--without-litter" not in OS.get_cmdline_user_args() and not render_compare:
		# Readbacks are outside sampling. Continuous camera motion, documented timestamps.
		world.session.weather.time_of_day = .55
		world.session.weather.weather_state = 3
		world.session.weather._update()
		world.player.teleport(Vector3(86.7,.08,101.5))
		world.camera.target_size = 14
		world.camera.initialized = false
		for index in 80:
			world.camera.heading = sin(float(index)*.05)*.35
			await create_timer(.1).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/motion-%03d.png"%index)
		FileAccess.open(folder+"/motion.txt",FileAccess.WRITE).store_string("80 consecutive rendered captures, 0.1 s minimum interval plus readback; camera heading varies continuously. Readbacks excluded from benchmark.")
	world.queue_free()
	await process_frame
	quit()


func _show_litter(shown: bool) -> void:
	load("res://world/city_look/CityGroundLitter.gd").render_visible = shown
	for node in world.production.region.find_children("CityGroundLitter","Node3D",true,false): node.visible = shown


## Janelas curtas e alternadas equilibram a carga de trânsito/incidentes que depende do tempo.
## Os dois modos usam o mesmo código, atores e chunks gerados já carregados.
func _alternate(folder: String, report: Dictionary) -> bool:
	for site in [{"id":"day","time":.55,"weather":3},{"id":"night-rain","time":.84,"weather":1}]:
		world.player.teleport(Vector3(86.7,.08,101.5))
		world.production._update_physical_residency(world.player.position)
		world.production._update_logical_region(world.player.position)
		world.camera.heading = 0
		world.camera.target_size = 26
		world.camera.initialized = false
		world.session.weather.time_of_day = site.time
		world.session.weather.weather_state = site.weather
		world.session.weather.weather_timer = 10000
		world.session.weather._update()
		var warm: Array[float] = []
		var began := Time.get_ticks_usec()
		var last := began
		var shown := false
		while Time.get_ticks_usec()-began<10000000:
			var next := int((Time.get_ticks_usec()-began)/1000000)%2==0
			if next!=shown: _show_litter(next); shown = next
			await process_frame
			var now := Time.get_ticks_usec()
			warm.append((now-last)/1000.0)
			last = now
		var visible_frames: Array[float] = []
		var hidden_frames: Array[float] = []
		var windows: Array = []
		var elapsed_start := Time.get_ticks_usec()
		for pair in 30:
			# Inverte a ordem em pares alternados, evitando um viés sistemático de tendência.
			for mode in ([false,true] if pair%2==0 else [true,false]):
				_show_litter(mode)
				var window_start := Time.get_ticks_usec()
				last = window_start
				var skip := 4
				var frames: Array[float] = []
				while Time.get_ticks_usec()-window_start<1400000:
					await process_frame
					var now := Time.get_ticks_usec()
					if skip>0: skip -= 1
					else: frames.append((now-last)/1000.0)
					last = now
					var t := (now-elapsed_start)/1000000.0
					world.player.automatic_direction = Vector3(0,0,sin(t*.45))
					world.camera.heading = sin(t*.18)*.25
				if frames.is_empty():
					push_error("Alternating benchmark: no stable frames in window")
					return false
				if mode: visible_frames.append_array(frames)
				else: hidden_frames.append_array(frames)
				windows.append({"pair":pair,"visible":mode,"summary":stats(frames),"population":world.people.size(),"vehicles":world.production.vehicles.size(),"density":world.production.density_scale})
		world.player.automatic_direction = Vector3.ZERO
		_show_litter(true)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+site.id+".png")
		var result := {"id":site.id,"visible":stats(visible_frames),"hidden":stats(hidden_frames),"visible_frames_ms":visible_frames,"hidden_frames_ms":hidden_frames,"windows":windows,"warmup":stats(warm),"warmup_ms":warm}
		report.cases.append(result)
		FileAccess.open(folder+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		print("GROUND_LITTER_ALTERNATING ",site.id," hidden=",JSON.stringify(result.hidden)," visible=",JSON.stringify(result.visible))
	return true
