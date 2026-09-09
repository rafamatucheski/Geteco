extends SceneTree

## Per-node _process/_physics_process cost ranking for the PRODUCTION HarborGame
## scene (not the bare HarborPreview review scene), during the exact
## post-arrival driving scenario measure_harbor_game_driving.gd benchmarks.
## Diagnostic only — manually re-invokes each node's callback outside the
## normal engine loop to time it in isolation; does not change any behavior.

var idle_nodes: Array[Node] = []
var physics_nodes: Array[Node] = []
var totals := {}

func _init() -> void: call_deferred("run")

func collect(node: Node) -> void:
	# is_physics_processing()/is_processing() reflect set_physics_process(true),
	# NOT process_mode — a node parked at PROCESS_MODE_DISABLED (e.g. the
	# EmergencyPool's dormant off-map vehicles) still reports "processing" here
	# even though the real engine never calls its callback. Skip anything the
	# engine itself would skip, via can_process(), or every such node gets
	# manually forced to run its full (often worst-case/off-map) logic below —
	# a profiler artifact, not a real per-frame cost.
	if node.process_mode == Node.PROCESS_MODE_DISABLED or not node.can_process():
		for child in node.get_children(): collect(child)
		return
	if node.get_script() != null and node.is_physics_processing() and node.has_method("_physics_process"):
		physics_nodes.append(node)
		node.set_physics_process(false)
	if node.get_script() != null and node.is_processing() and node.has_method("_process"):
		idle_nodes.append(node)
		node.set_process(false)
	for child in node.get_children(): collect(child)

func run() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 90: await process_frame
	if not world.gameplay_ready or paused:
		push_error("Profiling checkpoint did not become playable")
		quit(1)
		return
	var player: Node2D = world.get_node("Player")
	player.global_position = Vector2(2200, 1050)
	var car: CharacterBody2D = world.get_node("PlayerCar")
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	world.call("_drive")
	for i in 30: await process_frame
	Input.action_press("ui_up")
	collect(root)
	var sample_count := 600
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("samples="):
			sample_count = maxi(1, int(argument.trim_prefix("samples=")))
	for frame in sample_count:
		await process_frame
		for node in physics_nodes:
			if not is_instance_valid(node): continue
			var before := Time.get_ticks_usec()
			node.call("_physics_process", 1.0 / 60.0)
			var elapsed := Time.get_ticks_usec() - before
			var key := String(node.get_path()) + " physics"
			totals[key] = int(totals.get(key, 0)) + elapsed
			if elapsed > 20000: print("SLOW_CALLBACK frame=%d us=%d node=%s" % [frame, elapsed, key])
		for node in idle_nodes:
			if not is_instance_valid(node): continue
			var before := Time.get_ticks_usec()
			node.call("_process", 1.0 / 60.0)
			var elapsed := Time.get_ticks_usec() - before
			var key := String(node.get_path())
			totals[key] = int(totals.get(key, 0)) + elapsed
			if elapsed > 20000: print("SLOW_CALLBACK frame=%d us=%d node=%s" % [frame, elapsed, key])
	Input.action_release("ui_up")
	var names := totals.keys()
	names.sort_custom(func(a, b): return totals[a] > totals[b])
	var grand_total := 0
	for name_value in totals: grand_total += totals[name_value]
	print("CALLBACK_TOTAL_MS %.2f over_%d_frames" % [grand_total / 1000.0, sample_count])
	for name_value in names.slice(0, 25):
		print("CALLBACK_COST %s avg_us=%.1f total_ms=%.2f" % [name_value, totals[name_value] / float(sample_count), totals[name_value] / 1000.0])
	world.queue_free()
	await process_frame
	quit()
