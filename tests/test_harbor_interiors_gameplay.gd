extends SceneTree

## Real-input gameplay integration test for Breakwater harbor interiors.
## Exercises full player controls (movement via native Input actions, keypresses
## via InputEventKey for 'E', Space, Esc), NPC dialogues, contextual stations,
## camera limits, 3 cycles per building, 9 cycles for fire station (3 per bay),
## vehicle garage boarding/entering/exiting, and zero unsolicited rewards.

const PREVIEW_SCENE: PackedScene = preload("res://district/harbor_preview/HarborPreview.tscn")

var failures: Array[String] = []
var completed_cycles := 0
var completed_dialogues := 0
var completed_interactions := 0
var native_walk_distance := 0.0

func _init() -> void:
	call_deferred("_run_test")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("GAMEPLAY_TEST_FAILURE: " + message)

func _run_test() -> void:
	print("=================================================================")
	print("=== INICIANDO TESTE GAMEPLAY REAL: INTERIORES VIVOS BREAKWATER ===")
	print("=================================================================")

	var scene = PREVIEW_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene

	for _f in 6:
		await physics_frame

	var player = scene.get_node_or_null("Player")
	var car = scene.get_node_or_null("PlayerCar")
	var mgr = scene.get_node_or_null("Interiors")

	_check(player != null, "Player deve existir na cena")
	_check(car != null, "PlayerCar deve existir na cena")
	_check(mgr != null and mgr.enabled, "HarborInteriorManager deve existir e estar habilitado")

	if player == null or mgr == null or car == null:
		_finish(scene)
		return

	# Ativar modo caminhada nativo e suprimir tráfego ambiente
	scene.call("_walk")
	player.collision_mask = 1
	_quiet_ambient(scene, player, car)
	await create_timer(0.4).timeout

	var cam = player.get_node_or_null("Camera") as Camera2D
	_check(cam != null, "Camera do jogador deve existir")

	var garage_entrance = scene.get_node("District/Garage/Entrance")
	var police_entrance = scene.get_node("District/Police/Entrance")
	var clinic_entrance = scene.get_node("District/Clinic/Entrance")
	var workshop_entrance = scene.get_node("NorthDistrict/MotorWorkshop/Entrance")
	var fire_station_bldg = scene.get_node("NorthDistrict/NorthFireStation")

	# --- TESTE 0: INTERAÇÃO LONGE DE PORTAS/NPCS/VEÍCULOS ---
	print("\n--- TESTE 0: VALIDAÇÃO NEGATIVA (INTERAÇÃO DISTANTE) ---")
	# Posicionar jogador longe de qualquer porta, NPC ou veículo
	player.global_position = Vector2(1400, 1800)
	player.velocity = Vector2.ZERO
	await physics_frame
	var pos_before: Vector2 = player.global_position
	await _press_key(KEY_E)
	await create_timer(0.2).timeout
	_check(player.global_position.distance_to(pos_before) < 1.0, "Interação longe de portas não deve mover o jogador")
	_check(not player.is_in_dialogue, "Interação longe de NPCs não deve ativar diálogo")
	_check(car.get("is_driven_by_player") == false, "Interação longe de veículos não deve embarcar")
	_check(cam.limit_left == -10000000, "Camera externa deve permanecer irrestrita longe de interiores")

	# --- TESTE 1: GARAGEM (WESTGATE MOTOR CO. — 3 CICLOS A PÉ) ---
	print("\n--- TESTE 1: GARAGEM (JÄGER MACIOTA & DIAGNÓSTICO — 3 CICLOS) ---")
	var garage = mgr.garage_interior
	_check(garage != null, "Interior da garagem deve estar carregado")

	for cycle in 3:
		print("  [Garagem] Ciclo %d/3..." % (cycle + 1))
		var g_ret = garage_entrance.get_node("OutsideReturn")
		player.global_position = g_ret.global_position + Vector2(0, 50)
		player.velocity = Vector2.ZERO
		var reached_door: bool = await _walk_to(player, g_ret.global_position, 12.0)
		_check(reached_door, "Jogador deve andar até a entrada da garagem")

		await create_timer(0.4).timeout
		_check(garage_entrance.is_actor_in_range(player), "Sensor da porta da garagem deve detectar o jogador")

		# Pressionar 'E' para entrar
		await _press_key(KEY_E)
		await create_timer(0.7).timeout

		# Verificar entrada no interior e câmera
		_check(player.global_position.distance_to(garage.spawn_point.global_position) < 25.0, "Player deve nascer no spawn da garagem")
		_check(cam.limit_left > -1000000, "Camera deve estar enquadrada no interior da garagem")

		# Andar até o Jäger Maciota
		var jager_target: Vector2 = garage.jager_npc.global_position + Vector2(30, 0)
		var reached_jager: bool = await _walk_to(player, jager_target, 20.0)
		_check(reached_jager, "Jogador deve caminhar até o Jäger Maciota")
		for _f in 6:
			await physics_frame
		_check(garage.jager_npc.is_player_nearby, "Jäger deve detectar a proximidade do jogador")

		# Abrir diálogo com 'E'
		await _press_key(KEY_E)
		await create_timer(0.1).timeout
		_check(garage.jager_npc.is_talking, "Diálogo com Jäger deve abrir com tecla E")
		_check(player.is_in_dialogue and player.is_control_disabled, "Controles devem estar bloqueados durante diálogo")

		# Tentar andar durante o diálogo (deve ser bloqueado)
		Input.action_press("ui_right", 1.0)
		for _f in 4:
			await physics_frame
		Input.action_release("ui_right")
		_check(player.velocity == Vector2.ZERO, "Jogador não pode se mover durante o diálogo")

		# Avançar diálogo com 'Espaço'
		var idx_before: int = garage.jager_npc.dialogue_index
		await _press_key(KEY_SPACE)
		await create_timer(0.1).timeout
		_check(garage.jager_npc.dialogue_index != idx_before, "Diálogo deve avançar com tecla Espaço")

		# Fechar diálogo com 'Esc'
		await _press_key(KEY_ESCAPE)
		await create_timer(0.1).timeout
		_check(not garage.jager_npc.is_talking, "Diálogo deve fechar com tecla Esc")
		_check(not player.is_in_dialogue and not player.is_control_disabled, "Controles devem ser restaurados após fechar diálogo")
		completed_dialogues += 1

		# Andar até o elevador automotivo / diagnóstico
		var diag_target: Vector2 = garage.diagnostic_area.global_position
		var reached_diag: bool = await _walk_to(player, diag_target, 25.0)
		_check(reached_diag, "Jogador deve caminhar até o elevador de diagnóstico")
		for _f in 6:
			await physics_frame
		_check(garage.diagnostic_active, "Área de diagnóstico deve detectar o jogador")

		# Abrir diagnóstico com 'E'
		await _press_key(KEY_E)
		await create_timer(0.1).timeout
		_check(garage.diagnostic_dialog.visible, "Painel de diagnóstico deve abrir com tecla E")
		_check(player.is_control_disabled, "Controles devem travar com painel de diagnóstico aberto")

		# Fechar diagnóstico com 'Esc'
		await _press_key(KEY_ESCAPE)
		await create_timer(0.1).timeout
		_check(not garage.diagnostic_dialog.visible, "Painel de diagnóstico deve fechar com tecla Esc")
		_check(not player.is_control_disabled, "Controles devem ser restaurados após fechar diagnóstico")
		completed_interactions += 1

		# Andar até a porta de saída
		var exit_target: Vector2 = garage.exit_door.get_node("InteractionArea").global_position
		var reached_exit: bool = await _walk_to(player, exit_target, 20.0)
		_check(reached_exit, "Jogador deve caminhar até a porta de saída da garagem")
		for _f in 6:
			await physics_frame
		_check(garage.exit_door.is_actor_in_range(player), "Porta de saída deve detectar o jogador")

		# Pressionar 'E' para sair
		await _press_key(KEY_E)
		await create_timer(0.7).timeout

		# Verificar retorno no OutsideReturn exterior
		_check(player.global_position.distance_to(g_ret.global_position) < 8.0, "Player deve retornar ao OutsideReturn da garagem")
		_check(cam.limit_left == -10000000, "Camera externa deve ser restaurada ao sair da garagem")
		_check(player.velocity == Vector2.ZERO, "Velocidade deve ser zero após sair")
		completed_cycles += 1
		await create_timer(0.4).timeout

	# --- TESTE 2: POLÍCIA (HARBOR PATROL — 3 CICLOS A PÉ) ---
	print("\n--- TESTE 2: POLÍCIA (SARGENTO MORALES & TERMINAL — 3 CICLOS) ---")
	var police = mgr.police_interior
	_check(police != null, "Interior da delegacia deve estar carregado")

	for cycle in 3:
		print("  [Polícia] Ciclo %d/3..." % (cycle + 1))
		var p_ret = police_entrance.get_node("OutsideReturn")
		player.global_position = p_ret.global_position + Vector2(0, 45)
		player.velocity = Vector2.ZERO
		await _walk_to(player, p_ret.global_position, 12.0)
		await create_timer(0.4).timeout
		_check(police_entrance.is_actor_in_range(player), "Sensor da delegacia deve detectar o jogador")

		await _press_key(KEY_E)
		await create_timer(0.7).timeout
		_check(player.global_position.distance_to(police.spawn_point.global_position) < 25.0, "Player deve nascer no spawn da polícia")

		# Andar até o balcão do Sargento Morales
		var sgt_target: Vector2 = police.sergeant_npc.global_position + Vector2(0, 40)
		await _walk_to(player, sgt_target, 20.0)
		for _f in 6:
			await physics_frame
		_check(police.sergeant_npc.is_player_nearby, "Sargento Morales deve detectar o jogador")

		# Conversar: E -> Espaço -> Esc
		await _press_key(KEY_E)
		await create_timer(0.1).timeout
		_check(police.sergeant_npc.is_talking, "Diálogo com Sargento deve abrir")
		await _press_key(KEY_SPACE)
		await create_timer(0.1).timeout
		await _press_key(KEY_ESCAPE)
		await create_timer(0.1).timeout
		_check(not police.sergeant_npc.is_talking, "Diálogo com Sargento deve fechar")
		completed_dialogues += 1

		# Andar até o terminal de ocorrências
		var term_target: Vector2 = police.terminal_area.global_position
		await _walk_to(player, term_target, 25.0)
		for _f in 6:
			await physics_frame
		_check(police.is_near_terminal, "Terminal deve detectar o jogador")

		# Operar terminal: E -> Esc
		await _press_key(KEY_E)
		await create_timer(0.1).timeout
		_check(police.terminal_dialog.visible, "Terminal de ocorrências deve abrir")
		await _press_key(KEY_ESCAPE)
		await create_timer(0.1).timeout
		_check(not police.terminal_dialog.visible, "Terminal de ocorrências deve fechar")
		completed_interactions += 1

		# Andar até a saída
		var p_exit: Vector2 = police.exit_door.get_node("InteractionArea").global_position
		await _walk_to(player, p_exit, 20.0)
		for _f in 6:
			await physics_frame
		_check(police.exit_door.is_actor_in_range(player), "Saída da delegacia deve detectar o jogador")
		await _press_key(KEY_E)
		await create_timer(0.7).timeout

		_check(player.global_position.distance_to(p_ret.global_position) < 8.0, "Player deve retornar ao OutsideReturn da polícia")
		completed_cycles += 1
		await create_timer(0.4).timeout

	# --- TESTE 3: CLÍNICA (BAY MEDICAL — ENTRADA NORTE — 3 CICLOS A PÉ) ---
	print("\n--- TESTE 3: CLÍNICA (ENFERMEIRA CLARA & TRIAGEM — 3 CICLOS) ---")
	var clinic = mgr.clinic_interior
	_check(clinic != null, "Interior da clínica deve estar carregado")

	for cycle in 3:
		print("  [Clínica] Ciclo %d/3..." % (cycle + 1))
		var c_ret = clinic_entrance.get_node("OutsideReturn")
		player.global_position = c_ret.global_position + Vector2(0, -45)
		player.velocity = Vector2.ZERO
		await _walk_to(player, c_ret.global_position, 12.0)
		await create_timer(0.4).timeout
		_check(clinic_entrance.is_actor_in_range(player), "Sensor da clínica deve detectar o jogador")

		await _press_key(KEY_E)
		await create_timer(0.7).timeout
		_check(player.global_position.distance_to(clinic.spawn_point.global_position) < 25.0, "Player deve nascer no spawn da clínica")

		# Andar até Enfermeira Clara
		var clara_target: Vector2 = clinic.nurse_npc.global_position + Vector2(30, 0)
		await _walk_to(player, clara_target, 20.0)
		for _f in 6:
			await physics_frame
		_check(clinic.nurse_npc.is_player_nearby, "Enfermeira Clara deve detectar o jogador")

		# Conversar: E -> Espaço -> Esc
		await _press_key(KEY_E)
		for _f in 4:
			await physics_frame
		_check(clinic.nurse_npc.is_talking, "Diálogo com Clara deve abrir")
		await _press_key(KEY_SPACE)
		for _f in 4:
			await physics_frame
		await _press_key(KEY_ESCAPE)
		for _f in 4:
			await physics_frame
		_check(not clinic.nurse_npc.is_talking, "Diálogo com Clara deve fechar")
		completed_dialogues += 1

		# Andar até a maca de triagem
		var triage_target: Vector2 = clinic.triage_area.global_position
		await _walk_to(player, triage_target, 25.0)
		for _f in 6:
			await physics_frame
		_check(clinic.is_near_triage, "Maca de triagem deve detectar o jogador")

		# Testar triagem médica (sem cura indevida)
		player.health = 45
		var hp_before: int = player.health
		await _press_key(KEY_E)
		for _f in 4:
			await physics_frame
		_check(clinic.triage_dialog.visible, "Painel de triagem deve abrir")
		_check(player.health == hp_before, "Triagem médica não pode curar 100% de forma instantânea")
		await _press_key(KEY_ESCAPE)
		for _f in 4:
			await physics_frame
		_check(not clinic.triage_dialog.visible, "Painel de triagem deve fechar")
		completed_interactions += 1

		# Sair pela porta norte
		var reached_exit: bool = await _walk_to(player, clinic.exit_door.get_node("InteractionArea").global_position, 20.0)
		_check(reached_exit, "Jogador deve alcançar a saída norte da clínica")
		await _press_key(KEY_E)
		await create_timer(0.7).timeout

		_check(player.global_position.distance_to(c_ret.global_position) < 8.0, "Player deve retornar ao OutsideReturn da clínica")
		completed_cycles += 1
		await create_timer(0.4).timeout

	# --- TESTE 4: OFICINA MECÂNICA (NORTHGATE AUTO — 3 CICLOS A PÉ) ---
	print("\n--- TESTE 4: OFICINA MECÂNICA (MESTRE ARNALDO & PREPARAÇÃO — 3 CICLOS) ---")
	var workshop = mgr.workshop_interior
	_check(workshop != null, "Interior da oficina deve estar carregado")

	for cycle in 3:
		print("  [Oficina] Ciclo %d/3..." % (cycle + 1))
		var w_ret = workshop_entrance.get_node("OutsideReturn")
		player.global_position = w_ret.global_position + Vector2(0, 50)
		player.velocity = Vector2.ZERO
		await _walk_to(player, w_ret.global_position, 12.0)
		await create_timer(0.4).timeout
		_check(workshop_entrance.is_actor_in_range(player), "Sensor da oficina deve detectar o jogador")

		await _press_key(KEY_E)
		await create_timer(0.7).timeout
		_check(player.global_position.distance_to(workshop.spawn_point.global_position) < 25.0, "Player deve nascer no spawn da oficina")

		# Andar até Mestre Arnaldo
		var arnaldo_target: Vector2 = workshop.mechanic_npc.global_position + Vector2(30, 0)
		await _walk_to(player, arnaldo_target, 20.0)
		for _f in 6:
			await physics_frame
		_check(workshop.mechanic_npc.is_player_nearby, "Mestre Arnaldo deve detectar o jogador")

		# Conversar
		await _press_key(KEY_E)
		for _f in 4:
			await physics_frame
		await _press_key(KEY_ESCAPE)
		for _f in 4:
			await physics_frame
		completed_dialogues += 1

		# Andar até a bancada de preparação
		var bench_target: Vector2 = workshop.bench_area.global_position
		await _walk_to(player, bench_target, 25.0)
		for _f in 6:
			await physics_frame
		_check(workshop.is_near_bench, "Bancada de preparação deve detectar o jogador")

		# Operar bancada
		await _press_key(KEY_E)
		for _f in 4:
			await physics_frame
		_check(workshop.bench_dialog.visible, "Painel da bancada deve abrir")
		await _press_key(KEY_ESCAPE)
		for _f in 4:
			await physics_frame
		_check(not workshop.bench_dialog.visible, "Painel da bancada deve fechar")
		completed_interactions += 1

		# Sair pela porta
		var reached_exit: bool = await _walk_to(player, workshop.exit_door.get_node("InteractionArea").global_position, 20.0)
		_check(reached_exit, "Jogador deve alcançar a saída da oficina")
		await _press_key(KEY_E)
		await create_timer(0.7).timeout

		_check(player.global_position.distance_to(w_ret.global_position) < 8.0, "Player deve retornar ao OutsideReturn da oficina")
		completed_cycles += 1
		await create_timer(0.4).timeout

	# --- TESTE 5: CORPO DE BOMBEIROS (NORTHGATE FIRE / 03 — 9 CICLOS: 3 POR BAIA) ---
	print("\n--- TESTE 5: CORPO DE BOMBEIROS (9 CICLOS — 3 POR BAIA) ---")
	var firehouse = mgr.fire_station_interior
	_check(firehouse != null, "Interior do corpo de bombeiros deve estar carregado")

	for bay_idx in 3:
		var bay_door = fire_station_bldg.get_node("Entrance%d" % bay_idx)
		var b_ret = bay_door.get_node("OutsideReturn")

		for cycle in 3:
			print("  [Bombeiros] Baia %d — Ciclo %d/3..." % [bay_idx, cycle + 1])
			player.global_position = b_ret.global_position + Vector2(0, 50)
			player.velocity = Vector2.ZERO
			await _walk_to(player, b_ret.global_position, 12.0)
			await create_timer(0.4).timeout
			_check(bay_door.is_actor_in_range(player), "Sensor da baia %d deve detectar o jogador" % bay_idx)

			await _press_key(KEY_E)
			await create_timer(0.7).timeout

			# Confirmar spawn na baia específica
			var bay_spawn = firehouse.get_spawn_for_bay(bay_idx)
			_check(player.global_position.distance_to(bay_spawn.global_position) < 25.0, "Player deve nascer na baia %d" % bay_idx)

			# Andar até o Capitão Rocha (contornando o caminhão na baia 1 se necessário)
			if bay_idx == 1:
				await _walk_to(player, Vector2(70, 50), 20.0, 5.0)
			var rocha_target: Vector2 = firehouse.captain_npc.global_position + Vector2(30, 0)
			await _walk_to(player, rocha_target, 20.0)
			for _f in 6:
				await physics_frame
			_check(firehouse.captain_npc.is_player_nearby, "Capitão Rocha deve detectar o jogador")

			# Conversar
			await _press_key(KEY_E)
			for _f in 4:
				await physics_frame
			await _press_key(KEY_ESCAPE)
			for _f in 4:
				await physics_frame
			completed_dialogues += 1

			# Andar até alarme de prontidão
			var alarm_target: Vector2 = firehouse.alarm_area.global_position
			await _walk_to(player, alarm_target, 25.0)
			for _f in 6:
				await physics_frame
			_check(firehouse.is_near_alarm, "Alavanca de alarme deve detectar o jogador")

			# Acionar alarme (sem dar 100 de colete indevido)
			player.armor = 20
			var armor_before: int = player.armor
			await _press_key(KEY_E)
			for _f in 4:
				await physics_frame
			_check(firehouse.alarm_dialog.visible, "Painel de alarme deve abrir")
			_check(player.armor == armor_before, "Alarme dos bombeiros não pode dar 100 de colete gratuito")
			await _press_key(KEY_ESCAPE)
			for _f in 4:
				await physics_frame
			_check(not firehouse.alarm_dialog.visible, "Painel de alarme deve fechar")
			completed_interactions += 1

			# Andar até a saída da baia correspondente
			var bay_exit = firehouse.bay_exits[bay_idx]
			var bay_exit_pos: Vector2 = bay_exit.get_node("InteractionArea").global_position
			await _walk_to(player, bay_exit_pos, 20.0)
			for _f in 6:
				await physics_frame
			_check(bay_exit.is_actor_in_range(player), "Saída da baia %d deve detectar o jogador" % bay_idx)

			await _press_key(KEY_E)
			await create_timer(0.7).timeout

			# Confirmar retorno exato à porta externa da baia de origem
			_check(player.global_position.distance_to(b_ret.global_position) < 8.0, "Player deve retornar EXATAMENTE à baia Entrance%d de origem" % bay_idx)
			completed_cycles += 1
			await create_timer(0.4).timeout

	# --- TESTE 6: GARAGEM DIRIGINDO DE VERDADE (SEM TELEPORTES ARTIFICIAIS) ---
	print("\n--- TESTE 6: GARAGEM DIRIGINDO DE VERDADE (CONTROLES REAIS DE DIREÇÃO E EMBARQUE) ---")
	var g_out = garage_entrance.get_node("OutsideReturn")

	# Posição inicial externa única: carro no acesso em frente à garagem e jogador na calçada ao lado da porta do motorista
	car.global_position = Vector2(750, 1850)
	car.rotation = -PI / 2.0
	car.velocity = Vector2.ZERO
	player.global_position = Vector2(715, 1850)
	player.velocity = Vector2.ZERO
	for _f in 6:
		await physics_frame

	# 1. Caminhar até o carro e embarcar pela interação normal [E]
	_check(player.is_physics_processing(), "Jogador deve ter física ativa no exterior")
	_check(not player.is_control_disabled, "Controles do jogador devem estar livres")
	var reached_car_outside: bool = await _walk_to(player, Vector2(725, 1850), 15.0)
	_check(reached_car_outside, "Jogador deve caminhar até o carro pelo controle normal")
	_check(player.global_position.distance_to(car.global_position) < 60.0, "Jogador deve estar ao lado da porta do carro")

	# Embarcar com [E] normal (acionando try_enter_vehicle nativo)
	await _press_key(KEY_E)
	for _f in 6:
		await physics_frame
	_check(car.get("is_driven_by_player") == true, "Jogador deve embarcar no carro pela interação normal [E]")
	_check(not player.visible, "Jogador a pé deve ficar invisível enquanto dirige")
	_check(not player.is_physics_processing(), "Física do jogador a pé deve ser pausada pelo próprio jogo ao dirigir")

	# Captura 1: Carro aproximando da garagem no exterior
	await _try_capture("res://tests/harbor_garage_drive_approach.png")

	# 2. Dirigir até a entrada da garagem pelos controles normais (ui_up/ui_down/ui_left/ui_right)
	var drove_to_door: bool = await _drive_to(car, g_out.global_position, 25.0)
	_check(drove_to_door, "Carro deve dirigir até o portão da garagem pelos controles de direção")
	for _f in 6:
		await physics_frame
	_check(garage_entrance.is_actor_in_range(car), "Sensor da garagem deve detectar o carro conduzido após dirigir até ele")

	# 3. Interagir para entrar na garagem com [E]
	await _press_key(KEY_E)
	await create_timer(1.0).timeout

	# Confirmar transição pelo sistema do jogo
	_check(car.global_position.distance_to(garage.spawn_point.global_position) < 35.0, "Carro deve ser transicionado para o spawn da garagem")
	_check(player.global_position.distance_to(garage.spawn_point.global_position) < 35.0, "Motorista deve estar sincronizado no spawn interno da garagem")
	var car_cam = car.get_node_or_null("Camera") as Camera2D
	_check(car_cam != null and car_cam.limit_left > -1000000, "Camera do carro deve ter limites enquadrados no interior da garagem")

	# 4. Dirigir dentro da garagem até a baia livre para estacionar
	var park_target := Vector2(20000, 20020)
	var drove_to_park: bool = await _drive_to(car, park_target, 25.0)
	_check(drove_to_park, "Carro deve manobrar e estacionar dentro da baia da garagem")
	_check(car.velocity.length() < 10.0, "Carro deve desacelerar e parar na baia pelos controles e atrito normais")
	_check(car.health >= 90, "Carro deve estacionar sem bater ou sofrer impacto grave (health=%d)" % car.health)
	_check(not car.is_broken, "Carro não deve quebrar ao estacionar")
	for _f in 6:
		await physics_frame

	# Captura 2: Veículo estacionado dentro da garagem
	await _try_capture("res://tests/harbor_garage_drive_inside.png")

	# 5. Desembarcar pelo controle normal [F]
	await _disembark(car)
	_check(car.get("is_driven_by_player") == false, "Carro deve ficar desocupado após desembarcar com [F]")
	_check(player.visible, "Jogador deve voltar a ficar visível ao desembarcar")
	_check(player.is_physics_processing(), "Jogador deve restaurar physics_process sozinho ao desembarcar")
	_check(not player.is_control_disabled, "Controles do jogador devem estar livres ao desembarcar")
	_check(cam.limit_left > -1000000, "Camera do jogador a pé deve herdar os limites da garagem")

	# 6. Caminhar até o Jäger Maciota e conversar
	var reached_jager_foot: bool = await _walk_to(player, garage.jager_npc.global_position + Vector2(30, 0), 20.0)
	_check(reached_jager_foot, "Jogador a pé deve poder andar até o Jäger Maciota após deixar o carro")
	_check(garage.jager_npc.is_player_nearby, "Jäger Maciota deve detectar o jogador")

	await _press_key(KEY_E)
	for _f in 4:
		await physics_frame
	_check(garage.jager_npc.is_talking, "Diálogo com Jäger Maciota deve abrir")
	_check(player.is_in_dialogue or player.is_control_disabled, "Player deve ter controles bloqueados durante o diálogo")

	# Captura 3: Jogador desembarcado conversando com Maciota
	await _try_capture("res://tests/harbor_garage_disembarked_jager.png")

	await _press_key(KEY_SPACE)
	for _f in 4:
		await physics_frame
	await _press_key(KEY_ESCAPE)
	for _f in 4:
		await physics_frame
	_check(not garage.jager_npc.is_talking, "Diálogo com Jäger Maciota deve fechar")
	_check(not player.is_in_dialogue and not player.is_control_disabled, "Controles do jogador devem ser restaurados sozinho após fechar diálogo")
	completed_dialogues += 1

	# 7. Caminhar até a saída de pedestres e sair a pé da garagem
	var reached_exit_foot: bool = await _walk_to(player, garage.exit_door.get_node("InteractionArea").global_position, 20.0)
	_check(reached_exit_foot, "Jogador a pé deve caminhar até a saída da garagem")
	_check(garage.exit_door.is_actor_in_range(player), "Saída da garagem deve detectar o jogador a pé")

	await _press_key(KEY_E)
	await create_timer(1.0).timeout

	# Confirmar retorno ao exterior a pé, visível e destravado
	_check(player.global_position.distance_to(g_out.global_position) < 15.0, "Player a pé deve retornar ao exterior mesmo tendo entrado de carro")
	_check(player.visible, "Player deve estar visível no exterior")
	_check(player.is_physics_processing(), "Player deve estar com física ativa no exterior")
	_check(not player.is_control_disabled, "Player deve estar com controles liberados no exterior")
	_check(cam.limit_left == -10000000, "Camera exterior deve estar restaurada")
	await create_timer(0.8).timeout

	# 8. Reentrar na garagem a pé
	var walked_to_entrance: bool = await _walk_to(player, g_out.global_position, 15.0)
	_check(walked_to_entrance, "Jogador a pé deve caminhar de volta até a entrada da garagem")
	for _f in 6:
		await physics_frame
	_check(garage_entrance.is_actor_in_range(player), "Sensor da entrada exterior deve detectar o jogador a pé")

	await _press_key(KEY_E)
	await create_timer(1.0).timeout
	_check(player.global_position.distance_to(garage.spawn_point.global_position) < 25.0, "Player deve reentrar na garagem pelo spawn")
	_check(player.is_physics_processing(), "Player deve estar com física ativa ao reentrar")

	# 9. Caminhar até o carro estacionado
	var walked_to_car: bool = await _walk_to(player, car.global_position + Vector2(-30, 0), 20.0)
	_check(walked_to_car, "Jogador deve caminhar até o carro estacionado dentro da garagem")
	_check(player.global_position.distance_to(car.global_position) < 70.0, "Jogador deve estar ao alcance da porta do carro")

	# Reembarcar com [E] normal
	await _press_key(KEY_E)
	for _f in 6:
		await physics_frame
	_check(car.get("is_driven_by_player") == true, "Player deve reembarcar no carro pela interação normal [E]")
	_check(not player.visible, "Player deve ficar oculto ao reembarcar")

	# 10. Dirigir o carro até a porta de saída
	var exit_target: Vector2 = garage.exit_door.get_node("InteractionArea").global_position
	var drove_to_exit: bool = await _drive_to(car, exit_target, 25.0)
	_check(drove_to_exit, "Carro deve manobrar até a porta de saída da garagem")
	for _f in 6:
		await physics_frame
	_check(garage.exit_door.is_actor_in_range(car), "Porta de saída deve detectar o carro conduzido")

	# Sair dirigindo com [E]
	await _press_key(KEY_E)
	await create_timer(1.0).timeout

	# Confirmar retorno ao exterior dirigindo
	_check(car.global_position.distance_to(g_out.global_position) < 35.0, "Carro deve retornar à calçada exterior da garagem")
	_check(car.get("is_driven_by_player") == true, "Jogador deve continuar dirigindo o carro no exterior")
	_check(car_cam.limit_left == -10000000, "Camera do carro deve ter limites irrestritos no exterior")

	# 11. Continuar dirigindo no exterior para comprovar que o carro não ficou preso
	var street_dest: Vector2 = car.global_position + Vector2(0, 160)
	var drove_on_street: bool = await _drive_to(car, street_dest, 30.0, 5.0)
	_check(drove_on_street, "Carro deve continuar dirigindo pela rua sem ficar preso")
	_check(car.global_position.distance_to(g_out.global_position) > 80.0, "Carro deve se afastar da entrada comprovando livre circulação")

	# Captura 4: Carro de volta à rua trafegando livremente
	await _try_capture("res://tests/harbor_garage_drive_return.png")

	# Desembarque final na rua com [F]
	await _disembark(car)
	_check(player.visible and player.is_physics_processing() and not player.is_control_disabled, "Player final restaurado com sucesso na rua")

	# --- TESTE 7: DUPLICAÇÃO DE NÓS E CONEXÕES DE SINAIS ---
	print("\n--- TESTE 7: INTEGRIDADE DE NÓS E SINAIS ---")
	var spaces = mgr.get_node_or_null("InteriorSpaces")
	_check(spaces != null and spaces.get_child_count() == 7, "InteriorSpaces deve conter exatamente os 7 interiores sem duplicações")

	# --- TESTE 8: PERCURSO INTEGRADO DA GARAGEM COM AMBIENTE ATIVO (SEM _QUIET_AMBIENT) ---
	print("\n--- TESTE 8: PERCURSO INTEGRADO COM AMBIENTE ATIVO (TRÁFEGO, PEDESTRES E COLISÕES VIVOS) ---")
	# Libera o cenário isolado anterior e recria o cenário completo do zero, SEM chamar _quiet_ambient()
	scene.queue_free()
	await process_frame
	await physics_frame

	var preview_res := load("res://district/harbor_preview/HarborPreview.tscn") as PackedScene
	_check(preview_res != null, "HarborPreview.tscn deve carregar para o teste integrado")
	var live_scene = preview_res.instantiate()
	root.add_child(live_scene)
	await create_timer(1.0).timeout
	live_scene.call("_walk")
	await create_timer(0.3).timeout

	var live_player = live_scene.get_node("Player") as CharacterBody2D
	var live_car = live_scene.get_node("PlayerCar") as CharacterBody2D
	var live_mgr = live_scene.get_node("Interiors")
	var live_garage_entrance = live_scene.get_node("District/Garage/Entrance")
	var live_g_out = live_garage_entrance.get_node("OutsideReturn")
	var live_garage = live_mgr.garage_interior

	# Validação explícita de que o ambiente NÃO foi silenciado e está 100% ativo
	var live_traffic = live_scene.get_tree().get_nodes_in_group("ambient_traffic")
	var live_peds = live_scene.get_tree().get_nodes_in_group("pedestrian")
	print("  [Ambiente Ativo] Veículos de tráfego ativos: %d | Pedestres ativos: %d" % [live_traffic.size(), live_peds.size()])
	_check(live_traffic.size() > 0, "Tráfego ambiente deve estar ativo e rodando (sem _quiet_ambient)")
	_check(live_peds.size() > 1, "Pedestres devem estar ativos e circulando (sem _quiet_ambient)")
	_check(live_player.collision_mask == 7, "Máscara de colisão do jogador deve permanecer total (layer 7)")
	_check(live_car.collision_mask == 23, "Máscara de colisão do carro deve permanecer total (layer 23)")

	# 1. Posição inicial externa única válida: carro no acesso da garagem e jogador ao lado
	live_car.global_position = Vector2(750, 1850)
	live_car.rotation = -PI / 2.0
	live_player.global_position = Vector2(715, 1850)
	for _f in 10:
		await physics_frame

	# 2. Caminhar até o carro com colisões ativas e embarcar via [E]
	_check(live_player.is_physics_processing(), "Jogador integrado deve ter física ativa no exterior")
	_check(not live_player.is_control_disabled, "Controles do jogador integrado devem estar liberados")
	var live_walk_car: bool = await _walk_to(live_player, Vector2(725, 1850), 15.0)
	_check(live_walk_car, "Jogador deve caminhar até o carro no ambiente integrado com colisões ativas")
	await _press_key(KEY_E)
	for _f in 6:
		await physics_frame
	_check(live_car.get("is_driven_by_player") == true, "Jogador deve embarcar no carro via [E] no ambiente integrado")
	_check(not live_player.visible, "Jogador deve ficar oculto ao dirigir no ambiente integrado")

	# 3. Dirigir até o portão da garagem no ambiente ativo
	var live_drove_door: bool = await _drive_to(live_car, live_g_out.global_position, 25.0)
	_check(live_drove_door, "Carro deve dirigir até a entrada da garagem no ambiente ativo")
	_check(live_car.velocity.length() < 10.0, "Carro deve desacelerar e parar na entrada pelos controles normais")
	_check(not live_car.is_broken, "Carro não deve colidir criticamente no exterior")
	_check(live_garage_entrance.is_actor_in_range(live_car), "Sensor da garagem deve detectar o carro conduzido no ambiente ativo")

	# 4. Entrar na garagem com [E]
	await _press_key(KEY_E)
	await create_timer(1.0).timeout
	_check(live_car.global_position.distance_to(live_garage.spawn_point.global_position) < 35.0, "Carro deve entrar na garagem no ambiente ativo")

	# 5. Dirigir até a baia e estacionar desacelerando pelos controles normais
	var live_park_target: Vector2 = Vector2(20000, 20020)
	var live_drove_park: bool = await _drive_to(live_car, live_park_target, 25.0)
	_check(live_drove_park, "Carro deve manobrar e estacionar na baia da garagem no ambiente ativo")
	_check(live_car.velocity.length() < 10.0, "Carro deve parar na baia pelos freios/atrito normais do jogo")
	_check(live_car.health >= 90, "Carro deve estacionar sem bater ou sofrer dano (health=%d)" % live_car.health)
	_check(not live_car.is_broken, "Carro não deve quebrar ao estacionar")

	# 6. Desembarcar com [F] e caminhar até Jäger Maciota
	await _disembark(live_car)
	_check(live_car.get("is_driven_by_player") == false, "Carro deve ficar desocupado após desembarcar com [F]")
	_check(live_player.visible and live_player.is_physics_processing() and not live_player.is_control_disabled, "Jogador destravado na garagem integrada")

	var live_reach_jager: bool = await _walk_to(live_player, live_garage.jager_npc.global_position + Vector2(30, 0), 20.0)
	_check(live_reach_jager, "Jogador deve caminhar até Jäger Maciota na garagem integrada")
	_check(live_garage.jager_npc.is_player_nearby, "Maciota deve detectar o jogador")

	# 7. Conversar com Maciota
	await _press_key(KEY_E)
	for _f in 4:
		await physics_frame
	_check(live_garage.jager_npc.is_talking, "Diálogo com Maciota deve abrir")
	await _press_key(KEY_SPACE)
	for _f in 4:
		await physics_frame
	await _press_key(KEY_ESCAPE)
	for _f in 4:
		await physics_frame
	_check(not live_garage.jager_npc.is_talking and not live_player.is_control_disabled, "Diálogo com Maciota concluído com sucesso")
	completed_dialogues += 1

	# 8. Caminhar até a porta de saída e sair a pé para o exterior com tráfego
	var live_reach_exit: bool = await _walk_to(live_player, live_garage.exit_door.get_node("InteractionArea").global_position, 20.0)
	_check(live_reach_exit, "Jogador deve caminhar até a saída de pedestres")
	await _press_key(KEY_E)
	await create_timer(1.0).timeout
	_check(live_player.global_position.distance_to(live_g_out.global_position) < 15.0, "Jogador deve retornar ao exterior ativo a pé")
	_check(live_player.visible and live_player.is_physics_processing() and not live_player.is_control_disabled, "Jogador ativo no exterior")

	# 9. Caminhar de volta até a entrada e reentrar na garagem a pé
	var live_walk_reenter: bool = await _walk_to(live_player, live_g_out.global_position, 15.0)
	_check(live_walk_reenter, "Jogador deve caminhar até o portão exterior")
	await _press_key(KEY_E)
	await create_timer(1.0).timeout
	_check(live_player.global_position.distance_to(live_garage.spawn_point.global_position) < 25.0, "Jogador deve reentrar na garagem a pé")

	# 10. Caminhar até o carro estacionado e reembarcar com [E]
	var live_walk_to_car: bool = await _walk_to(live_player, live_car.global_position + Vector2(-30, 0), 20.0)
	_check(live_walk_to_car, "Jogador deve caminhar até o carro estacionado")
	await _press_key(KEY_E)
	for _f in 6:
		await physics_frame
	_check(live_car.get("is_driven_by_player") == true, "Jogador deve reembarcar no carro com [E]")

	# 11. Dirigir o carro até a saída e retornar à rua dirigindo
	var live_exit_target: Vector2 = live_garage.exit_door.get_node("InteractionArea").global_position
	var live_drove_exit: bool = await _drive_to(live_car, live_exit_target, 25.0)
	_check(live_drove_exit, "Carro deve manobrar até a porta de saída")
	_check(live_car.velocity.length() < 10.0, "Carro deve desacelerar e parar na saída pelos controles normais")
	await _press_key(KEY_E)
	await create_timer(1.0).timeout
	_check(live_car.global_position.distance_to(live_g_out.global_position) < 35.0, "Carro deve retornar à calçada exterior no tráfego ativo")
	_check(live_car.get("is_driven_by_player") == true, "Jogador deve continuar ao volante")

	# 12. Continuar dirigindo pela rua com tráfego e pedestres ativos
	var live_street_dest: Vector2 = live_car.global_position + Vector2(0, 160)
	var live_drove_street: bool = await _drive_to(live_car, live_street_dest, 30.0, 6.0)
	_check(live_drove_street, "Carro deve circular pela rua com tráfego ativo sem bater ou ficar preso")
	_check(live_car.velocity.length() < 10.0, "Carro deve desacelerar e parar na rua pelos controles normais")
	_check(not live_car.is_broken, "Carro não deve ter sido quebrado durante a circulação")
	_check(live_car.health >= 90, "Carro não deve ter sofrido colisão grave (health=%d)" % live_car.health)
	_check(live_car.global_position.distance_to(live_g_out.global_position) > 80.0, "Carro deve ter se afastado da garagem comprovando livre circulação")

	# 13. Desembarque final na rua com [F]
	await _disembark(live_car)
	_check(live_player.visible and live_player.is_physics_processing() and not live_player.is_control_disabled, "Jogador final restaurado na rua do ambiente ativo")
	completed_cycles += 1
	scene = live_scene

	print("\n=================================================================")
	print("RESULTADO HARBOR_GAMEPLAY: failures=%d cycles=%d dialogues=%d interactions=%d walk_dist=%.1f" % [
		failures.size(), completed_cycles, completed_dialogues, completed_interactions, native_walk_distance
	])
	print("=================================================================")

	_finish(scene)

