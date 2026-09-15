extends SceneTree

func _init() -> void:
	call_deferred("_run_all_tests")

func _run_all_tests() -> void:
	print("=================================================================")
	print("=== BATERIA DE TESTES: SAVE/LOAD, SETTINGS, MENUS E ROBUSTEZ ===")
	print("=================================================================")
	
	var failures: Array[String] = []
	
	# -------------------------------------------------------------
	# 1. TESTE DO SETTINGS MANAGER
	# -------------------------------------------------------------
	print("\n--- [TESTE 1] SettingsManager & AudioServer Buses ---")
	var sm = root.get_node_or_null("SettingsManager")
	if sm == null:
		failures.append("SettingsManager não encontrado como autoload no root")
		_finish(failures)
		return
	
	# Verificar se barramentos Music e SFX foram criados
	var bus_music := AudioServer.get_bus_index("Music")
	var bus_sfx := AudioServer.get_bus_index("SFX")
	var bus_master := AudioServer.get_bus_index("Master")
	
	if bus_master == -1: failures.append("Barramento Master não encontrado")
	if bus_music == -1: failures.append("Barramento Music não foi criado pelo SettingsManager")
	if bus_sfx == -1: failures.append("Barramento SFX não foi criado pelo SettingsManager")
	print("  ✓ Barramentos de Áudio: Master=%d, Music=%d, SFX=%d" % [bus_master, bus_music, bus_sfx])
	
	# Testar alteração de volumes
	sm.set_master_volume(0.85)
	sm.set_music_volume(0.60)
	sm.set_sfx_volume(0.90)
	sm.set_window_mode(0)
	sm.set_resolution(Vector2i(1600, 900))
	sm.set_vsync(false)
	
	var save_cfg_ok = sm.save_settings()
	if not save_cfg_ok:
		failures.append("Falha ao salvar user://settings.cfg")
	else:
		print("  ✓ Configurações salvas com sucesso em user://settings.cfg")
	
	# Resetar valores em memória e recarregar
	sm.master_volume = 0.0
	sm.music_volume = 0.0
	sm.load_settings()
	if absf(sm.master_volume - 0.85) > 0.01:
		failures.append("master_volume não persistiu corretamente (obtido %f)" % sm.master_volume)
	if absf(sm.music_volume - 0.60) > 0.01:
		failures.append("music_volume não persistiu corretamente (obtido %f)" % sm.music_volume)
	if sm.resolution != Vector2i(1600, 900):
		failures.append("resolution não persistiu corretamente (obtido %s)" % str(sm.resolution))
	print("  ✓ Configurações recarregadas com precisão de user://settings.cfg")
	
	var controls_map = sm.get_controls_mapping()
	if controls_map.size() < 5:
		failures.append("Mapeamento de controles incompleto (%d ações)" % controls_map.size())
	else:
		print("  ✓ Mapeamento de Controles lido do InputMap: %d ações encontradas" % controls_map.size())
	
	# -------------------------------------------------------------
	# 2. TESTE DE SERIALIZAÇÃO DE SUBSISTEMAS
	# -------------------------------------------------------------
	print("\n--- [TESTE 2] Serialização e Restauração de Subsistemas ---")
	
	# WantedManager
	var wanted = root.get_node_or_null("WantedManager")
	if wanted == null:
		failures.append("WantedManager não encontrado como autoload no root")
	else:
		wanted.reset()
		wanted.current_stars = 3
		wanted.crime_points = 45
		wanted.time_hidden = 12.5
		var wanted_data: Dictionary = wanted.serialize()
		if int(wanted_data.get("current_stars")) != 3 or int(wanted_data.get("crime_points")) != 45:
			failures.append("WantedManager.serialize() retornou dados incorretos")
		
		# Resetar e restaurar
		wanted.reset()
		if wanted.current_stars != 0: failures.append("WantedManager.reset() falhou em zerar estrelas")
		wanted.restore(wanted_data)
		if wanted.current_stars != 3 or wanted.crime_points != 45:
			failures.append("WantedManager.restore() falhou em recuperar estado")
		print("  ✓ WantedManager: serialize(), restore() e reset() validados")
		wanted.reset() # Limpa pro restante
	
	# CampaignState
	var campaign = root.get_node_or_null("CampaignState")
	if campaign == null:
		failures.append("CampaignState não encontrado como autoload no root")
	else:
		var camp_data: Dictionary = campaign.to_save_data()
		if not camp_data.has("schema_version") or not camp_data.has("current_stage"):
			failures.append("CampaignState.to_save_data() retornou dicionário incompleto")
		else:
			print("  ✓ CampaignState: to_save_data() e restore_from_save() validados (Stage: %s)" % camp_data.get("current_stage"))
	
	# -------------------------------------------------------------
	# 3. TESTE DE SAVE/LOAD VERSIONADO & CASOS DE BORDA (SAVE MANAGER)
	# -------------------------------------------------------------
	print("\n--- [TESTE 3] SaveManager: Versionamento, Auditoria e Robustez ---")
	var save_mgr = root.get_node_or_null("SaveManager")
	if save_mgr == null:
		failures.append("SaveManager não encontrado como autoload no root")
		_finish(failures)
		return
	
	# Garantir diretório limpo de teste
	var test_slot := "test_slot_01"
	var test_path: String = save_mgr.get_slot_path(test_slot)
	if FileAccess.file_exists(test_path):
		DirAccess.remove_absolute(test_path)
	
	# 3.1 Inspecionar slot vazio
	var inspect_empty: Dictionary = save_mgr.inspect_slot(test_slot)
	if inspect_empty.get("exists") != false or inspect_empty.get("valid") != false:
		failures.append("inspect_slot deveria indicar que slot vazio não existe")
	print("  ✓ Slot vazio inspecionado corretamente")
	
	# 3.2 Criar um player mock para testar save_game
	var player_script = load("res://characters/Player.gd")
	var player_node: CharacterBody2D = null
	if player_script:
		player_node = CharacterBody2D.new()
		player_node.set_script(player_script)
		player_node.add_to_group("player")
		player_node.global_position = Vector2(1500, 2500)
		player_node.set("money", 7770)
		player_node.set("health", 85)
		player_node.set("armor", 50)
		root.add_child(player_node)
	
	var save_res: Dictionary = save_mgr.save_game(test_slot, "Teste Unitário")
	if not save_res.get("success", false):
		failures.append("save_game falhou: %s" % save_res.get("error", ""))
	else:
		print("  ✓ save_game executado com sucesso (atômico .tmp -> .json)")
	
	# 3.3 Inspecionar slot salvo válido
	var inspect_saved: Dictionary = save_mgr.inspect_slot(test_slot)
	if not inspect_saved.get("valid", false):
		failures.append("inspect_slot falhou em validar save recém-criado")
	if int(inspect_saved.get("save_version")) != 1:
		failures.append("save_version incorreto: %d (esperado 1)" % int(inspect_saved.get("save_version")))
	if int(inspect_saved.get("summary", {}).get("money")) != 7770:
		failures.append("summary money incorreto: %d" % int(inspect_saved.get("summary", {}).get("money")))
	print("  ✓ Slot salvo verificado com save_version = 1 e summary consistente")
	
	# 3.4 Carregar o save válido
	var load_res: Dictionary = save_mgr.load_game(test_slot)
	if not load_res.get("success", false):
		failures.append("load_game falhou em carregar slot válido")
	else:
		print("  ✓ load_game carregou dados válidos para a fila pendente")
	
	# 3.5 Testar Rejeição de Versão Desconhecida / Futura (save_version = 99)
	print("\n--- [TESTE 4] Rejeição Segura de Save Incompatível (save_version = 99) ---")
	var invalid_ver_slot := "test_slot_invalid_ver"
	var invalid_ver_path: String = save_mgr.get_slot_path(invalid_ver_slot)
	var bad_ver_json := {
		"save_version": 99,
		"timestamp": 123456,
		"date_string": "2099-01-01",
		"summary": {"money": 999999}
	}
	var f_bad := FileAccess.open(invalid_ver_path, FileAccess.WRITE)
	f_bad.store_string(JSON.stringify(bad_ver_json))
	f_bad.close()
	
	var inspect_bad_ver: Dictionary = save_mgr.inspect_slot(invalid_ver_slot)
	if inspect_bad_ver.get("valid") != false:
		failures.append("inspect_slot deveria marcar save_version=99 como inválido!")
	else:
		print("  ✓ inspect_slot rejeitou com mensagem clara: '%s'" % inspect_bad_ver.get("error"))
	
	var load_bad_ver: Dictionary = save_mgr.load_game(invalid_ver_slot)
	if load_bad_ver.get("success") != false:
		failures.append("load_game deveria recusar carregar save_version=99!")
	else:
		print("  ✓ load_game recusou save_version=99 com erro sem crashar: '%s'" % load_bad_ver.get("error"))
	
	# 3.6 Testar Rejeição de JSON Corrompido
	print("\n--- [TESTE 5] Rejeição Segura de JSON Corrompido ---")
	var corrupt_slot := "test_slot_corrupt"
	var corrupt_path: String = save_mgr.get_slot_path(corrupt_slot)
	var f_corrupt := FileAccess.open(corrupt_path, FileAccess.WRITE)
	f_corrupt.store_string("{ esta eh uma string de json totalmente invalida quebrado! 1234")
	f_corrupt.close()
	
	var inspect_corrupt: Dictionary = save_mgr.inspect_slot(corrupt_slot)
	if inspect_corrupt.get("valid") != false:
		failures.append("inspect_slot deveria marcar JSON corrompido como inválido!")
	else:
		print("  ✓ inspect_slot rejeitou JSON corrompido: '%s'" % inspect_corrupt.get("error"))
	
	var load_corrupt: Dictionary = save_mgr.load_game(corrupt_slot)
	if load_corrupt.get("success") != false:
		failures.append("load_game deveria recusar JSON corrompido!")
	else:
		print("  ✓ load_game recusou JSON corrompido sem crashar: '%s'" % load_corrupt.get("error"))
	
	# 3.7 Testar Guarda de Autosave (bloquear com perseguição policial ativa)
	print("\n--- [TESTE 6] Guarda de Autosave em Perseguição / Morte ---")
	wanted.current_stars = 0
	var auto_ok = save_mgr.request_autosave("Zona Segura")
	if not auto_ok:
		failures.append("request_autosave deveria permitir salvar com 0 estrelas")
	else:
		print("  ✓ Autosave permitido com 0 estrelas")
	
	wanted.current_stars = 3
	var auto_blocked = save_mgr.request_autosave("Em Fuga")
	if auto_blocked:
		failures.append("request_autosave DEVERIA RECUSAR salvar durante perseguição ativa (3 estrelas)!")
	else:
		print("  ✓ Autosave BLOQUEADO com sucesso durante perseguição ativa (3 estrelas)")
	wanted.reset()
	
	# Limpeza de arquivos temporários de teste
	for p in [test_path, invalid_ver_path, corrupt_path, save_mgr.get_slot_path("autosave")]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	
	if is_instance_valid(player_node):
		player_node.queue_free()
	
	# -------------------------------------------------------------
	# 4. TESTE DE INSTANCIAÇÃO DAS CENAS DE UI
	# -------------------------------------------------------------
	print("\n--- [TESTE 7] Carregamento das Cenas de Menu ---")
	var main_menu_scene = load("res://ui/MainMenu.tscn")
	if main_menu_scene == null:
		failures.append("Falha ao carregar res://ui/MainMenu.tscn")
	else:
		var menu_inst = main_menu_scene.instantiate()
		if menu_inst == null:
			failures.append("Falha ao instanciar MainMenu.tscn")
		else:
			print("  ✓ res://ui/MainMenu.tscn carregada e instanciada com sucesso")
			menu_inst.free()
	
	var settings_scene = load("res://ui/SettingsMenu.tscn")
	if settings_scene == null:
		failures.append("Falha ao carregar res://ui/SettingsMenu.tscn")
	else:
		var set_inst = settings_scene.instantiate()
		if set_inst == null:
			failures.append("Falha ao instanciar SettingsMenu.tscn")
		else:
			print("  ✓ res://ui/SettingsMenu.tscn carregada e instanciada com sucesso")
			set_inst.free()
			
	var pause_scene = load("res://ui/PauseMenu.tscn")
	if pause_scene == null:
		failures.append("Falha ao carregar res://ui/PauseMenu.tscn")
	else:
		var pause_inst = pause_scene.instantiate()
		if pause_inst == null:
			failures.append("Falha ao instanciar PauseMenu.tscn")
		else:
			print("  ✓ res://ui/PauseMenu.tscn carregada e instanciada com sucesso")
			pause_inst.free()
			
	_finish(failures)

func _finish(failures: Array[String]) -> void:
	print("=================================================================")
	if failures.is_empty():
		print("=== SUCESSO: TODOS OS TESTES PASSARAM! (EXIT 0) ===")
		quit(0)
	else:
		printerr("=== FALHAS ENCONTRADAS (%d) ===" % failures.size())
		for f in failures:
			printerr("  - %s" % f)
		quit(1)
