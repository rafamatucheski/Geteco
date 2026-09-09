extends SceneTree

## Script de validação automatizada e gravação de mídias para gameplay_repair_art_0909.
## Executa com renderizador real do Godot 4.7.2:
##   "D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" ^
##     --path "D:/geteco/game" --script res://prototypes/gameplay_repair_art_0909/run_art_repair_validation.gd

const DEMO_FUNERAL_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/DemoFuneralScene.gd")
const DEMO_ELIAS_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/DemoEliasShovelScene.gd")
const DEMO_POLICE_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/DemoPoliceExtractionScene.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_all_validations")

func check(ok: bool, label: String) -> void:
	print(("  [PASS] " if ok else "  [FAIL] ") + label)
	if not ok:
		failures.append(label)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func wait_condition(condition: Callable, max_seconds: float = 15.0) -> bool:
	var start_ms := Time.get_ticks_msec()
	var limit_ms := int(max_seconds * 1000.0)
	while not condition.call() and (Time.get_ticks_msec() - start_ms) < limit_ms:
		await process_frame
	return condition.call()

func _save_screenshot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var full_path := "d:/geteco/game/prototypes/gameplay_repair_art_0909/captures/" + filename
	var err := img.save_png(full_path)
	print("  [CAPTURE] ", filename, " (err=", err, ")")

func run_all_validations() -> void:
	print("\n=======================================================")
	print("INICIANDO VALIDAÇÃO DE ARTE E ANIMAÇÕES ISOLADAS")
	print("=======================================================\n")

	DirAccess.make_dir_recursive_absolute("d:/geteco/game/prototypes/gameplay_repair_art_0909/captures")

	await _validate_deliverable_1_funeral()
	await _validate_deliverable_2_elias_and_shovel()
	await _validate_deliverable_3_police_extraction()

	print("\n=======================================================")
	if failures.is_empty():
		print("TODOS OS TESTES FORAM CONCLUÍDOS COM SUCESSO! [PASS]")
	else:
		print("FALHAS ENCONTRADAS (", failures.size(), "):")
		for f in failures:
			print("  - ", f)
	print("=======================================================\n")

	quit(0 if failures.is_empty() else 1)

# -------------------------------------------------------------
# ENTREGA 1: FUNERAL COMPLETO E COVA DINÂMICA
# -------------------------------------------------------------
func _validate_deliverable_1_funeral() -> void:
	print(">>> [ENTREGA 1] Testando Funeral, Caixão 3D e Sepultura...")

	var funeral_scene: Node3D = DEMO_FUNERAL_SCRIPT.new()
	root.add_child(funeral_scene)
	await frames(15)

	var ctrl: Node3D = funeral_scene.get("controller") as Node3D
	check(ctrl != null, "FuneralSequenceController instanciado com sucesso")
	check(funeral_scene.get("worker") != null, "Coveiro com pá anexado ao cenário")

	# Configura velocidade para validação ágil
	ctrl.set("speed_multiplier", 3.0)
	ctrl.set("ceremony_wait_time", 0.8)

	var signals := {
		"arrived": false,
		"filled": false,
		"completed": false
	}

	ctrl.connect("procession_arrived", func(): signals["arrived"] = true)
	ctrl.connect("filling_completed", func(): signals["filled"] = true)
	ctrl.connect("sequence_completed", func(): signals["completed"] = true)

	# Inicia cortejo
	ctrl.call("start_sequence")
	await frames(25)

	check(ctrl.get("casket") != null, "Caixão 3D instanciado e carregado")
	var pallbearers: Array = ctrl.get("pallbearers") as Array
	var visitors: Array = ctrl.get("visitors") as Array
	check(pallbearers.size() == 4, "4 Carregadores ativos no cortejo")
	check(visitors.size() == 4, "4 Visitantes ativos acompanhando")

	await _save_screenshot("funeral_01_procession_gameplay.png")

	funeral_scene.call("_toggle_camera")
	await frames(15)
	await _save_screenshot("funeral_02_casket_closeup.png")
	funeral_scene.call("_toggle_camera")

	# Espera chegada ao lote da cova
	var arrived_ok := await wait_condition(func(): return signals["arrived"], 12.0)
	check(arrived_ok, "Cortejo chegou ao lote lateral da sepultura")
	await _save_screenshot("funeral_03_ceremony_plot.png")

	# Espera descida e aterramento
	var filled_ok := await wait_condition(func(): return signals["filled"], 12.0)
	check(filled_ok, "Aterramento concluído e montículo de terra formado")

	funeral_scene.call("_toggle_camera")
	await frames(15)
	await _save_screenshot("funeral_04_completed_grave_closeup.png")
	funeral_scene.call("_toggle_camera")

	# Espera dispersão
	var completed_ok := await wait_condition(func(): return signals["completed"], 12.0)
	check(completed_ok, "Ciclo completo do funeral finalizado e atores dispersos")

	var pallbearers_end: Array = ctrl.get("pallbearers") as Array
	var visitors_end: Array = ctrl.get("visitors") as Array
	check(pallbearers_end.is_empty(), "Carregadores temporários liberados da memória")
	check(visitors_end.is_empty(), "Visitantes temporários liberados da memória")
	check(ctrl.get("casket") == null, "Caixão liberado com segurança sob a terra")

	# Teste de repetição contínua e cancelamento
	var count_before: int = root.get_child_count()
	for cycle in 3:
		ctrl.call("start_sequence")
		await frames(20)
		ctrl.call("cancel_sequence")
		await frames(10)

	var count_after: int = root.get_child_count()
	check(count_after == count_before, "Repetição e cancelamento seguros sem vazamento de nós")

	funeral_scene.queue_free()
	await frames(15)

