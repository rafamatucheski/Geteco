extends SceneTree
## Contratos de carregamento, foco, preferências e entrada; saves isolados.
const OUT := "res://docs/measurements/premium-ui-0910/"
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func frames(count := 4) -> void:
	for i in count: await process_frame
func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")
func key(code: Key) -> void:
	for pressed in [true,false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await frames(2)
func loading_complete() -> void:
	var loader := root.get_node("GameLoading")
	var deadline := Time.get_ticks_msec()+120000
	var previous := 0.0
	while loader.active and Time.get_ticks_msec()<deadline:
		if is_instance_valid(loader.screen):
			check(loader.screen.target_progress >= previous,"progresso monotônico") if loader.screen.target_progress < previous else null
			previous = loader.screen.target_progress
		await process_frame
	check(not loader.active,"carregamento termina e libera a tela")
func run() -> void:
	create_timer(230).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var temp := OS.get_temp_dir().path_join("geteco_premium_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(temp.path_join("saves"))
	var sm := root.get_node("SettingsManager")
	sm._settings_path = temp.path_join("settings.cfg")
	sm.language = "pt_BR"
	sm.window_mode = 0
	sm.resolution = Vector2i(1280,720)
	sm.apply_all_settings()
	var saves := root.get_node("SaveManager")
	saves._save_dir = temp.path_join("saves")+"/"
	saves._save_directory_ready = false
	var input := root.get_node("GameInput")
	input.reset_bindings()
	var loader := root.get_node("GameLoading")
	loader.begin(temp.path_join("missing_scene.tscn"))
	await frames(6)
	check(loader.screen.recovery.visible,"falha de carregamento oferece retorno")
	loader.screen.recovery.pressed.emit()
	await frames()
	check(not loader.active and not paused,"retorno após falha recupera navegação")
	change_scene_to_file("res://ui/MainMenu.tscn")
	await frames(8)
	var menu := current_scene
	check(not menu.btn_continue.visible,"sem save, Novo jogo é a entrada principal")
	await shot("01_menu")
	menu.btn_load_game.grab_focus()
	await key(KEY_ENTER)
	check(menu.load_panel.is_ancestor_of(root.gui_get_focus_owner()),"foco fica dentro do modal de carregar")
	check(menu.btn_new_game.disabled,"ações atrás do modal bloqueadas")
	await key(KEY_ESCAPE)
	check(not menu.load_panel.visible and not menu.btn_new_game.disabled,"Esc fecha modal e restaura ações")
	menu._on_btn_settings_pressed()
	await frames()
	var settings: Node = menu._settings_instance
	settings._select_tab(2)
	await shot("02_controls")
	var old_bindings: Dictionary = input.export_bindings()
	var event := InputEventKey.new()
	event.physical_keycode = KEY_K
	event.keycode = KEY_K
	check(input.rebind("horn",event).is_empty(),"remapeia buzina para K")
	check(input.hint("horn",true).contains("K") and not input.hint("horn",true).contains("H"),"atalho antigo removido")
	check(not input.rebind("fire",event).is_empty(),"conflito de atalho rejeitado")
	sm.text_scale = 1.25
	settings._on_btn_back_pressed()
	check(input.export_bindings() == old_bindings and is_equal_approx(sm.text_scale,1.0),"Cancelar restaura preferências mesmo sem arquivo anterior")
	menu._on_btn_settings_pressed()
	settings._select_tab(3)
	await shot("03_comfort")
	settings._select_tab(1)
	settings.opt_resolution.select(1)
	settings._on_btn_save_pressed()
	check(settings._video_seconds>0,"troca de resolução exige confirmação")
	settings._video_seconds = 0.01
	await create_timer(0.5).timeout
	check(sm.resolution == Vector2i(1280,720),"vídeo reverte automaticamente sem confirmação")
	settings._on_btn_back_pressed()
	# Variantes independentes de captura; não falseiam o progresso de uma partida.
	for variant in 3:
		var layer := CanvasLayer.new()
		layer.layer = 200
		root.add_child(layer)
		var screen = preload("res://ui/LoadingScreen.gd").new()
		screen.variant = variant
		layer.add_child(screen)
		screen.set_stage(0.52,"Carregando a cidade…")
		await shot("loading_%d" % variant)
		layer.queue_free()
		await frames()
	menu.btn_new_game.pressed.emit()
	check(root.get_node("GameLoading").active,"Novo jogo abre tela de loading")
	check(not root.get_node("GameLoading").begin("res://ui/MainMenu.tscn"),"clique duplo não inicia outra transição")
	await shot("04_loading_live")
	await loading_complete()
	check(current_scene.scene_file_path == "res://world/harbor/HarborGame.tscn","entrada termina no jogo principal")
	var world := current_scene
	check(world.gameplay_ready and world.world_build_ready,"loading aguarda preparo do mundo e gameplay")
	var mission: Node = world.get_node("ArrivalMission")
	mission.skip_cinematic()
	var deadline := Time.get_ticks_msec()+20000
	while mission.phase in ["arrival","disembark","arrival_wait"] and Time.get_ticks_msec()<deadline: await process_frame
	mission.answer_phone()
	for i in 4: mission.advance_dialogue()
	await frames(10)
	var player: Node = world.get_node("Player")
	player.money = 7654
	player.health = 77
	var result: Dictionary = saves.save_game("slot_01","UI review")
	check(result.success,"save isolado criado")
	world.get_node("HUD").set_money(player.money)
	world.get_node("HUD").update_health(player.health)
	await create_timer(1).timeout
	check(world.get_node("Minimap").route_points.size()>1,"rota do objetivo segue segmentos de rua")
	await shot("05_gameplay")
	var pause: Node = world.get_node("PauseMenu")
	pause.pause_game()
	await shot("06_pause")
	pause._modal_mode = "load"
	pause._execute_slot_action("slot_01")
	check(root.get_node("GameLoading").active,"Carregar na pausa abre loading")
	await loading_complete()
	await frames(8)
	player = current_scene.get_node("Player")
	check(player.money == 7654 and player.health == 77,"load restaura dinheiro e vida")
	check(not paused,"load de pausa não deixa a partida congelada")
	# Estados artificiais apenas para revisão de composição dos modais.
	var world_after := current_scene
	var campaign := root.get_node("CampaignState")
	campaign.set_campaign_flag(&"harbor_delivery_complete",true)
	await frames(12)
	var bridge := world_after.get_node("CobraCampaign")
	bridge._toggle_journal()
	await shot("07_journal")
	check(root.gui_get_focus_owner() == bridge._close_button,"diário destaca retorno à partida")
	bridge._toggle_journal()
	var garage: Node = world_after.get_node("Interiors").garage_interior
	player.set_physics_process(false)
	player.global_position = garage.jager_npc.global_position+Vector2(0,30)
	await frames()
	garage.jager_npc._open_dialogue()
	await shot("08_dialogue")
	check(not world_after.get_node("HUD/RootMargin").visible and not world_after.get_node("Minimap").panel.visible,"diálogo limpa HUD e mapa")
	garage.jager_npc._close_dialogue()
	garage.mission_board.interaction_enabled = true
	garage.mission_board.open_chalkboard()
	await shot("09_board")
	garage.mission_board.close_chalkboard()
	player.set_dialogue_active(false)
	player.is_control_disabled = false
	var manager := world_after.get_node("PersonalCarManager")
	manager.car.unlocked = true
	manager.car.velocity = Vector2.ZERO
	player.is_in_dialogue = false
	player.global_position = manager.car.global_position-manager.car.global_transform.x*47
	manager.open_panel()
	check(manager.panel.visible,"arsenal abre para revisão")
	await shot("10_trunk")
	manager.close_panel()
	player.global_position = Vector2(960,760)
	sm.text_scale = 1.25
	sm.interface_changed.emit()
	var scaled_pause := world_after.get_node("PauseMenu")
	scaled_pause.pause_game()
	await shot("11_pause_text125")
	check(root.get_visible_rect().encloses(scaled_pause.root_control.get_node("CenterPanel").get_global_rect()),"pausa com texto 125% cabe em 720p")
	scaled_pause._on_settings_pressed()
	await frames()
	scaled_pause._settings_instance._select_tab(3)
	await shot("12_comfort_text125")
	check(root.get_visible_rect().encloses(scaled_pause._settings_instance.get_node("MainPanel").get_global_rect()),"configurações com texto 125% cabem em 720p")
	scaled_pause._settings_instance._on_btn_back_pressed()
	scaled_pause.resume_game()
	sm.text_scale = 1.0
	sm.interface_changed.emit()
	var touch := preload("res://ui/TouchControls.gd").new()
	world_after.add_child(touch)
	await frames()
	touch._action("fire",true)
	touch._release_all()
	check(not Input.is_action_pressed("fire"),"toque solta disparo ao suspender controles")
	touch.queue_free()
	var pause_after: Node = current_scene.get_node("PauseMenu")
	pause_after._on_main_menu_pressed()
	await frames(12)
	check(current_scene.btn_continue.visible,"save válido oferece Continuar")
	await shot("13_continue")
	for viewport_size in [Vector2i(1920,1080),Vector2i(1600,1000),Vector2i(1920,810)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		await shot("menu_%dx%d" % [viewport_size.x,viewport_size.y])
		check(root.get_visible_rect().size == Vector2(viewport_size),"viewport real %s" % viewport_size)
	sm.apply_display_settings()
	current_scene.btn_continue.pressed.emit()
	check(root.get_node("GameLoading").active,"Continuar abre loading")
	await loading_complete()
	check(current_scene.get_node("Player").money == 7654,"Continuar usa o save válido")
	print("PREMIUM UI: ",failures.size()," falha(s)")
	quit(0 if failures.is_empty() else 1)
