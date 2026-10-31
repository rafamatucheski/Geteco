extends SceneTree
## Configurações novas (25/09/2026) e tela de carregamento: abas, opções de vídeo,
## remapeamento por posição (principal/secundária), tecla de mouse, conflito que troca
## de ação, Cancelar desfaz tudo; cortina com barra que avança e sai.
## Não chama Salvar: o settings.cfg do jogador não é tocado.

var failures: Array[String] = []

class ControllerMap extends "res://ui/hud/MapUI.gd":
	# Exercise the production input handler without unrelated region cartography.
	func _ready() -> void: set_process(false)
	# Nenhum mundo/conexão do mapa é criado por esta fixture só de entrada.
	func _exit_tree() -> void: pass

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void: run.call_deferred()

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func pad(button: JoyButton, pressed := true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event

func trigger(value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = JOY_AXIS_TRIGGER_RIGHT
	event.axis_value = value
	return event

func binding_button(menu: Control, action: String, slot := "pad") -> Button:
	for button in menu._controls_list.find_children("*", "Button", true, false):
		if button.get_meta("binding_key", "") == action + ":" + slot: return button
	return null

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
	check(menu._tabs.size() == 4, "quatro abas: vídeo, áudio, controles e ajuda")
	menu._select_tab(3)
	await process_frame
	check(menu._pages[3].visible and not menu._defaults_button.visible, "ajuda tem página própria sem restaurar configurações")
	check(menu._help_bindings.text.contains(controls.prompt("interact")), "ajuda usa o atalho atual de conversa")
	var help_topics: Array = menu._pages[3].find_children("*", "Label", true, false).filter(func(node): return node.focus_mode == Control.FOCUS_ALL)
	check(help_topics.size() == 6, "tópicos da ajuda permitem leitura pelo foco do controle")
	help_topics[-1].grab_focus()
	for frame in 4: await process_frame
	var last_topic: Control = help_topics[-1]
	var help_view: Rect2 = menu._pages[3].get_global_rect()
	check(help_view.encloses(last_topic.get_global_rect()), "último tópico da ajuda fica inteiramente visível após receber foco")
	var help_scale: float = settings.render_scale
	menu._restore_tab_defaults()
	check(is_equal_approx(settings.render_scale, help_scale), "ajuda não altera opções ao restaurar padrões")
	for key_name in ["window_mode", "resolution", "vsync", "fps_limit", "show_fps", "render_scale", "msaa", "shadow_quality", "brightness", "master_volume", "music_volume", "sfx_volume", "ambient_volume", "vehicle_volume", "radio_volume", "dialogue_volume", "ui_volume", "mute_unfocused", "voice_language"]:
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
	for action in ["skate_ollie", "skate_flip", "skate_shove", "radio_toggle", "camera_left", "camera_right"]:
		check(binding_button(menu, action) != null, "ação atual remapeável: " + action)
	check(menu._context_choice.item_count == 8, "guia cobre exploração, combate, veículos, esportes, câmera e menus")
	menu._context_choice.select(3)
	menu._context_choice.item_selected.emit(3)
	check(menu._pad_diagram.context == 3, "seletor abre o guia do skate")
	menu._unhandled_input(pad(JOY_BUTTON_RIGHT_SHOULDER))
	check(menu._tab == 3, "R1 abre ajuda depois de controles")
	menu._unhandled_input(pad(JOY_BUTTON_RIGHT_SHOULDER))
	check(menu._tab == 0, "R1 circula da ajuda para a primeira aba")
	menu._unhandled_input(pad(JOY_BUTTON_LEFT_SHOULDER))
	check(menu._tab == 3, "L1 volta à ajuda")
	menu._unhandled_input(pad(JOY_BUTTON_LEFT_SHOULDER))
	check(menu._tab == 2, "L1 volta da ajuda aos controles")
	menu._begin_remap("skate_flip", 0, binding_button(menu, "skate_flip"), true)
	menu._input(pad(JOY_BUTTON_RIGHT_SHOULDER))
	check(menu.remap_action.is_empty() and menu._tab == 2, "ombro durante captura remapeia sem trocar de aba")
	check(controls.gamepad_events("skate_flip").size() == 1 and controls.gamepad_events("weapon_next").size() == 1 and controls.gamepad_events("radio_next").size() == 1, "remap de skate preserva arma e rádio contextuais")
	check(codes("move_up") == [KEY_W, KEY_UP], "padrão de Avançar: W e ↑")
	menu._begin_remap("move_up", 1, binding_button(menu, "move_up", "1"))
	menu._input(key(KEY_I))
	check(codes("move_up") == [KEY_W, KEY_I], "trocar a secundária mantém a principal")
	menu._begin_remap("move_up", 1, binding_button(menu, "move_up", "1"))
	menu._input(key(KEY_E))
	check(codes("move_up") == [KEY_W, KEY_E] and codes("interact").is_empty(), "tecla repetida sai da outra ação")
	var conflict_notice := String(TranslationServer.translate("%s saiu de \"%s\".")) % [controls.event_label(key(KEY_E)), controls.label("interact")]
	check(menu._status.text == conflict_notice, "aviso localizado identifica tecla e ação de origem")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	mouse.pressed = true
	menu._begin_remap("reload", 1, binding_button(menu, "reload", "1"))
	menu._input(mouse)
	check(codes("reload") == [KEY_R, -MOUSE_BUTTON_MIDDLE], "aceita botão do mouse")
	menu._begin_remap("horn", 0, binding_button(menu, "horn", "0"))
	menu._input(key(KEY_TAB))
	check(codes("horn") == [KEY_H] and not menu.remap_action.is_empty(), "Tab é reservada e a captura continua")
	menu._input(key(KEY_ESCAPE))
	check(menu.remap_action.is_empty(), "Esc cancela a captura")
	menu._begin_remap("horn", 0, binding_button(menu, "horn", "0"))
	menu._input(key(KEY_DELETE))
	check(codes("horn").is_empty(), "Delete limpa a posição")
	check(controls.rebind_slot("fire", 0, key(KEY_ENTER)).ok == false, "Enter recusado")
	menu._choose_control_mode(1)
	check(binding_button(menu,"horn").is_visible_in_tree(),"foco de remapeamento do controle usa a coluna visível")
	binding_button(menu, "horn").grab_focus()
	controls.set_controller_layout(1)
	controls.set_controller_layout(2)
	await process_frame
	check(root.gui_get_focus_owner() == binding_button(menu, "horn"), "reconstruções seguidas restauram foco no botão atual")

	menu.close()
	await process_frame
	check(codes("move_up") == [KEY_W, KEY_UP] and codes("interact") == [KEY_E] and codes("horn") == [KEY_H], "Cancelar desfaz os remapeamentos")
	check(is_equal_approx(settings.render_scale, original_scale) and is_equal_approx(root.scaling_3d_scale, original_scale), "Cancelar desfaz o vídeo")
	check(not menu.visible, "tela fecha")
	var focus_after_close := root.gui_get_focus_owner()
	check(focus_after_close == null or not menu.is_ancestor_of(focus_after_close), "fechar não restaura foco na lista oculta")
	menu.queue_free()

	var map := ControllerMap.new()
	map.controller = {"session": {"modal": true}}
	root.add_child(map)
	var saved_pad: Dictionary = controls.export_gamepad_bindings()
	controls.rebind_gamepad("weapon_next", pad(JOY_BUTTON_DPAD_RIGHT))
	map._input(pad(JOY_BUTTON_DPAD_RIGHT))
	check(is_equal_approx(map.target_zoom, 1.25), "mapa usa o botão remapeado para aproximar")
	map._input(pad(JOY_BUTTON_RIGHT_SHOULDER))
	check(is_equal_approx(map.target_zoom, 1.25), "botão antigo não aproxima após remapeamento")
	map._input(pad(JOY_BUTTON_DPAD_RIGHT, false))
	check(is_equal_approx(map.target_zoom, 1.25), "soltar botão do mapa não repete o zoom")
	map._input(pad(JOY_BUTTON_LEFT_SHOULDER))
	check(is_equal_approx(map.target_zoom, 1.0), "mapa mantém afastar pelo comando anterior")
	controls.rebind_gamepad("weapon_next", trigger(1.0))
	map._input(trigger(.8))
	map._input(trigger(.95))
	check(is_equal_approx(map.target_zoom, 1.25), "gatilho remapeado aproxima uma vez enquanto segurado")
	map._input(trigger(0.0))
	map._input(trigger(.9))
	check(is_equal_approx(map.target_zoom, 1.5625), "soltar e apertar gatilho permite o próximo zoom")
	controls.import_gamepad_bindings(saved_pad)
	map.queue_free()

	var curtain = load("res://runtime/StartupCurtain.gd").new()
	curtain.variant = 1
	root.add_child(curtain)
	await process_frame
	check(curtain.get_node_or_null("/root/LoadingCurtain") == curtain, "cortina fica acessível na raiz para o mundo adotar")
	check(curtain._root.get_node("Background") is ColorRect and curtain._root.get_node("Background").material == null, "loading usa fundo sólido sem shader animado")
	curtain.set_stage(.5, "Teste")
	for i in 60: await process_frame
	check(curtain._shown > .3 and curtain._shown <= .5, "barra não inventa progresso além da etapa (%.2f)" % curtain._shown)
	check(curtain._percent.text.ends_with("%"), "percentual visível")
	curtain.set_stage(.2, "Volta?")
	check(curtain._target >= .5, "progresso nunca volta")
	await curtain.lift(2)
	await process_frame
	check(not is_instance_valid(curtain), "cortina sai depois do lift")

	await process_frame
	print("SETTINGS_MENU ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
