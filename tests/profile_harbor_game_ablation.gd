extends SceneTree

## Diagnostic-only ablation: measures the render weight of character
## SubViewports and the weight of population (traffic + pedestrian) physics
## by temporarily disabling each in THIS throwaway process, on the same real
## drive as measure_harbor_game_driving.gd, then re-measuring. Nothing is
## shipped disabled — this process quits after printing results. Uses only
## engine monitors and drives via the same real Input action; never manually
## invokes _process/_physics_process.

const GAME := preload("res://world/harbor/HarborGame.tscn")

var character_viewports: Array[SubViewport] = []

func _initialize() -> void: call_deferred("_run")

func _collect_viewports(node: Node) -> void:
	if node is SubViewport and (node as SubViewport).own_world_3d:
		character_viewports.append(node)
	for child in node.get_children(): _collect_viewports(child)

func _measure(label: String, car: CharacterBody2D, frame_count: int) -> void:
	var frame_ms: Array[float] = []
	Input.action_press("ui_up")
	for i in frame_count:
		var start := Time.get_ticks_usec()
		await process_frame
		frame_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
	Input.action_release("ui_up")
	var sorted_ms := frame_ms.duplicate()
	sorted_ms.sort()
	var total := 0.0
	for value in frame_ms: total += value
	print("ABLATION %s avg_ms=%.2f avg_fps=%.1f p50_ms=%.2f p90_ms=%.2f worst_ms=%.2f render_cpu_ms=%.2f render_gpu_ms=%.2f draw_calls=%.0f" % [
		label, total / frame_count, (frame_count * 1000.0) / total,
		sorted_ms[int(frame_count * 0.5)], sorted_ms[int(frame_count * 0.9)], sorted_ms[-1],
		RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
		RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	])

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.grab_focus()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
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
		push_error("Ablation checkpoint did not become playable")
		quit(1)
		return
	var player: Node2D = world.get_node("Player")
	player.global_position = Vector2(2200, 1050)
	var car: CharacterBody2D = world.get_node("PlayerCar")
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	world.call("_drive")
	for i in 30: await process_frame
	_collect_viewports(world)
	print("ABLATION_CONTEXT character_viewports=%d" % character_viewports.size())

	var frame_count := 300

	await _measure("baseline", car, frame_count)

	var saved_modes: Dictionary = {}
	for view in character_viewports:
		saved_modes[view] = view.render_target_update_mode
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	await _measure("no_character_viewports", car, frame_count)
	for view in character_viewports:
		if is_instance_valid(view): view.render_target_update_mode = saved_modes[view]

	var frozen_vehicles: Array[Node] = []
	for node in get_nodes_in_group("vehicle"):
		if node != car and node.is_physics_processing():
			frozen_vehicles.append(node)
			node.set_physics_process(false)
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	await _measure("no_traffic_vehicle_physics", car, frame_count)
	for node in frozen_vehicles:
		if is_instance_valid(node): node.set_physics_process(true)

	var frozen_pedestrians: Array[Node] = []
	for node in get_nodes_in_group("pedestrian"):
		if node.is_physics_processing():
			frozen_pedestrians.append(node)
			node.set_physics_process(false)
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	await _measure("no_pedestrian_physics", car, frame_count)
	for node in frozen_pedestrians:
		if is_instance_valid(node): node.set_physics_process(true)

	var frozen: Array[Node] = frozen_vehicles + frozen_pedestrians
	for node in frozen:
		if is_instance_valid(node): node.set_physics_process(false)
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	await _measure("no_population_physics", car, frame_count)
	for node in frozen:
		if is_instance_valid(node): node.set_physics_process(true)

	world.queue_free()
	await process_frame
	quit()
