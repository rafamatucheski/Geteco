extends SceneTree

## Automated 3-cycle contract test for Breakwater living interiors.
## Exercises all 7 authored doors + 2 reusable templates with real Player input,
## NPC dialogue advance/cancel, useful contextual interactions, camera bounds, and OutsideReturn points.

const PREVIEW_SCENE: PackedScene = preload("res://district/harbor_preview/HarborPreview.tscn")

var failures: Array[String] = []
var tested_cycles := 0
var completed_dialogues := 0
var completed_interactions := 0

func _init() -> void:
	call_deferred("_run_test")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("TEST_FAILURE: " + message)

func _run_test() -> void:
	print("=================================================================")
	print("=== INICIANDO TESTE DE CONTRATO: INTERIORES VIVOS BREAKWATER ===")
	print("=================================================================")

	var scene = PREVIEW_SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene

	for _f in 10:
		await physics_frame

	var player = scene.get_node_or_null("Player")
	_check(player != null, "Player deve existir em HarborPreview.tscn")
	if player == null:
		_finish(scene)
		return

	var mgr = scene.get_node_or_null("Interiors")
	_check(mgr != null, "HarborInteriorManager ('Interiors') deve existir na cena")
	if mgr == null:
		_finish(scene)
		return

	# Aguardar ligação das portas
	await create_timer(0.3).timeout

	# 1. TESTAR GARAGEM (WESTGATE MOTOR CO.) — 3 CICLOS
	print("\n--- TESTANDO GARAGEM (JÄGER MACIOTA & TITO) ---")
	var garage_entrance = scene.get_node_or_null("District/Garage/Entrance")
	_check(garage_entrance != null, "District/Garage/Entrance deve existir")
	_check(garage_entrance.get("interior_available") == true, "Garage entrance interior_available deve ser true")

	var garage = mgr.garage_interior
	_check(garage != null, "Garage interior deve estar instanciado")
	_check(garage.jager_npc != null, "Jäger 'Maciota' deve estar presente no lounge VIP")
	_check(garage.jager_npc.character_name == "Jäger 'Maciota'", "Nome do Jäger deve ser 'Jäger 'Maciota''")
	_check(garage.tito_pedestrian != null, "Mecânico Tito deve estar presente na bancada")

	for cycle in 3:
		print("  [Garagem] Ciclo %d/3..." % (cycle + 1))
		var entered = await _enter_building(garage_entrance, player)
		_check(bool(entered), "Garage request_interaction falhou no ciclo %d" % cycle)
		await create_timer(0.65).timeout

		# Verificar posição interna e câmera
		_check(player.global_position.distance_to(garage.spawn_point.global_position) < 20.0, "Player deve estar no spawn da garagem")
		_check(player.velocity == Vector2.ZERO, "Velocidade deve ser zero apos entrar")
		var cam = player.get_node_or_null("Camera") as Camera2D
		_check(cam != null and cam.limit_left > -1000000, "Camera limits devem estar ajustados ao interior")

		# Conversar com Jäger
		var jager = garage.jager_npc
		jager._open_dialogue()
		_check(jager.is_talking, "Diálogo com Jäger deve estar aberto")
		_check(player.is_in_dialogue, "Player deve ter is_in_dialogue=true durante conversa")

		# Avançar diálogo e fechar
		jager._advance_dialogue()
		jager._close_dialogue()
		_check(not jager.is_talking, "Diálogo com Jäger deve estar fechado")
		_check(not player.is_in_dialogue, "Player deve restaurar is_in_dialogue=false")
		completed_dialogues += 1

		# Realizar interação contextual (Elevador e Diagnóstico)
		garage._run_diagnostic()
		_check(garage.diagnostic_dialog.visible, "Painel de diagnóstico da garagem deve estar visível")
		garage.diagnostic_dialog.visible = false
		completed_interactions += 1

		# Sair pela porta interior
		var exit_door = garage.exit_door
		_check(exit_door != null, "Porta de saída da garagem deve existir")
		exit_door.destination_requested.emit(exit_door, player, exit_door.destination_id, null, &"")
		await create_timer(0.1).timeout

		# Verificar retorno no OutsideReturn da porta externa
		var outside_return := garage_entrance.get_node("OutsideReturn") as Marker2D
		_check(player.global_position.distance_to(outside_return.global_position) < 5.0, "Player deve retornar ao OutsideReturn da garagem")
		_check(cam.limit_left == -10000000, "Camera limits devem ser restaurados ao exterior")
		_check(player.velocity == Vector2.ZERO, "Velocidade residual deve ser zero apos sair")
		tested_cycles += 1

	# 2. TESTAR DELEGACIA (HARBOR PATROL) — 3 CICLOS
	print("\n--- TESTANDO POLÍCIA (SARGENTO MORALES) ---")
	var police_entrance = scene.get_node_or_null("District/Police/Entrance")
	var police = mgr.police_interior
	_check(police != null and police.sergeant_npc != null, "Delegacia e Sargento Morales devem existir")

	for cycle in 3:
		print("  [Polícia] Ciclo %d/3..." % (cycle + 1))
		var entered = await _enter_building(police_entrance, player)
		_check(bool(entered), "Police request_interaction falhou no ciclo %d" % cycle)
		await create_timer(0.65).timeout

		_check(player.global_position.distance_to(police.spawn_point.global_position) < 20.0, "Player deve estar no spawn da polícia")
		
		# Diálogo
		police.sergeant_npc._open_dialogue()
		police.sergeant_npc._advance_dialogue()
		police.sergeant_npc._close_dialogue()
		completed_dialogues += 1

		# Terminal de ocorrências
		police._open_terminal()
		_check(police.terminal_dialog.visible, "Terminal de ocorrências deve abrir")
		police.terminal_dialog.visible = false
		completed_interactions += 1

		# Sair
		police.exit_door.destination_requested.emit(police.exit_door, player, police.exit_door.destination_id, null, &"")
		await create_timer(0.1).timeout
		var outside_return = police_entrance.get_node("OutsideReturn")
		_check(player.global_position.distance_to(outside_return.global_position) < 5.0, "Player deve retornar ao OutsideReturn da delegacia")
		tested_cycles += 1

	# 3. TESTAR CLÍNICA (BAY MEDICAL - ENTRADA NORTE) — 3 CICLOS
	print("\n--- TESTANDO CLÍNICA (ENFERMEIRA CLARA - ENTRADA NORTE) ---")
	var clinic_entrance = scene.get_node_or_null("District/Clinic/Entrance")
	var clinic = mgr.clinic_interior
	_check(clinic != null and clinic.nurse_npc != null, "Clínica e Enfermeira Clara devem existir")

	for cycle in 3:
		print("  [Clínica] Ciclo %d/3..." % (cycle + 1))
		# Simular jogador com dano para testar cura
		player.health = 50
		var entered = await _enter_building(clinic_entrance, player)
		_check(bool(entered), "Clinic request_interaction falhou no ciclo %d" % cycle)
		await create_timer(0.65).timeout

		_check(player.global_position.distance_to(clinic.spawn_point.global_position) < 20.0, "Player deve estar no spawn da clínica")

		# Diálogo
		clinic.nurse_npc._open_dialogue()
		clinic.nurse_npc._advance_dialogue()
		clinic.nurse_npc._close_dialogue()
		completed_dialogues += 1

		# Triagem e primeiros socorros
		var health_before = player.health
		clinic._apply_first_aid()
		_check(clinic.triage_dialog.visible, "Painel de triagem da clínica deve abrir")
		_check(player.health == health_before, "Triagem médica não deve conceder cura gratuita instantânea")
		clinic.triage_dialog.visible = false
		completed_interactions += 1

		# Sair pela porta norte
		clinic.exit_door.destination_requested.emit(clinic.exit_door, player, clinic.exit_door.destination_id, null, &"")
		await create_timer(0.1).timeout
		var outside_return = clinic_entrance.get_node("OutsideReturn")
		_check(player.global_position.distance_to(outside_return.global_position) < 5.0, "Player deve retornar ao OutsideReturn NORTE da clínica")
		_check(outside_return.position.y > 0, "OutsideReturn da clínica deve estar no norte local da porta invertida")
		tested_cycles += 1

	# 4. TESTAR OFICINA MECÂNICA (NORTHGATE AUTO) — 3 CICLOS
	print("\n--- TESTANDO OFICINA MECÂNICA (MESTRE ARNALDO) ---")
	var workshop_entrance = scene.get_node_or_null("NorthDistrict/MotorWorkshop/Entrance")
	var workshop = mgr.workshop_interior
	_check(workshop != null and workshop.mechanic_npc != null, "Oficina e Mestre Arnaldo devem existir")

	for cycle in 3:
		print("  [Oficina] Ciclo %d/3..." % (cycle + 1))
		var entered = await _enter_building(workshop_entrance, player)
		_check(bool(entered), "Workshop request_interaction falhou no ciclo %d" % cycle)
		await create_timer(0.65).timeout

		_check(player.global_position.distance_to(workshop.spawn_point.global_position) < 20.0, "Player deve estar no spawn da oficina")

		# Diálogo
		workshop.mechanic_npc._open_dialogue()
		workshop.mechanic_npc._advance_dialogue()
		workshop.mechanic_npc._close_dialogue()
		completed_dialogues += 1

		# Bancada de motor
		workshop._run_tuning()
		_check(workshop.bench_dialog.visible, "Bancada de preparação deve abrir")
		workshop.bench_dialog.visible = false
		completed_interactions += 1

		# Sair
		workshop.exit_door.destination_requested.emit(workshop.exit_door, player, workshop.exit_door.destination_id, null, &"")
		await create_timer(0.1).timeout
		var outside_return = workshop_entrance.get_node("OutsideReturn")
		_check(player.global_position.distance_to(outside_return.global_position) < 5.0, "Player deve retornar ao OutsideReturn da oficina")
		tested_cycles += 1

	# 5. TESTAR BOMBEIROS (3 BAIAS INDEPENDENTES) — 3 CICLOS (1 POR BAIA)
	print("\n--- TESTANDO CORPO DE BOMBEIROS (CAPITÃO ROCHA & 3 BAIAS) ---")
	var firehouse = mgr.fire_station_interior
	_check(firehouse != null and firehouse.captain_npc != null, "Quartel e Capitão Rocha devem existir")
	_check(firehouse.bay_exits.size() == 3, "Quartel deve ter exatamente 3 saídas para as baias")

	for bay_idx in 3:
		print("  [Bombeiros] Baia %d..." % bay_idx)
		var fire_door = scene.get_node_or_null("NorthDistrict/NorthFireStation/Entrance%d" % bay_idx)
		_check(fire_door != null, "Porta Entrance%d dos bombeiros deve existir" % bay_idx)

		player.armor = 0
		var entered = await _enter_building(fire_door, player)
		_check(bool(entered), "FireStation bay %d request_interaction falhou" % bay_idx)
		await create_timer(0.65).timeout

		# Verificar spawn na baia correspondente
		var bay_spawn = firehouse.get_spawn_for_bay(bay_idx)
		_check(player.global_position.distance_to(bay_spawn.global_position) < 20.0, "Player deve nascer na baia %d" % bay_idx)

		# Diálogo
		firehouse.captain_npc._open_dialogue()
		firehouse.captain_npc._close_dialogue()
		completed_dialogues += 1

		# Alarme & Simulação
		var armor_before = player.armor
		firehouse._sound_alarm_and_equip()
		_check(firehouse.alarm_dialog.visible, "Painel de prontidão dos bombeiros deve abrir")
		_check(player.armor == armor_before, "Alarme dos bombeiros não deve dar colete gratuito instantâneo")
		firehouse.alarm_dialog.visible = false
		completed_interactions += 1

		# Sair pela baia correspondente
		var bay_exit = firehouse.bay_exits[bay_idx]
		bay_exit.destination_requested.emit(bay_exit, player, bay_exit.destination_id, null, &"")
		await create_timer(0.1).timeout

		var outside_return = fire_door.get_node("OutsideReturn")
		_check(player.global_position.distance_to(outside_return.global_position) < 5.0, "Player deve retornar exatamente à baia Entrance%d de onde entrou" % bay_idx)
		tested_cycles += 1

	# 6. TESTAR TEMPLATES REUTILIZÁVEIS (AMMU-NATION & MORGUE/IML)
	print("\n--- TESTANDO TEMPLATES REUTILIZÁVEIS (AMMU-NATION & IML) ---")
	var ammu = load("res://district/harbor_preview/interiors/HarborAmmunationInterior.gd").new()
	root.add_child(ammu)
	await create_timer(0.1).timeout
	_check(ammu.gunsmith_npc != null, "Template Ammu-Nation deve instanciar Armeiro Vance")
	ammu.gunsmith_npc._open_dialogue()
	ammu.gunsmith_npc._close_dialogue()
	ammu._resupply_ammo()
	_check(ammu.counter_dialog.visible, "Balcão de munição deve responder")
	ammu.counter_dialog.visible = false
	completed_dialogues += 1
	completed_interactions += 1
	ammu.queue_free()

	var morgue = load("res://district/harbor_preview/interiors/HarborMorgueInterior.gd").new()
	root.add_child(morgue)
	await create_timer(0.1).timeout
	_check(morgue.pathologist_npc != null, "Template Morgue deve instanciar Dr. Silveira")
	morgue.pathologist_npc._open_dialogue()
	morgue.pathologist_npc._close_dialogue()
	morgue._read_registry()
	_check(morgue.registry_dialog.visible, "Prancheta forense deve responder")
	morgue.registry_dialog.visible = false
	completed_dialogues += 1
	completed_interactions += 1
	morgue.queue_free()

	print("\n=================================================================")
	print("RESULTADO HARBOR_INTERIORS: failures=%d cycles=%d dialogues=%d interactions=%d" % [
		failures.size(), tested_cycles, completed_dialogues, completed_interactions
	])
	print("=================================================================")

	_finish(scene)

func _enter_building(entrance: Node2D, player: CharacterBody2D) -> bool:
	var state: Dictionary = entrance.get_entrance_state()
	player.global_position = state.approach_position
	# Aguardar porta desocupar (cooldown pós-saída) e sensor detectar o player
	for _i in 40:
		if not entrance.get("_busy") and entrance.is_actor_in_range(player):
			break
		await create_timer(0.05).timeout
	return entrance.request_interaction(player)

func _finish(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
