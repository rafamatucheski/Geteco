extends "res://tests/measure/measure_rain_driving.gd"
## Cena real do Main, clima nativo e roteamento C#. Desempenho e gravação são separados.
## Obrigatório: --no-save --benchmark --isolated-save-root=<pasta nova>
## Opções: --label=before --out-dir=<pasta> --only=storm-parked
## --capture-only grava 30 segundos estacionado (chuva e tiros) e depois 10 segundos dirigindo.
const GLASS := preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const BODY_RAIN := preload("res://gameplay/vehicle_effects/VehicleRain.gd")
const SOURCES := ["res://gameplay/vehicle_effects/VehicleRain.gd", "res://gameplay/vehicle_effects/VehicleBodyRain.gdshader", "res://gameplay/vehicle_effects/VehicleRainDrops.gdshaderinc", "res://gameplay/vehicle_effects/VehicleWindshieldRain.gd", "res://gameplay/vehicle_effects/VehicleWindshieldRain.gdshader", "res://gameplay/vehicle_effects/VehicleWiper.gdshader", "res://gameplay/vehicle_effects/VehicleGlassDamage.gd", "res://gameplay/vehicle_effects/VehicleGlassRemnants.gd", "res://gameplay/vehicle_effects/VehicleDamage.gd", "res://gameplay/vehicle_effects/VehicleMaterialVariantPrewarm.gd", "res://scripts/Vehicle.gd", "res://runtime/Weather.gd", "res://runtime/ProductionWorld.gd", "res://runtime/FullSession.gd", "res://runtime/GameInput.gd", "res://scripts/World.gd", "res://scripts/CameraRig.gd"]
var capture_only := false
var capture_camera: Camera3D

func run() -> void:
	var isolated := false
	label = "current"
	folder = "res://evidence/vehicle-rain-finish-%d" % OS.get_process_id()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--isolated-save-root="): isolated = true
		if arg.begins_with("--out-dir="): folder = arg.trim_prefix("--out-dir=")
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		if arg == "--capture-only": capture_only = true
	if DisplayServer.get_name() == "headless" or not isolated or "--no-save" not in OS.get_cmdline_user_args() or "--benchmark" not in OS.get_cmdline_user_args():
		push_error("Rendered scene and isolated save/settings root are mandatory")
		quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	seed(26102026)
	root.size = Vector2i(1280,720)
	DisplayServer.window_move_to_foreground()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+150000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.dispatch.router.nearest_edge(world.player.position)
	if not OS.get_environment("HARBOR_NO_CSHARP").is_empty() or world.dispatch.router._native == null:
		push_error("Rain comparison requires the actual C# backend"); quit(3); return
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	game_input = root.get_node("GameInput")
	game_input.using_gamepad = false
	weather = world.session.weather
	weather.weather_locked = true
	weather.weather_timer = 100000
	weather.time_scale = 0.0
	weather.coastal_wetness = 1.0
	car = world.driving.car
	path = world.production.traffic_routes.route_between(Vector3(30,0,25),Vector3(400,0,25),Vector3.RIGHT)
	if path == null: push_error("Missing authored avenue route"); quit(4); return
	initial_offset = path.get_closest_offset(Vector3(35,0,25))
	reset_car()
	for i in 6: await physics_frame
	var entered := false
	for side in [-1,1]:
		world.player.teleport(car.to_global(Vector3(side*(car.half_width+.65),.04,.15)))
		await physics_frame
		if world.driving.interact(): entered = true; break
	if not entered: push_error("Could not board actual player vehicle"); quit(4); return
	deadline = Time.get_ticks_msec()+15000
	while not car.controlled and Time.get_ticks_msec()<deadline: await physics_frame
	if not car.controlled: quit(5); return
	var probe := Probe.new()
	probe.owner_probe = self
	probe.process_priority = 110
	probe.process_physics_priority = -10
	root.add_child(probe)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var settings := root.get_node("V2Settings")
	report = {"label":label,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"render_scale":root.scaling_3d_scale,"shadow_quality":settings.shadow_quality,"target_ms":16.67,"regression_confirmation_percent":5,"native_csharp":true,"cases":[],"source_hashes":{},"notes":"Real Main with traffic/NPCs active. Board through interaction; steering input injected. Capture shots use production bullet handling with scripted rays. No claims of full input end-to-end or save persistence."}
	for source in SOURCES: report.source_hashes[source] = FileAccess.get_sha256(source)
	if capture_only:
		await record_sequence()
	else:
		for scenario in [["drizzle-parked",1,.14,.45,false],["storm-parked",2,1.0,.45,false],["storm-driving",2,1.0,.93,true]]:
			if not only.is_empty() and scenario[0] not in only.split(","): continue
			reset_car()
			car.repair()
			car.set_meta("rain_wet",1.0)
			set_weather(scenario[1],scenario[2],scenario[3])
			moving = scenario[4]
			running = true
			world.camera.initialized = false
			print("VEHICLE_RAIN_BEGIN ",scenario[0]," ",label)
			var warm := await sample(8.0)
			# Reinicia a rota depois do aquecimento para que uma direção completa de 30 s caiba na avenida.
			if moving: reset_car()
			var start_distance: float = car.distance_travelled
			var start_position: Vector3 = car.position
			var load_start := scene_load()
			var data := await sample(30.0)
			var distance: float = car.distance_travelled-start_distance
			var item := {"scenario":scenario[0],"summary":stats(data.frames),"warmup":stats(warm.frames),"frames_ms":data.frames,"warmup_ms":warm.frames,"cpu_ms":data.cpu,"gpu_ms":data.gpu,"physics_ms":data.physics,"render_cpu_ms":data.render_cpu,"speed_mps":data.speed,"distance_m":distance,"start_position":str(start_position),"end_position":str(car.position),"population":world.people.size(),"scene_load_start":load_start,"scene_load_end":scene_load(),"unfocused_frames":data.unfocused,"draw_calls":data.draws,"camera_size":world.camera.size,"controlled":car.controlled,"rain_strength":weather.rain_strength_at(car.global_position),"start_unix":data.start_unix,"end_unix":data.end_unix}
			for key in ["cpu","gpu","physics","render_cpu","speed"]: item[key+"_summary"] = distribution(data[key])
			item.route_valid = not moving or distance >= 100.0
			report.cases.append(item)
			write_report()
			print("VEHICLE_RAIN_RESULT ",scenario[0]," ",JSON.stringify(item.summary)," distance=",distance)
			running = false
			game_input.touch_move = Vector2.ZERO
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join(str(scenario[0])+".png"))
			if not item.route_valid: push_error("Route did not travel 100 m; comparison is invalid"); quit(6); return
	running = false
	game_input.touch_move = Vector2.ZERO
	report.source_hashes_end = {}
	for source in SOURCES: report.source_hashes_end[source] = FileAccess.get_sha256(source)
	write_report()
	probe.queue_free()
	world.queue_free()
	await process_frame
	quit()

