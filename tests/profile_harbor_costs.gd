extends SceneTree

var scene: Node2D
var views: Array[SubViewport] = []
var lights: Array[Light2D] = []
var disabled_views := false
var disabled_lights := false

func _init() -> void: call_deferred("run")
func collect(node: Node) -> void:
	if node is SubViewport: views.append(node)
	if node is Light2D: lights.append(node)
	for child in node.get_children(): collect(child)
func measure(label: String) -> void:
	var samples: Array[float] = []
	var draws := 0.0
	var physics := 0.0
	var processing := 0.0
	var render_cpu := 0.0
	var render_gpu := 0.0
	for i in 210:
		if disabled_views:
			for view in views:
				view.disable_3d = true
				view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if disabled_lights:
			for light in lights: light.hide()
		var before := Time.get_ticks_usec()
		await process_frame
		if i >= 30:
			samples.append((Time.get_ticks_usec()-before)/1000.0)
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
			processing += Performance.get_monitor(Performance.TIME_PROCESS)*1000
			render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
			render_gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	var total := 0.0
	for value in samples: total += value
	samples.sort()
	print("COST_PROFILE %s avg_ms=%.2f median_ms=%.2f p95_ms=%.2f drawcalls=%.0f physics_ms=%.2f viewports=%d" % [label,total/samples.size(),samples[90],samples[171],draws/180,physics/180,views.size()])
	print("COST_DETAIL %s process_ms=%.2f root_render_cpu_ms=%.2f root_render_gpu_ms=%.2f" % [label,processing/180,render_cpu/180,render_gpu/180])
func run() -> void:
	root.size = Vector2i(1920,1080)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.grab_focus()
	print("PROFILE_CONTEXT focused=%s low_processor=%s" % [root.has_focus(),OS.low_processor_usage_mode])
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 30: await physics_frame
	collect(scene)
	if "overview" in OS.get_cmdline_user_args():
		await measure("overview_baseline")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("harbor-performance-overview.png"))
		scene.queue_free()
		await process_frame
		quit()
		return
	scene._walk()
	scene.get_node("Player").global_position = Vector2(1620,900)
	scene.get_node("Player/Camera").reset_smoothing()
	await measure("walk_baseline")
	if "logic" in OS.get_cmdline_user_args():
		scene.process_mode = Node.PROCESS_MODE_DISABLED
		await measure("logic_without_scene")
		scene.process_mode = Node.PROCESS_MODE_INHERIT
		var modes := {}
		for node in root.get_children():
			if node != scene:
				modes[node] = node.process_mode
				node.process_mode = Node.PROCESS_MODE_DISABLED
		await measure("logic_without_autoloads")
		for node in modes: node.process_mode = modes[node]
		for name_value in ["DayNightWeather","Interiors","Life","FreightRail","RoadSafety","Player"]:
			var node := scene.get_node(name_value)
			var previous_mode := node.process_mode
			node.process_mode = Node.PROCESS_MODE_DISABLED
			await measure("logic_without_"+name_value)
			node.process_mode = previous_mode
		scene.queue_free()
		await process_frame
		quit()
		return
	if "quick" in OS.get_cmdline_user_args():
		for node in root.get_children(): node.process_mode = Node.PROCESS_MODE_DISABLED
		await measure("quick_all_logic_paused")
		RenderingServer.render_loop_enabled = false
		await measure("quick_no_render_no_logic")
		RenderingServer.render_loop_enabled = true
		scene.queue_free()
		await process_frame
		quit()
		return
	disabled_views = true
	await measure("walk_no_3d_render")
	disabled_lights = true
	await measure("walk_no_3d_no_lights")
	scene.get_node("Waterfront").set_process(false)
	await measure("walk_no_3d_no_lights_no_water_animation")
	var processing_nodes: Array[Node] = []
	for group in ["vehicle","pedestrian"]:
		for node in get_nodes_in_group(group):
			if node.is_physics_processing():
				processing_nodes.append(node)
				node.set_physics_process(false)
	await measure("walk_visual_only_no_population_physics")
	scene.get_node("Waterfront").hide()
	await measure("walk_without_waterfront")
	scene.get_node("RoadNetwork").hide()
	await measure("walk_without_waterfront_and_roads")
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	await measure("walk_all_scene_logic_paused")
	# New instance restores all render/processing states exactly for overview.
	scene.queue_free()
	await process_frame
	views.clear()
	lights.clear()
	disabled_views = false
	disabled_lights = false
	scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 30: await physics_frame
	collect(scene)
	await measure("overview_baseline")
	disabled_views = true
	await measure("overview_no_3d_render")
	scene.queue_free()
	await process_frame
	quit()
