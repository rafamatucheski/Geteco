extends SceneTree
## GETECO-PERF-03A-R2 — valida o ciclo de vida real de HarborSoundscape:
## Novo Jogo, Continuar, e retorno ao menu seguido de reentrada. Não injeta
## o nó manualmente em nenhum momento — só usa os mesmos handlers de botão
## que o jogo real usa (padrão de tests/perf_audit_claude/measure_loading_03a.gd).
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL " + message)
	else:
		print("PASS " + message)

func _initialize() -> void: _run.call_deferred()

func _inspect(world: Node, label: String) -> void:
	var matches := world.find_children("HarborSoundscape", "", true, false)
	check(matches.size() == 1, "%s: exatamente 1 HarborSoundscape (encontrado %d)" % [label, matches.size()])
	if matches.size() >= 1:
		var node: Node = matches[0]
		check(node.get_parent() == world, "%s: HarborSoundscape é filho direto do mundo" % label)
		check(node.get_script() == preload("res://world/harbor/HarborSoundscape.gd"), "%s: script correto" % label)
		var listener = node.get("listener")
		check(listener != null and is_instance_valid(listener), "%s: listener (AudioListener2D) criado e válido" % label)
		if listener != null and is_instance_valid(listener):
			check(listener is AudioListener2D, "%s: listener é AudioListener2D" % label)
			check(listener.get_parent() == node, "%s: listener é filho de HarborSoundscape" % label)
		var weights = node.get("weights")
		check(weights != null and weights.size() > 0, "%s: weights inicializado (%s)" % [label, str(weights)])

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var out_dir := ProjectSettings.globalize_path("res://tests/perf_audit_claude/results/03a_r2_lifecycle_probe")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not OS.get_user_data_dir().replace("\\", "/").contains("perf_audit_claude"):
		push_error("PROBE_R2_LIFECYCLE abortado: user data não isolado (%s)" % OS.get_user_data_dir())
		quit(1)
		return

	var saves := root.get_node("SaveManager")
	var save_dir := out_dir.path_join("saves") + "/"
	DirAccess.make_dir_recursive_absolute(save_dir)
	saves.set("_save_dir", save_dir)
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()

	# --- 1. Novo Jogo ---
	var menu: Node = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for i in 5: await process_frame
	menu.call("_on_btn_new_game_pressed")
	var loader := root.get_node("GameLoading")
	var deadline := Time.get_ticks_msec() + 60000
	while not is_instance_valid(loader.opening) or not loader.opening._running:
		await process_frame
		if Time.get_ticks_msec() > deadline: break
	loader.opening.skip()
	while not loader.opening_complete: await process_frame
	await loader.finished
	var world_new: Node = current_scene
	_inspect(world_new, "Novo Jogo")

	# --- 2. Salva, volta ao menu, e Continua (fluxo real de save/load) ---
	var slot_id := "r2_probe"
	saves.save_game(slot_id)
	world_new.get_node("PauseMenu").call("_on_main_menu_pressed")
	await scene_changed
	for i in 5: await process_frame
	var menu2: Node = current_scene
	menu2.call("_select_and_load_slot", slot_id)
	deadline = Time.get_ticks_msec() + 60000
	while not loader.active:
		await process_frame
		if Time.get_ticks_msec() > deadline: break
	await loader.finished
	var world_continue: Node = current_scene
	_inspect(world_continue, "Continuar")

	# --- 3. Retorno ao menu + reentrada (Novo Jogo de novo) — checa duplicação
	#        e callbacks sobre instância inválida ---
	var old_matches := world_continue.find_children("HarborSoundscape", "", true, false)
	var old_soundscape: Node = old_matches[0] if old_matches.size() > 0 else null
	world_continue.get_node("PauseMenu").call("_on_main_menu_pressed")
	await scene_changed
	for i in 10: await process_frame
	check(not is_instance_valid(old_soundscape) or old_soundscape.get_parent() == null, "Retorno ao menu: HarborSoundscape antigo não continua na árvore ativa")
	var menu3: Node = current_scene
	menu3.call("_on_btn_new_game_pressed")
	deadline = Time.get_ticks_msec() + 60000
	while not is_instance_valid(loader.opening) or not loader.opening._running:
		await process_frame
		if Time.get_ticks_msec() > deadline: break
	loader.opening.skip()
	while not loader.opening_complete: await process_frame
	await loader.finished
	var world_reentry: Node = current_scene
	_inspect(world_reentry, "Reentrada após retorno ao menu")

	print("PROBE_R2_LIFECYCLE failures=%d" % failures)
	quit(1 if failures else 0)
