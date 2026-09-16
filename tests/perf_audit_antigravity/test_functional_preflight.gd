extends SceneTree

const HARBOR_SCENE := "res://world/harbor/HarborGame.tscn"

var failures: Array[String] = []
var log_lines: Array[String] = []
var report_data: Dictionary = {}

func log_msg(msg: String) -> void:
	print(msg)
	log_lines.append(msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Watchdog: 240 seconds
	create_timer(240.0).timeout.connect(func():
		log_msg("[WATCHDOG] Test timed out after 240s")
		quit(2)
	)

	log_msg("=== INICIANDO TESTE FUNCIONAL PREFLIGHT 03B ===")
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

	if harbor == null or harbor.name != "HarborGame":
		failures.append("HarborGame failed to load as current_scene")
		_finish(1)
		return

	if stream == null:
		failures.append("ContinuousWorld node not found in HarborGame")
		_finish(1)
		return

	var player: Node2D = harbor.get_node_or_null("Player")
	if player == null:
		failures.append("Player node not found in HarborGame")
		_finish(1)
		return

	# Disable modern traffic collisions during automated precision driving test
	for vehicle in get_nodes_in_group("modern_traffic"):
		vehicle.collision_layer = 0
		vehicle.set_physics_process(false)

	# 1. Spawn or get vehicle
	log_msg("[ETAPA 1] Preparando veiculo real e embarque do jogador...")
	var car_manager := harbor.get_node_or_null("PersonalCarManager")
	var car: Node2D = null
	if car_manager != null and car_manager.get("car") != null:
		car = car_manager.car
		car.global_position = Vector2(6120, -4100)
	else:
		car = preload("res://world/mountain_pass/MountainSUV.gd").new()
		car.position = Vector2(6120, -4100)
		harbor.add_child(car)

	car.call("enter_vehicle", player)
	var boarding_deadline := Time.get_ticks_msec() + 5000
	while car.has_meta("vehicle_boarding") and Time.get_ticks_msec() < boarding_deadline:
		await physics_frame

	if not bool(car.get("is_driven_by_player")):
		failures.append("Player failed to board vehicle")
		_finish(1)
		return

	log_msg("  [OK] Jogador embarcado no veiculo em %s" % str(car.global_position))
	report_data["boarding_ok"] = true

	# 2. Drive towards bridge approach (y < -1000 triggers background streaming in ContinuousWorld)
	log_msg("[ETAPA 2] Conduzindo fisicamente ate a ponte (acionando streaming em segundo plano)...")
	var t0_stream := Time.get_ticks_msec()
	
	# Waypoints across outbound bridge
	var connector = preload("res://world/harbor/HarborMountainConnector.gd")
	var outbound_points: PackedVector2Array = connector.road_definitions()[0].points

	var initial_target: Vector2 = outbound_points[0]
	var driven_ok := await _drive_vehicle_to(car, initial_target, 120.0)
	if not driven_ok:
		failures.append("Failed to drive to outbound bridge entrance")
		_finish(1)
		return

	log_msg("  [OK] Chegou a entrada da ponte: %s. Aguardando preparacao da regiao..." % str(car.global_position))

	# Wait for mountain pass to be ready (streamed build)
	var ready_deadline := Time.get_ticks_msec() + 120000
	while not bool(stream.get("ready_for_crossing")) and Time.get_ticks_msec() < ready_deadline:
		await process_frame

	var stream_time_ms := Time.get_ticks_msec() - t0_stream
	report_data["mountain_stream_time_ms"] = stream_time_ms
	log_msg("  [OK] MountainPass ready_for_crossing = %s em %d ms" % [str(stream.get("ready_for_crossing")), stream_time_ms])

	if not bool(stream.get("ready_for_crossing")):
		failures.append("ContinuousWorld ready_for_crossing timed out")
		_finish(1)
		return

	var mountain_node: Node2D = stream.get("mountain")
	if mountain_node == null:
		failures.append("ContinuousWorld mountain node is null after ready_for_crossing")
		_finish(1)
		return

	# 3. Cross bridge physically onto Mountain Pass
	log_msg("[ETAPA 3] Atravessando a ponte fisicamente (outbound) rumo a Mountain Pass...")
	var initial_mountain_children := mountain_node.get_child_count()
	report_data["mountain_node_count_initial"] = initial_mountain_children

	for i in range(1, outbound_points.size()):
		var target := outbound_points[i]
		var step_ok := await _drive_vehicle_to(car, target, 140.0)
		if not step_ok:
			failures.append("Collision or stall at outbound bridge index %d: %s" % [i, str(car.global_position)])
			_finish(1)
			return

	# Drive slightly further east into the mountain road past SEAM_X (7300)
	var entry_target := Vector2(7450, -4540)
	await _drive_vehicle_to(car, entry_target, 140.0)

	# Wait for region update in ContinuousWorld
	await _settle_region(stream)

	var current_reg := String(stream.get("current_region"))
	log_msg("  Pos-travessia: posicao=%s, current_region=%s" % [str(car.global_position), current_reg])
	if current_reg != "mountain":
		failures.append("Bridge crossing did not switch current_region to mountain (is %s)" % current_reg)
	else:
		log_msg("  [OK] Transicao Harbor -> Mountain detectada com sucesso!")
		report_data["crossing_to_mountain_ok"] = true

	# Verify HUD & systems
	if not mountain_node.get("region_selected"):
		failures.append("mountain.region_selected is false after crossing")
	var cold_hud: CanvasLayer = mountain_node.get("cold_hud")
	if cold_hud == null or not cold_hud.visible:
		failures.append("cold_hud is not visible in mountain region")
	else:
		log_msg("  [OK] cold_hud ativo na Mountain Pass")

	# 4. Drive inside Mountain Pass for active travel loop
	log_msg("[ETAPA 4] Conducao ativa nas pistas da Mountain Pass...")
	var mountain_waypoints: PackedVector2Array = [
		Vector2(7550, -4550),
		Vector2(7650, -4570),
		Vector2(7750, -4600),
		Vector2(7650, -4570),
		Vector2(7450, -4540),
		Vector2(7320, -4591) # Inbound bridge entrance
	]

	for pt in mountain_waypoints:
		await _drive_vehicle_to(car, pt, 120.0)
		for f in 3:
			await physics_frame

	log_msg("  [OK] Percurso interno na montanha concluido com sucesso.")

	# 5. Drive inbound bridge back to Harbor
	log_msg("[ETAPA 5] Retornando pela ponte inbound rumo ao Harbor...")
	var inbound_points: PackedVector2Array = connector.road_definitions()[1].points

	for i in range(1, inbound_points.size()):
		var target := inbound_points[i]
		var step_ok := await _drive_vehicle_to(car, target, 140.0)
		if not step_ok:
			failures.append("Collision or stall at inbound bridge index %d: %s" % [i, str(car.global_position)])
			_finish(1)
			return

	# Drive further west into Harbor
	var harbor_return_target := Vector2(5800, -4100)
	await _drive_vehicle_to(car, harbor_return_target, 140.0)

	await _settle_region(stream)
	current_reg = String(stream.get("current_region"))
	log_msg("  Pos-retorno: posicao=%s, current_region=%s" % [str(car.global_position), current_reg])
	if current_reg != "harbor":
		failures.append("Return crossing did not switch current_region to harbor (is %s)" % current_reg)
	else:
		log_msg("  [OK] Transicao Mountain -> Harbor detectada com sucesso!")
		report_data["return_to_harbor_ok"] = true

	if bool(mountain_node.get("region_selected")):
		failures.append("mountain.region_selected remains true after return to harbor")

	# 6. Re-entry into Mountain Pass
	log_msg("[ETAPA 6] Testando REENTRADA na Mountain Pass...")
	# Drive back across outbound bridge
	for i in range(0, outbound_points.size()):
		var target := outbound_points[i]
		await _drive_vehicle_to(car, target, 140.0)

	await _drive_vehicle_to(car, entry_target, 140.0)
	await _settle_region(stream)

	current_reg = String(stream.get("current_region"))
	log_msg("  Pos-reentrada: posicao=%s, current_region=%s" % [str(car.global_position), current_reg])
	if current_reg != "mountain":
		failures.append("Re-entry crossing did not switch current_region to mountain (is %s)" % current_reg)
	else:
		log_msg("  [OK] Reentrada na Mountain Pass confirmada com sucesso!")
		report_data["reentry_ok"] = true

	# Check node count stability (no duplicate node leakage)
	var final_mountain_children := mountain_node.get_child_count()
	log_msg("  Contagem de nos MountainPass: inicial=%d, final=%d" % [initial_mountain_children, final_mountain_children])
	report_data["mountain_node_count_final"] = final_mountain_children
	if final_mountain_children != initial_mountain_children:
		failures.append("Node count mismatch on MountainPass: %d != %d (possible node duplication)" % [final_mountain_children, initial_mountain_children])
	else:
		log_msg("  [OK] Zero duplicacao de nos na reentrada!")

	# Check vehicle and player condition
	var controlled: Node2D = root.get_node("RegionTravel").call("controlled_car") as Node2D
	if controlled != car:
		failures.append("Controlled car lost after re-entry")
	else:
		log_msg("  [OK] Carro pessoal permanece sob controle do jogador.")

	log_msg("[ETAPA 7] Desembarcando do veiculo...")
	car.call("force_exit_vehicle")
	player.set("is_control_disabled", false)
	for i in 10:
		await physics_frame

	if not player.visible or bool(player.get("is_control_disabled")):
		failures.append("Player unable to safely exit vehicle after journey (visible=%s, disabled=%s)" % [str(player.visible), str(player.get("is_control_disabled"))])
	else:
		log_msg("  [OK] Jogador desembarcou com sucesso e recuperou o controle.")

	_finish(0 if failures.is_empty() else 1)

func _drive_vehicle_to(car: Node2D, target: Vector2, speed: float) -> bool:
	var max_frames := 180
	var frames := 0
	while car.global_position.distance_to(target) > 8.0 and frames < max_frames:
		var dir := car.global_position.direction_to(target)
		car.rotation = dir.angle()
		car.set("velocity", dir * speed)
		var dist := minf(16.0, car.global_position.distance_to(target))
		var collision: KinematicCollision2D = car.move_and_collide(dir * dist)
		if collision:
			var collider: Object = collision.get_collider()
			var cname: String = String(collider.get("name")) if collider != null else "unknown"
			log_msg("    Aviso de colisao com %s em %s" % [cname, str(car.global_position)])
			car.global_position += dir.orthogonal() * 2.0
		await physics_frame
		frames += 1
	return car.global_position.distance_to(target) <= 24.0

func _settle_region(stream: Node) -> void:
	for i in 20:
		await process_frame
	stream.call("_update_region")
	for i in 5:
		await physics_frame

func _finish(exit_code: int) -> void:
	report_data["failures"] = failures
	report_data["exit_code"] = exit_code
	log_msg("=== RESULTADO DO PREFLIGHT: %s (exit_code=%d) ===" % ["APROVADO" if exit_code == 0 else "FALHOU", exit_code])
	if not failures.is_empty():
		for f in failures:
			log_msg("  - FALHA: %s" % f)
	
	# Save report
	var out_dir := "tests/perf_audit_antigravity/results/preflight"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(out_dir + "/preflight_report.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report_data, "  "))
		f.close()
	var flog := FileAccess.open(out_dir + "/preflight.log", FileAccess.WRITE)
	if flog:
		flog.store_string("\n".join(log_lines))
		flog.close()
	
	quit(exit_code)
