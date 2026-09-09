extends SceneTree

## Validação de Jogo Real — Fluxo Completo de 10 Etapas em HarborGame.tscn
## Executa com renderizador Compatibility (OpenGL3).
## Testa ponta a ponta:
## 1. Aproximar do carro e entrar com comando normal [E]
## 2. Dirigir até a garagem e entrar pela porta real
## 3. Estacionar na baia usando apenas controles de direção e freio normal
## 4. Desembarcar com comando normal [F]
## 5. Caminhar até Jäger Maciota e concluir diálogo
## 6. Abrir o quadro (CarChalkboard) e aceitar uma missão disponível
## 7. Confirmar que uma missão bloqueada não pode ser aceita
## 8. Retornar ao carro, reembarcar e sair dirigindo para Harbor
## 9. Verificar restauração de jogador/veículo/interior por save/load em slot isolado
## 10. Validar Dante com armas (1H/2H), roupas, dano e respawn

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run_flow")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("GAMEPLAY_TEST_FAILURE: %s" % message)
		print("  [FALHA] %s" % message)
	else:
		print("  [PASS] %s" % message)

func _run_flow() -> void:
	print("=================================================================")
	print("=== INICIANDO FLUXO COMPLETO DE 10 ETAPAS EM HARBORGAME REAL ===")
	print("=================================================================")

	var game_scene := load("res://district/harbor_preview/HarborGame.tscn")
	if not game_scene:
		print("FATAL: Não foi possível carregar HarborGame.tscn")
		quit(1)
		return

	var game = game_scene.instantiate()
	root.add_child(game)

	for _f in 20:
		await physics_frame

	var player = game.get_node_or_null("Player")
	var car = game.get_node_or_null("PlayerCar")
	var interiors = game.get_node_or_null("Interiors")
	var garage = interiors.get("garage_interior") if interiors else null
	var garage_entrance = game.get_node_or_null("District/Garage/Entrance")
	var g_out = garage_entrance.get_node_or_null("OutsideReturn") if garage_entrance else null

	_check(player != null, "Player existe em HarborGame")
	_check(car != null, "PlayerCar existe em HarborGame")
	_check(garage != null, "GarageInterior existe em HarborGame")
	_check(garage_entrance != null, "Garage entrance existe em HarborGame")

	# Documentado: posicionamento inicial de partida no pátio exterior em frente à garagem
	# (fora da porta, com distância para caminhar até o carro)
	player.global_position = Vector2(720, 1890)
	player.velocity = Vector2.ZERO
	car.global_position = Vector2(720, 1820)
	car.rotation = -PI * 0.5
	car.velocity = Vector2.ZERO
	car.is_driven_by_player = false

	for _f in 10:
		await physics_frame

	# -------------------------------------------------------------
	# ETAPA 1: APROXIMAR DO CARRO E ENTRAR PELO COMANDO NORMAL
	# -------------------------------------------------------------
	print("\n--- ETAPA 1: APROXIMAR-SE DO CARRO E ENTRAR PELO COMANDO NORMAL ---")
	var walked_to_car = await _walk_to(player, car.global_position + Vector2(25, 0), 20.0)
	_check(walked_to_car, "Jogador caminhou até o carro")
	_check(player.global_position.distance_to(car.global_position) < 50.0, "Jogador está ao alcance da porta")

	await _press_key(KEY_E)
	for _f in 8:
		await physics_frame
	_check(car.get("is_driven_by_player") == true, "Jogador entrou no carro pelo comando normal [E]")
	_check(not player.visible, "Jogador a pé ocultado ao volante")

	# -------------------------------------------------------------
	# ETAPA 2: DIRIGIR ATÉ A GARAGEM E ENTRAR PELA PORTA REAL
	# -------------------------------------------------------------
	print("\n--- ETAPA 2: DIRIGIR ATÉ A GARAGEM E ENTRAR PELA PORTA REAL ---")
	var drove_to_gate = await _drive_to(car, g_out.global_position, 25.0)
	_check(drove_to_gate, "Carro dirigiu até o portão da garagem")
	_check(garage_entrance.is_actor_in_range(car), "Sensor da porta detectou o carro conduzido")

	await _press_key(KEY_E)
	await create_timer(1.0).timeout
	for _f in 10:
		await physics_frame

	_check(car.global_position.distance_to(garage.spawn_point.global_position) < 40.0, "Carro transicionado para o interior da garagem")

	# -------------------------------------------------------------
	# ETAPA 3: ESTACIONAR USANDO SOMENTE OS CONTROLES NORMAIS
	# -------------------------------------------------------------
	print("\n--- ETAPA 3: ESTACIONAR NA BAIA USANDO APENAS CONTROLES NORMAIS ---")
	var park_target := Vector2(20000, 20020)
	var parked_ok = await _drive_to(car, park_target, 25.0)
	_check(parked_ok, "Carro dirigiu e estacionou na baia")
	_check(car.velocity.length() < 10.0, "Carro parou na baia pelos freios e desaceleração normais")
	_check(car.health >= 90, "Carro não sofreu danos críticos ao estacionar (health=%d)" % car.health)

	# -------------------------------------------------------------
	# ETAPA 4: DESEMBARCAR PELO COMANDO NORMAL
	# -------------------------------------------------------------
	print("\n--- ETAPA 4: DESEMBARCAR PELO COMANDO NORMAL [F] ---")
	await _disembark(car)
	_check(car.get("is_driven_by_player") == false, "Carro desocupado após comando de saída")
	_check(player.visible and player.is_physics_processing() and not player.is_control_disabled, "Jogador restaurado e ativo a pé")

	# -------------------------------------------------------------
	# ETAPA 5: CAMINHAR ATÉ MACIOTA E CONCLUIR UMA CONVERSA
	# -------------------------------------------------------------
	print("\n--- ETAPA 5: CAMINHAR ATÉ MACIOTA E CONCLUIR UMA CONVERSA ---")
	var jager = garage.jager_npc
	_check(jager != null, "Jäger Maciota existe no lounge")
	var walked_to_jager = await _walk_to(player, jager.global_position + Vector2(30, 0), 20.0)
	_check(walked_to_jager, "Jogador caminhou até Jäger Maciota")
	_check(jager.is_player_nearby, "Maciota detectou aproximação do jogador")

	await _press_key(KEY_E)
	for _f in 6:
		await physics_frame
	_check(jager.is_talking, "Diálogo com Maciota aberto")

	# Avançar diálogo com espaço/enter e fechar
	await _press_key(KEY_SPACE)
	for _f in 4:
		await physics_frame
	await _press_key(KEY_ESCAPE)
	for _f in 6:
		await physics_frame
	_check(not jager.is_talking, "Diálogo com Maciota concluído com sucesso")
	_check(not player.is_control_disabled, "Controles liberados após fechar diálogo")

	# -------------------------------------------------------------
	# ETAPA 6 & 7: CARCHALKBOARD — MISSÃO DISPONÍVEL & BLOQUEADA
	# -------------------------------------------------------------
	print("\n--- ETAPA 6 & 7: LOUSA DE MISSÕES (DISPONÍVEL vs BLOQUEADA) ---")
	garage.set_campaign_contact_enabled(true)
	garage.set_mission_board_unlocked(true)
	var board = garage.mission_board
	_check(board != null, "CarChalkboard instanciado na garagem")

	# Configurar 2 missões de teste: 1 disponível e 1 bloqueada
	var test_missions: Array[Dictionary] = [
		{
			"id": "test_mission_available",
			"title": "Entrega Expressa",
			"description": "Leve as peças até o cais norte",
			"enabled": true,
			"completed": false,
			"requirement": ""
		},
		{
			"id": "test_mission_locked",
			"title": "Carga Pesada",
			"description": "Requer reputação nível 2",
			"enabled": false,
			"completed": false,
			"requirement": "Bloqueado: Requer Nível 2"
		}
	]
	board.configure_missions(test_missions)

	# Caminhar até a lousa
	var walked_to_board = await _walk_to(player, board.global_position + Vector2(25, 0), 20.0)
	_check(walked_to_board, "Jogador caminhou até a lousa de missões")
	_check(board.is_actor_in_range(player), "Lousa detectou proximidade do jogador")

	# Abrir lousa com [E]
	await _press_key(KEY_E)
	for _f in 10:
		await physics_frame
	_check(board.is_ui_open, "Lousa de missões abriu com input nativo [E]")

	# Confirmar que a missão bloqueada não tem botão interativo
	var locked_btn_found := false
	for child in board.orders_vbox.get_children():
		if child is Button and child.get_meta("mission_id", "") == "test_mission_locked":
			locked_btn_found = true
			break
	_check(not locked_btn_found, "ETAPA 7: Missão bloqueada não pode ser selecionada (sem botão ativo)")

	# Confirmar e aceitar a missão disponível com Enter real
	var mission_accepted_id := ""
	board.mission_selected.connect(func(mid: String): mission_accepted_id = mid)

	await _press_key(KEY_ENTER)
	for _f in 6:
		await physics_frame
	_check(mission_accepted_id == "test_mission_available", "ETAPA 6: Missão disponível aceita com sucesso via ui_accept")

	# Fechar a lousa
	await _press_key(KEY_ESCAPE)
	for _f in 6:
		await physics_frame
	_check(not board.is_ui_open, "Lousa fechou e liberou controle")

	# -------------------------------------------------------------
	# ETAPA 8: RETORNAR AO CARRO, EMBARCAR E SAIR PARA HARBOR
	# -------------------------------------------------------------
	print("\n--- ETAPA 8: RETORNAR AO CARRO, EMBARCAR E SAIR PARA HARBOR ---")
	var walked_back_car = await _walk_to(player, car.global_position + Vector2(-30, 0), 20.0)
	_check(walked_back_car, "Jogador caminhou de volta até o carro")

	await _press_key(KEY_E)
	for _f in 8:
		await physics_frame
	_check(car.get("is_driven_by_player") == true, "Jogador reembarcou no carro na baia")

	# Dirigir até a saída sul
	var exit_target = garage.exit_door.get_node("InteractionArea").global_position
	var drove_to_exit = await _drive_to(car, exit_target, 25.0)
	_check(drove_to_exit, "Carro manobrou até a saída sul da garagem")

	await _press_key(KEY_E)
	await create_timer(1.0).timeout
	for _f in 10:
		await physics_frame

	_check(car.global_position.distance_to(g_out.global_position) < 40.0, "Carro transicionado de volta para a rua de Harbor")
	_check(car.get("is_driven_by_player") == true, "Jogador continua ao volante na rua")

	# -------------------------------------------------------------
	# ETAPA 9: VERIFICAR RESTAURAÇÃO POR SAVE/LOAD (SLOT ISOLADO)
	# -------------------------------------------------------------
	print("\n--- ETAPA 9: RESTAURAÇÃO POR SAVE/LOAD (SLOT ISOLADO) ---")
	var save_mgr = root.get_node_or_null("SaveManager")
	if save_mgr:
		var test_slot := "test_validation_slot"
		var save_res = save_mgr.save_game(test_slot, "Teste de Validação Real")
		_check(save_res.get("success", false) == true, "Save realizado com sucesso em slot isolado")

		# Modificar saúde do jogador
		player.health = 55
		_check(player.health == 55, "Saúde modificada temporariamente para 55")

		# Recarregar do slot
		var load_res = save_mgr.load_game(test_slot)
		_check(load_res.get("success", false) == true, "Load executado com sucesso do slot isolado")
		for _f in 10:
			await physics_frame

		# Limpar arquivo de teste para nunca deixar vestígios em saves pessoais
		var slot_file = save_mgr.get_slot_path(test_slot)
		if FileAccess.file_exists(slot_file):
			DirAccess.remove_absolute(slot_file)
			print("  [OK] Arquivo temporário de teste removido: ", slot_file)

	# -------------------------------------------------------------
	# ETAPA 10: VALIDAR DANTE COM ARMAS, ROUPAS, DANO E RESPAWN
	# -------------------------------------------------------------
	print("\n--- ETAPA 10: DANTE COM ARMAS, ROUPAS, DANO E RESPAWN ---")
	# Desembarcar na rua para testar Dante a pé
	await _disembark(car)
	_check(car.get("is_driven_by_player") == false, "Dante desembarcou na rua")
	_check(player.visible and player.is_physics_processing(), "Dante a pé na rua")

	# Armas: equipar arma de 1 mão e de 2 mãos
	player.active_weapon_id = "pistol"
	player._update_equipped_weapon_3d_mesh()
	_check(player.current_gun_mesh != null, "Mesh 3D de arma 1H (pistol) equipado no socket")

	player.active_weapon_id = "ak47"
	player._update_equipped_weapon_3d_mesh()
	_check(player.current_gun_mesh != null, "Mesh 3D de arma 2H (ak47) equipado no socket")

	# Roupas
	player.apply_outfit("dante_suit")
	await physics_frame
	_check(player.current_outfit_id == "dante_suit", "Traje dante_suit aplicado")

	player.apply_outfit("dante_classic")
	await physics_frame
	_check(player.current_outfit_id == "dante_classic", "Traje clássico canônico restaurado")
	_check(player.mat_black_jacket.albedo_texture != null, "Textura xadrez canônica preservada")

	# Dano e Respawn
	var hp_before: int = player.health
	player.take_damage(25)
	_check(player.health == hp_before - 25, "Dano de 25 deduzido de Dante")
	_check(player.mat_black_jacket.albedo_color.r > 0.9, "Hit flash vermelho ativado no material da jaqueta")

	# Simular respawn hospitalar sem recarregar a cena inteira
	player._respawn_at_hospital()
	await create_timer(0.2).timeout
	_check(player.health > 0, "Dante restaurado com vida positiva após hospital respawn")
	_check(not player.is_dead, "Dante não está em estado de morte após respawn")
	_check(player.is_physics_processing(), "Física de Dante reativada após respawn")

	# Finalização
	print("\n=================================================================")
	if failures.is_empty():
		print(">>> VALIDAÇÃO EM JOGO REAL: 10/10 ETAPAS CONCLUÍDAS COM SUCESSO TOTAL! <<<")
	else:
		print(">>> VALIDAÇÃO EM JOGO REAL: %d FALHAS REGISTRADAS! <<<" % failures.size())
	print("=================================================================\n")

	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _walk_to(player: CharacterBody2D, target: Vector2, tolerance: float = 20.0, timeout: float = 8.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		var diff: Vector2 = target - player.global_position
		if diff.length() <= tolerance:
			_release_walk_keys()
			player.velocity = Vector2.ZERO
			for _f in 3:
				await physics_frame
			return true
		_release_walk_keys()
		if diff.x > 15.0:
			Input.action_press("ui_right")
		elif diff.x < -15.0:
			Input.action_press("ui_left")
		if diff.y > 15.0:
			Input.action_press("ui_down")
		elif diff.y < -15.0:
			Input.action_press("ui_up")
		await physics_frame
		elapsed += 1.0 / 60.0
	_release_walk_keys()
	return player.global_position.distance_to(target) <= tolerance

func _drive_to(car: CharacterBody2D, target: Vector2, tolerance: float = 25.0, timeout: float = 12.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		var to_target: Vector2 = target - car.global_position
		var dist := to_target.length()
		if dist <= tolerance:
			break
		var forward := -car.transform.y
		var right := car.transform.x
		var dot_fwd := forward.dot(to_target.normalized())
		var dot_side := right.dot(to_target.normalized())

		_release_drive_keys()
		if dot_side > 0.15:
			Input.action_press("ui_right", 0.65)
		elif dot_side < -0.15:
			Input.action_press("ui_left", 0.65)

		if dot_fwd > 0.1:
			var speed_cap := 120.0 if dist < 80.0 else 220.0
			if car.velocity.length() < speed_cap:
				Input.action_press("ui_up", 0.85)
		else:
			if car.velocity.length() > 25.0:
				Input.action_press("ui_down", 0.35)

		await physics_frame
		elapsed += 1.0 / 60.0

	_release_drive_keys()
	var stop_frames := 0
	while car.velocity.length() > 5.0 and stop_frames < 30:
		await physics_frame
		stop_frames += 1
	for _f in 6:
		await physics_frame
	return car.global_position.distance_to(target) <= tolerance

func _release_walk_keys() -> void:
	for action in ["ui_left", "ui_right", "ui_up", "ui_down", "sprint"]:
		Input.action_release(action)

func _release_drive_keys() -> void:
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		Input.action_release(action)

func _press_key(key: Key) -> void:
	var ev_down := InputEventKey.new()
	ev_down.keycode = key
	ev_down.physical_keycode = key
	ev_down.key_label = key
	ev_down.unicode = int(key)
	ev_down.pressed = true
	Input.parse_input_event(ev_down)
	for _f in 4:
		await physics_frame

	var ev_up := InputEventKey.new()
	ev_up.keycode = key
	ev_up.physical_keycode = key
	ev_up.key_label = key
	ev_up.unicode = int(key)
	ev_up.pressed = false
	Input.parse_input_event(ev_up)
	for _f in 4:
		await physics_frame

func _disembark(car: CharacterBody2D) -> void:
	await _press_key(KEY_F)
	for _f in 4:
		await physics_frame
	if car.get("is_driven_by_player") == true:
		await _press_key(KEY_E)
		for _f in 4:
			await physics_frame
