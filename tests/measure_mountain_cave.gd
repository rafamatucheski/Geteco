extends SceneTree

var output := "D:/geteco/artifacts/cave-review-0912/before"
var duration := 30.0
var mountain: Node2D
var player: CharacterBody2D
var camera: Camera2D

func _initialize() -> void: run.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="): output = arg.trim_prefix("out=")
		if arg.begins_with("seconds="): duration = float(arg.trim_prefix("seconds="))
	DirAccess.make_dir_recursive_absolute(output)
	root.get_node("SaveManager")._save_dir = output.path_join("saves/")
	DirAccess.make_dir_recursive_absolute(output.path_join("saves"))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	seed(912428)
	create_timer(180).timeout.connect(func(): quit(2))
	change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
	while current_scene == null or not current_scene.region_ready: await process_frame
	mountain = current_scene
	player = mountain.player_instance
	player.set_physics_process(false)
	player.mountain_thermal_coat = true
	player.health = player.max_health
	# Keep weather and NPCs running, with a deterministic clock and population.
	mountain.storm_manager.dynamic_weather = false
	mountain.storm_manager.weather_clock = 0.0
	mountain.storm_manager.advance_weather(0)
	for node in mountain.find_children("*", "Camera2D", true, false): node.enabled = false
	camera = Camera2D.new()
	camera.set_meta("mountain_fixed_framing", true)
	mountain.add_child(camera)
	camera.make_current()
	var exterior := mountain.find_child("WaterfallCaveExterior", true, false)
	player.global_position = exterior.entrance.global_position + Vector2(0,35)
	camera.global_position = mountain.to_global(Vector2(6345,-415))
	camera.zoom = Vector2.ONE * 1.55
	await measure("waterfall")
	exterior.entrance.request_interaction(player)
	await create_timer(0.5).timeout
	var room: Node2D = mountain.interior_manager.mystery_cave_interior
	camera.make_current()
	camera.global_position = room.global_position + Vector2(0,-15)
	camera.zoom = Vector2.ONE * 1.02
	await measure("interior")
	var reward := room.get_node_or_null("SecretRPG")
	if reward != null:
		player.global_position = reward.global_position+Vector2(0,32)
		camera.global_position = room.global_position+Vector2(75,-10)
		camera.zoom = Vector2.ONE*1.45
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("secret-weapon.png"))
	quit()

func measure(label: String) -> void:
	var cold: Array[float] = []
	var samples: Array[float] = []
	var last := Time.get_ticks_usec()
	var started := last
	while Time.get_ticks_usec() - started < 3000000:
		await process_frame
		var now := Time.get_ticks_usec()
		cold.append(float(now-last)/1000.0)
		last = now
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	last = Time.get_ticks_usec()
	started = last
	while Time.get_ticks_usec() - started < int(duration*1000000):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-last)/1000.0)
		last = now
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var stalls := 0
	for ms in samples:
		total += ms
		if ms > 33.3: slow += 1
		if ms > 66.7: stalls += 1
	var result := {"scenario":label,"frames":samples.size(),"seconds":total/1000.0,"fps":samples.size()*1000.0/total,"p50":sorted[int(sorted.size()*0.50)],"p95":sorted[int(sorted.size()*0.95)],"p99":sorted[int(sorted.size()*0.99)],"max":sorted[-1],"over_33_3":slow,"over_66_7":stalls,"warmup_max":cold.max(),"samples_ms":samples,"warmup_ms":cold,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"resolution":[root.size.x,root.size.y]}
	FileAccess.open(output.path_join(label + ".json"),FileAccess.WRITE).store_string(JSON.stringify(result))
	result.erase("samples_ms")
	result.erase("warmup_ms")
	print(JSON.stringify(result))
