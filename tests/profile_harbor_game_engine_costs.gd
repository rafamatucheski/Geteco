extends SceneTree

## Engine-measured (Performance/RenderingServer) CPU/GPU/physics breakdown and
## slow-frame correlation for the exact HarborGame post-arrival driving
## benchmark used by measure_harbor_game_driving.gd. Reads only engine
## monitors during normal process_frame ticks driven by real Input actions —
## never manually invokes _process/_physics_process. Diagnostic only, does
## not change any behavior or leave anything disabled.

const GAME := preload("res://world/harbor/HarborGame.tscn")

var character_viewports: Array[SubViewport] = []

func _initialize() -> void: call_deferred("_run")

func _collect_viewports(node: Node) -> void:
	if node is SubViewport and (node as SubViewport).own_world_3d:
		character_viewports.append(node)
	for child in node.get_children(): _collect_viewports(child)

func _percentile(sorted_values: Array, fraction: float) -> float:
	var index: int = clampi(int(sorted_values.size() * fraction), 0, sorted_values.size() - 1)
	return sorted_values[index]

func _summarize(label: String, values: Array[float]) -> void:
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var total := 0.0
	for value in values: total += value
	print("METRIC %s avg=%.3f p50=%.3f p90=%.3f p99=%.3f worst=%.3f" % [
		label, total / values.size(), _percentile(sorted_values, 0.50),
		_percentile(sorted_values, 0.90), _percentile(sorted_values, 0.99), sorted_values[-1],
	])

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.grab_focus()
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world := GAME.instantiate()
	root.add_child(world)
	current_scene = world
	for i in 90: await process_frame
	if not world.gameplay_ready or paused:
		push_error("Engine-cost profiling checkpoint did not become playable")
		quit(1)
		return
	var player: Node2D = world.get_node("Player")
	player.global_position = Vector2(2200, 1050)
	var car: CharacterBody2D = world.get_node("PlayerCar")
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	world.call("_drive")
	for i in 30: await process_frame

	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_collect_viewports(world)
	for view in character_viewports:
		RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
	print("ENGINE_PROFILE_CONTEXT character_viewports=%d player_visible=%s" % [character_viewports.size(), player.is_visible_in_tree()])

	var controller = world.get_node_or_null("Life/JunctionTrafficController")
	var last_sync_elapsed: float = controller.get("_sync_elapsed") if controller else 0.0
	var last_crossing_elapsed: float = controller.get("_crossing_sync_elapsed") if controller else 0.0
	var last_physics_frame := Engine.get_physics_frames()

	var frame_ms: Array[float] = []
	var cpu_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var render_cpu_ms: Array[float] = []
	var render_gpu_ms: Array[float] = []
	var char_render_cpu_ms: Array[float] = []
	var char_render_gpu_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var phys_active: Array[float] = []
	var phys_pairs: Array[float] = []
	var phys_islands: Array[float] = []
	var physics_steps: Array[float] = []
	var sync_tick: Array[bool] = []

	Input.action_press("ui_up")
	var previous_pos := car.global_position
	var distance := 0.0
	for i in 600:
		var start := Time.get_ticks_usec()
		await process_frame
		frame_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
		distance += car.global_position.distance_to(previous_pos)
		previous_pos = car.global_position

		cpu_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		render_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		var sum_cpu := 0.0
		var sum_gpu := 0.0
		for view in character_viewports:
			if not is_instance_valid(view): continue
			sum_cpu += RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid())
			sum_gpu += RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
		char_render_cpu_ms.append(sum_cpu)
		char_render_gpu_ms.append(sum_gpu)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		phys_active.append(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS))
		phys_pairs.append(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS))
		phys_islands.append(Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT))
		var pf := Engine.get_physics_frames()
		physics_steps.append(float(pf - last_physics_frame))
		last_physics_frame = pf
		var tick := false
		if controller != null:
			var se: float = controller.get("_sync_elapsed")
			var ce: float = controller.get("_crossing_sync_elapsed")
			if se < last_sync_elapsed or ce < last_crossing_elapsed: tick = true
			last_sync_elapsed = se
			last_crossing_elapsed = ce
		sync_tick.append(tick)
	Input.action_release("ui_up")

	print("HARBOR_ENGINE_PROFILE frames=600 travelled_px=%.1f" % distance)
	_summarize("frame_ms", frame_ms)
	_summarize("script_process_ms", cpu_ms)
	_summarize("script_physics_ms", physics_ms)
	_summarize("main_render_cpu_ms", render_cpu_ms)
	_summarize("main_render_gpu_ms", render_gpu_ms)
	_summarize("character_viewport_cpu_ms", char_render_cpu_ms)
	_summarize("character_viewport_gpu_ms", char_render_gpu_ms)
	_summarize("draw_calls", draw_calls)
	_summarize("physics_active_objects", phys_active)
	_summarize("physics_collision_pairs", phys_pairs)
	_summarize("physics_islands", phys_islands)
	_summarize("physics_steps_per_frame", physics_steps)

	var sync_ticks_total := 0
	for value in sync_tick:
		if value: sync_ticks_total += 1
	print("JUNCTION_SYNC_TICKS_OBSERVED %d" % sync_ticks_total)

	# Correlate the slowest frames against every metric captured that same
	# frame, to see what is actually elevated during a spike rather than
	# only how the aggregate average moves.
	var order: Array[int] = []
	for i in frame_ms.size(): order.append(i)
	order.sort_custom(func(a, b): return frame_ms[a] > frame_ms[b])
	var slow_with_sync := 0
	var slow_with_multi_physics_step := 0
	var slow_count := int(frame_ms.size() * 0.10)
	for rank in slow_count:
		var i: int = order[rank]
		if sync_tick[i]: slow_with_sync += 1
		if physics_steps[i] > 1.0: slow_with_multi_physics_step += 1
	print("SLOWEST_10PCT_CORRELATION count=%d sync_tick_frames=%d multi_physics_step_frames=%d" % [slow_count, slow_with_sync, slow_with_multi_physics_step])

	print("SLOWEST_FRAMES (top 15, frame_ms desc)")
	for rank in mini(15, order.size()):
		var i: int = order[rank]
		print("  frame_idx=%d frame_ms=%.2f script_process_ms=%.2f script_physics_ms=%.2f render_cpu_ms=%.2f render_gpu_ms=%.2f char_viewport_cpu_ms=%.2f char_viewport_gpu_ms=%.2f draw_calls=%.0f phys_active=%.0f phys_pairs=%.0f phys_islands=%.0f physics_steps=%.0f sync_tick=%s" % [
			i, frame_ms[i], cpu_ms[i], physics_ms[i], render_cpu_ms[i], render_gpu_ms[i],
			char_render_cpu_ms[i], char_render_gpu_ms[i], draw_calls[i], phys_active[i], phys_pairs[i], phys_islands[i], physics_steps[i], sync_tick[i],
		])

	world.queue_free()
	await process_frame
	quit()
