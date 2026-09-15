extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	seed(510)
	create_timer(180,true,false,true).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	await process_frame
	while current_scene == null: await process_frame
	while not current_scene.gameplay_ready: await process_frame
	root.size = Vector2i(1280,720)
	var player: Node2D = get_first_node_in_group("player")
	current_scene.get_node("CobraCampaign").set_process(false)
	var system: Node2D = current_scene.get_node("UrbanTransit")
	while not system.ready_for_service: await process_frame
	system.clock.is_dynamic_time = false
	system.clock.time_of_day = 12.0/24.0
	print("BUS_PERF GPU=",RenderingServer.get_video_adapter_name()," renderer=",RenderingServer.get_current_rendering_method()," fps_cap=",Engine.max_fps," vsync=",DisplayServer.window_get_vsync_mode())
	for point in [Vector2(1650,2200),Vector2(1790,1020)]:
		player.global_position = point
		await create_timer(5).timeout
		var samples: Array[float] = []
		var start := Time.get_ticks_usec()
		var last := start
		while Time.get_ticks_usec()-start < 30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-last)/1000.0)
			last = now
		var seconds := (last-start)/1000000.0
		samples.sort()
		print("BUS_PERF point=",point," frames=",samples.size()," seconds=",seconds," fps=",samples.size()/seconds," p50=",samples[int(samples.size()*.5)]," p95=",samples[int(samples.size()*.95)]," p99=",samples[int(samples.size()*.99)]," max=",samples.back()," over33=",samples.filter(func(x): return x>33.3).size()," over66=",samples.filter(func(x): return x>66.7).size())
	if OS.get_cmdline_user_args().has("--capture"):
		var operations: Node2D = get_first_node_in_group("harbor_terminal_operations")
		var service: Node2D = operations.fleet[0]
		player.global_position = service.coach.global_position + Vector2(0,42)
		player.is_control_disabled = false
		service.coach.enter_vehicle(player)
		await create_timer(3.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/stolen-terminal-coach.png")
		service.coach.force_exit_vehicle()
		await create_timer(.5).timeout
		var bus: CharacterBody2D = system.buses[0]
		player.global_position = bus.door_position()
		player.is_control_disabled = false
		bus.enter_vehicle(player)
		await create_timer(3.0).timeout
		bus.camera.zoom = Vector2.ONE*.85
		await create_timer(.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/stolen-biarticulated.png")
	quit()
