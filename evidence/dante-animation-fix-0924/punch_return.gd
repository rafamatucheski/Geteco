extends "res://evidence/dante-animation-fix-0924/main_capture.gd"

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	create_timer(45).timeout.connect(func(): quit(3))
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for tick in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(4); return
	player = world.player
	player.controlled_automatically = true
	world.gameplay.health = 1000000
	world.gameplay.state.equip_weapon("fists")
	world.camera.target_size = 4.0
	world.session.weather.time_of_day = 0.36
	await frames(45)
	# Cliques separados, sem manter a mira: inclui o retorno que faltava
	# na captura anterior e o relaxamento após o último soco.
	var direction: Vector3 = world.camera.global_basis.z
	direction.y = 0.0
	direction = direction.normalized()
	label = "punch_return"
	physics_frame.connect(observe)
	for tick in 210:
		if tick in [0, 30, 60, 90, 120]:
			world.gameplay.fire_at(player.global_position + direction * 15)
		await physics_frame
		if tick % 3 == 0: await capture("punch_return_%03d" % tick)
	print("PUNCH_RETURN ", JSON.stringify(measurements))
	quit()
