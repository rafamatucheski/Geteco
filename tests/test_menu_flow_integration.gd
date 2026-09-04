extends SceneTree

## Teste de Integração de Fluxo de Menus (End-to-End Headless)
## Valida o ciclo completo entre cenas:
## MainMenu -> Novo Jogo -> Main.tscn -> PauseMenu (ESC, Salvar, Config, Voltar) -> MainMenu -> Configurações -> Carregar Jogo -> Main.tscn restaurado

const MAIN_MENU_SCENE: String = "res://ui/MainMenu.tscn"
const MAIN_GAME_SCENE: String = "res://Main.tscn"

var failures: Array[String] = []
var step_results: Dictionary = {}

func _init() -> void:
	call_deferred("_run_integration_flow")

func _report_step(step_name: String, success: bool, details: String = "") -> void:
	step_results[step_name] = success
	if success:
		print("  [PASS] %s %s" % [step_name, ("- " + details) if not details.is_empty() else ""])
	else:
		print("  [FAIL] %s - %s" % [step_name, details])
		failures.append("%s: %s" % [step_name, details])

func _run_integration_flow() -> void:
	print("=================================================================")
	print("=== TESTE DE INTEGRAÇÃO DE FLUXO DE MENUS (HEADLESS) ===")
	print("=================================================================")

	var sm = root.get_node_or_null("SaveManager")
	var set_m = root.get_node_or_null("SettingsManager")
	var campaign = root.get_node_or_null("CampaignState")
	var wanted = root.get_node_or_null("WantedManager")

	if not sm or not set_m or not campaign or not wanted:
		_report_step("Autoloads Presentes", false, "Autoloads obrigatórios ausentes")
		_finish()
		return
	_report_step("Autoloads Presentes", true, "SaveManager, SettingsManager, CampaignState e WantedManager ativos")

	# =================================================================
	# ETAPA 1: MainMenu -> "Novo Jogo" -> Transição para Main.tscn
	# =================================================================
	print("\n--- [ETAPA 1] MainMenu -> 'Novo Jogo' -> Main.tscn ---")
	
	# Simular estado modificado pré-novo-jogo para provar reset
	campaign.current_stage = "pre_test_stage"
	wanted.current_stars = 3
	
	var menu_scene := load(MAIN_MENU_SCENE) as PackedScene
	if not menu_scene:
		_report_step("Carregar MainMenu.tscn", false, "Falha ao carregar PackedScene")
		_finish()
		return
	
	var main_menu := menu_scene.instantiate()
	root.add_child(main_menu)
	current_scene = main_menu
	_report_step("Instanciar MainMenu", true, "MainMenu instanciado e adicionado ao root como current_scene")
	
	await process_frame
	await process_frame
	
	var btn_new_game := main_menu.get_node_or_null("%BtnNewGame") as Button
	if not btn_new_game:
		_report_step("Botão Novo Jogo", false, "Nó %BtnNewGame não encontrado no MainMenu")
		_finish()
		return
	
	print("  Acionando sinal 'pressed' do botão Novo Jogo...")
	btn_new_game.pressed.emit()
	
	# Aguardar transição de cena e frames de física/inicialização
	for i in range(15):
		await process_frame
	
	var in_main_scene: bool = (current_scene != null and (current_scene.scene_file_path == MAIN_GAME_SCENE or current_scene.name == "World"))
	_report_step("Transição de Cena para Main.tscn", in_main_scene, "Cena atual: %s" % (current_scene.scene_file_path if current_scene else "null"))
	
	var campaign_reset: bool = (campaign.current_stage != "pre_test_stage")
	var wanted_reset: bool = (wanted.current_stars == 0)
	_report_step("Reset de Estado (CampaignState & Wanted)", campaign_reset and wanted_reset, "Stage: %s, Stars: %d" % [campaign.current_stage, wanted.current_stars])
	
	var player = get_first_node_in_group("player")
	var player_valid: bool = (player != null and is_instance_valid(player))
	_report_step("Player Inicializado no Mundo", player_valid, "Player em %s" % (str(player.global_position) if player_valid else "N/A"))
	
	if not in_main_scene or not player_valid:
		_finish()
		return

	# =================================================================
	# ETAPA 2: PauseMenu dentro de Main.tscn (ESC, Salvar, Config, Voltar)
	# =================================================================
	print("\n--- [ETAPA 2] PauseMenu In-Game (ESC, Salvar, Config, Voltar ao Menu) ---")
	
	# Localizar PauseMenu injetado pelo CityDemo
	var pause_menu = root.find_child("PauseMenu", true, false)
	if not pause_menu:
		# Aguardar mais alguns frames caso deferred ainda esteja pendente
		for i in range(5):
			await process_frame
		pause_menu = root.find_child("PauseMenu", true, false)
	
	var pause_menu_found: bool = (pause_menu != null and is_instance_valid(pause_menu))
	_report_step("PauseMenu Presente no Mundo", pause_menu_found, "PauseMenu localizado na árvore")
	if not pause_menu_found:
		_finish()
		return
	
	# 2.1 Testar abertura via tecla ESC
	var esc_event := InputEventKey.new()
	esc_event.pressed = true
	esc_event.keycode = KEY_ESCAPE
	pause_menu._unhandled_input(esc_event)
	await process_frame
	
	var is_paused: bool = paused
	var pause_visible: bool = pause_menu.visible
	_report_step("Abertura via ESC (Pausa e Visibilidade)", is_paused and pause_visible, "Paused: %s, Visible: %s" % [str(is_paused), str(pause_visible)])
	
	# 2.2 Testar opção 'Salvar' do PauseMenu
	var btn_save := pause_menu.get_node_or_null("%BtnSaveGame") as Button
	var slots_modal = pause_menu.get_node_or_null("%SlotsModal")
	if btn_save and slots_modal:
		btn_save.pressed.emit()
		await process_frame
		var slots_list = pause_menu.get_node_or_null("%SlotsList")
		var save_modal_open: bool = slots_modal.visible and (slots_list != null and slots_list.get_child_count() > 0)
		_report_step("Opção 'Salvar' no PauseMenu", save_modal_open, "Modal de slots aberta com %d slots" % (slots_list.get_child_count() if slots_list else 0))
		# Fechar modal
		var btn_close_modal = pause_menu.get_node_or_null("%BtnCloseModal") as Button
		if btn_close_modal:
			btn_close_modal.pressed.emit()
	else:
		_report_step("Opção 'Salvar' no PauseMenu", false, "BtnSaveGame ou SlotsModal ausente")
	
	# 2.3 Testar opção 'Configurações' do PauseMenu
	var btn_pause_settings := pause_menu.get_node_or_null("%BtnSettings") as Button
	if btn_pause_settings:
		btn_pause_settings.pressed.emit()
		await process_frame
		var pause_settings_inst = pause_menu.get("_settings_instance")
		var settings_opened: bool = (pause_settings_inst != null and is_instance_valid(pause_settings_inst) and pause_settings_inst.visible)
		_report_step("Opção 'Configurações' no PauseMenu", settings_opened, "SettingsMenu instanciado e sobreposto ao PauseMenu")
		if settings_opened:
			pause_settings_inst.closed.emit()
			await process_frame
	else:
		_report_step("Opção 'Configurações' no PauseMenu", false, "BtnSettings ausente no PauseMenu")
	
	# 2.4 Criar um save de teste com estado conhecido antes de sair para o menu
	player.money = 77777
	player.health = 80
	player.armor = 45
	player.global_position = Vector2(1600.0, 900.0)
	var save_res = sm.save_game("slot_01", "Save para Teste de Carregamento")
	_report_step("Criação de Save de Teste em slot_01", save_res.get("success", false), "Dinheiro=$77777, HP=80, Armor=45")
	
	# 2.5 Testar 'Voltar ao Menu' do PauseMenu
	var btn_main_menu := pause_menu.get_node_or_null("%BtnMainMenu") as Button
	if not btn_main_menu:
		_report_step("Opção 'Voltar ao Menu'", false, "BtnMainMenu ausente")
		_finish()
		return
	
	print("  Acionando 'Voltar ao Menu' a partir do PauseMenu...")
	btn_main_menu.pressed.emit()
	for i in range(15):
		await process_frame
	
	var returned_to_main_menu: bool = (current_scene != null and (current_scene.scene_file_path == MAIN_MENU_SCENE or current_scene.name == "MainMenu"))
	var unpaused: bool = not paused
	_report_step("Opção 'Voltar ao Menu' e Despausa", returned_to_main_menu and unpaused, "Cena: %s, Paused: %s" % [(current_scene.scene_file_path if current_scene else "null"), str(paused)])
	
	if not returned_to_main_menu:
		_finish()
		return

	# =================================================================
	# ETAPA 3: MainMenu -> 'Configurações' (Empilhamento e Persistência)
	# =================================================================
	print("\n--- [ETAPA 3] MainMenu -> 'Configurações' (Empilhamento & Persistência) ---")
	
	var active_main_menu = current_scene
	var btn_settings := active_main_menu.get_node_or_null("%BtnSettings") as Button
	if not btn_settings:
		_report_step("Botão Configurações no MainMenu", false, "BtnSettings ausente")
		_finish()
		return
	
	btn_settings.pressed.emit()
	await process_frame
	
	var settings_inst = active_main_menu.get("_settings_instance")
	var settings_stacked: bool = (settings_inst != null and is_instance_valid(settings_inst) and settings_inst.visible and settings_inst.get_parent() == active_main_menu)
	_report_step("SettingsMenu Empilhado sobre MainMenu", settings_stacked, "SettingsMenu adicionado como filho sem descarregar MainMenu")
	
	if settings_stacked:
		# Modificar valor (ex: master volume = 0.42) e salvar
		var slider_master = settings_inst.get_node_or_null("%SliderMaster") as HSlider
		var btn_save_settings = settings_inst.get_node_or_null("%BtnSave") as Button
		
		if slider_master and btn_save_settings:
			slider_master.value = 0.42
			slider_master.value_changed.emit(0.42)
			await process_frame
			
			btn_save_settings.pressed.emit()
			await process_frame
			
			var settings_closed: bool = not settings_inst.visible
			# Verificar persistência no SettingsManager
			set_m.master_volume = 0.0
			set_m.load_settings()
			var persisted: bool = absf(set_m.master_volume - 0.42) < 0.01
			_report_step("Persistência de Configurações (Master Volume)", settings_closed and persisted, "Volume salvo e recarregado: %.2f (esperado 0.42)" % set_m.master_volume)
		else:
			_report_step("Controles de SettingsMenu", false, "SliderMaster ou BtnSave ausente")
	else:
		_report_step("Persistência de Configurações", false, "SettingsMenu não estava aberto")

	# =================================================================
	# ETAPA 4: MainMenu -> 'Carregar Jogo' -> Slot -> Main.tscn Restaurado
	# =================================================================
	print("\n--- [ETAPA 4] MainMenu -> 'Carregar Jogo' -> Carregar slot_01 -> Main.tscn ---")
	
	var btn_load_game := active_main_menu.get_node_or_null("%BtnLoadGame") as Button
	var load_panel := active_main_menu.get_node_or_null("%LoadPanel") as Control
	var slot_list_container := active_main_menu.get_node_or_null("%SlotListContainer") as VBoxContainer
	
	if not btn_load_game or not load_panel or not slot_list_container:
		_report_step("Controles de Carregamento no MainMenu", false, "BtnLoadGame, LoadPanel ou SlotListContainer ausentes")
		_finish()
		return
	
	btn_load_game.pressed.emit()
	await process_frame
	
	var load_panel_open: bool = load_panel.visible and slot_list_container.get_child_count() > 0
	_report_step("Painel de Carregamento Aberto", load_panel_open, "Slots renderizados: %d" % slot_list_container.get_child_count())
	
	# Encontrar botão do slot_01 na lista gerada
	var slot_01_btn: Button = null
	for child in slot_list_container.get_children():
		if child is Button and "SLOT_01" in child.text:
			slot_01_btn = child
			break
	
	var slot_01_ready: bool = (slot_01_btn != null and not slot_01_btn.disabled)
	_report_step("Slot_01 Disponível e Válido", slot_01_ready, "Botão do slot_01 habilitado: %s" % (slot_01_btn.text.strip_edges() if slot_01_btn else "não encontrado"))
	
	if slot_01_ready:
		print("  Selecionando slot_01 para carregamento...")
		slot_01_btn.pressed.emit()
		
		# Aguardar troca de cena para Main.tscn e restauração do save
		for i in range(15):
			await process_frame
		
		var in_game_after_load: bool = (current_scene != null and (current_scene.scene_file_path == MAIN_GAME_SCENE or current_scene.name == "World"))
		_report_step("Transição de Cena pós-Load", in_game_after_load, "Cena: %s" % (current_scene.scene_file_path if current_scene else "null"))
		
		var restored_player = get_first_node_in_group("player")
		var player_restored: bool = false
		if restored_player and is_instance_valid(restored_player):
			var money_match: bool = (int(restored_player.get("money")) == 77777)
			var hp_match: bool = (int(restored_player.get("health")) == 80)
			var armor_match: bool = (int(restored_player.get("armor")) == 45)
			var pos_match: bool = (restored_player.global_position.distance_to(Vector2(1600.0, 900.0)) < 10.0)
			player_restored = money_match and hp_match and armor_match and pos_match
			_report_step("Estado do Jogador Restaurado pelo Save", player_restored, "Money=$%d (esp 77777), HP=%d (esp 80), Armor=%d (esp 45), Pos=%s" % [
				restored_player.money, restored_player.health, restored_player.armor, str(restored_player.global_position)
			])
		else:
			_report_step("Estado do Jogador Restaurado pelo Save", false, "Player não encontrado após carregar save")
	else:
		_report_step("Transição de Cena pós-Load", false, "Slot_01 não pôde ser acionado")

	_finish()

func _finish() -> void:
	print("\n=================================================================")
	print("=== RESULTADOS FINAIS DA INTEGRAÇÃO DE FLUXO DE MENUS ===")
	print("=================================================================")
	for step in step_results.keys():
		var status = "PASS" if step_results[step] else "FAIL"
		print("  [%s] %s" % [status, step])
	
	print("-----------------------------------------------------------------")
	if failures.is_empty():
		print("=== SUCESSO COMPLETO: FLUXO DE MENUS 100% FUNCIONAL! (EXIT 0) ===")
		quit(0)
	else:
		printerr("=== FALHAS DETECTADAS (%d) ===" % failures.size())
		for f in failures:
			printerr("  - %s" % f)
		quit(1)
