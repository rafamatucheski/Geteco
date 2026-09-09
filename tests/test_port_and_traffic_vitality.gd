extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=================================================================")
	print("=== TESTE: PORTO VISIVEL & CIDADE VIVA POS-MORTE DO JOGADOR =====")
	print("=================================================================")
	
	var main_scene = load("res://Main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)
	
	for i in range(15):
		await process_frame

	var player = main.get_node_or_null("Player")
	assert(player != null, "Player deve existir na cena")
	
	# -------------------------------------------------------------
	# PASSO 1: Validar presenca e estrutura do PortMarkedCarSet
	# -------------------------------------------------------------
	print("\n[PASSO 1] Verificando PortMarkedCarSet na arvore de nos...")
	var doc = main.get_node_or_null("DistrictOneComplete")
	assert(doc != null, "DistrictOneComplete deve existir")
	var port = doc.get_node_or_null("PortMarkedCarSet")
	assert(port != null, "PortMarkedCarSet deve existir em DistrictOneComplete")
	
	var ground = port.get_node_or_null("GroundVisuals")
	var buildings = port.get_node_or_null("IndustrialBuildings")
	var containers = port.get_node_or_null("ContainerStacks")
	var crane = port.get_node_or_null("PierGantryCrane")
	var gatehouse = port.get_node_or_null("SecurityGatehouse")
	
	assert(ground != null, "Porto deve ter GroundVisuals")
	assert(buildings != null, "Porto deve ter IndustrialBuildings")
	assert(containers != null, "Porto deve ter ContainerStacks")
	assert(crane != null, "Porto deve ter PierGantryCrane")
	assert(gatehouse != null, "Porto deve ter SecurityGatehouse")
	
	print("  ✓ PortMarkedCarSet instanciado em: ", port.global_position)
	print("  ✓ Nos filhos visuais validados: Ground, Buildings, Containers, Crane, Gatehouse!")
	
	# -------------------------------------------------------------
	# PASSO 2: Testar vitalidade do transito apos a morte do jogador
	# -------------------------------------------------------------
	print("\n[PASSO 2] Testando reposicao e transito apos a morte do jogador...")
	var central = main.get_node_or_null("CentralDistrict")
	assert(central != null, "CentralDistrict deve existir")
	
	var initial_traffic_count = get_nodes_in_group("central_district_traffic").size()
	print("  Carros iniciais no CentralDistrict: ", initial_traffic_count)
	assert(initial_traffic_count > 0, "Deve haver trafego inicial")
	
	# Simular destruicao de carros de transito
	var traffic_nodes = get_nodes_in_group("central_district_traffic")
	for i in range(mini(4, traffic_nodes.size())):
		var car = traffic_nodes[i] as DemoTrafficVehicle
		if car:
			car.take_damage(200)
			
	print("  4 carros foram destruidos violentamente!")
	
	# Simular morte do jogador
	player.global_position = Vector2(870, 600)
	player._wasted()
	print("  Jogador sofreu _wasted()!")
	
	# Aguardar frames e processamento de reposicao
	for f in range(200):
		await process_frame
		
	# Chamar manutencao de trafego
	central._maintain_traffic_population()
	
	var post_death_traffic = get_nodes_in_group("central_district_traffic").size()
	print("  Carros no CentralDistrict apos reposicao pos-morte: ", post_death_traffic)
	assert(post_death_traffic >= 6, "Trafego deve ter sido reposto e manter a cidade viva!")
	
	print("\n=================================================================")
	print("=== SUCESSO: PORTO ATIVO E TRANSITO CONTINUO APROVADOS! =========")
	print("=================================================================")
	quit(0)
