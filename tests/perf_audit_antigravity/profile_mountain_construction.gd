extends SceneTree
## GETECO-PERF-03B: Sonda de Perfilamento da Construção da Mountain Pass
## Mede com precisão de microssegundos cada etapa da montagem da Mountain Pass.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requer renderização real")
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)

	for i in 5:
		await process_frame

	print("=== PERFILAMENTO DA CONSTRUÇÃO DA MOUNTAIN PASS ===")

	var t0 := Time.get_ticks_usec()
	var mp_scene = load("res://world/mountain_pass/MountainPass.tscn")
	var t_load_scene_us := Time.get_ticks_usec() - t0
	print("[1] Carga do recurso MountainPass.tscn: %.3f ms" % (t_load_scene_us / 1000.0))

	t0 = Time.get_ticks_usec()
	var mountain: Node2D = mp_scene.instantiate()
	var t_instantiate_us := Time.get_ticks_usec() - t0
	print("[2] instantiate() de MountainPass: %.3f ms" % (t_instantiate_us / 1000.0))

	mountain.streamed_region = true
	mountain.region_selected = false
	mountain.connect_to_harbor = false
	mountain.spawn_player_on_ready = false
	mountain.spawn_suv_on_ready = false

	var dummy_world := Node2D.new()
	dummy_world.name = "DummyHarbor"
	root.add_child(dummy_world)
	current_scene = dummy_world

	var player_script = load("res://characters/Player.gd")
	var dummy_player = player_script.new()
	dummy_player.name = "Player"
	dummy_player.add_to_group("player")
	dummy_world.add_child(dummy_player)
	mountain.player_instance = dummy_player

	t0 = Time.get_ticks_usec()
	dummy_world.add_child(mountain)
	var t_add_child_us := Time.get_ticks_usec() - t0
	print("[3] add_child(mountain) (até o primeiro yield/await): %.3f ms" % (t_add_child_us / 1000.0))

	var wait_start := Time.get_ticks_usec()
	var frame_count := 0
	var max_frame_time_us := 0
	var prev_tick := Time.get_ticks_usec()

	while not mountain.region_ready:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := now - prev_tick
		prev_tick = now
		frame_count += 1
		if dt > max_frame_time_us:
			max_frame_time_us = dt
		if dt > 50000:
			print("  [FREEZE DETECTED] frame %d: %.3f ms" % [frame_count, dt / 1000.0])

	var t_ready_total_us := Time.get_ticks_usec() - wait_start
	print("[4] Tempo até mountain.region_ready: %.3f ms em %d frames (pior frame: %.3f ms)" % [
		t_ready_total_us / 1000.0,
		frame_count,
		max_frame_time_us / 1000.0
	])

	# Mede primeiro frame com a montanha visível e process_mode INHERIT
	t0 = Time.get_ticks_usec()
	mountain.visible = true
	mountain.process_mode = Node.PROCESS_MODE_INHERIT
	mountain.region_selected = true
	await process_frame
	var t_first_present_us := Time.get_ticks_usec() - t0
	print("[5] Primeiro frame após mountain.visible = true e INHERIT: %.3f ms" % (t_first_present_us / 1000.0))

	# Mede frames subsequentes na montanha
	var active_frames := []
	for i in 30:
		t0 = Time.get_ticks_usec()
		await process_frame
		active_frames.append((Time.get_ticks_usec() - t0) / 1000.0)

	var avg_active := 0.0
	for f in active_frames: avg_active += f
	avg_active /= active_frames.size()
	print("[6] 30 frames ativos na montanha: média=%.3f ms, pior=%.3f ms" % [
		avg_active, active_frames.max()
	])

	# Teste de transição de retorno (ocultação / desativação)
	t0 = Time.get_ticks_usec()
	mountain.visible = false
	mountain.process_mode = Node.PROCESS_MODE_DISABLED
	mountain.region_selected = false
	await process_frame
	var t_hide_us := Time.get_ticks_usec() - t0
	print("[7] Frame de retorno (mountain.visible=false, DISABLED): %.3f ms" % (t_hide_us / 1000.0))

	# Teste de reentrada (reativação)
	t0 = Time.get_ticks_usec()
	mountain.visible = true
	mountain.process_mode = Node.PROCESS_MODE_INHERIT
	mountain.region_selected = true
	await process_frame
	var t_reentry_us := Time.get_ticks_usec() - t0
	print("[8] Frame de REENTRADA (mountain.visible=true, INHERIT): %.3f ms" % (t_reentry_us / 1000.0))

	# Limpeza
	dummy_world.queue_free()
	await process_frame
	print("=== FIM DO PERFILAMENTO ===")
	quit(0)
