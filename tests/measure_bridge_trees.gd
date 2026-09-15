extends SceneTree
## Rendered integrated preview comparison; uses no save writes.
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(150).timeout.connect(func(): quit(2))
	var label := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "after"
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.get_node("SaveManager").clear_pending_save()
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		state.set_campaign_flag(StringName(flag), true)
	var world = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.world_build_ready: await process_frame
	world.get_node("Player").global_position = Vector2(5880,-3850)
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = 0.45
	world.weather.set_weather(0)
	world.weather.set_biome(world.weather.current_biome)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(6030,-3700)
	camera.zoom = Vector2.ONE * 0.65
	camera.make_current()
	await create_timer(8).timeout
	var values: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		values.append((now-previous)/1000.0)
		previous = now
	var elapsed := (previous-start)/1000000.0
	values.sort()
	var slow := 0
	var stalls := 0
	for value in values:
		if value > 33.3: slow += 1
		if value > 66.7: stalls += 1
	print("BRIDGE_TREES %s gpu=%s frames=%d seconds=%.2f fps=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f over33=%d over66=%d" % [label,RenderingServer.get_video_adapter_name(),values.size(),elapsed,values.size()/elapsed,values[int(values.size()*.5)],values[int(values.size()*.95)],values[int(values.size()*.99)],values[-1],slow,stalls])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/bridge-trees-%s.png" % label)
	quit()
