extends SceneTree

func _init() -> void:
	call_deferred("_run_lifecycle_test")

func _run_lifecycle_test() -> void:
	print("=================================================================")
	print("=== TESTE DE CICLO COMPLETO DE JOGO (BOOT, NEW, SAVE, LOAD) ===")
	print("=================================================================")
	
	# 1. Carregar MainMenu
	print("\n[PASSO 1] Instanciando MainMenu (Cena de Boot)...")
	var main_menu_scene := load("res://ui/MainMenu.tscn") as PackedScene
	if not main_menu_scene:
		_fail("Falha ao carregar res://ui/MainMenu.tscn")
		return
	
	var main_menu := main_menu_scene.instantiate()
	root.add_child(main_menu)
	print("  ✓ MainMenu ativo no root")
	
	# 2. Simular Novo Jogo -> Transição para Main.tscn
	print("\n[PASSO 2] Disparando 'Novo Jogo' e carregando Main.tscn...")
	main_menu.queue_free()
	await process_frame
	await process_frame
	
	var main_scene := load("res://legacy/Main.tscn") as PackedScene
	if not main_scene:
		_fail("Falha ao carregar res://legacy/Main.tscn")
		return
	
	var world := main_scene.instantiate()
	root.add_child(world)
	current_scene = world
	print("  ✓ World (Main.tscn) instanciado com sucesso")
	
	# Aguardar alguns frames para inicialização física, HUD, etc.
	for i in range(10):
		await process_frame
	
	var player = get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		_fail("Player não encontrado no mundo")
		return
	print("  ✓ Player localizado em %s, Dinheiro: $%d, Vida: %d" % [str(player.global_position), player.money, player.health])
	
	# 3. Simular gameplay: alterar dinheiro e mover jogador
	print("\n[PASSO 3] Simulando gameplay (alterando dinheiro e posição)...")
	var test_target_pos := Vector2(1820.0, 950.0)
	player.global_position = test_target_pos
	player.money = 12500
	player.health = 75
	player.armor = 40
	
	var wanted = root.get_node_or_null("WantedManager")
	if wanted:
		wanted.current_stars = 2
	
	# 4. Pausar e Salvar Manualmente em slot_01
	print("\n[PASSO 4] Pausando jogo e salvando em slot_01...")
	paused = true
	var sm = root.get_node_or_null("SaveManager")
	if not sm:
		_fail("SaveManager não encontrado")
		return
	
	var save_res: Dictionary = sm.save_game("slot_01", "Checkpoint Lifecycle Test")
	if not save_res.get("success", false):
		_fail("Falha no save_game: %s" % save_res.get("error"))
		return
	print("  ✓ Jogo salvo em slot_01 com sucesso")
	
	# 5. Despausar e alterar estado do mundo (simular avanço ou morte)
	print("\n[PASSO 5] Modificando estado após o save para testar recuperação...")
	paused = false
	player.global_position = Vector2(0, 0)
	player.money = 100
	player.health = 20
	player.armor = 0
	if wanted:
		wanted.current_stars = 0
	print("  ✓ Estado temporário alterado: Pos=%s, Dinheiro=$%d, Stars=%d" % [str(player.global_position), player.money, wanted.current_stars if wanted else 0])
	
	# 6. Carregar slot_01 e aplicar sobre o mundo
	print("\n[PASSO 6] Carregando slot_01 e aplicando restauração...")
	var load_res: Dictionary = sm.load_game("slot_01")
	if not load_res.get("success", false):
		_fail("Falha no load_game: %s" % load_res.get("error"))
		return
	
	var apply_ok: bool = sm.apply_pending_save(self)
	if not apply_ok:
		_fail("apply_pending_save retornou falso")
		return
	
	# 7. Validar se o estado foi 100% restaurado
	print("\n[PASSO 7] Validando dados restaurados:")
	print("  - Posição: %s (Esperado: %s)" % [str(player.global_position), str(test_target_pos)])
	print("  - Dinheiro: $%d (Esperado: $12500)" % player.money)
	print("  - Vida: %d (Esperado: 75)" % player.health)
	print("  - Colete: %d (Esperado: 40)" % player.armor)
	print("  - Estrelas de Procurado: %d (Esperado: 2)" % (wanted.current_stars if wanted else 0))
	
	if player.global_position.distance_to(test_target_pos) > 1.0:
		_fail("Posição do jogador não foi restaurada corretamente")
		return
	if player.money != 12500:
		_fail("Dinheiro do jogador não foi restaurado corretamente")
		return
	if player.health != 75:
		_fail("Vida do jogador não foi restaurada corretamente")
		return
	if player.armor != 40:
		_fail("Colete do jogador não foi restaurado corretamente")
		return
	if wanted and wanted.current_stars != 2:
		_fail("Estrelas de procurado não foram restauradas corretamente")
		return
	
	print("  ✓ Todos os atributos de estado foram restaurados com exatidão!")
	
	# 8. Limpeza de teste
	var slot_path: String = sm.get_slot_path("slot_01")
	if FileAccess.file_exists(slot_path):
		DirAccess.remove_absolute(slot_path)
	
	print("\n=================================================================")
	print("=== SUCESSO: CICLO COMPLETO APROVADO COM ÊXITO! (EXIT 0) ===")
	print("=================================================================")
	await _cleanup_and_quit(world, 0)


func _cleanup_and_quit(world: Node, exit_code: int) -> void:
	if is_instance_valid(world):
		world.process_mode = Node.PROCESS_MODE_DISABLED
		for audio in world.find_children("*", "AudioStreamPlayer", true, false):
			(audio as AudioStreamPlayer).stop()
		for audio in world.find_children("*", "AudioStreamPlayer2D", true, false):
			(audio as AudioStreamPlayer2D).stop()
	await process_frame
	await process_frame
	await process_frame
	quit(exit_code)

func _fail(msg: String) -> void:
	printerr("\n[ERRO FATAL]: %s" % msg)
	quit(1)