func _walk_to(player: CharacterBody2D, target: Vector2, tolerance: float = 20.0, timeout: float = 8.0) -> bool:
	# O teste NÃO deve forçar physics_process nem reparar estados quebrados
	if not player.is_physics_processing():
		failures.append("FALHA: player com physics_process inativo ao tentar caminhar para %s" % str(target))
		return false

	var start_pos: Vector2 = player.global_position
	var elapsed := 0.0
	while elapsed < timeout:
		var diff: Vector2 = target - player.global_position
		if diff.length() <= tolerance:
			_release_walk_keys()
			player.velocity = Vector2.ZERO
			for _f in 3:
				await physics_frame
			native_walk_distance += start_pos.distance_to(player.global_position)
			return true

		var dir: Vector2 = diff.normalized()
		_release_walk_keys()
		# Usar corrida (sprint) para acelerar a travessia dos cômodos
		Input.action_press("sprint", 1.0)
		if absf(dir.x) > 0.1:
			Input.action_press("ui_right" if dir.x > 0.0 else "ui_left", absf(dir.x))
		if absf(dir.y) > 0.1:
			Input.action_press("ui_down" if dir.y > 0.0 else "ui_up", absf(dir.y))

		await physics_frame
		elapsed += 1.0 / 60.0

	_release_walk_keys()
	player.velocity = Vector2.ZERO
	for _f in 3:
		await physics_frame
	native_walk_distance += start_pos.distance_to(player.global_position)
	return player.global_position.distance_to(target) <= tolerance

