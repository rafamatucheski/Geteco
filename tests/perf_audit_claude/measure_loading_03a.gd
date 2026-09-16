extends SceneTree
## GETECO-PERF-03A — medição fim-a-fim do carregamento real.
## Fluxo real de produção: MainMenu.tscn -> clique (Novo Jogo/Continuar) via os
## mesmos métodos que os botões chamam -> GameLoading -> mundo pronto -> alguns
## quadros de gameplay. Não pula nenhuma etapa de produção; a única simulação é
## o clique do mouse (chama o handler do botão diretamente, mesmo efeito).
##
## Uso (renderizado, nunca headless; APPDATA isolado por execução):
##   Godot_console.exe --path . --script res://tests/perf_audit_claude/measure_loading_03a.gd -- \
##     run=<nome> mode=new|continue|produce_save [save_fixture=<pasta absoluta>]
##
## mode=new       Novo Jogo real: menu -> transição -> abertura (pulada com
##                opening.skip(), como test_opening_loading.gd) -> construção.
## mode=continue  Botão Carregar Jogo real sobre um save de verdade, produzido
##                por mode=produce_save (SaveManager.save_game em processo
##                separado). save_fixture aponta para a pasta com esse save;
##                é somente lida (load_game), nunca escrita nesta execução.
## mode=produce_save  Roda Novo Jogo até gameplay_ready, salva em save_fixture e
##                     sai. Não entra nas estatísticas de nenhum lado do A/B.

const MAIN_MENU := "res://ui/MainMenu.tscn"
const HARBOR := "res://world/harbor/HarborGame.tscn"
const SLOT_ID := "perf_audit_03a"

var run_name := "loading03a"
var mode := "new"
var save_fixture := ""
var out_dir := ""
var _start_us := 0
var _prev_us := 0
var phases: Array[String] = []
var phase_id := 0
var f_t := PackedFloat32Array()
var f_ms := PackedFloat32Array()
var f_phase := PackedInt32Array()
var markers: Array = []
var world: Node
var _world_ready_seen := false
var report := {}

func _initialize() -> void:
	_run.call_deferred()

func _now_ms() -> float:
	return (Time.get_ticks_usec() - _start_us) / 1000.0

func _set_phase(label: String) -> void:
	if not phases.has(label): phases.append(label)
	phase_id = phases.find(label)
	markers.append({"t_ms": _now_ms(), "name": "phase:" + label})

func _on_frame() -> void:
	var now := Time.get_ticks_usec()
	if _prev_us > 0:
		f_t.append(_now_ms())
		f_ms.append((now - _prev_us) / 1000.0)
		f_phase.append(phase_id)
	_prev_us = now

# Mesma técnica de atribuição das rodadas 01/02B: node_added marca o timestamp
# monotônico de cada nó, independente de haver quadro renderizado entre eles —
# é o que permite atribuir custo DENTRO de um bloco síncrono sem yield.
func _on_node_added(node: Node) -> void:
	if world == null and node.get_parent() == root and node.scene_file_path == HARBOR:
		world = node
		markers.append({"t_ms": _now_ms(), "name": "world_enter_tree", "children": node.get_child_count()})
		for child in node.get_children():
			child.ready.connect(_on_child_ready.bind(String(child.name)), CONNECT_ONE_SHOT)
		node.ready.connect(func():
			_world_ready_seen = true
			markers.append({"t_ms": _now_ms(), "name": "world_ready"}), CONNECT_ONE_SHOT)
		return
	if _world_ready_seen and is_instance_valid(world) and node.get_parent() == world:
		markers.append({"t_ms": _now_ms(), "name": "deferred_child_added:" + String(node.name)})

func _on_child_ready(child_name: String) -> void:
	markers.append({"t_ms": _now_ms(), "name": "child_ready:" + child_name})

func _environment() -> Dictionary:
	return {
		"engine": Engine.get_version_info(), "executable": OS.get_executable_path(), "debug_build": OS.is_debug_build(),
		"display_server": DisplayServer.get_name(), "renderer_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(), "adapter": RenderingServer.get_video_adapter_name(),
		"cpu": OS.get_processor_name(), "cpu_threads": OS.get_processor_count(),
		"screen_refresh_hz": DisplayServer.screen_get_refresh_rate(), "root_size": str(root.size),
		"vsync_mode": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"physics_ticks_per_second": Engine.physics_ticks_per_second, "user_data_dir": OS.get_user_data_dir(),
		"args": OS.get_cmdline_user_args(),
	}

