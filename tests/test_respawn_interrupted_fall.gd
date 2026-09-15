extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "respawn_interrupted_fall"
	arm_watchdog(25.0)
	isolate_saves(_tag)
	root.get_node("SaveManager").clear_pending_save()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	var hospital := Marker2D.new()
	hospital.position = Vector2(300, 300)
	hospital.add_to_group("hospital_spawn")
	world.add_child(hospital)
	for pause_delay in [0.0, 0.2, -1.0]:
		player._respawn_grace_active = false
		player.take_damage(999)
		check(player.is_dead, "Lethal damage starts the real death sequence")
		if pause_delay >= 0.0:
			if pause_delay > 0.0: await create_timer(pause_delay).timeout
			paused = true
		await create_timer(2.4).timeout
		check(not player.is_dead and player.health == player.max_health, "Real death timer restores health even across pause")
		check(player.model_root.rotation.is_zero_approx(), "Respawn starts upright")
		paused = false
		await create_timer(0.7).timeout
		check(absf(player.model_root.rotation.x) < 0.01 and absf(player.model_root.rotation.z) < 0.01, "Unpausing cannot replay the old fall (delay %.1f)" % pause_delay)
		check(player.visible and player.is_physics_processing(), "Living actor remains visible and controllable")
	await finish(_tag, world)
