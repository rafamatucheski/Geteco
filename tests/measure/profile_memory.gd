extends SceneTree
## Diagnostic only: production world, isolated saves, fixed route, process/native/GPU counters.
var world: Node
var output := "res://artifacts/memory-renderers-20261019/run"
var samples: Array[Dictionary] = []
var frames: Array[float] = []
var started := Time.get_ticks_msec()
var advanced_probe := false
var short_probe := false
var full_regression := false
var custom_only := false
class InputGuard extends Node:
	func _input(_event: InputEvent) -> void: get_viewport().set_input_as_handled()

func _initialize() -> void: run.call_deferred()

func snapshot(stage: String) -> void:
	var data := {"stage":stage,"elapsed_s":(Time.get_ticks_msec()-started)/1000.0,
		"pid":OS.get_process_id(),"epoch":Time.get_unix_time_from_system(),
		"renderer":RenderingServer.get_current_rendering_method(),
		"driver":RenderingServer.get_current_rendering_driver_name(),
		"native":Performance.get_monitor(Performance.MEMORY_STATIC),
		"native_peak":Performance.get_monitor(Performance.MEMORY_STATIC_MAX),
		"texture":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"buffers":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
		"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)}
	data["pipelines"]={"surface":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),"draw":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),"mesh":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),"specialization":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)}
	data["caches"]={"families":preload("res://world/chunk_bake/ChunkCellMerge.gd")._family_materials.size(),"tunnel":preload("res://world/urban_detail/TunnelCutaway.gd")._primed.size(),"release":preload("res://runtime/GpuReleaseQueue.gd").debug_snapshot()}
	var diagnostics := root.get_node_or_null("SessionDiagnostics")
	if diagnostics != null: data["diagnostics"] = JSON.parse_string(diagnostics.call("RuntimeSnapshot"))
	samples.append(data)
	var file := FileAccess.open(output+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"samples":samples,"frames_ms":frames},"\t"))
	print("MEMORY ", JSON.stringify(data))

func run() -> void:
	auto_accept_quit = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--memory-out="): output = arg.trim_prefix("--memory-out=")
		if arg == "--memory-advanced": advanced_probe = true
		if arg == "--memory-short": short_probe = true
		if arg == "--memory-regression": full_regression = true
		if arg == "--memory-custom": custom_only = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	snapshot("autoloads")
	var scene := load("res://Main.tscn") as PackedScene
	snapshot("main_loaded")
	world = scene.instantiate()
	snapshot("instantiated")
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+240000
	var next := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if Time.get_ticks_msec()>=next:
			snapshot("loading")
			next=Time.get_ticks_msec()+10000
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	if world.production == null or not world.production.ready_for_play or world.session == null or not world.session.ready_for_play:
		snapshot("load_timeout")
		quit(2)
		return
	var settings := root.get_node("V2Settings")
	settings.set_graphics_preset(2)
	settings.vsync=false
	settings.fps_limit=4
	settings.apply_settings()
	var weather: Node = world.session.weather
	weather.time_of_day=.5
	weather.weather_state=0
	weather.weather_timer=1.0e9
	world.player.set_physics_process(false)
	world.driving.car.set_physics_process(false)
	world.camera.target=world.player
	root.add_child(InputGuard.new())
	snapshot("ready")
	# Three identical loops distinguish initial cache warming from retained growth.
	var route := [Vector3(64,0,82),Vector3(150,0,82),Vector3(143,0,60),Vector3(84,0,60),Vector3(84,0,123),Vector3(65,0,113)]
	var lap_length := 0.0
	for i in route.size(): lap_length += route[i].distance_to(route[(i+1)%route.size()])
	for lap in (1 if custom_only or (advanced_probe and not full_regression) else 3):
		var distance := 0.0
		var previous := Time.get_ticks_usec()
		next=Time.get_ticks_msec()+5000
		while distance<lap_length:
			var along := distance
			for i in route.size():
				var length: float=route[i].distance_to(route[(i+1)%route.size()])
				if along<=length:
					world.player.global_position=route[i].lerp(route[(i+1)%route.size()],along/length)+Vector3.UP*.1
					break
				along-=length
			await process_frame
			var now := Time.get_ticks_usec()
			var ms := (now-previous)/1000.0
			previous=now
			if lap>0: frames.append(ms)
			distance+=12.0*minf(ms,100.0)/1000.0
			if Time.get_ticks_msec()>=next:
				snapshot("lap_%d"%(lap+1))
				next=Time.get_ticks_msec()+5000
		snapshot("lap_%d_end"%(lap+1))
	if advanced_probe:
		var choices := ["taa","medium_after_taa"] if short_probe else ["taa","medium_after_taa","ssr","medium_after_ssr","fsr2","medium_after_fsr2"]
		for choice in choices:
			settings.set_graphics_preset(2)
			if choice == "taa": settings.aa_mode=3
			if choice == "ssr":
				# Stale environments from an older config must also be cleaned by the policy.
				world.production.environment.environment.ssr_enabled=true
			if choice == "fsr2": settings.upscale_mode=2
			settings.apply_settings()
			for second in 15:
				await create_timer(1.0).timeout
				if second in [4,14]: snapshot(choice)
	if full_regression:
		for preset in [1,2,3,2]:
			settings.set_graphics_preset(preset)
			await create_timer(5.0).timeout
			snapshot("preset_%d"%preset)
		# Exercise the remaining custom effects, including the user's high-quality combination.
		settings.set_graphics_preset(3)
		settings.aa_mode=2
		settings.volumetric_fog=true
		settings.apply_settings()
		await create_timer(15.0).timeout
		snapshot("custom_ssao_fog")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"-custom.png")
		settings.set_graphics_preset(2)
		await create_timer(10.0).timeout
		snapshot("medium_recovered")
	if OS.has_method("print_all_resources_to_file"): OS.call("print_all_resources_to_file",ProjectSettings.globalize_path(output+"-resources.txt"))
	RenderingServer.call_on_render_thread(_gpu_report)
	for frame in 3: await process_frame
	var inventory := {}
	for node in root.find_children("*","",true,false):
		var kind: String=node.get_class()
		inventory[kind]=int(inventory.get(kind,0))+1
	FileAccess.open(output+"-nodes.json",FileAccess.WRITE).store_string(JSON.stringify(inventory,"\t"))
	snapshot("finished")
	quit(0)

func _gpu_report() -> void:
	var device := RenderingServer.get_rendering_device()
	if device == null: return
	FileAccess.open(output+"-gpu.csv",FileAccess.WRITE).store_string(device.get_driver_and_device_memory_report())
