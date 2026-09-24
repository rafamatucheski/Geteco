extends "res://tests/capture_lighting_glitches.gd"
## Pedestres na cidade real (Main, clima, câmera do jogo), de dia e à noite, em
## zoom de jogo e aproximado. Só evidência visual; custo em
## tests/measure_pedestrian_cost.gd.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	output_dir = "res://evidence/pedestrian-look-0922/ingame"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 1800:
		await process_frame
		if world.session != null and world.session.weather != null: break
	if world.session == null or world.session.weather == null: quit(1); return
	world.player.controlled_automatically = true
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	world.set_population(48)
	await move_to(Vector3(137.5, .08, 105), 0, 22, true)
	for entry in [["dia", .55, 22.0], ["dia_perto", .55, 10.0], ["noite", .84, 18.0]]:
		world.session.weather.time_of_day = entry[1]
		world.session.weather.weather_state = 0
		world.session.weather.weather_timer = 10000
		world.session.weather._update()
		world.camera.target_size = entry[2]
		# Tempo para a população preencher a rua e a câmera assentar.
		for i in 40: await create_timer(.1).timeout
		for frame in 3:
			await create_timer(.35).timeout
			await capture(output_dir + "/%s-%02d.png" % [entry[0], frame])
	print("PEDESTRIAN_INGAME ok pessoas=", world.population)
	world.queue_free()
	await process_frame
	quit()
