extends SceneTree
## GETECO-PERF-01-ANTIGRAVITY: Sessão de Auditoria Integrada e Ablações Controladas
## Executa com renderização real (Vulkan Mobile, 1280x720).
## Compara Baseline de condução em HarborGame com ablações diagnósticas pontuais:
## 1. Baseline: 30s condução (mesma rota e condições da auditoria do Claude)
## 2. Ablação SubViewports: congela todos os SubViewports (UPDATE_DISABLED) mantendo a última textura
## 3. Ablação Animação/IK CPU: pausa a trigonometria procedural de CitizenGait
## 4. Ablação Áudio: muta AudioServer
## 5. Resolução: compara carga nativa 1280x720 vs 1920x1080
##
## Salva resultados em tests/perf_audit_antigravity/results/report_antigravity.json

const HARBOR := "res://world/harbor/HarborGame.tscn"

var run_name := "session"
var results_dir := "res://tests/perf_audit_antigravity/results/"
var report := {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requer renderização real")
		quit(1)
		return

	# Garante que user data está isolado
	if not OS.get_user_data_dir().replace("\\", "/").contains("perf_audit_antigravity"):
		push_error("User data não isolado: %s" % OS.get_user_data_dir())
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)

	var saves = root.get_node_or_null("SaveManager")
	if saves:
		saves.set("_save_dir", "res://tests/perf_audit_antigravity/temp_saves/")
		saves.set("_save_directory_ready", false)
		saves.clear_pending_save()

	var campaign = root.get_node_or_null("CampaignState")
	if campaign:
		campaign.reset_campaign()
		for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
			campaign.set_campaign_flag(StringName(flag), true)

	report["environment"] = {
		"os": OS.get_name(),
		"engine_version": Engine.get_version_info()["string"],
		"debug_build": OS.is_debug_build(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"api_version": RenderingServer.get_video_adapter_api_version(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"vsync": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps,
		"window_size": "%dx%d" % [root.size.x, root.size.y]
	}

	print("=== CARREGANDO HARBORGAME ===")
	var t_load_start := Time.get_ticks_usec()
	var world = load(HARBOR).instantiate()
	root.add_child(world)
	current_scene = world

	var deadline := Time.get_ticks_msec() + 60000
	while (not world.get("gameplay_ready") or not world.get("world_build_ready")) and Time.get_ticks_msec() < deadline:
		await process_frame

	report["loading_time_ms"] = (Time.get_ticks_usec() - t_load_start) / 1000.0
	print("HarborGame carregado em %.2f ms" % report["loading_time_ms"])

	# Estabilização inicial
	for i in 60:
		await process_frame

	var player: Node2D = world.get_node("Player")
	var car: CharacterBody2D = world.get_node("PlayerCar")
	player.global_position = Vector2(2200, 1050)
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	world.call("_drive")

	# Settle inicial de 3 segundos
	print("Settle 3s...")
	for i in 180:
		await process_frame

	report["experiments"] = {}

	# -------------------------------------------------------------
	# 1. BASELINE (30s de condução normal com tráfego e pedestres)
	# -------------------------------------------------------------
	print("\n>>> Executando: 1. BASELINE (30s)")
	report["experiments"]["baseline"] = await _measure_drive(world, car, 30.0)

	# -------------------------------------------------------------
	# 2. ABLAÇÃO: CONGELAMENTO DE SUBVIEWPORTS
	# -------------------------------------------------------------
	print("\n>>> Executando: 2. ABLAÇÃO SUBVIEWPORTS CONGELADOS")
	var all_vps := root.find_children("*", "SubViewport", true, false)
	var saved_modes := {}
	for vp in all_vps:
		var s := vp as SubViewport
		if s != root:
			saved_modes[s] = s.render_target_update_mode
			s.render_target_update_mode = SubViewport.UPDATE_DISABLED

	_reset_car(car)
	report["experiments"]["ablation_frozen_subviewports"] = await _measure_drive(world, car, 30.0)

	# Restaura modos originais dos SubViewports
	for s in saved_modes:
		if is_instance_valid(s):
			s.render_target_update_mode = saved_modes[s]

	# -------------------------------------------------------------
	# 3. ABLAÇÃO: SEM IK PROCEDURAL DE PEDESTRES (CitizenGait)
	# -------------------------------------------------------------
	print("\n>>> Executando: 3. ABLAÇÃO SEM IK PROCEDURAL DE PEDESTRES")
	var peds = get_nodes_in_group("pedestrian")
	for p in peds:
		p.set_meta("skip_gait_ik", true)

	_reset_car(car)
	report["experiments"]["ablation_no_pedestrian_ik"] = await _measure_drive(world, car, 30.0)

	for p in peds:
		if is_instance_valid(p):
			p.remove_meta("skip_gait_ik")

	# -------------------------------------------------------------
	# 4. ABLAÇÃO: ÁUDIO MUTADO
	# -------------------------------------------------------------
	print("\n>>> Executando: 4. ABLAÇÃO ÁUDIO MUTADO")
	for b in AudioServer.bus_count:
		AudioServer.set_bus_mute(b, true)

	_reset_car(car)
	report["experiments"]["ablation_mute_audio"] = await _measure_drive(world, car, 30.0)

	for b in AudioServer.bus_count:
		AudioServer.set_bus_mute(b, false)

	# -------------------------------------------------------------
	# 5. TESTE DE RESOLUÇÃO: 1920x1080 vs 1280x720
	# -------------------------------------------------------------
	print("\n>>> Executando: 5. RESOLUÇÃO 1920x1080")
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	await process_frame
	await process_frame

	_reset_car(car)
	report["experiments"]["res_1920x1080"] = await _measure_drive(world, car, 30.0)

	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)

	# Salva relatório JSON
	var json_str := JSON.stringify(report, "\t")
	var dir_path := ProjectSettings.globalize_path("res://tests/perf_audit_antigravity/results")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open("res://tests/perf_audit_antigravity/results/report_antigravity.json", FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()

	print("\n=== RESUMO COMPARATIVO DE EXPERIMENTOS ===")
	print("%-30s | %-7s | %-8s | %-8s | %-8s | %-8s | %-8s | %-8s" % [
		"Cenário", "Frames", "p50 (ms)", "p95 (ms)", "p99 (ms)", "Máx (ms)", "DrawCalls", "GPU (ms)"
	])
	for exp_name in report["experiments"]:
		var data = report["experiments"][exp_name]
		print("%-30s | %7d | %8.2f | %8.2f | %8.2f | %8.2f | %8.0f | %8.2f" % [
			exp_name, data.frames, data.p50, data.p95, data.p99, data.max, data.avg_draw_calls, data.avg_render_gpu_ms
		])

	print("\nResultados gravados em res://tests/perf_audit_antigravity/results/report_antigravity.json")
	print("=== FIM DA AUDITORIA ANTIGRAVITY ===")
	quit(0)

func _reset_car(car: CharacterBody2D) -> void:
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	car.velocity = Vector2.ZERO
	car.reset_physics_interpolation()

func _measure_drive(world: Node, car: CharacterBody2D, duration_sec: float) -> Dictionary:
	var frame_ms: Array[float] = []
	var proc_ms: Array[float] = []
	var phys_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var gpu_ms: Array[float] = []
	var cpu_render_ms: Array[float] = []

	var target_frames := int(duration_sec * 60.0)
	var start_time := Time.get_ticks_usec()
	var prev_time := start_time

	Input.action_press("move_up")

	var frames_over_16 := 0
	var frames_over_33 := 0
	var frames_over_50 := 0
	var frames_over_100 := 0

	var now := start_time
	for i in target_frames:
		await process_frame
		now = Time.get_ticks_usec()
		var dt := (now - prev_time) / 1000.0
		prev_time = now

		frame_ms.append(dt)
		proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu_render_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))

		if dt > 16.67: frames_over_16 += 1
		if dt > 33.33: frames_over_33 += 1
		if dt > 50.0: frames_over_50 += 1
		if dt > 100.0: frames_over_100 += 1

	Input.action_release("move_up")

	var sorted_ms := frame_ms.duplicate()
	sorted_ms.sort()
	var count := sorted_ms.size()

	var sum_draw_calls := 0.0
	for dc in draw_calls: sum_draw_calls += dc
	var sum_gpu := 0.0
	for g in gpu_ms: sum_gpu += g
	var sum_proc := 0.0
	for p in proc_ms: sum_proc += p
	var sum_phys := 0.0
	for ph in phys_ms: sum_phys += ph

	return {
		"frames": count,
		"p50": sorted_ms[int(count * 0.50)],
		"p95": sorted_ms[int(count * 0.95)],
		"p99": sorted_ms[int(count * 0.99)],
		"max": sorted_ms[-1],
		"avg_ms": (now - start_time) / (1000.0 * count),
		"avg_draw_calls": sum_draw_calls / count,
		"avg_render_gpu_ms": sum_gpu / count,
		"avg_proc_ms": sum_proc / count,
		"avg_phys_ms": sum_phys / count,
		"frames_over_16": frames_over_16,
		"frames_over_33": frames_over_33,
		"frames_over_50": frames_over_50,
		"frames_over_100": frames_over_100
	}
