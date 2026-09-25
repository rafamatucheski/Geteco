extends SceneTree
## Configurações novas (25/09/2026) e tela de carregamento: abas, opções de vídeo,
## remapeamento por posição (principal/secundária), tecla de mouse, conflito que troca
## de ação, Cancelar desfaz tudo; cortina com barra que avança e sai.
## Não chama Salvar: o settings.cfg do jogador não é tocado.

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void: run.call_deferred()

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func codes(action: String) -> Array:
	var result := []
	for e in root.get_node("GameInput").keyboard_events(action):
		result.append(e.physical_keycode if e is InputEventKey else -int(e.button_index))
	return result

func run() -> void:
	var controls := root.get_node("GameInput")
	var settings := root.get_node("V2Settings")
	controls.reset_bindings()
	var menu: Control = load("res://ui/SettingsMenu.tscn").instantiate()
	root.add_child(menu)
	menu.size = Vector2(1280, 720)
	await process_frame
	menu.open()
	await process_frame
	check(menu._tabs.size() == 3, "três abas: vídeo, áudio, controles")
	for key_name in ["window_mode", "resolution", "vsync", "fps_limit", "show_fps", "render_scale", "msaa", "shadow_quality", "brightness", "master_volume", "music_volume", "sfx_volume", "ambient_volume", "mute_unfocused"]:
		check(menu._widgets.has(key_name), "opção presente: " + key_name)
	var original_scale: float = settings.render_scale
	var scale_slider: HSlider = menu._widgets.render_scale.get_meta("slider")
	scale_slider.value = .7
	check(is_equal_approx(root.scaling_3d_scale, .7), "escala de renderização aplica na hora")
	menu._widgets.fps_limit.select(2)
	menu._widgets.fps_limit.item_selected.emit(2)
	check(Engine.max_fps == 120, "limite de FPS aplica na hora")

	menu._select_tab(2)
	await process_frame
	check(menu._controls_list.get_child_count() > 40, "controles agrupados em linhas (%d)" % menu._controls_list.get_child_count())
	check(codes("move_up") == [KEY_W, KEY_UP], "padrão de Avançar: W e ↑")
	menu._begin_remap("move_up", 1, Button.new())
	menu._input(key(KEY_I))
	check(codes("move_up") == [KEY_W, KEY_I], "trocar a secundária mantém a principal")
	menu._begin_remap("move_up", 1, Button.new())
	menu._input(key(KEY_E))
	check(codes("move_up") == [KEY_W, KEY_E] and codes("interact").is_empty(), "tecla repetida sai da outra ação")
	check(menu._status.text.contains("saiu de"), "aviso diz de onde a tecla saiu")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	mouse.pressed = true
	menu._begin_remap("reload", 1, Button.new())
	menu._input(mouse)
	check(codes("reload") == [KEY_R, -MOUSE_BUTTON_MIDDLE], "aceita botão do mouse")
	menu._begin_remap("horn", 0, Button.new())
	menu._input(key(KEY_TAB))
	check(codes("horn") == [KEY_H] and not menu.remap_action.is_empty(), "Tab é reservada e a captura continua")
	menu._input(key(KEY_ESCAPE))
	check(menu.remap_action.is_empty(), "Esc cancela a captura")
	menu._begin_remap("horn", 0, Button.new())
	menu._input(key(KEY_DELETE))
	check(codes("horn").is_empty(), "Delete limpa a posição")
	check(controls.rebind_slot("fire", 0, key(KEY_ENTER)).ok == false, "Enter recusado")

	menu.close()
	await process_frame
	check(codes("move_up") == [KEY_W, KEY_UP] and codes("interact") == [KEY_E] and codes("horn") == [KEY_H], "Cancelar desfaz os remapeamentos")
	check(is_equal_approx(settings.render_scale, original_scale) and is_equal_approx(root.scaling_3d_scale, original_scale), "Cancelar desfaz o vídeo")
	check(not menu.visible, "tela fecha")
	menu.queue_free()

	var curtain = load("res://runtime/StartupCurtain.gd").new()
	curtain.variant = 1
	root.add_child(curtain)
	await process_frame
	check(curtain.get_node_or_null("/root/LoadingCurtain") == curtain, "cortina fica acessível na raiz para o mundo adotar")
	check(curtain._art.texture != null, "arte da serra carregada")
	curtain.set_stage(.5, "Teste")
	for i in 60: await process_frame
	check(curtain._shown > .3 and curtain._shown <= .56, "barra avança até perto da etapa (%.2f)" % curtain._shown)
	check(curtain._percent.text.ends_with("%"), "percentual visível")
	curtain.set_stage(.2, "Volta?")
	check(curtain._target >= .5, "progresso nunca volta")
	await curtain.lift(2)
	await process_frame
	check(not is_instance_valid(curtain), "cortina sai depois do lift")

	await process_frame
	print("SETTINGS_MENU ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