func present() -> void:
	# Herda só a direção e a amostragem da rota; nunca troca efeitos de chuva não relacionados.
	if not capture_only or not is_instance_valid(capture_camera): return
	var pose: Transform3D = car.get_global_transform_interpolated()
	var center := pose.origin + Vector3.UP*.8
	capture_camera.global_position = center + pose.basis * Vector3(-6,6,-8)
	capture_camera.look_at(center)

func set_weather(state: int, strength: float, hour: float) -> void:
	weather.weather_state = state
	weather.rain_intensity = strength
	weather.rain_level = strength
	weather.time_of_day = hour
	weather._sync_external_state()
	weather._update()

func write_report() -> void:
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))

func scene_load() -> Dictionary:
	# O ProductionWorld é dono dos veículos reais; world.traffic é um contêiner legado vazio.
	var vehicles := 0
	var traffic := 0
	var visible_traffic := 0
	var current_camera := root.get_camera_3d()
	for vehicle in world.production.vehicles:
		if not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion(): continue
		vehicles += 1
		if not vehicle.traffic or vehicle.health <= 0.0: continue
		traffic += 1
		if vehicle.is_visible_in_tree() and current_camera.is_position_in_frustum(vehicle.global_position): visible_traffic += 1
	return {"pedestrians":world.people.size(),"vehicles":vehicles,"traffic":traffic,"ambient_traffic":world.production._ambient_traffic_count(),"visible_traffic":visible_traffic,"traffic_cap":world.production._traffic_cap(),"pedestrian_cap":world.production._population_cap()}

