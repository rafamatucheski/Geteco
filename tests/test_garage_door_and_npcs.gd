extends SceneTree

func _init() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("=================================================================")
	print("=== TESTE: PORTA DA GARAGEM, FIM DO BLACKOUT E NPCS =============")
	print("=================================================================")

	var main_scene = load("res://legacy/Main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame

	var dim = main.get_node_or_null("DistrictInteriors") as DistrictInteriorManager
	assert(dim != null, "DistrictInteriors deve existir em Main.tscn")

	# 1. Verificar posições de retorno da Garagem
	print("[PASSO 1] Verificando coordenadas de retorno da garagem no mapa exterior...")
	print("  Posicao da entrada da garagem: %s" % str(dim.common_garage_entrance_position))
	print("  Offset de retorno da garagem: %s" % str(dim.garage_return_offset))
	var exterior_pos = dim.common_garage_entrance_position + dim.garage_return_offset
	print("  Destino exterior ao sair da garagem: %s" % str(exterior_pos))

	assert(exterior_pos.y >= 700.0 and exterior_pos.y <= 1200.0, "O retorno da garagem deve ficar na rua das DOCAS (Y ~ 1064), nao no breu (Y=45)!")
	print("  ✓ Ponto de retorno externo validado: fica na calcada das DOCAS!")

	# 2. Verificar o interior da garagem e a porta de saída
	print("[PASSO 2] Verificando interior da garagem e sensor da porta de saída...")
	var garage = dim.get_node_or_null("InteriorSpaces/CommonGarageInterior") as CentralGarageInterior
	assert(garage != null, "CommonGarageInterior deve existir")

	var exit_door = garage.get_node_or_null("InteriorExit") as BuildingEntrance
	assert(exit_door != null, "InteriorExit deve existir na garagem")

	var sensor = exit_door.get_node_or_null("InteractionArea") as Area2D
	assert(sensor != null, "InteractionArea do exit_door deve existir")
	print("  Posicao do sensor da porta: %s" % str(sensor.position))
	assert(sensor.position.y < 0.0, "O sensor da porta deve ficar voltado para DENTRO da garagem (Y < 0)")
	print("  ✓ Sensor da porta fica no piso da garagem, evitando que o jogador pise no breu!")

	# 3. Verificar NPCs na garagem
	print("[PASSO 3] Verificando presenca dos NPCs na garagem...")
	var jager = garage.get_node_or_null("JagerMaciota")
	assert(jager != null, "Jäger 'Maciota' deve estar presente no lounge VIP da garagem!")
	print("  Jäger 'Maciota' encontrado em: %s" % str(jager.position))

	var tito = garage.get_node_or_null("MechanicTito")
	assert(tito != null, "Mecânico Tito 'Graxa' deve estar presente na oficina da garagem!")
	print("  Mecânico Tito 'Graxa' encontrado em: %s" % str(tito.position))
	print("  ✓ Ambos os NPCs estao ativos e presentes na garagem!")

	# 4. Simular saida da garagem
	print("[PASSO 4] Simulando saida do jogador pela porta da garagem...")
	var player = main.get_node_or_null("Player")
	assert(player != null, "Player deve existir")

	dim.router._on_destination_requested(exit_door, player, &"garage_exterior_return", null, &"")
	await process_frame

	print("  Posicao do jogador apos sair da garagem: %s" % str(player.global_position))
	assert(player.global_position.distance_to(exterior_pos) < 5.0, "Jogador deve estar exatamente na calcada em frente a garagem")
	print("  ✓ Jogador sai na calcada iluminada das DOCAS com sucesso e sem tela preta!")

	print("=================================================================")
	print("=== SUCESSO: TESTE DA GARAGEM E NPCS APROVADO! (EXIT 0) =========")
	print("=================================================================")
	main.queue_free()
	await process_frame
	await process_frame
	quit(0)
