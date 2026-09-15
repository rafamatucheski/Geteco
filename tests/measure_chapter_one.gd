extends SceneTree
## Bounded production sample: identical night plaza camera before/after.
var world: Node
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	create_timer(180.0).timeout.connect(func(): quit(2))
	seed(913)
	var out := "D:/geteco/artifacts/chapter-one-0913/"
	DirAccess.make_dir_recursive_absolute(out + "saves")
	var saves := root.get_node("SaveManager")
	saves._save_dir = out + "saves/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null: await process_frame
	world = current_scene
	while not world.gameplay_ready: await process_frame
	var bank_sample := "--bank" in OS.get_cmdline_user_args()
	if bank_sample:
		var manager = world.get_node("Interiors")
		var room = manager.get_node("InteriorSpaces/BankInterior")
		var player = world.get_node("Player")
		player.active_weapon_id = "fists"
		manager._on_exterior_destination_requested(room.entrance, player, room.entrance.destination_id, null, &"", room, room.spawn_point)
		for i in 60: await process_frame
	var bridge = world.get_node("CobraCampaign")
	bridge.ledger.data.day_elapsed = (21.0 / 24.0 - 0.35) * 600.0
	world.weather.set_weather(0)
	if not bank_sample: world.get_node("Player").global_position = Vector2(3150, 590)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = Vector2(3150, 590)
	camera.zoom = Vector2.ONE
	if not bank_sample: camera.make_current()
	for i in 180: await process_frame
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-previous)/1000.0)
		previous = now
	var sorted := samples.duplicate()
	sorted.sort()
	var label := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	if bank_sample: label += "-bank"
	var report := {"label":label,"seconds":float(previous-start)/1000000.0,"frames":samples.size(),"fps":samples.size()*1000000.0/(previous-start),"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted[-1],"over33":sorted.filter(func(v): return v>33.3).size(),"over66":sorted.filter(func(v): return v>66.7).size(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode()}
	print("CHAPTER_ONE_PERF ", JSON.stringify(report))
	report.samples_ms = samples
	FileAccess.open(out+label+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+label+".png")
	quit()
