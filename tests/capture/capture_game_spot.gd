extends SceneTree
## Foto com a câmera normal do jogo num ponto qualquer (26/10/2026): carrega o jogo de verdade (Main) com o
## jogador no ponto, espera o streaming e grava a tela. Serve para conferir relato com vídeo/foto do
## jogador num lugar específico. Inspeção visual; não mede FPS.
## Uso (com tela): "$GODOT" --path . --script res://tests/capture/capture_game_spot.gd -- --no-save
##   --region=mountain --spot=512,-468 [--spot=...] [--label=serra-trilha]
##   [--behind-tallest [--behind=38]]: jogador ao norte do prédio mais alto perto do ponto
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")

func _initialize() -> void:
	create_timer(420).timeout.connect(func(): push_error("GAME_SPOT timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var region := "harbor"
	var label := "ponto"
	var spots: Array[Vector3] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--region="): region = arg.get_slice("=", 1)
		elif arg.begins_with("--label="): label = arg.get_slice("=", 1)
		elif arg.begins_with("--spot="):
			var xz := arg.get_slice("=", 1).split(",")
			spots.append(Vector3(float(xz[0]), 0, float(xz[1])))
	if spots.is_empty(): push_error("--spot=x,z obrigatório"); quit(2); return
	root.size = Vector2i(1600, 900)
	var folder := FIXTURE.output_dir("game-spot-" + label)
	var start: Vector3 = spots[0]
	var data := FIXTURE.full_snapshot(start, true)
	data.region_id = region
	data.world.pedestrian = {"region": region, "position": [start.x, start.y + .3, start.z]}
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
	for index in spots.size():
		var at: Vector3 = spots[index]
		world.player.teleport(at + Vector3(0, .3, 0))
		world.production.region.set_focus(at, true)
		deadline = Time.get_ticks_msec() + 25000
		while Time.get_ticks_msec() < deadline and not world.production.region.is_streaming_idle(): await process_frame
		if "--behind-tallest" in OS.get_cmdline_user_args():
			# Prédio mais alto perto do ponto: o jogador vai para o lado norte dele, com o prédio entre a
			# câmera (ao sul) e o jogador, onde o plano de corte da câmera fatiava o telhado.
			var best := AABB()
			for node in get_nodes_in_group(&"exterior_reveal_building"):
				var box := AABB()
				for mesh in (node as Node).find_children("*", "MeshInstance3D", true, false):
					var part: AABB = mesh.global_transform * mesh.get_aabb()
					box = part if box.size == Vector3.ZERO else box.merge(part)
				if box.size == Vector3.ZERO or Vector2(box.get_center().x - at.x, box.get_center().z - at.z).length() > 150.0: continue
				if box.size.y < 60.0 and box.end.y > best.end.y: best = box
			if best.size != Vector3.ZERO:
				var behind := 5.0
				for arg in OS.get_cmdline_user_args():
					if arg.begins_with("--behind="): behind = float(arg.get_slice("=", 1))
				at = Vector3(best.get_center().x, 0, best.position.z - behind)
				world.player.teleport(at + Vector3(0, .3, 0))
				world.production.region.set_focus(at, true)
				print("GAME_SPOT prédio ", best)
				for i in 30: await process_frame
				# Diagnóstico: o que um raio de trás da câmera até o telhado encontra.
				var top := best.get_center() + Vector3(0, best.size.y * .5 - .2, 0)
				var camera_position: Vector3 = world.camera.global_position
				var back: Vector3 = (camera_position - at).normalized()
				var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(top + back * 60.0, top - back * 2.0, 0xFFFFFFFF))
				if hit.is_empty(): print("GAME_SPOT raio no telhado: nada")
				else:
					var groups := []
					var node: Node = hit.collider
					for level in 8:
						if node == null: break
						groups.append("%s%s" % [node.name, node.get_groups()])
						node = node.get_parent()
					print("GAME_SPOT raio no telhado: camada ", hit.collider.collision_layer, " ", groups)
		world.camera.initialized = false
		for i in 60: await process_frame
		await RenderingServer.frame_post_draw
		var file := "%s/%s-%d.png" % [folder, label, index]
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(file))
		print("GAME_SPOT ", file, " jogador ", world.player.global_position, " câmera ", world.camera.global_position.distance_to(world.player.global_position))
	quit(0)
