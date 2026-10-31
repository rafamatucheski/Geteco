extends "res://tests/measure/measure.gd"
## A/B renderizado de apresentação; veículo real do jogador, dirigibilidade, trânsito e luzes.
## A variante legada é injetada só neste processo; sem flag/save de produção.
class Probe extends Node:
	var owner_probe
	func _process(_delta: float) -> void: owner_probe.present()
	func _physics_process(_delta: float) -> void: owner_probe.drive()

class MeteredGround extends "res://runtime/atmosphere/RainGroundPresentation.gd":
	var batch_us: Array[float] = []
	func _physics_process(delta: float) -> void:
		var before := probe_count
		var begin := Time.get_ticks_usec()
		super._physics_process(delta)
		if probe_count>before: batch_us.append(float(Time.get_ticks_usec()-begin))

var folder := "res://evidence/rain-night-driving-20261015"
var weather
var car
var path: Curve3D
var initial_offset := 0.0
var moving := false
var legacy := false
var running := false
var game_input
var report := {}
var only := ""
var order := "before,after,after,before"
var contact_diagnostic := false
var diagnostic_start := 0
var ground_enabled := true

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or "--benchmark" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg=="--interleave-ground": contact_diagnostic = true
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		if arg.begins_with("--order="): order = arg.trim_prefix("--order=")
		if arg.begins_with("--out-dir="): folder = arg.trim_prefix("--out-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	seed(15102026)
	root.size = Vector2i(1920,1080)
	DisplayServer.window_move_to_foreground()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+150000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(3); return
	world.dispatch.router.nearest_edge(world.player.position)
	if not OS.get_environment("HARBOR_NO_CSHARP").is_empty() or world.dispatch.router._native==null:
		push_error("Rain benchmark requires the actual C# route backend"); quit(3); return
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	game_input = root.get_node("GameInput")
	game_input.using_gamepad = false
	weather = world.session.weather
	weather.weather_state = 2
	weather.weather_timer = 100000
	weather.coastal_wetness = 1.0
	weather.time_of_day = .93
	car = world.driving.car
	# Foundry Avenue autoral: uma reta contínua de 370m, sem esquinas fechadas de volta no quarteirão
	# que possam acumular colisões e invalidar amostras A/B posteriores.
	path = world.production.traffic_routes.route_between(Vector3(30,0,25),Vector3(400,0,25),Vector3.RIGHT)
	if path==null: push_error("No authored avenue route"); quit(4); return
	initial_offset = path.get_closest_offset(Vector3(35,0,25))
	reset_car()
	for i in 6: await physics_frame
	var entered := false
	for side in [-1,1]:
		world.player.teleport(car.to_global(Vector3(side*(car.half_width+.65),.04,.15)))
		await physics_frame
		if world.driving.interact(): entered=true; break
	if not entered: push_error("Rain benchmark could not board real player car"); quit(4); return
	deadline = Time.get_ticks_msec()+15000
	while not car.controlled and Time.get_ticks_msec()<deadline: await physics_frame
	if not car.controlled: quit(5); return
	print("RAIN_ROUTE_READY length=",path.get_baked_length()," start=",car.position," open=",path.get_meta("traffic_open",false))
	car.health = 1000000
	var probe := Probe.new()
	probe.owner_probe = self
	probe.process_priority = 110
	probe.process_physics_priority = -10
	root.add_child(probe)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var settings := root.get_node("V2Settings")
	report = {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"render_scale":root.scaling_3d_scale,"shadow_quality":settings.shadow_quality,"target_ms":16.67,"regression_confirmation_percent":5,"order":order,"route_length":path.get_baked_length(),"route_start":initial_offset,"cases":[],"source_hashes":{}}
	report.native_csharp = true
	for p in ["res://runtime/Weather.gd","res://runtime/atmosphere/CoastalRainPresentation.gd","res://runtime/atmosphere/RainGroundPresentation.gd","res://runtime/atmosphere/PrecipitationCoverage.gd","res://runtime/atmosphere/rain_impact.gdshader","res://runtime/atmosphere/rain_contact_drop.gdshader","res://scripts/Vehicle.gd","res://runtime/ProductionWorld.gd","res://world/regions/NativeRegion.gd","res://world/city_look/CoastalPlanarReflections.gd"]:
		report.source_hashes[p] = FileAccess.get_sha256(p)
	if contact_diagnostic:
		await diagnose_contacts()
		contact_diagnostic = false
		diagnostic_start = 0
		ground_enabled = true
		if only.is_empty():
			game_input.touch_move = Vector2.ZERO
			probe.queue_free()
			world.queue_free()
			await process_frame
			quit()
			return
	for scenario in [["day-driving",.45,true],["night-driving",.93,true],["night-parked",.93,false]]:
		if not only.is_empty() and scenario[0] not in only.split(","): continue
		var index := 0
		for variant in order.split(","):
			DisplayServer.window_move_to_foreground()
			print("RAIN_SAMPLE_BEGIN ",scenario[0]," ",variant," #",index)
			legacy = variant=="before"
			moving = scenario[2]
			weather.time_of_day = scenario[1]
			weather.rain_ground.process_mode = Node.PROCESS_MODE_DISABLED if legacy else Node.PROCESS_MODE_INHERIT
			weather.precipitation.amount = 1000 if legacy else 1400
			weather.precipitation.local_coords = legacy
			weather.precipitation.preprocess = weather.precipitation.lifetime
			weather.precipitation.restart()
			reset_car()
			world.camera.initialized = false
			running = true
			# Assenta o clima e aquece rota/shaders separado da amostra estável.
			for i in 200: weather._update()
			var warm := await sample(8.0)
			var start_distance: float = car.distance_travelled
			var start_position: Vector3 = car.position
			var data := await sample(30.0)
			var distance: float = car.distance_travelled-start_distance
			var item := {"scenario":scenario[0],"variant":variant,"round":index,"summary":stats(data.frames),"warmup":stats(warm.frames),"frames_ms":data.frames,"warmup_ms":warm.frames,"cpu_ms":data.cpu,"gpu_ms":data.gpu,"physics_ms":data.physics,"render_cpu_ms":data.render_cpu,"speed_mps":data.speed,"distance_m":distance,"start_position":str(start_position),"end_position":str(car.position),"population":world.people.size(),"traffic_children":world.traffic.get_child_count(),"unfocused_frames":data.unfocused,"draw_calls":data.draws,"camera_size":world.camera.size,"controlled":car.controlled,"external_input":car.external_input,"contacts":weather.rain_ground.impact_count,"roof_contacts":weather.rain_ground.roof_impact_count}
			item.start_unix = data.start_unix
			item.end_unix = data.end_unix
			for key in ["cpu","gpu","physics","render_cpu","speed"]: item[key+"_summary"] = distribution(data[key])
			report.cases.append(item)
			FileAccess.open(folder+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
			print("RAIN_DRIVING ",scenario[0]," ",variant," #",index," ",JSON.stringify(item.summary)," distance=",distance," speed=",JSON.stringify(item.speed_summary))
			running = false
			game_input.touch_move = Vector2.ZERO
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/"+scenario[0]+"-"+variant+"-"+str(index)+".png")
			if moving and distance<100.0:
				push_error("Driving sample did not travel 100m; comparison is invalid")
				quit(6); return
			index += 1
	game_input.touch_move = Vector2.ZERO
	report.source_hashes_end = {}
	for p in report.source_hashes: report.source_hashes_end[p] = FileAccess.get_sha256(p)
	FileAccess.open(folder+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	probe.queue_free()
	world.queue_free()
	await process_frame
	quit()

func reset_car() -> void:
	var point := path.sample_baked(initial_offset,true)
	var forward := path.sample_baked(initial_offset+1.0,true)-point
	car.place(point+Vector3.UP*.12,atan2(-forward.x,-forward.z))
	if car.handling != null: car.handling.reset()

func drive() -> void:
	if not running: return
	if not moving:
		game_input.touch_move = Vector2.ZERO
		return
	var offset := path.get_closest_offset(car.position)
	var ahead: Vector3 = path.sample_baked(minf(offset+5.0,path.get_baked_length()),true)-car.position
	var yaw := atan2(-ahead.x,-ahead.z)
	var error := angle_difference(car.rotation.y,yaw)
	var target := 4.5 if contact_diagnostic else 4.0 if absf(error)>.5 else 8.0
	if car.obstacle_ahead(): target = 0.0
	var speed: float = car.horizontal_velocity.length()
	game_input.touch_move = Vector2(clampf(-error*1.8,-1,1),-clampf((target-speed)*.35,-.5,1))

func present() -> void:
	if not running: return
	if contact_diagnostic and diagnostic_start>0:
		var block := int((Time.get_ticks_usec()-diagnostic_start)/2000000)%4
		ground_enabled = block==1 or block==2
		weather.rain_ground.process_mode = Node.PROCESS_MODE_INHERIT if ground_enabled else Node.PROCESS_MODE_DISABLED
	weather.rain_ground.visible = not legacy and ground_enabled
	if legacy:
		var emitter: GPUParticles3D = weather.precipitation
		emitter.amount_ratio = 1.0
		emitter.draw_pass_1.size = Vector2(.065,.86)
		var mat: StandardMaterial3D = emitter.draw_pass_1.material
		var day: float = weather.REGIONAL_ATMOSPHERE.daylight_at(weather.time_of_day)
		var tint := Color("708692").lerp(Color("b0bfc5"),day)
		tint.a = .54*lerpf(.72,1.0,day)
		mat.albedo_color = tint
		emitter.process_material.direction = Vector3(.1,-1,.05)

func sample(seconds: float) -> Dictionary:
	var frames: Array[float] = []
	var result := {"frames":frames,"cpu":[],"gpu":[],"physics":[],"render_cpu":[],"speed":[],"draws":[],"unfocused":0}
	result.start_unix = Time.get_unix_time_from_system()
	var start := Time.get_ticks_usec()
	var previous := start
	var traced := 0
	while Time.get_ticks_usec()-start<int(seconds*1000000):
		await process_frame
		var now := Time.get_ticks_usec()
		result.frames.append((now-previous)/1000.0)
		previous = now
		result.cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		result.physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
		result.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		result.render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		result.speed.append(car.horizontal_velocity.length())
		result.draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if not DisplayServer.window_is_focused(): result.unfocused += 1
		if (now-start)/1000000>traced+10:
			traced += 10
			print("RAIN_PROGRESS ",traced,"s position=",car.position," speed=",car.horizontal_velocity.length())
	result.end_unix = Time.get_unix_time_from_system()
	return result

func distribution(values: Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	return {"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted[-1]}

func diagnose_contacts() -> void:
	# Isolate surface contacts while the full 1400-drop storm stays unchanged.
	# 2s ABBA blocks balance adjacent road sections; 32 seconds per condition.
	weather.rain_ground.queue_free()
	var ground := MeteredGround.new()
	world.add_child(ground)
	weather.rain_ground = ground
	weather.precipitation.amount = 1400
	weather.precipitation.local_coords = false
	weather.time_of_day = .45
	legacy = false
	moving = true
	reset_car()
	running = true
	DisplayServer.window_move_to_foreground()
	for i in 200: weather._update()
	await sample(8.0)
	ground.batch_us.clear()
	var on_frames: Array[float] = []
	var off_frames: Array[float] = []
	var data := {"on":{"frames":on_frames,"gpu":[],"speed":[],"position_x":[],"unfocused":0},"off":{"frames":off_frames,"gpu":[],"speed":[],"position_x":[],"unfocused":0}}
	var start_distance: float = car.distance_travelled
	diagnostic_start = Time.get_ticks_usec()
	var previous := diagnostic_start
	var begin_unix := Time.get_unix_time_from_system()
	while Time.get_ticks_usec()-diagnostic_start<64000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var entry: Dictionary = data["on" if ground_enabled else "off"]
		entry.frames.append((now-previous)/1000.0)
		entry.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		entry.speed.append(car.horizontal_velocity.length())
		entry.position_x.append(car.position.x)
		if not DisplayServer.window_is_focused(): entry.unfocused += 1
		previous = now
	running = false
	for key in data:
		data[key].summary = stats(data[key].frames)
		data[key].gpu_summary = distribution(data[key].gpu)
		data[key].speed_summary = distribution(data[key].speed)
	report.diagnostic = {"kind":"contact-only alternating ABBA, 2s blocks, full storm held constant","start_unix":begin_unix,"end_unix":Time.get_unix_time_from_system(),"distance_m":car.distance_travelled-start_distance,"conditions":data,"probe_ticks_us":ground.batch_us.duplicate(),"probe_tick_summary_us":distribution(ground.batch_us)}
	report.source_hashes_end = {}
	for p in report.source_hashes: report.source_hashes_end[p] = FileAccess.get_sha256(p)
	FileAccess.open(folder+"/diagnostic.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/diagnostic.png")
	print("RAIN_CONTACT_DIAGNOSTIC ",JSON.stringify(data.on.summary)," vs ",JSON.stringify(data.off.summary)," probe_tick_us=",JSON.stringify(report.diagnostic.probe_tick_summary_us))