func glass_ray() -> Array:
	car.finish_doors()
	var owner := GLASS.owner_for(car,true)
	var best: Array = []
	var best_score := -1.0
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		for surface in part.mesh.get_surface_count():
			if GLASS._hidden(part,surface) or not INTERIOR._is_glass(part,surface,part.get_active_material(surface)): continue
			var arrays := INTERIOR.contact_arrays(part.mesh,surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := GLASS._indices(arrays)
			for i in range(0,indices.size()-2,3):
				var a := part.to_global(points[indices[i]])
				var b := part.to_global(points[indices[i+1]])
				var c := part.to_global(points[indices[i+2]])
				var world_point := (a+b+c)/3.0
				var car_point: Vector3 = car.to_local(world_point)
				var cross := (b-a).cross(c-a)
				var facing: Vector3 = car.global_basis.inverse()*cross.normalized()
				# A câmera fica do lado do motorista. Prefere o vidro grande da porta, deixando
				# o para-brisa intacto para observar as gotas dele durante os tiros.
				if car_point.x >= 0.0 or absf(facing.x) < .5 or absf(facing.x) < absf(facing.z): continue
				var normal: Vector3 = car.global_basis * Vector3.LEFT
				var from := world_point + normal*5.0
				var to := world_point - normal*5.0
				var hit: Dictionary = owner.contact(from,to)
				if hit.is_empty() or not hit.glass or hit.point.distance_to(world_point) > .05: continue
				var score := cross.length()/(1.0+absf(car_point.z+.2))
				if "DriverDoorL" in str(part.get_path()): score *= 4.0
				if score <= best_score: continue
				best_score = score
				best = [from,to]
				report.shot_target = {"part":str(part.get_path()),"surface":surface,"triangle":i,"car_point":str(car_point),"triangle_area":cross.length()*.5,"score":score}
	return best

func rain_state() -> Dictionary:
	var materials: Array = []
	for material: StandardMaterial3D in car._paint.materials:
		var record: Dictionary = material.get_meta("rain_base",{})
		materials.append({"has_beads":BODY_RAIN.has_beads(material),"wet":record.get("wet",0.0),"falling":record.get("falling",0.0),"albedo":str(material.albedo_color),"roughness":material.roughness})
	var windshield = car.effects.windshield_rain
	return {"health":car.health,"glass_records":car.snapshot_glass(),"body_wet":car.get_meta("rain_wet",0.0),"body_level":car.get_meta("rain_level",0.0),"materials":materials,"windshield_active":windshield.is_active() if windshield != null else false,"windshield_level":windshield.level() if windshield != null else 0.0}

func record_sequence() -> void:
	reset_car()
	car.repair()
	car.paint_color = Color("356d8f")
	world.gameplay.god_mode = false
	car.set_meta("rain_wet",1.0)
	set_weather(1,.14,.45)
	moving = false
	running = true
	await sample(8.0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	camera.current = true
	capture_camera = camera
	present()
	var ray := glass_ray()
	if ray.is_empty(): push_error("No reachable glass for capture"); quit(7); return
	# Salva todo quadro renderizado, limitado a 30 fps. O custo da gravação fica fora do desempenho.
	Engine.max_fps = 30
	var frames: Array = []
	var events: Array = [{"time":0.0,"event":"start","state":rain_state()}]
	var began := Time.get_ticks_usec()
	var previous_draw := Engine.get_frames_drawn()
	var phase := 0
	var shots := 0
	var moving_start := -1.0
	while Time.get_ticks_usec()-began<40000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var elapsed := (now-began)/1000000.0
		var drawn := Engine.get_frames_drawn()
		var file := "%05d.jpg" % frames.size()
		root.get_texture().get_image().save_jpg(folder.path_join(file),.94)
		frames.append({"time":elapsed,"drawn":drawn,"draw_gap":drawn-previous_draw,"file":file,"rain":weather.rain_strength_at(car.global_position),"wet":car.get_meta("rain_wet",0.0),"glass_records":car.snapshot_glass().size(),"health":car.health,"distance":car.distance_travelled,"speed":car.horizontal_velocity.length()})
		previous_draw = drawn
		if elapsed >= 8.0 and phase == 0: set_weather(1,.30,.45); phase = 1; events.append({"time":elapsed,"event":"light-rain"})
		if elapsed >= 16.0 and phase == 1: set_weather(2,1.0,.45); phase = 2; events.append({"time":elapsed,"event":"storm"})
		if shots < 3 and elapsed >= 22.0+shots*2.0:
			var before := rain_state()
			world.gameplay._damage_bullet(car,10.0,null,ray[0],ray[1])
			shots += 1
			events.append({"time":elapsed,"event":"glass-shot","number":shots,"before":before,"after":rain_state()})
		if elapsed >= 30.0 and moving_start < 0.0:
			moving_start = car.distance_travelled
			moving = true
			events.append({"time":elapsed,"event":"driving-start","distance":moving_start,"state":rain_state()})
	var distance_end: float = car.distance_travelled
	var moving_distance := distance_end-moving_start if moving_start >= 0.0 else 0.0
	events.append({"time":(Time.get_ticks_usec()-began)/1000000.0,"event":"driving-end","distance":distance_end,"distance_travelled":moving_distance,"state":rain_state()})
	moving = false
	game_input.touch_move = Vector2.ZERO
	report.capture = {"duration":(Time.get_ticks_usec()-began)/1000000.0,"camera":"integrated close-up follows car center/basis at fixed zoom; scene/traffic remain active","capture_limit_fps":30,"frames":frames,"events":events,"shots":shots,"moving_distance":moving_distance,"motion_valid":moving_distance>10.0,"note":"First 30 seconds parked, last 10 seconds use production driving input. Every rendered frame written; draw_gap and timestamps expose missed/slow capture frames. Inspect the sequence for presentation; this is not the performance sample."}
	write_report()
	print("VEHICLE_RAIN_CAPTURE ",frames.size()," frames in ",report.capture.duration," seconds")
