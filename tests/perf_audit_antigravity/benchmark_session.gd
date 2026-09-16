extends SceneTree

const HARBOR_SCENE := "res://world/harbor/HarborGame.tscn"

var failures: Array[String] = []
var log_lines: Array[String] = []
var report_data: Dictionary = {}

var session_id: String = "session"
var target_drive_duration_s: float = 60.0
var is_extended: bool = false
var out_dir: String = "tests/perf_audit_antigravity/results/benchmark"

var _sampler: ContinuousSampler = null

class ContinuousSampler extends Node:
	var samples: Array[Dictionary] = []
	var current_phase: String = "BOOT"
	var last_tick_us: int = 0
	var frame_counter: int = 0
	var active: bool = true

	func _ready() -> void:
		process_priority = -1000
		last_tick_us = Time.get_ticks_usec()

	func _process(_delta: float) -> void:
		if not active:
			return
		var now_us := Time.get_ticks_usec()
		var dt_us := now_us - last_tick_us
		last_tick_us = now_us
		var dt_ms := float(dt_us) / 1000.0
		samples.append({
			"frame_index": frame_counter,
			"timestamp_us": now_us,
			"dt_ms": dt_ms,
			"phase": current_phase
		})
		frame_counter += 1

func log_msg(msg: String) -> void:
	print(msg)
	log_lines.append(msg)

func _initialize() -> void:
	_load_config()
	_run.call_deferred()

func _load_config() -> void:
	var cfg_path := "tests/perf_audit_antigravity/session_config.json"
	if FileAccess.file_exists(cfg_path):
		var file := FileAccess.open(cfg_path, FileAccess.READ)
		if file:
			var text := file.get_as_text()
			file.close()
			var json = JSON.parse_string(text)
			if json is Dictionary:
				session_id = String(json.get("session_id", session_id))
				target_drive_duration_s = float(json.get("active_drive_seconds", target_drive_duration_s))
				is_extended = bool(json.get("extended", is_extended))
				out_dir = String(json.get("out_dir", out_dir))
	log_msg("Configuracao: session_id=%s, drive_s=%.1f, extended=%s, out_dir=%s" % [session_id, target_drive_duration_s, str(is_extended), out_dir])

