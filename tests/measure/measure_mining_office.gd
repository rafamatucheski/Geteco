extends "res://tests/measure/measure.gd"
## Escritório da Serra Bruta no Main real com save isolado (29/10).
## `--office-before`: linha de base (`mining_office_baseline`), só a fachada antiga e a foto.
## Depois: empurra a porta pintada andando, foto da sala, pega a recompensa, sai andando,
## volta e confere que a recompensa não duplica e que o save restaura dentro.
## Uso (com tela): tools/run_godot_locked.sh --path . --script res://tests/measure/measure_mining_office.gd -- [--office-before]
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const OFFICE := preload("res://world/mining/MiningOffice.gd")
var folder := ""
var issues: Array[String] = []

func verify(ok: bool, message: String) -> void:
	print("MINING_OFFICE ", "PASS " if ok else "FAIL ", message)
	if not ok: issues.append(message)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(300).timeout.connect(func(): push_error("MINING_OFFICE timeout"); quit(3))
	var baseline := "--office-before" in OS.get_cmdline_user_args()
	Engine.set_meta("mining_office_baseline", baseline)
	folder = FIXTURE.output_dir("mining-office-" + ("before" if baseline else "after"))
	var door := OFFICE.door_position()
	var outward := OFFICE.basis() * Vector3.BACK
	var point := door + outward * 4.0 + Vector3(0, .08, 0)
	var snapshot := FIXTURE.full_snapshot(point, true)
	snapshot.campaign.aftermath = {"call_complete":true}
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region":"desert","position":[point.x,point.y,point.z]}
	snapshot.world.time = .45
	var save_path := FIXTURE.write_fixture(folder, "save.json", snapshot)
	verify(not save_path.is_empty(), "save isolado aceito")
	if save_path.is_empty(): quit(2); return
	var settings = root.get_node("V2Settings")
	settings.window_mode = 0; settings.resolution = 0; settings.vsync = true; settings.fps_limit = 1; settings.apply_settings()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	world.set_meta("menu_save_path", save_path)
	root.add_child(world); current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	while world.session.is_transition_blocked(): await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	for i in 60: await physics_frame
	world.camera.target_size = 16
	await photo("01-exterior")
	var results := {"door":[door.x, door.y, door.z]}
	if not baseline:
		var session = world.session
		var definition: Dictionary = preload("res://world/places/PlaceCatalog.gd").get_definition(OFFICE.ID)
		verify(not definition.is_empty(), "lugar no catálogo")
		# Para encostado na porta fechada: só chegar perto não abre.
		await walk(door + outward * .9, 4.0)
		for i in 40: await physics_frame
		var facade := _facade()
		verify(facade != null, "fachada da porta no grupo v2_walkin_facade")
		if facade != null: verify(facade.open_amount < .05, "presença parada não abre (aberta=" + str(facade.open_amount) + ")")
		var opened := 0.0
		var deadline := Time.get_ticks_msec() + 7000
		while Time.get_ticks_msec() < deadline and session.state.place_id != OFFICE.ID:
			world.player.automatic_direction = -outward
			if facade != null and is_instance_valid(facade): opened = maxf(opened, facade.open_amount)
			if facade != null and is_instance_valid(facade) and opened > .3 and results.get("push_photo") == null:
				results.push_photo = true
				await photo("02-push")
			await physics_frame
		world.player.automatic_direction = Vector3.ZERO
		while session.is_transition_blocked(): await physics_frame
		await wait_access()
		verify(opened > .5, "a folha pintada abre ao empurrar (máx=" + str(opened) + ")")
		verify(session.state.place_id == OFFICE.ID, "entra andando pela porta pintada")
		if session.state.place_id == OFFICE.ID:
			var room = session.room
			verify(session.position_clear(world.player.global_position + Vector3.UP * .04), "spawn com o corpo inteiro livre")
			verify(world.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "câmera ortográfica")
			for i in 20: await physics_frame
			await photo("03-interior")
			var cash: int = session.state.economy.balance
			var reward: Vector3 = room.to_global(room.definition.rewards[0].local_position)
			verify(await walk(reward, 6.0), "anda até a recompensa")
			for i in 30: await physics_frame
			verify(session.state.economy.balance == cash + 450, "recompensa de R$ 450 recebida (saldo " + str(cash) + " -> " + str(session.state.economy.balance) + ")")
			await photo("04-reward")
			verify(await walk(room.to_global(room.definition.spawn), 5.0), "volta ao corredor da porta")
			await walk(room.exit_position + Vector3(0, 0, 1.0), 6.0)
			while session.is_transition_blocked(): await physics_frame
			await wait_access()
			verify(session.state.place_id.is_empty(), "sai andando")
			if not session.state.place_id.is_empty(): await session.leave_place()
			verify(world.player.global_position.distance_to(definition.return_position) < 3.0, "volta na frente da porta usada (" + str(world.player.global_position.distance_to(definition.return_position)) + " m)")
			await photo("05-after-exit")
			var balance_out: int = session.state.economy.balance
			deadline = Time.get_ticks_msec() + 7000
			while Time.get_ticks_msec() < deadline and session.state.place_id != OFFICE.ID:
				world.player.automatic_direction = -outward
				await physics_frame
			world.player.automatic_direction = Vector3.ZERO
			while session.is_transition_blocked(): await physics_frame
			await wait_access()
			verify(session.state.place_id == OFFICE.ID, "segunda entrada andando")
			if session.state.place_id == OFFICE.ID:
				room = session.room
				await walk(room.to_global(room.definition.rewards[0].local_position), 6.0)
				for i in 30: await physics_frame
				verify(session.state.economy.balance == balance_out, "recompensa não paga de novo na reentrada")
				verify(session.save_game(), "save dentro do escritório")
				var saved := preload("res://runtime/SaveStore.gd").read_valid(save_path)
				var restored = preload("res://runtime/GameState.gd").new()
				verify(not saved.is_empty() and restored.restore_snapshot(saved) and restored.place_id == OFFICE.ID, "save restaura dentro do escritório")
	results.environment = {"engine":Engine.get_version_info().string, "gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(), "resolution":str(root.size)}
	results.issues = issues
	FileAccess.open(folder.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(results, "\t"))
	print("MINING_OFFICE_RESULTS ", folder, " issues=", issues)
	world.queue_free(); await process_frame
	quit(0 if issues.is_empty() else 1)

func _facade() -> Node3D:
	for candidate in get_nodes_in_group("v2_walkin_facade"):
		if str(candidate.get_meta("place_id", "")) == OFFICE.ID: return candidate
	return null

func walk(point: Vector3, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	var origin: String = world.session.state.place_id
	while Time.get_ticks_msec() < deadline and world.session.state.place_id == origin:
		var offset: Vector3 = point - world.player.global_position
		offset.y = 0
		if offset.length() < .15:
			world.player.automatic_direction = Vector3.ZERO
			return true
		world.player.automatic_direction = offset.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	return false

func photo(id: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id + ".png"))

func wait_access() -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline and (world.player.input_locked or world.session.weapon_shop_entrance._entering or world.session.weapon_shop_entrance._leaving): await physics_frame
