extends "res://tests/measure/measure.gd"
## Main real, dados isolados: comparação de fachadas em três bairros.
## --no-save --skip-arrival --out=res://evidence/<pasta-nova>
## --visual percorre câmera/distância/ciclo; usar com --write-movie para vídeo.
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
var output := ""
var visual := false

func run() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	visual = "--visual" in args
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or not output.begins_with("res://evidence/") or DirAccess.dir_exists_absolute(output):
		push_error("Exige renderização, --no-save e --out novo dentro de evidence.")
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	seed(6102026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_dispatch",true)
	root.add_child(world)
	current_scene = world
	for frame in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play and world.production.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.urban_operations.security.authorized_visit = true
	world.camera.set_process_unhandled_input(false)
	world.session.weather.set_process(false)
	var sites := [
		{"id":"centro-hospital","point":Vector3(84,.15,107)},
		{"id":"northbank","point":Vector3(319,.15,65)},
		{"id":"bairro-residencial","point":Vector3(487,.15,106)}]
	for site in sites:
		world.player.set_physics_process(false)
		world.player.teleport(site.point)
		world.production._update_physical_residency(site.point)
		for frame in 1200:
			await process_frame
			if world.production.region.pending.is_empty() and world.production.region.build_jobs.is_empty(): break
		await physics_frame
		await physics_frame
		world.player.teleport(site.point)
		world.player.set_physics_process(true)
		world.camera.heading = 0
		world.camera.target_size = 40
		world.camera.initialized = false
		set_time(.93)
		var warm: Array[float] = []
		var frames: Array[float] = []
		var started_usec := Time.get_ticks_usec()
		var previous_usec := started_usec
		var first_video_frame := Engine.get_frames_drawn()
		var captured_frames := 0
		while (visual and captured_frames < 2280) or (not visual and Time.get_ticks_usec()-started_usec < 38000000):
			await process_frame
			captured_frames += 1
			var now := Time.get_ticks_usec()
			if now-started_usec < 8000000: warm.append((now-previous_usec)/1000.0)
			else: frames.append((now-previous_usec)/1000.0)
			previous_usec = now
			if visual:
				var t := float(captured_frames)/60.0
				if captured_frames == 1920:
					world.session.weather.weather_state = 1
					world.session.weather._update()
				# Still, pan out/back across streaming cells, rotate and zoom.
				var distance := sin(clampf((t-12.0)/12.0,0,1)*PI)*24.0
				world.player.teleport(site.point+Vector3(distance,0,0))
				world.camera.heading = sin(maxf(0,t-20.0)*.18)*.5
				world.camera.target_size = 40+sin(maxf(0,t-20.0)*.24)*12
		var report := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"visual_recording":visual,"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,"facades":inventory(site.point),"point":str(world.player.global_position),"population":world.people.size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
		if visual: report.video = {"first_frame":first_video_frame,"frames":captured_frames,"fps":60,"rain_starts_at_seconds":32}
		if world.player.global_position.distance_to(site.point)>35 or world.gameplay.health<=0:
			push_error("Medição inválida: jogador saiu do cenário "+site.id)
			quit(4); return
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/"+site.id+"-night.png")
		for condition in [{"id":"day","time":.4},{"id":"dusk","time":.76}]:
			set_time(condition.time)
			await create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/"+site.id+"-"+condition.id+".png")
		FileAccess.open(output+"/"+site.id+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
		print("WINDOW_LIGHTING ",site.id," ",JSON.stringify(report.summary)," facades=",JSON.stringify(report.facades))
	quit()

func set_time(value: float) -> void:
	world.session.weather.time_of_day = value
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999
	world.session.weather._update()
	world.session.weather._process(0)

func inventory(point: Vector3) -> Dictionary:
	var lit := 0
	var total := 0
	var buildings := {}
	var window_materials: Array = [UrbanMaterials.glass_window(),UrbanMaterials.glass_window_lit(true),UrbanMaterials.glass_window_lit(false),MATERIALS.window_tv()]
	for index in MATERIALS.WINDOW_TONES.size(): window_materials.append(MATERIALS.window_lit(index))
	for index in MATERIALS.UNLIT_VARIANTS: window_materials.append(MATERIALS.window_unlit(index))
	for node in world.find_children("*","GeometryInstance3D",true,false):
		if not (node is MeshInstance3D or node is MultiMeshInstance3D) or node.global_position.distance_to(point)>65: continue
		var mat: Material = node.material_override
		if mat == null: continue
		var is_window: bool = mat in window_materials or bool(node.get_meta("city_window",false)) or String(node.name).begins_with("WindowGlass") or bool(mat.get_meta("city_window",false))
		if not is_window: continue
		var count: int = node.multimesh.instance_count if node is MultiMeshInstance3D else 1
		total += count
		if mat is StandardMaterial3D and mat.emission_enabled and mat.emission_energy_multiplier > .5: lit += count
		var owner_node: Node = node.get_parent()
		while owner_node.get_parent()!=null and owner_node.get_parent().name != "Chunks" and not owner_node is UrbanBuildingBase and not owner_node.has_meta("_urban_data"):
			owner_node = owner_node.get_parent()
		buildings[str(owner_node.name)] = true
	return {"lit":lit,"total":total,"buildings":buildings.keys(),"lights":world.find_children("*","Light3D",true,false).size()}