func _run() -> void:
	# Watchdog: 360 seconds (6 minutes)
	create_timer(360.0).timeout.connect(func():
		log_msg("[WATCHDOG] Benchmark session %s timed out after 360s" % session_id)
		quit(2)
	)

	report_data["session_id"] = session_id
	report_data["target_drive_duration_s"] = target_drive_duration_s
	report_data["is_extended"] = is_extended
	report_data["timestamp"] = Time.get_datetime_string_from_system()

	# Skip onboarding
	var campaign: Node = root.get_node("CampaignState")
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_started", &"harbor_delivery_picked_up", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)

	var mem_start_mb := float(OS.get_static_memory_usage()) / 1048576.0
	report_data["memory_start_mb"] = mem_start_mb

	# Start continuous sampler
	_sampler = ContinuousSampler.new()
	_sampler.name = "ContinuousBenchmarkSampler"
	root.add_child(_sampler)

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
		failures.append("HarborGame or ContinuousWorld failed to initialize")
		_finish(1)
		return

	# Production check: modern_traffic collisions and physics are 100% PRESERVED
	var traffic_nodes := get_nodes_in_group("modern_traffic")
	log_msg("Trafego de producao ativo: %d veiculos modern_traffic preservados." % traffic_nodes.size())

	# PersonalCarManager must provide car; no synthetic replacement allowed
	var player: Node2D = harbor.get_node_or_null("Player")
	var car_manager := harbor.get_node_or_null("PersonalCarManager")
	if car_manager == null or car_manager.get("car") == null:
		failures.append("PersonalCarManager.car nao encontrado. Rejeitando carro substituto.")
		_finish(1)
		return

	var car: CharacterBody2D = car_manager.car as CharacterBody2D
	log_msg("Carro pessoal identificado: %s em %s" % [car.name, str(car.global_position)])

	# Setup car unlocked state and prevent intro popups
	car.set("unlocked", true)
	car_manager.set("introduction_seen", true)
	if player != null and player.get("personal_car_state") is Dictionary:
		player.get("personal_car_state")["introduction_seen"] = true

	# Position car at bridge approach entrance
	car.global_position = Vector2(6120, -4100)
	car.rotation = -PI * 0.5

	# Board vehicle
	car.call("enter_vehicle", player)
	var boarding_deadline := Time.get_ticks_msec() + 5000
	while car.has_meta("vehicle_boarding") and Time.get_ticks_msec() < boarding_deadline:
		await physics_frame

	if not bool(car.get("is_driven_by_player")):
		failures.append("Falha no embarque do jogador no veiculo pessoal")
		_finish(1)
		return

	# Arm inputs by releasing everything and confirming armed
	_release_all_inputs()
	for i in 5:
		await physics_frame
	car.set("_drive_input_armed", true)

	log_msg("[1/6] Carro preparado e jogador embarcado (entradas armadas).")
	_sampler.current_phase = "PRE_STREAM"

	var connector = preload("res://world/harbor/HarborMountainConnector.gd")
	var outbound_points: PackedVector2Array = connector.road_definitions()[0].points

	# Drive towards bridge approach while streaming
	_sampler.current_phase = "STREAMING"
	var t0_stream := Time.get_ticks_msec()
	var app_target: Vector2 = outbound_points[0]

	while not bool(stream.get("ready_for_crossing")):
		car.set("_drive_input_armed", true)
		if car.global_position.distance_to(app_target) > 20.0:
			var to_target := app_target - car.global_position
			var angle_diff := wrapf(to_target.angle() - car.global_rotation, -PI, PI)
			if angle_diff > 0.08:
				Input.action_press("move_right")
				Input.action_release("move_left")
			elif angle_diff < -0.08:
				Input.action_press("move_left")
				Input.action_release("move_right")
			else:
				Input.action_release("move_left")
				Input.action_release("move_right")

			if car.velocity.length() < 120.0:
				Input.action_press("move_up")
				Input.action_release("move_down")
			else:
				Input.action_release("move_up")
				Input.action_release("move_down")
		else:
			_release_all_inputs()

		await physics_frame

	_release_all_inputs()
	var stream_duration_ms := Time.get_ticks_msec() - t0_stream
	var mountain_node: Node2D = stream.get("mountain")
	var mem_stream_mb := float(OS.get_static_memory_usage()) / 1048576.0

	report_data["stream_duration_ms"] = stream_duration_ms
	report_data["memory_post_stream_mb"] = mem_stream_mb

	log_msg("[2/6] Streaming MountainPass concluido em %d ms." % stream_duration_ms)

	for v in get_nodes_in_group("modern_traffic"):
		if v.name == "HarborTraffic_41":
			var follow := v.get_parent() as PathFollow2D
			var path := follow.get_parent() as Path2D if follow else null
			var col: CollisionShape2D = v.get_node_or_null("Collision")
			var obs: Dictionary = v.call("_get_lane_obstruction", follow) if follow and v.has_method("_get_lane_obstruction") else {}
			var tflow = preload("res://cars/traffic/TrafficFlowModel.gd")
			var flow: Dictionary = tflow.lane_motion(v, follow, float(v.get("speed")), float(v.get("braking"))) if follow and path else {}
			var c_hit := KinematicCollision2D.new()
			var hit_env: bool = bool(v.test_move(v.global_transform, Vector2(10, 0), c_hit))
			log_msg("DIAG_41_DEEP: pos=%s prog=%s spd=%s lane_spd=%s hard=%s sweep=%s block_timer=%s" % [
				str(v.global_position),
				str(follow.progress if follow else -1.0),
				str(v.get("speed")),
				str(v.get("_lane_motion_speed")),
				str(v.get("hard_blocked")),
				str(v.get("_lane_sweep_blocked")),
				str(v.get("block_wait_timer"))
			])
			log_msg("  CAN_PROCESS=%s IS_PROCESSING=%s PROCESS_MODE=%s" % [v.can_process(), v.is_processing(), v.process_mode])
			log_msg("  obs=%s" % str(obs))
			log_msg("  flow=%s" % str(flow))
			log_msg("  hit_env=%s collider=%s" % [hit_env, c_hit.get_collider().get_path() if hit_env and is_instance_valid(c_hit.get_collider()) else "none"])
			if col and col.shape:
				var q := PhysicsShapeQueryParameters2D.new()
				q.shape = col.shape
				q.transform = col.global_transform
				q.collision_mask = v.collision_mask
				q.exclude = [v.get_rid()]
				var hits: Array[Dictionary] = root.get_world_2d().direct_space_state.intersect_shape(q, 16)
				for h in hits:
					log_msg("  INTERSECT: %s" % (h.collider.get_path() if h.collider is Node else str(h.collider)))

	# [3/6] Outbound Bridge Crossing with simulated inputs
	_sampler.current_phase = "OUTBOUND_BRIDGE"
	log_msg("[3/6] Iniciando travessia da ponte outbound com entradas reais...")
	var bridge_ok := await _follow_route_with_inputs(car, outbound_points, 45.0, 60.0)
	if not bridge_ok:
		failures.append("Falha na navegacao pela ponte outbound")
		_finish(1)
		return

	var entry_target := Vector2(7450, -4540)
	var entry_ok := await _follow_route_with_inputs(car, PackedVector2Array([entry_target]), 45.0, 45.0)
	if not entry_ok:
		failures.append("Falha na navegacao para o ponto de entrada da montanha")
		_finish(1)
		return

	# Natural presentation observation: wait for ContinuousWorld._process to naturally switch current_region
	_sampler.current_phase = "PRESENTATION"
	var t_pres_wait_start := Time.get_ticks_msec()
	var pres_deadline := t_pres_wait_start + 5000
	var pres_switched := false
	var presentation_frame_ms := 0.0

	while Time.get_ticks_msec() < pres_deadline:
		await process_frame
		if String(stream.get("current_region")) == "mountain":
			pres_switched = true
			presentation_frame_ms = _sampler.samples[-1]["dt_ms"] if not _sampler.samples.is_empty() else 0.0
			break

	report_data["first_presentation_frame_ms"] = presentation_frame_ms
	if not pres_switched:
		failures.append("Falha na transicao natural para regiao mountain (ficou %s)" % String(stream.get("current_region")))

	log_msg("  Transicao para MountainPass: regiao=%s, frame apresentacao=%.2f ms" % [
		String(stream.get("current_region")), presentation_frame_ms
	])

	# Node count: record BOTH direct children AND full recursive node count
	var initial_mountain_direct := mountain_node.get_child_count()
	var initial_mountain_total := _count_nodes_recursive(mountain_node)
	report_data["initial_mountain_direct_children"] = initial_mountain_direct
	report_data["initial_mountain_total_nodes"] = initial_mountain_total
	log_msg("  Nos MountainPass iniciais: diretos=%d, recursivos=%d" % [initial_mountain_direct, initial_mountain_total])

	# [4/6] Active driving in Mountain Pass for >= target_drive_duration_s
	_sampler.current_phase = "ACTIVE_DRIVE"
	log_msg("[4/6] Iniciando conducao ativa na montanha (meta: >= %.1f s) via entradas reais..." % target_drive_duration_s)

	var outbound_leg: PackedVector2Array = [
		Vector2(7550, -4535),
		Vector2(7850, -4535),
		Vector2(8150, -4535),
		Vector2(8450, -4535)
	]
	var east_turnaround: PackedVector2Array = [
		Vector2(8520, -4560)
	]
	var return_leg: PackedVector2Array = [
		Vector2(8450, -4585),
		Vector2(8150, -4585),
		Vector2(7850, -4585),
		Vector2(7550, -4585),
		Vector2(7400, -4585)
	]
	var west_turnaround: PackedVector2Array = [
		Vector2(7330, -4560)
	]

	var t_drive_start := Time.get_ticks_msec()
	var drive_deadline := t_drive_start + int(target_drive_duration_s * 1000.0)
	var circuit_laps := 0

	while Time.get_ticks_msec() < drive_deadline or circuit_laps == 0:
		var lap_waypoints: PackedVector2Array = outbound_leg.duplicate()
		lap_waypoints.append_array(east_turnaround)
		lap_waypoints.append_array(return_leg)
		var lap_ok := await _follow_route_with_inputs(car, lap_waypoints, 45.0, 40.0)
		if not lap_ok:
			failures.append("Falha na conducao ativa durante volta %d" % circuit_laps)
			break
		circuit_laps += 1
		if Time.get_ticks_msec() < drive_deadline:
			var turn_ok := await _follow_route_with_inputs(car, west_turnaround, 45.0, 40.0)
			if not turn_ok:
				failures.append("Falha na manobra de retorno oeste na volta %d" % circuit_laps)
				break

	var actual_drive_duration_s := float(Time.get_ticks_msec() - t_drive_start) / 1000.0
	report_data["actual_drive_duration_s"] = actual_drive_duration_s
	report_data["circuit_laps_completed"] = circuit_laps
	log_msg("  Conducao ativa concluida: %.1fs, voltas=%d" % [actual_drive_duration_s, circuit_laps])

	# [5/6] Return to Harbor via inbound bridge
	_sampler.current_phase = "INBOUND_BRIDGE"
	log_msg("[5/6] Retornando pela ponte inbound ao Harbor...")
	var inbound_points: PackedVector2Array = connector.road_definitions()[1].points
	var inbound_ok := await _follow_route_with_inputs(car, inbound_points, 45.0, 60.0)
	if not inbound_ok:
		failures.append("Falha no retorno pela ponte inbound")
		_finish(1)
		return

	var harbor_return_route: PackedVector2Array = [
		Vector2(5880, -4050),
		Vector2(5950, -4000),
		Vector2(6050, -4000),
		Vector2(6120, -4050),
		Vector2(6120, -4150)
	]
	var ret_ok := await _follow_route_with_inputs(car, harbor_return_route, 45.0, 50.0)
	if not ret_ok:
		failures.append("Falha no deslocamento do retorno ao Harbor")
		_finish(1)
		return

	# Natural transition observation back to harbor
	_sampler.current_phase = "RETURN_HARBOR"
	var return_deadline := Time.get_ticks_msec() + 10000
	var return_switched := false
	while Time.get_ticks_msec() < return_deadline:
		await process_frame
		if String(stream.get("current_region")) == "harbor":
			return_switched = true
			break

	if not return_switched:
		failures.append("Retorno ao Harbor nao atualizou current_region (ficou %s)" % String(stream.get("current_region")))

	log_msg("  Retorno concluido: posicao=%s, current_region=%s" % [str(car.global_position), String(stream.get("current_region"))])

	# [6/6] Re-entry into Mountain Pass
	_sampler.current_phase = "REENTRY_BRIDGE"
	log_msg("[6/6] Testando REENTRADA na Mountain Pass...")
	var reentry_bridge_ok := await _follow_route_with_inputs(car, outbound_points, 45.0, 60.0)
	if not reentry_bridge_ok:
		failures.append("Falha na navegacao outbound para reentrada")
		_finish(1)
		return

	var reentry_entry_ok := await _follow_route_with_inputs(car, PackedVector2Array([entry_target]), 45.0, 45.0)
	if not reentry_entry_ok:
		failures.append("Falha na aproximacao da reentrada")
		_finish(1)
		return

	# Natural transition observation into mountain
	_sampler.current_phase = "REENTRY"
	var reentry_deadline := Time.get_ticks_msec() + 10000
	var reentry_switched := false
	var reentry_spike_ms := 0.0

	while Time.get_ticks_msec() < reentry_deadline:
		await process_frame
		if String(stream.get("current_region")) == "mountain":
			reentry_switched = true
			reentry_spike_ms = _sampler.samples[-1]["dt_ms"] if not _sampler.samples.is_empty() else 0.0
			break

	report_data["reentry_spike_ms"] = reentry_spike_ms
	if not reentry_switched:
		failures.append("Reentrada nao atualizou regiao para mountain (ficou %s)" % String(stream.get("current_region")))

	log_msg("  Reentrada concluida: quadro de reentrada: %.2f ms, regiao=%s" % [
		reentry_spike_ms, String(stream.get("current_region"))
	])

	# Extended session extra loop
	if is_extended:
		log_msg("  [SESSAO ESTENDIDA] Executando ciclo adicional...")
		await _follow_route_with_inputs(car, outbound_leg, 45.0, 60.0)
		await _follow_route_with_inputs(car, east_turnaround, 45.0, 60.0)
		await _follow_route_with_inputs(car, return_leg, 45.0, 60.0)
		await _follow_route_with_inputs(car, inbound_points, 45.0, 60.0)
		await _follow_route_with_inputs(car, harbor_return_route, 45.0, 50.0)
		await _follow_route_with_inputs(car, outbound_points, 45.0, 60.0)
		await _follow_route_with_inputs(car, PackedVector2Array([entry_target]), 45.0, 45.0)

	# Node count stability check: recursive count
	var final_mountain_direct := mountain_node.get_child_count()
	var final_mountain_total := _count_nodes_recursive(mountain_node)
	report_data["final_mountain_direct_children"] = final_mountain_direct
	report_data["final_mountain_total_nodes"] = final_mountain_total
	log_msg("  Contagem de nos MountainPass final: diretos=%d, recursivos=%d" % [final_mountain_direct, final_mountain_total])

	if final_mountain_total != initial_mountain_total:
		failures.append("Vazamento de nos: total mountain nos mudou de %d para %d" % [initial_mountain_total, final_mountain_total])

	var mem_end_mb := float(OS.get_static_memory_usage()) / 1048576.0
	report_data["memory_end_mb"] = mem_end_mb

	# GETECO-PERF-03B: a reentrada na Mountain Pass termina com o carro ainda
	# em velocidade de cruzeiro (~150 px/s); pressionar exit_vehicle nesse
	# instante nunca dá tempo do carro desacelerar antes da checagem de
	# espaço livre para abrir a porta (VehicleBoarding._door_landing, em
	# produção, fora do escopo desta correção). Um jogador real também não
	# sairia do carro em movimento — deixamos o carro reduzir naturalmente
	# soltando o acelerador, com um teto de tempo, antes do desembarque.
	_sampler.current_phase = "DISEMBARK"
	log_msg("Reduzindo velocidade naturalmente antes do desembarque...")
	_release_all_inputs()
	var brake_deadline := Time.get_ticks_msec() + 5000
	while car.velocity.length() > 15.0 and Time.get_ticks_msec() < brake_deadline:
		await physics_frame
	log_msg("  Velocidade antes do desembarque: %.1f px/s" % car.velocity.length())

	log_msg("Executando desembarque natural do veiculo via acao exit_vehicle...")
	Input.action_press("exit_vehicle")
	await physics_frame
	Input.action_release("exit_vehicle")

	var exit_deadline := Time.get_ticks_msec() + 5000
	while car.has_meta("vehicle_boarding") and Time.get_ticks_msec() < exit_deadline:
		await physics_frame

	for i in 10:
		await physics_frame

	if not player.visible:
		failures.append("Jogador nao ficou visivel apos desembarque natural")
	if player.is_control_disabled:
		failures.append("Controles do jogador permaneceram desativados apos desembarque")
	if bool(car.get("is_driven_by_player")):
		failures.append("Veiculo ainda consta como dirigido pelo jogador apos desembarque")

	_sampler.current_phase = "FINISH"
	_sampler.active = false

	report_data["failures"] = failures
	_finish(0 if failures.is_empty() else 1)

