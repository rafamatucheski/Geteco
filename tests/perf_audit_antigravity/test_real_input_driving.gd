extends SceneTree

const HARBOR_SCENE := "res://world/harbor/HarborGame.tscn"

var failures: Array[String] = []
var log_lines: Array[String] = []

func log_msg(msg: String) -> void:
	print(msg)
	log_lines.append(msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(120.0).timeout.connect(func():
		log_msg("[WATCHDOG] Teste de condução real excedeu 120s")
		quit(2)
	)

	log_msg("=== TESTANDO CONDUTOR AUTOMATIZADO COM ENTRADAS REAIS DO JOGO ===")
	var campaign: Node = root.get_node("CampaignState")
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_started", &"harbor_delivery_picked_up", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)

	change_scene_to_file(HARBOR_SCENE)
	
	var harbor: Node2D = null
	var stream: Node = null
	var boot_deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < boot_deadline:
		await process_frame
		harbor = current_scene as Node2D
		if harbor != null and harbor.name == "HarborGame":
			stream = harbor.get_node_or_null("ContinuousWorld")
			if stream != null:
				break

	if harbor == null or stream == null:
		failures.append("HarborGame ou ContinuousWorld não inicializado")
		_finish(1)
		return

	# NÃO alteramos modern_traffic! Mantemos física, tráfego e colisões reais de produção!
	log_msg("  [OK] Tráfego e colisões de produção preservados intactos.")

	var player: Node2D = harbor.get_node_or_null("Player")
	var car_manager := harbor.get_node_or_null("PersonalCarManager")
	if car_manager == null or car_manager.get("car") == null:
		failures.append("PersonalCarManager.car não existe! Rejeitando carro substituto.")
		_finish(1)
		return

	var car: CharacterBody2D = car_manager.car as CharacterBody2D
	log_msg("  [OK] Carro pessoal identificado: %s em %s" % [car.name, str(car.global_position)])

	# Posiciona na entrada da ponte (fixture declarada para o teste)
	car.global_position = Vector2(6120, -4100)
	car.rotation = -PI * 0.5 # Apontando para o norte

	# Garante que o veículo esteja desbloqueado e que a introdução não intercepte os inputs
	car.set("unlocked", true)
	car_manager.set("introduction_seen", true)
	if player != null and player.get("personal_car_state") is Dictionary:
		player.get("personal_car_state")["introduction_seen"] = true

	# Embarque
	car.call("enter_vehicle", player)
	var boarding_deadline := Time.get_ticks_msec() + 5000
	while car.has_meta("vehicle_boarding") and Time.get_ticks_msec() < boarding_deadline:
		await physics_frame

	if not bool(car.get("is_driven_by_player")):
		failures.append("Falha no embarque do jogador")
		_finish(1)
		return

	# Arma os inputs do veículo soltando tudo por 3 physics frames
	_release_all_inputs()
	for i in 5:
		await physics_frame

	log_msg("  [OK] Jogador embarcado e controles armados.")

	# Waypoints da ponte de ida
	var connector = preload("res://world/harbor/HarborMountainConnector.gd")
	var outbound_points: PackedVector2Array = connector.road_definitions()[0].points

	log_msg("  Aguardando prontidão do streaming...")
	var stream_deadline := Time.get_ticks_msec() + 60000
	while not bool(stream.get("ready_for_crossing")) and Time.get_ticks_msec() < stream_deadline:
		await process_frame

	if not bool(stream.get("ready_for_crossing")):
		failures.append("Timeout esperando ready_for_crossing")
		_finish(1)
		return

	log_msg("  Iniciando condução com ações reais (move_up, move_left, move_right, move_down)...")
	var car_unlocked: bool = bool(car.get("unlocked"))
	var is_driven: bool = bool(car.get("is_driven_by_player"))
	var armed: bool = bool(car.get("_drive_input_armed"))
	var is_phys: bool = car.is_physics_processing()
	var is_vis: bool = car.visible
	var proc_m: int = car.process_mode
	var can_move_north: bool = not car.test_move(car.global_transform, Vector2(0, -20))
	var force: float = car.get("_engine_sound").drive_force(0.0, 600.0)
	var is_hold: bool = bool(car.get("_launch").holding)
	log_msg("  ESTADO INICIAL: unlocked=%s, driven=%s, armed=%s, pos=%s, phys=%s, vis=%s, mode=%d" % [
		str(car_unlocked), str(is_driven), str(armed), str(car.global_position), str(is_phys), str(is_vis), proc_m
	])
	log_msg("  FORCA: drive_force=%.3f, holding=%s, can_move_north=%s, accel=%.1f" % [force, str(is_hold), str(can_move_north), float(car.get("acceleration"))])

	# Testa os primeiros 5 waypoints da ponte
	for wp_idx in range(min(5, outbound_points.size())):
		var target := outbound_points[wp_idx]
		var ok := await _drive_to_target_with_inputs(car, target, 12.0)
		if not ok:
			failures.append("Falha ao navegar para waypoint %d (%s) usando entradas reais" % [wp_idx, str(target)])
			break

	_release_all_inputs()
	_finish(0 if failures.is_empty() else 1)

func _drive_to_target_with_inputs(car: CharacterBody2D, target: Vector2, timeout_s: float) -> bool:
	var start_pos := car.global_position
	var t_start := Time.get_ticks_msec()
	var deadline := t_start + int(timeout_s * 1000.0)

	var sim_frame := 0
	while Time.get_ticks_msec() < deadline:
		sim_frame += 1
		var pos := car.global_position
		var dist := pos.distance_to(target)
		if dist <= 38.0:
			_release_all_inputs()
			return true

		var to_target := target - pos
		var target_angle := to_target.angle()
		var forward_angle := car.global_rotation
		var angle_diff := wrapf(target_angle - forward_angle, -PI, PI)
		var speed := car.velocity.length()

		if sim_frame % 30 == 1:
			var g_mov: Vector2 = root.get_node("/root/GameInput").movement()
			log_msg("    FRAME %d: pos=%s, vel=%s, g_mov=%s, angle_diff=%.2f" % [sim_frame, str(pos), str(car.velocity), str(g_mov), angle_diff])

		# Direção (volante)
		if angle_diff > 0.10:
			Input.action_press("move_right")
			Input.action_release("move_left")
		elif angle_diff < -0.10:
			Input.action_press("move_left")
			Input.action_release("move_right")
		else:
			Input.action_release("move_left")
			Input.action_release("move_right")

		# Aceleração / Freio
		if absf(angle_diff) > 0.75 and speed > 80.0:
			Input.action_release("move_up")
			Input.action_press("move_down")
		else:
			Input.action_release("move_down")
			if speed < 160.0:
				Input.action_press("move_up")
			else:
				Input.action_release("move_up")

		await physics_frame

	_release_all_inputs()
	var final_dist := car.global_position.distance_to(target)
	var travel_dist := start_pos.distance_to(car.global_position)
	log_msg("  [TIMEOUT ROTA] target=%s, pos=%s, dist_restante=%.1f, dist_percorrida=%.1f" % [str(target), str(car.global_position), final_dist, travel_dist])
	return false

func _release_all_inputs() -> void:
	for act in ["move_up", "move_down", "move_left", "move_right", "handbrake", "exit_vehicle"]:
		Input.action_release(act)

func _finish(exit_code: int) -> void:
	_release_all_inputs()
	if failures.is_empty():
		log_msg("=== RESULTADO DO TESTE DE CONDUCAO REAL: APROVADO ===")
	else:
		log_msg("=== RESULTADO DO TESTE DE CONDUCAO REAL: FALHOU ===")
		for f in failures:
			log_msg("  - %s" % f)
	quit(exit_code)
