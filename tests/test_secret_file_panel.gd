extends SceneTree
## Teste isolado da pasta de Vicente: sem FullSession, save ou mundo 3D.

const PROGRESSION := preload("res://runtime/SecretNetworkProgression.gd")
const PANEL := preload("res://ui/SecretFilePanel.gd")

var checks := 0
var failures: Array[String] = []
var panel: Control
var progression: RefCounted
var closed_count := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	print("SECRET_FILE ", "PASS " if condition else "FAIL ", label)
	if not condition:
		failures.append(label)


func frames(count := 3) -> void:
	for _index in count:
		await process_frame


func action(name: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	return event


func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	progression = PROGRESSION.new()
	panel = PANEL.new()
	panel.closed.connect(func(): closed_count += 1)
	root.add_child(panel)
	await frames()

	check(not panel.open(progression), "arquivo permanece fechado antes de Maciota entregar a pasta")
	check(not panel.visible, "tentativa prematura nao exibe a interface")
	check(progression.receive_dossier(), "fixture recebe a pasta pela API real")
	check(progression.collect_fragment("map_village_fold"), "primeiro fragmento coletado")
	check(progression.collect_fragment("map_drainage_grid"), "segundo fragmento coletado")
	panel.configure(progression)
	check(panel.open(), "arquivo abre depois de recebido")
	await frames()
	check(panel.visible and panel.current_tab == 0, "arquivo inicia na aba MAPA")
	check(panel.tab_buttons.size() == 3 and panel.zoom_row.visible, "abas e controles de zoom ficam visiveis")
	check(panel.tab_buttons[2].disabled, "REDE fica bloqueada antes de descobrir o QG")
	check(panel.canvas.tab == 0 and panel.canvas.snapshot.fragments.size() == 2, "canvas consulta snapshot e desenha mapa parcial")
	panel.select_tab(2)
	check(panel.current_tab == 0, "aba REDE nao abre antes do QG")

	panel._change_zoom(1.0)
	check(is_equal_approx(panel.map_zoom, 1.4) and is_equal_approx(panel.canvas.map_zoom, 1.4), "zoom aproxima e respeita limite superior")
	panel._change_zoom(-2.0)
	check(is_equal_approx(panel.map_zoom, 0.8) and is_equal_approx(panel.canvas.map_zoom, 0.8), "zoom afasta e respeita limite inferior")

	check(progression.discover_keypad_clue("keypad_invoice"), "evidencia de keypad registrada")
	check(progression.discover_audio_log("audio_vicente_field"), "audio registrado")
	check(progression.discover_lab_clue("lab_incident_photo"), "fotografia ambigua registrada")
	panel.refresh()
	panel.select_tab(1)
	await frames()
	check(panel.current_tab == 1 and panel.item_scroll.visible, "EVIDENCIAS abre a lista navegavel")
	check(panel.item_list.get_child_count() == 3, "lista mostra apenas registros descobertos")
	check(panel.audio_button.visible == panel.selected_id.begins_with("audio_"), "controle de audio acompanha a selecao")

	check(progression.discover_house(), "casa descoberta")
	for id in PROGRESSION.KEYPAD_CLUE_IDS:
		progression.discover_keypad_clue(id)
	check(progression.unlock_keypad(), "keypad desbloqueado com todas as pistas")
	check(progression.discover_headquarters(), "QG descoberto")
	check(progression.activate_power_node("power_main"), "energia principal ativada")
	check(progression.activate_power_node("power_drainage"), "energia da drenagem ativada")
	check(progression.activate_route("route_village_house"), "rota da casa ativada")
	check(progression.activate_route("route_harbor_sewer"), "rota do esgoto ativada")
	panel.refresh()
	check(not panel.tab_buttons[2].disabled, "REDE e liberada depois do QG")
	panel.select_tab(2)
	await frames()
	check(panel.current_tab == 2 and panel.canvas.tab == 2, "canvas troca do mapa fragmentado para a rede")
	check(panel.item_list.get_child_count() == 2 and panel.route_button.visible, "REDE lista somente rotas ativas e oferece selecao")

	panel.open()
	panel._input(action(&"journal"))
	check(not panel.visible and closed_count == 1, "acao journal fecha a pasta")
	check(panel.open(), "pasta reabre depois de fechar por journal")
	panel._input(action(&"ui_cancel"))
	check(not panel.visible and closed_count == 2, "acao ui_cancel fecha a pasta")

	print("SECRET_FILE_RESULT checks=", checks, " failures=", failures.size())
	panel.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