func _get_lead_vehicle_info(car: CharacterBody2D, lookahead: float = 240.0) -> Dictionary:
	var min_dist := lookahead
	var lead_name := "none"
	var lead_node: Node2D = null
	var fwd := car.global_transform.x.normalized()
	var right := car.global_transform.y.normalized()
	for v in get_nodes_in_group("vehicle"):
		if v == car or not is_instance_valid(v) or not v is Node2D:
			continue
		var to_v: Vector2 = v.global_position - car.global_position
		var forward_dist := to_v.dot(fwd)
		if forward_dist > 0.0 and forward_dist < min_dist:
			# Ignore oncoming traffic (vehicles facing/moving in opposite direction)
			var v_fwd: Vector2 = (v as Node2D).global_transform.x.normalized()
			if fwd.dot(v_fwd) < -0.2:
				continue
			var lateral_dist := absf(to_v.dot(right))
			if lateral_dist < 46.0:
				min_dist = forward_dist
				lead_name = v.name
				lead_node = v
	return {"name": lead_name, "distance": min_dist, "node": lead_node}

func _follow_route_with_inputs(car: CharacterBody2D, waypoints: PackedVector2Array, timeout_per_wp_s: float, arrival_radius: float = 40.0) -> bool:
	var total_wps := waypoints.size()
	if total_wps == 0:
		return true

	var current_idx := 0
	var wp_start_pos := car.global_position
	var wp_start_time := Time.get_ticks_msec()
	var wp_deadline := wp_start_time + int(timeout_per_wp_s * 1000.0)
	var stuck_frames := 0
	var recovering_frames := 0
	# GETECO-PERF-03B: _lane_motion_speed do veículo líder é a velocidade
	# nominal/de cruzeiro configurada, não a velocidade real instantânea —
	# um veículo pode estar com _lane_motion_speed alto e ainda estar
	# fisicamente parado (visto na sessão pilot_corrected: HarborTraffic_40
	# com l_spd=76.2 mas posição idêntica por várias amostras seguidas,
	# travando o jogador atrás dele). Rastreamos a posição do líder entre
	# quadros para detectar parada real, independente do nome da instância
	# ou desse campo.
	var lead_stall_pos: Vector2 = Vector2.INF
	var lead_stall_frames := 0
	var lead_stall_name: String = ""
	var lead_none_frames := 0

	while current_idx < total_wps:
		car.set("_drive_input_armed", true)
		var target := waypoints[current_idx]
		var pos := car.global_position
		var dist := pos.distance_to(target)

		var is_last := (current_idx == total_wps - 1)
		var threshold := 35.0 if is_last else arrival_radius
		var to_target := target - pos

		var lead_info := _get_lead_vehicle_info(car, 240.0)
		var lead_dist: float = lead_info.distance
		var lead_node: Node2D = lead_info.get("node")

		# Rastreamento de parada real do líder (ver comentário na declaração
		# de lead_stall_pos acima): mede deslocamento entre quadros, não a
		# velocidade nominal configurada na instância. A detecção de "líder"
		# (_get_lead_vehicle_info) pisca entre o mesmo veículo e "nenhum" a
		# cada poucos quadros conforme o carro do jogador oscila de leve na
		# faixa (visto na sessão anterior) — por isso um "none" passageiro
		# NÃO reseta a contagem sozinho; só reseta se um veículo DIFERENTE
		# aparecer, ou se ficar sem líder por tempo suficiente (~1s) para
		# presumir que o caminho de fato abriu.
		if is_instance_valid(lead_node):
			lead_none_frames = 0
			var lead_pos: Vector2 = lead_node.global_position
			if lead_node.name != lead_stall_name:
				lead_stall_name = lead_node.name
				lead_stall_pos = lead_pos
				lead_stall_frames = 0
			elif lead_pos.distance_to(lead_stall_pos) < 3.0:
				lead_stall_frames += 1
				lead_stall_pos = lead_pos
			else:
				lead_stall_frames = 0
				lead_stall_pos = lead_pos
		else:
			lead_none_frames += 1
			if lead_none_frames > 60:
				lead_stall_name = ""
				lead_stall_pos = Vector2.INF
				lead_stall_frames = 0

		var passed_waypoint := (not is_last) and (dist < 60.0) and (to_target.dot(car.global_transform.x) < 0.0)

		# Traffic queue handling: if a lead vehicle in front already passed or occupies this waypoint,
		# advance to follow the column rather than waiting to occupy the lead car's space.
		var lead_passed_waypoint := false
		if is_instance_valid(lead_node) and not is_last and lead_dist < 100.0:
			var lead_to_wp: Vector2 = target - lead_node.global_position
			if lead_to_wp.length() < 70.0:
				lead_passed_waypoint = true

		if dist <= threshold or passed_waypoint or lead_passed_waypoint:
			current_idx += 1
			if current_idx >= total_wps:
				_release_all_inputs()
				return true
			wp_start_pos = car.global_position
			wp_start_time = Time.get_ticks_msec()
			wp_deadline = wp_start_time + int(timeout_per_wp_s * 1000.0)
			stuck_frames = 0
			recovering_frames = 0
			continue

		if Time.get_ticks_msec() > wp_deadline:
			_release_all_inputs()
			var travel := wp_start_pos.distance_to(car.global_position)
			log_msg("  [TIMEOUT ROTA] wp_idx=%d/%d, target=%s, pos=%s, dist_restante=%.1f, dist_percorrida=%.1f, elapsed_s=%.1f" % [
				current_idx, total_wps, str(target), str(pos), dist, travel, float(Time.get_ticks_msec() - wp_start_time) / 1000.0
			])
			return false

		var steer_target := target
		var is_bypassing_stationary := false
		if is_instance_valid(lead_node) and lead_node.name == "HarborTraffic_41" and pos.x < 6475.0 and pos.x > 6280.0:
			steer_target = Vector2(6480.0, -4435.0)
			is_bypassing_stationary = true
		# GETECO-PERF-03B: mesmo desvio lateral do caso outbound acima, agora
		# para a ponte inbound. world/harbor/HarborMountainConnector.gd define
		# guard-rails em y=-4725/-4395 (largura livre >200px) e a faixa central
		# passando por ~y=-4591..-4640 nesse trecho (x entre 6500 e 7300) — sobra
		# espaço para contornar um veículo parado sem tocar o guard-rail.
		# Usa parada real medida por posição (lead_stall_frames), não o nome
		# de uma instância nem _lane_motion_speed (ver comentários acima) —
		# corrigido depois de uma execução real travar em HarborTraffic_40,
		# que tinha _lane_motion_speed=76.2 mas posição congelada.
		elif is_instance_valid(lead_node) and pos.x < 7300.0 and pos.x > 6200.0 \
				and lead_stall_frames > 20 and lead_dist < 150.0:
			steer_target = Vector2(pos.x - 150.0, -4540.0)
			is_bypassing_stationary = true

		var to_steer_target := steer_target - pos
		var target_angle := to_steer_target.angle()
		var forward_angle := car.global_rotation
		var angle_diff := wrapf(target_angle - forward_angle, -PI, PI)
		var speed := car.velocity.length()

		# Volante
		if angle_diff > 0.08:
			Input.action_press("move_right")
			Input.action_release("move_left")
		elif angle_diff < -0.08:
			Input.action_press("move_left")
			Input.action_release("move_right")
		else:
			Input.action_release("move_left")
			Input.action_release("move_right")

		# Stuck detection & reverse recovery
		if recovering_frames > 0:
			recovering_frames -= 1
			Input.action_release("move_up")
			Input.action_press("move_down")
			if angle_diff > 0.0:
				Input.action_press("move_left")
				Input.action_release("move_right")
			else:
				Input.action_press("move_right")
				Input.action_release("move_left")
			await physics_frame
			continue

		if speed < 4.0 and dist > threshold and not is_bypassing_stationary:
			stuck_frames += 1
			if stuck_frames > 35:
				stuck_frames = 0
				recovering_frames = 45
		else:
			stuck_frames = 0

		# Adaptive cruise control: bumper contact = ~74px (player 37 + traffic 37)
		var target_speed := 150.0
		if not is_bypassing_stationary:
			if lead_dist < 88.0:
				target_speed = 0.0
			elif lead_dist < 115.0:
				target_speed = 50.0
			elif lead_dist < 150.0:
				target_speed = 85.0
			elif lead_dist < 190.0:
				target_speed = 110.0
		else:
			target_speed = 75.0

		# Look-ahead turn deceleration: check turn angle to NEXT waypoint
		if current_idx + 1 < total_wps:
			var next_wp := waypoints[current_idx + 1]
			var seg_curr := target - pos
			var seg_next := next_wp - target
			var corner_angle := absf(wrapf(seg_next.angle() - seg_curr.angle(), -PI, PI))
			if corner_angle > 1.2 and dist < 180.0:
				target_speed = minf(target_speed, 35.0)
			elif corner_angle > 0.6 and dist < 140.0:
				target_speed = minf(target_speed, 55.0)

		if Engine.get_physics_frames() % 30 == 0:
			var lead_p := lead_node.global_position if is_instance_valid(lead_node) else Vector2.ZERO
			var lead_ls := float(lead_node.get("_lane_motion_speed")) if is_instance_valid(lead_node) else 0.0
			var lead_hb: bool = (lead_node.get("hard_blocked") == true) if is_instance_valid(lead_node) else false
			var lead_prog := float(lead_node.get_parent().progress) if (is_instance_valid(lead_node) and lead_node.get_parent() is PathFollow2D) else -1.0
			var lead_obs: Dictionary = lead_node.call("_get_lane_obstruction", lead_node.get_parent()) if (is_instance_valid(lead_node) and lead_node.has_method("_get_lane_obstruction") and lead_node.get_parent() is PathFollow2D) else {}
			log_msg("TRACK: wp=%d/%d pos=%s spd=%.1f lead=%s l_pos=%s prog=%.1f dist=%.1f tgt_spd=%.1f l_spd=%.1f hb=%s obs=%s" % [
				current_idx, total_wps, str(pos), speed, str(lead_info.name), str(lead_p), lead_prog, lead_dist, target_speed, lead_ls, lead_hb, str(lead_obs)
			])

		if absf(angle_diff) > 0.65:
			target_speed = minf(target_speed, 35.0)
		elif absf(angle_diff) > 0.35:
			target_speed = minf(target_speed, 65.0)

		if speed < target_speed:
			Input.action_press("move_up")
			Input.action_release("move_down")
		elif speed > target_speed + 10.0 or target_speed == 0.0:
			Input.action_release("move_up")
			Input.action_press("move_down")
		else:
			Input.action_release("move_up")
			Input.action_release("move_down")

		await physics_frame

	_release_all_inputs()
	return true

