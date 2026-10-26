extends SceneTree
## Rajada de tiros num carro parado no jogo de verdade (vídeo de 26/10/2026: o Monaliza perdeu a lataria por
## alguns quadros, afundou e sumiu). Carrega Main, põe o carro do lado do jogador e atira com o dano real do
## Gameplay; grava altura, vida, visibilidade e remoção a cada quadro e fotos do meio da sequência.
## Uso (com tela): "$GODOT" --path . --script res://tests/capture/capture_vehicle_shot_sequence.gd -- --no-save --no-traffic [arquétipo]
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const START := Vector3(80, 0, 80)

func _initialize() -> void:
	create_timer(400).timeout.connect(func(): push_error("SHOT_SEQUENCE timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var id := "monaliza"
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"): id = arg
	root.size = Vector2i(1280, 720)
	var folder := FIXTURE.output_dir("shot-sequence-" + id)
	var data := FIXTURE.full_snapshot(START, true)
	var path := FIXTURE.write_fixture(folder, "checkpoint.json", data)
	var world: Node3D = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.get("session") == null or not world.session.ready_for_play: push_error("sessão não carregou"); quit(1); return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.health = 100000.0
	# Como os testes de vidro: o carro entra direto no mundo, ao lado do jogador, com a física ligada.
	var car: Node3D = preload("res://scripts/Vehicle.gd").new()
	car.archetype = id
	car.vehicle_id = "shot_sequence"
	world.add_child(car)
	car.global_position = world.player.global_position + Vector3(4, .6, 0)
	world.production.vehicles.append(car)
	for tick in 90: await physics_frame
	print("SHOT_SEQUENCE carro ", car.get_path(), " y=%.2f vida=%.0f" % [car.global_position.y, car.health])
	var log := []
	for shot in 30:
		if not is_instance_valid(car): break
		var from: Vector3 = world.player.global_position + Vector3(0, 1.2, randf_range(-1.0, 1.0))
		world.gameplay._damage_bullet(car, 25.0, world.player, from, car.global_position + Vector3(0, .9, randf_range(-1.2, 1.2)))
		for tick in 3:
			await physics_frame
			if not is_instance_valid(car): break
			var shell := 0
			for mesh in car.visual.find_children("*", "MeshInstance3D", true, false):
				if mesh.is_visible_in_tree() and mesh.transparency < .5: shell += 1
			log.append("tiro %d y=%.2f vida=%.0f visível=%s malhas=%d removendo=%s meta=%s" % [shot, car.global_position.y, car.health, car.is_visible_in_tree(), shell, car.is_queued_for_deletion(), car.get_meta_list()])
		if shot in [5, 12, 20]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/tiro-%02d.png" % [folder, shot]))
	for line in log: print("SHOT_SEQUENCE ", line)
	print("SHOT_SEQUENCE_DONE ", folder, " carro existe=", is_instance_valid(car))
	quit(0)