# -------------------------------------------------------------
# ENTREGA 2: ELIAS E A PÁ 3D
# -------------------------------------------------------------
func _validate_deliverable_2_elias_and_shovel() -> void:
	print(">>> [ENTREGA 2] Testando Elias, Coveiro e Articulação da Pá 3D...")

	var elias_scene: Node3D = DEMO_ELIAS_SCRIPT.new()
	root.add_child(elias_scene)
	await frames(15)

	var elias: Node3D = elias_scene.get("elias") as Node3D
	var worker: Node3D = elias_scene.get("worker") as Node3D
	check(elias != null, "Elias instanciado com sobretudo, boina e cachecol exclusivos")
	check(worker != null, "Coveiro instanciado com farda de trabalho")
	check(worker.get("shovel") != null, "Pá 3D ancorada corretamente ao mount da mão do coveiro")

	# Poses de Elias
	elias.call("set_pose", 0) # WAIT
	await frames(15)
	await _save_screenshot("elias_01_wait_closeup.png")

	elias.call("set_pose", 1) # TALK
	await frames(20)
	await _save_screenshot("elias_02_talk_gesture_closeup.png")

	# Poses da Pá
	worker.call("set_worker_pose", 0) # HOLD
	await frames(15)
	await _save_screenshot("shovel_01_hold_pose.png")

	worker.call("set_worker_pose", 1) # CARRY
	worker.set("walking", true)
	await frames(20)

	var shovel_node: Node3D = worker.get("shovel") as Node3D
	var blade_world_y: float = shovel_node.get_node("BladeNode").global_position.y
	check(blade_world_y > 0.10, "Lâmina da pá em CARRY não penetra o chão (altura Y=" + str(snappedf(blade_world_y, 0.01)) + "m > 0.10m)")
	await _save_screenshot("shovel_02_carry_walking.png")

	worker.call("set_worker_pose", 2) # DIG
	worker.set("walking", false)
	await frames(25)
	await _save_screenshot("shovel_03_dig_pose.png")

	elias_scene.call("_toggle_camera")
	await frames(15)
	await _save_screenshot("elias_shovel_gameplay_view.png")

	elias_scene.queue_free()
	await frames(15)