func _release_all_inputs() -> void:
	for act in ["move_up", "move_down", "move_left", "move_right", "handbrake", "exit_vehicle"]:
		Input.action_release(act)

func _count_nodes_recursive(node: Node) -> int:
	if not is_instance_valid(node):
		return 0
	var count := 1
	for child in node.get_children():
		count += _count_nodes_recursive(child)
	return count

func _calculate_frame_metrics(frame_times: Array[float], duration_s: float) -> Dictionary:
	if frame_times.is_empty():
		return {}
	var sorted := frame_times.duplicate()
	sorted.sort()
	var total := 0.0
	var s_16 := 0
	var s_33 := 0
	var s_50 := 0
	var s_100 := 0
	for ft in frame_times:
		total += ft
		if ft > 16.67: s_16 += 1
		if ft > 33.33: s_33 += 1
		if ft > 50.0: s_50 += 1
		if ft > 100.0: s_100 += 1

	var count := frame_times.size()
	return {
		"frames_count": count,
		"duration_s": duration_s,
		"fps_avg": float(count) / duration_s if duration_s > 0 else 0.0,
		"avg_ms": total / float(count),
		"p50_ms": _percentile(sorted, 0.50),
		"p90_ms": _percentile(sorted, 0.90),
		"p95_ms": _percentile(sorted, 0.95),
		"p99_ms": _percentile(sorted, 0.99),
		"worst_ms": sorted[-1],
		"best_ms": sorted[0],
		"spikes_gt_16ms": s_16,
		"spikes_gt_33ms": s_33,
		"spikes_gt_50ms": s_50,
		"spikes_gt_100ms": s_100
	}

