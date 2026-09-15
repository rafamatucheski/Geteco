extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requer renderização real")
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world

	for i in 5:
		await process_frame

	var impact_script = preload("res://audio/combat/CombatImpactAudio.gd")

	var t0 := Time.get_ticks_usec()
	impact_script.prepare(world)
	var t_prepare_us := Time.get_ticks_usec() - t0

	# 1º Impacto após prepare
	t0 = Time.get_ticks_usec()
	impact_script.play_hit(world, Vector2(100, 100), &"metal", 20.0)
	var t_hit1_us := Time.get_ticks_usec() - t0

	# 2º Impacto
	t0 = Time.get_ticks_usec()
	impact_script.play_hit(world, Vector2(150, 100), &"concrete", 20.0)
	var t_hit2_us := Time.get_ticks_usec() - t0

	# 3º Impacto
	t0 = Time.get_ticks_usec()
	impact_script.play_hit(world, Vector2(200, 100), &"flesh", 20.0)
	var t_hit3_us := Time.get_ticks_usec() - t0

	print("BENCHMARK_AUDIO_RESULT: prepare_ms=%.3f hit1_ms=%.3f hit2_ms=%.3f hit3_ms=%.3f" % [
		t_prepare_us / 1000.0,
		t_hit1_us / 1000.0,
		t_hit2_us / 1000.0,
		t_hit3_us / 1000.0
	])

	world.queue_free()
	await process_frame
	quit(0)