func _run() -> void:
	_start_us = Time.get_ticks_usec()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("run="): run_name = arg.trim_prefix("run=")
		if arg.begins_with("mode="): mode = arg.trim_prefix("mode=")
		if arg.begins_with("save_fixture="): save_fixture = arg.trim_prefix("save_fixture=")
	if DisplayServer.get_name() == "headless":
		push_error("MEASURE_03A requer renderização real (nunca headless para medir performance)")
		quit(1)
		return
	if not OS.get_user_data_dir().replace("\\", "/").contains("perf_audit_claude"):
		push_error("MEASURE_03A abortado: user data não isolado (%s)" % OS.get_user_data_dir())
		quit(1)
		return
	out_dir = ProjectSettings.globalize_path("res://tests/perf_audit_claude/results/%s" % run_name)
	DirAccess.make_dir_recursive_absolute(out_dir)
	create_timer(180.0, true).timeout.connect(func():
		push_error("MEASURE_03A timeout")
		_write_outputs("timeout")
		quit(2))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	seed(15092026)
	report["environment"] = _environment()
	report["mode"] = mode

	var saves := root.get_node("SaveManager")
	var settings := root.get_node("SettingsManager")
	# Isolamento: cada execução usa seu próprio diretório de save, exceto
	# mode=continue, que só LÊ um fixture produzido antes (nunca escreve nele).
	var save_dir: String = save_fixture if (mode == "continue" and not save_fixture.is_empty()) else out_dir.path_join("saves") + "/"
	if mode != "continue": DirAccess.make_dir_recursive_absolute(save_dir)
	saves.set("_save_dir", save_dir)
	saves.set("_save_directory_ready", false)
	settings.set("_settings_path", out_dir.path_join("settings.cfg"))
	if mode != "continue": saves.clear_pending_save()

	process_frame.connect(_on_frame)
	node_added.connect(_on_node_added)

	# --- Menu: mesma cena real do project.godot main_scene ---
	_set_phase("menu_boot")
	var menu := (load(MAIN_MENU) as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	for i in 15: await process_frame
	report["t_menu_ready_ms"] = _now_ms()
	markers.append({"t_ms": _now_ms(), "name": "menu_ready"})

	if mode == "produce_save":
		await _boot_new_game(menu, true)
		await _hold(3.0)
		var result: Dictionary = saves.save_game(SLOT_ID)
		report["produce_save_result"] = result
		if not bool(result.get("success", false)):
			push_error("MEASURE_03A produce_save falhou: %s" % str(result))
			_write_outputs("save_failed")
			quit(1)
			return
		print("PRODUCE_SAVE_OK path=", saves.get_slot_path(SLOT_ID))
		_write_outputs("save_produced")
		quit(0)
		return

	if mode == "new":
		await _boot_new_game(menu, false)
	elif mode == "continue":
		await _boot_continue(menu)
	else:
		push_error("mode inválido: %s" % mode)
		quit(1)
		return

	report["t_loading_finished_ms"] = _now_ms()
	markers.append({"t_ms": _now_ms(), "name": "loading_finished"})
	# "Primeiro input válido": GameLoading só emite finished depois de despausar
	# e de gameplay_ready/world_build_ready; ainda assim aguardamos 2 quadros de
	# desenho real antes de considerar a tela realmente pronta para o jogador.
	for i in 2: await process_frame
	report["t_first_frame_after_finished_ms"] = _now_ms()
	report["world_gameplay_ready"] = bool(world.get("gameplay_ready")) if is_instance_valid(world) else null
	report["world_build_ready"] = bool(world.get("world_build_ready")) if is_instance_valid(world) else null
	report["tree_paused_after_finished"] = paused

	# Pequena amostra de gameplay pós-loading, só para confirmar estabilidade
	# (não é o foco desta medição; frame time de gameplay já é coberto por 01/02B).
	_set_phase("post_load_settle")
	if is_instance_valid(world) and world.has_node("Player") and world.has_node("PlayerCar"):
		var player: Node2D = world.get_node("Player")
		var car: Node2D = world.get_node("PlayerCar")
		if mode == "new" and not bool(world.get("loaded_from_save")):
			player.global_position = Vector2(2200, 1050)
			car.global_position = Vector2(700, 425)
			car.rotation = 0.0
		if world.has_method("_drive"): world.call("_drive")
		Input.action_press("move_up")
		await _hold(3.0)
		Input.action_release("move_up")

	_write_outputs("complete")
	quit(0)

func _hold(seconds: float) -> void:
	var until := _now_ms() + seconds * 1000.0
	while _now_ms() < until: await process_frame

func _boot_new_game(menu: Control, is_produce_save: bool) -> void:
	_set_phase("menu_click_new_game")
	menu.call("_on_btn_new_game_pressed")
	var loader := root.get_node("GameLoading")
	_set_phase("menu_transition_and_opening_wait")
	var waited_us := Time.get_ticks_usec()
	while not is_instance_valid(loader.opening) or not loader.opening._running:
		await process_frame
		if (Time.get_ticks_usec() - waited_us) / 1000000.0 > 20.0:
			push_error("MEASURE_03A: abertura não iniciou em 20s")
			break
	report["t_opening_started_ms"] = _now_ms()
	markers.append({"t_ms": _now_ms(), "name": "opening_started"})
	# Não contamos a duração narrativa da cutscene como custo de construção:
	# pulamos assim que ela começa a tocar, igual a tests/test_opening_loading.gd.
	_set_phase("opening_presentation_skip")
	loader.opening.skip()
	while not loader.opening_complete: await process_frame
	await process_frame
	report["t_opening_skipped_to_complete_ms"] = _now_ms()
	markers.append({"t_ms": _now_ms(), "name": "opening_complete"})
	_set_phase("world_construction")
	await loader.finished

func _boot_continue(menu: Control) -> void:
	if save_fixture.is_empty() or not FileAccess.file_exists(save_fixture.path_join(SLOT_ID + ".json")):
		push_error("MEASURE_03A: fixture de save ausente em %s" % save_fixture)
		quit(1)
		return
	_set_phase("menu_click_continue")
	menu.call("_select_and_load_slot", SLOT_ID)
	var loader := root.get_node("GameLoading")
	var waited_us := Time.get_ticks_usec()
	while not loader.active:
		await process_frame
		if (Time.get_ticks_usec() - waited_us) / 1000000.0 > 10.0:
			push_error("MEASURE_03A: GameLoading não ativou em 10s (load_game falhou?)")
			break
	_set_phase("world_construction")
	await loader.finished

func _pct(sorted_values: PackedFloat32Array, p: float) -> float:
	return sorted_values[clampi(ceili(p * sorted_values.size()) - 1, 0, sorted_values.size() - 1)]

func _stats(indices: Array) -> Dictionary:
	if indices.is_empty(): return {"frames": 0}
	var values := PackedFloat32Array()
	for i in indices: values.append(f_ms[i])
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	var over_16 := 0
	var over_33 := 0
	var over_50 := 0
	var over_100 := 0
	for v in values:
		total += v
		if v > 16.67: over_16 += 1
		if v > 33.33: over_33 += 1
		if v > 50.0: over_50 += 1
		if v > 100.0: over_100 += 1
	return {
		"frames": values.size(), "seconds": total / 1000.0, "mean_fps": values.size() * 1000.0 / total,
		"p50_ms": _pct(ordered, 0.5), "p95_ms": _pct(ordered, 0.95), "p99_ms": _pct(ordered, 0.99), "max_ms": ordered[-1],
		"over_16_67": over_16, "over_33_33": over_33, "over_50": over_50, "over_100": over_100,
	}

func _write_outputs(status: String) -> void:
	report["status"] = status
	report["phases_order"] = phases
	var by_phase := {}
	for pid in phases.size():
		var indices: Array = []
		for i in f_phase.size():
			if f_phase[i] == pid: indices.append(i)
		by_phase[phases[pid]] = _stats(indices)
	report["stats_by_phase"] = by_phase
	# Fim-a-fim real desde o clique até o mundo pronto (exclui menu_boot, inclui
	# a espera da abertura ainda visível na tela — ela é UI, não construção).
	var end_to_end_from_click: Array = []
	for i in f_phase.size():
		if phases[f_phase[i]] != "menu_boot" and phases[f_phase[i]] != "post_load_settle": end_to_end_from_click.append(i)
	report["stats_click_to_ready"] = _stats(end_to_end_from_click)
	var construction_only: Array = []
	for i in f_phase.size():
		if phases[f_phase[i]] == "world_construction": construction_only.append(i)
	report["stats_world_construction_only"] = _stats(construction_only)
	# Maiores quadros com atribuição: marcadores cujo timestamp cai dentro do quadro.
	var worst: Array = []
	var order := range(f_ms.size())
	order.sort_custom(func(a, b): return f_ms[a] > f_ms[b])
	for idx in order.slice(0, 15):
		var frame_start: float = f_t[idx] - f_ms[idx]
		var frame_end: float = f_t[idx]
		var during: Array = []
		for m in markers:
			if float(m.t_ms) >= frame_start and float(m.t_ms) <= frame_end: during.append(m.name)
		worst.append({"t_ms": f_t[idx], "ms": f_ms[idx], "phase": phases[f_phase[idx]], "markers_during": during})
	report["worst_frames"] = worst
	report["markers"] = markers
	var loader := root.get_node_or_null("GameLoading")
	if loader != null: report["gameloading_phase_times_ms"] = loader.phase_times_ms
	report["memory_static_mib"] = OS.get_static_memory_usage() / 1048576.0
	report["memory_video_mib"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	report["nodes"] = get_node_count()
	var file := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var csv := FileAccess.open(out_dir.path_join("frames.csv"), FileAccess.WRITE)
	csv.store_line("t_ms,frame_ms,phase")
	for i in f_ms.size():
		csv.store_line("%.3f,%.3f,%s" % [f_t[i], f_ms[i], phases[f_phase[i]]])
	csv.close()
	print("MEASURE_03A_STATUS ", status)
	print("MEASURE_03A_CLICK_TO_READY ", JSON.stringify(report.get("stats_click_to_ready", {})))
	print("MEASURE_03A_WORST3 ", JSON.stringify(worst.slice(0, 3)))