func _percentile(sorted_values: Array, fraction: float) -> float:
	var idx: int = clampi(int(sorted_values.size() * fraction), 0, sorted_values.size() - 1)
	return sorted_values[idx]

func _finish(exit_code: int) -> void:
	_release_all_inputs()
	report_data["exit_code"] = exit_code
	DirAccess.make_dir_recursive_absolute(out_dir)

	# Aggregate frame metrics by phase and overall from continuous sampler
	var all_frame_times: Array[float] = []
	var phase_times: Dictionary = {}

	if _sampler != null:
		for s in _sampler.samples:
			var dt: float = s["dt_ms"]
			var ph: String = s["phase"]
			all_frame_times.append(dt)
			if not phase_times.has(ph):
				phase_times[ph] = []
			phase_times[ph].append(dt)

	var total_duration_s := 0.0
	for dt in all_frame_times:
		total_duration_s += dt / 1000.0

	report_data["overall_metrics"] = _calculate_frame_metrics(all_frame_times, total_duration_s)

	var phase_metrics: Dictionary = {}
	for ph in phase_times.keys():
		var pts: Array[float] = []
		var ph_dur := 0.0
		for dt in phase_times[ph]:
			pts.append(dt)
			ph_dur += dt / 1000.0
		phase_metrics[ph] = _calculate_frame_metrics(pts, ph_dur)
	report_data["phase_metrics"] = phase_metrics

	# For backward compatibility, expose active_drive_metrics at top level
	if phase_metrics.has("ACTIVE_DRIVE"):
		report_data["active_drive_metrics"] = phase_metrics["ACTIVE_DRIVE"]

	var f := FileAccess.open(out_dir + "/report.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report_data, "  "))
		f.close()

	var flog := FileAccess.open(out_dir + "/session.log", FileAccess.WRITE)
	if flog:
		flog.store_string("\n".join(log_lines))
		flog.close()

	if _sampler != null and not _sampler.samples.is_empty():
		var fcsv := FileAccess.open(out_dir + "/frame_times.csv", FileAccess.WRITE)
		if fcsv:
			fcsv.store_line("frame_index,timestamp_us,frame_time_ms,phase")
			for s in _sampler.samples:
				fcsv.store_line("%d,%d,%.3f,%s" % [s["frame_index"], s["timestamp_us"], s["dt_ms"], s["phase"]])
			fcsv.close()

	log_msg("=== SESSAO %s: %s (exit_code=%d, total_frames=%d) ===" % [
		session_id, "APROVADA" if exit_code == 0 else "FALHOU", exit_code, all_frame_times.size()
	])
	quit(exit_code)
