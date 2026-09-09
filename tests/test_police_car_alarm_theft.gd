extends SceneTree

func _init() -> void:
	call_deferred("_run_police_test")

func _run_police_test() -> void:
	print("=================================================================")
	print("=== TESTE: VIATURAS REAIS DA PM, ALARME ANTI-FURTO E 2 ESTRELAS ===")
	print("=================================================================")
	
	var failures: Array[String] = []
	
	# 1. Carregar WantedManager se não estiver ativo
	var wanted_manager = root.get_node_or_null("WantedManager")
	if not wanted_manager:
		var wanted_script = load("res://WantedManager.gd")
		wanted_manager = Node.new()
		wanted_manager.name = "WantedManager"
		wanted_manager.set_script(wanted_script)
		root.add_child(wanted_manager)
		
	wanted_manager.reset_crime()
	print("[PASSO 1] WantedManager inicializado (Estrelas atuais: %d)" % wanted_manager.current_stars)
	if wanted_manager.current_stars != 0:
		failures.append("WantedManager deveria iniciar com 0 estrelas")
		
	# 2. Instanciar EmergencyDepots.tscn (que contém DocksAlleyUnit e WarehouseAlleyUnit da foto do usuário)
	print("\n[PASSO 2] Instanciando cena de viaturas de prontidão (EmergencyDepots.tscn)...")
	var depots_scene = load("res://world/shared/emergency/EmergencyDepots.tscn") as PackedScene
	if not depots_scene:
		printerr("Falha ao carregar res://world/shared/emergency/EmergencyDepots.tscn")
		quit(1)
		return
		
	var depots_node = depots_scene.instantiate()
	root.add_child(depots_node)
	await process_frame
	await process_frame
	
	var docks_unit = depots_node.get_node_or_null("DocksAlleyUnit") as EmergencyStandbyPoint
	if not docks_unit:
		failures.append("DocksAlleyUnit não encontrado em EmergencyDepots")
		quit(1)
		return
		
	var cruiser = docks_unit.parked_car
	if not is_instance_valid(cruiser):
		failures.append("EmergencyStandbyPoint não instanciou a viatura real da PM")
		quit(1)
		return
		
	print("  ✓ Viatura real da PM spawnada no pátio: %s" % cruiser.name)
	print("  - Posição global da viatura: %s" % str(cruiser.global_position))
	print("  - Rotação da viatura: %f" % cruiser.global_rotation)
	print("  - É viatura policial? %s" % str(cruiser.is_police_vehicle))
	print("  - Archetype ativo: %s (%s)" % [cruiser.active_archetype_id, cruiser.display_name])
	
	if not cruiser.is_police_vehicle:
		failures.append("Viatura deveria estar com is_police_vehicle = true")
	if cruiser.active_archetype_id != "police_cruiser":
		failures.append("Viatura deveria ter archetype police_cruiser")
	if cruiser.visual.texture == null:
		failures.append("Sprite visual da viatura está sem textura")
	else:
		print("  ✓ Textura oficial da viatura carregada: %s (Tamanho: %s)" % [cruiser.visual.texture.resource_path, str(cruiser.visual.texture.get_size())])
		
	# 3. Simular jogador chegando perto e tentando roubar a viatura
	print("\n[PASSO 3] Simulando jogador furtando a viatura da PM...")
	var player = CharacterBody2D.new()
	var player_script = load("res://Player.gd")
	player.set_script(player_script)
	var player_camera := Camera2D.new()
	player_camera.name = "Camera"
	player.add_child(player_camera)
	player.add_to_group("player")
	root.add_child(player)
	player.global_position = cruiser.global_position + Vector2(-15, 0)
	await process_frame
	
	# Jogador entra na viatura
	cruiser.enter_vehicle(player)
	await process_frame
	
	print("  - Jogador ao volante? %s" % str(cruiser.is_driven_by_player))
	print("  - Alarme disparou? %s (Timer: %.1fs)" % [str(cruiser.is_alarm_active), cruiser.alarm_timer])
	print("  - Áudio de alarme tocando? %s" % str(cruiser.alarm_audio != null and cruiser.alarm_audio.playing))
	print("  - Estrelas de procurado agora: %d" % wanted_manager.current_stars)
	print("  - Ponto de prontidão disponível? %s" % str(docks_unit.available))
	
	if not cruiser.is_driven_by_player:
		failures.append("Jogador falhou em entrar na viatura da PM")
	if not cruiser.is_alarm_active:
		failures.append("O alarme da viatura NÃO disparou ao ser roubada!")
	if wanted_manager.current_stars < 2:
		failures.append("O furto da viatura NÃO chamou a polícia com 2 estrelas! Estrelas atuais: %d" % wanted_manager.current_stars)
	if docks_unit.available:
		failures.append("O ponto de prontidão da viatura deveria estar desocupado (available = false) após o furto")
		
	# 4. Testar strobes / giroflex e sirene
	print("\n[PASSO 4] Testando animação de strobes (giroflex) e sirene...")
	cruiser._physics_process(0.1)
	var prop = cruiser.active_roof_prop_node
	if not prop:
		failures.append("Viatura não possui nó de giroflex ativo (active_roof_prop_node)")
	else:
		var blue = prop.get_node_or_null("LightBlue")
		var red = prop.get_node_or_null("LightRed")
		var halo = prop.get_node_or_null("SirenHalo")
		if not blue or not red or not halo:
			failures.append("Giroflex da viatura não possui nós LightBlue, LightRed ou SirenHalo")
		else:
			print("  ✓ Giroflex com strobes azul, vermelho e halo dinâmico validados com sucesso!")
			
	# Testar toggle da sirene
	cruiser.toggle_siren()
	print("  - Sirene manual ligada? %s (Áudio: %s)" % [str(cruiser.is_siren_on), str(cruiser.siren_audio.playing)])
	cruiser.toggle_siren()
	print("  - Sirene manual desligada? %s" % str(cruiser.is_siren_on))
	
	# 5. Testar saída segura
	print("\n[PASSO 5] Testando ejeção voluntária e desativação de alarme...")
	cruiser.exit_vehicle()
	await process_frame
	print("  - Jogador saiu da viatura? %s" % str(not cruiser.is_driven_by_player))
	
	cruiser.queue_free()
	depots_node.queue_free()
	player.queue_free()
	
	print("\n=================================================================")
	if failures.is_empty():
		print("=== SUCESSO: TODAS AS VERIFICAÇÕES DE VIATURA DA PM PASSARAM! (EXIT 0) ===")
		print("=================================================================")
		quit(0)
	else:
		printerr("=== FALHAS ENCONTRADAS (%d) ===" % failures.size())
		for f in failures:
			printerr("  - %s" % f)
		print("=================================================================")
		quit(1)
