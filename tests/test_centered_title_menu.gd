extends SceneTree
## Read-only menu navigation: never starts a session or writes a player save.
var failures: Array[String] = []
var output := "res://evidence/centered-title-menu/"
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures.append(message)
func shot(file: String) -> void:
	await create_timer(.2).timeout
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + file + ".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.get_node("V2Launch").direct_start_consumed = true
	TranslationServer.set_locale("pt_BR")
	root.size = Vector2i(1280, 720)
	var menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await create_timer(.6).timeout
	check(menu.presentation.artwork.texture != null, "fundo ilustrado carregado")
	for button in menu.presentation.buttons:
		if not button.visible: continue
		check(absf(button.get_global_rect().get_center().x - menu.size.x * .5) < 2, "botão centralizado: " + button.text)
	await shot("main")
	menu.btn_load_game.pressed.emit()
	check(menu.get_node("%LoadPanel").visible and not menu.presentation.main_content.visible, "saves substituem ações mantendo fundo")
	check(not menu.btn_import.disabled and menu.btn_import.is_visible_in_tree(), "importação permanece acessível nos saves")
	await shot("saves")
	menu.btn_import.pressed.emit()
	menu.import_dialog.hide()
	menu.import_dialog.canceled.emit()
	check(menu.get_node("%LoadPanel").visible and menu.btn_import.has_focus(), "cancelar importação retorna aos saves")
	menu._close_slots()
	check(menu.btn_load_game.has_focus(), "voltar restaura foco")
	menu.btn_settings.pressed.emit()
	check(menu.settings.visible and not menu.presentation.main_content.visible, "configurações substituem ações")
	for tab in 3:
		menu.settings._select_tab(tab)
		await shot("settings-%d" % tab)
	menu.settings.close()
	check(menu.presentation.main_content.visible and menu.btn_settings.has_focus(), "fechar configurações restaura menu e foco")
	menu.btn_new_game.pressed.emit()
	check(menu.selecting_new and menu.get_node("%LoadPanel").visible, "novo jogo abre slots sem iniciar nem sobrescrever saves")
	await shot("new-game")
	menu._close_slots()
	root.size = Vector2i(1024, 768)
	await shot("main-4x3")
	check(not menu.sky.loading and not is_instance_valid(menu.sky.world), "nenhum mundo carregado durante navegação")
	print("CENTERED_MENU ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