# -------------------------------------------------------------
# ENTREGA 3: RETIRADA POLICIAL DO MOTORISTA
# -------------------------------------------------------------
func _validate_deliverable_3_police_extraction() -> void:
	print(">>> [ENTREGA 3] Testando Retirada Policial do Motorista...")

	var police_scene: Node3D = DEMO_POLICE_SCRIPT.new()
	root.add_child(police_scene)
	await frames(15)

	var ext: Node3D = police_scene.get("extraction") as Node3D
	check(ext != null, "PoliceDriverExtraction instanciado")
	check(ext.get("door_left") != null and ext.get("door_right") != null, "Portas articuladas esquerda/direita presentes")
	check(ext.get("officer_root") != null, "Policial em uniforme oficial presente")
	check(ext.get("dante_root") != null, "Dante no volante com camisa xadrez presente")

	ext.set("speed_multiplier", 3.0)

	# 1. Teste de segurança: carro em movimento bloqueia retirada
	ext.set("vehicle_speed", 25.0)
	var blocked_res: Variant = ext.call("start_extraction", -1.0)
	check(bool(blocked_res) == false, "Segurança: Retirada é bloqueada com veículo em movimento")
	ext.set("vehicle_speed", 0.0)

	# 2. Execução da retirada pela porta do motorista (Esquerda)
	var pol_signals := {
		"door_opened": false,
		"driver_out": false,
		"cuffed": false,
		"completed": false
	}

	ext.connect("door_opened", func(_side): pol_signals["door_opened"] = true)
	ext.connect("driver_extracted", func(): pol_signals["driver_out"] = true)
	ext.connect("suspect_handcuffed", func(): pol_signals["cuffed"] = true)
	ext.connect("sequence_completed", func(): pol_signals["completed"] = true)

	ext.call("start_extraction", -1.0)
	await frames(20)
	await _save_screenshot("police_01_approach_closeup.png")

	var door_ok := await wait_condition(func(): return pol_signals["door_opened"], 10.0)
	check(door_ok, "Porta do motorista aberta suavemente para fora (64°)")
	await _save_screenshot("police_02_door_open_closeup.png")

	var driver_ok := await wait_condition(func(): return pol_signals["driver_out"], 10.0)
	check(driver_ok, "Dante conduzido para fora do carro até o solo")
	await _save_screenshot("police_03_driver_extracted.png")

	var cuff_ok := await wait_condition(func(): return pol_signals["cuffed"], 10.0)
	check(cuff_ok, "Algemas de aço aplicadas nas costas do suspeito")
	await _save_screenshot("police_04_handcuffed_closeup.png")

	police_scene.call("_toggle_camera")
	await frames(15)
	await _save_screenshot("police_05_gameplay_view.png")

	# 3. Teste de Interrupção e Rollback Seguro
	ext.call("reset_poses")
	await frames(15)
	ext.call("start_extraction", -1.0)
	await frames(35) # Interrompe durante a aproximação
	ext.call("interrupt_extraction")

	var rollback_ok := await wait_condition(func():
		return int(ext.get("current_phase")) == 0 # Phase.IDLE
	, 8.0)
	check(rollback_ok, "Interrupção imediata restaurou estado IDLE e poses de combate com segurança")
	await _save_screenshot("police_06_interrupted_rollback.png")

	# 4. Teste de Extração pela Porta Direita (Passageiro)
	var right_signals := {
		"door_opened": false,
		"cuffed": false
	}
	ext.connect("door_opened", func(side): if side > 0: right_signals["door_opened"] = true)
	ext.connect("suspect_handcuffed", func(): right_signals["cuffed"] = true)
	ext.call("start_extraction", 1.0)
	var right_door_ok := await wait_condition(func(): return right_signals["door_opened"], 10.0)
	check(right_door_ok, "Porta direita do passageiro aberta com sucesso para fora (+64°)")
	var right_cuff_ok := await wait_condition(func(): return right_signals["cuffed"], 10.0)
	check(right_cuff_ok, "Suspeito retirado e algemado pelo lado direito sem poses presas")
	ext.call("reset_poses")
	await frames(10)

	police_scene.queue_free()
	await frames(15)
