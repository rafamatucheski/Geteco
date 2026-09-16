extends SceneTree
## Medição detalhada das sub-etapas de MountainPass._ready()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)

	for i in 5:
		await process_frame

	var dummy_world := Node2D.new()
	dummy_world.name = "DummyHarbor"
	root.add_child(dummy_world)
	current_scene = dummy_world

	var player_script = load("res://characters/Player.gd")
	var real_player = player_script.new()
	real_player.name = "Player"
	real_player.add_to_group("player")
	dummy_world.add_child(real_player)

	var mp_scene = load("res://world/mountain_pass/MountainPass.tscn")
	var mountain: Node2D = mp_scene.instantiate()
	mountain.streamed_region = true
	mountain.region_selected = false
	mountain.connect_to_harbor = false
	mountain.spawn_player_on_ready = false
	mountain.spawn_suv_on_ready = false
	mountain.player_instance = real_player

	print("\n=== DECOMPOSIÇÃO DAS ETAPAS DE CONSTRUÇÃO DA MONTANHA ===")

	var step_times := {}
	var step_frames := {}

	var hook_node = func(name: String, action: Callable):
		var t0 := Time.get_ticks_usec()
		var f0 := Engine.get_process_frames()
		await action.call()
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		var df := Engine.get_process_frames() - f0
		print("  -> ETAPA '%s': %.3f ms (distribuído em %d frames)" % [name, dt, df])
		step_times[name] = dt
		step_frames[name] = df

	# Mede a inserção do mountain e monitora as fases
	var t_total_start := Time.get_ticks_usec()
	dummy_world.add_child(mountain)

	var last_ready := ""
	while not mountain.region_ready:
		await process_frame

	var t_total := (Time.get_ticks_usec() - t_total_start) / 1000.0
	print("TOTAL ATÉ REGION_READY: %.3f ms" % t_total)

	dummy_world.queue_free()
	await process_frame
	quit(0)