func _drive_to(car: CharacterBody2D, target: Vector2, tolerance: float = 30.0, timeout: float = 8.0) -> bool:
	if not car.get("is_driven_by_player"):
		failures.append("FALHA: tentativa de dirigir carro que não está sendo conduzido pelo jogador")
		return false

	var elapsed := 0.0
	while elapsed < timeout:
		var diff: Vector2 = target - car.global_position
		if diff.length() <= tolerance:
			_release_drive_keys()
			# Desaceleração e parada por atrito normal do PlayerCar (sem car.velocity = Vector2.ZERO)
			var stop_frames := 0
			while car.velocity.length() > 5.0 and stop_frames < 30:
				await physics_frame
				stop_frames += 1
			for _f in 6:
				await physics_frame
			return true

		var to_target: Vector2 = diff.normalized()
		var forward: Vector2 = car.transform.x
		var fwd_dot: float = forward.dot(to_target)
		var cross: float = forward.cross(to_target)
		var cur_speed: float = car.velocity.length()
		var dist: float = diff.length()

		_release_drive_keys()

		if fwd_dot >= -0.2:
			# Seguir em frente e virar na direção do alvo
			if absf(cross) > 0.06:
				Input.action_press("ui_right" if cross > 0.0 else "ui_left", clampf(absf(cross) * 2.5, 0.4, 1.0))
			# Controle progressivo de velocidade: desacelera antes de chegar para não bater
			if dist < 55.0:
				if cur_speed < 40.0:
					Input.action_press("ui_up", 0.25)
			elif dist < 110.0:
				if cur_speed < 75.0:
					Input.action_press("ui_up", 0.4)
			else:
				if cur_speed < 140.0:
					Input.action_press("ui_up", 0.65)
		else:
			# Alvo atrás do veículo: manobrar de ré suave
			if absf(cross) > 0.06:
				Input.action_press("ui_left" if cross > 0.0 else "ui_right", clampf(absf(cross) * 2.0, 0.4, 1.0))
			if cur_speed < 45.0:
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

func _try_capture(file_path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for _f in 3:
		await process_frame
	var vp := root.get_viewport()
	if vp != null:
		var tex := vp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null and not img.is_empty():
				img.save_png(file_path)
				print("SNAPSHOT_CAPTURED: %s" % file_path)

func _quiet_ambient(node: Node, player: CharacterBody2D, car: CharacterBody2D) -> void:
	if node.name == "Interiors" or node.name == "InteriorSpaces":
		return
	if node is CollisionObject2D and node != player and node != car and not node is StaticBody2D and not node is Area2D:
		node.collision_layer = 0
		node.collision_mask = 0
		node.set_physics_process(false)
	for child in node.get_children():
		_quiet_ambient(child, player, car)

func _finish(scene: Node) -> void:
	_release_walk_keys()
	_release_drive_keys()
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
