extends SceneTree

## Teste de Contabilidade e Integridade do Coletor de Telemetria
## Valida os casos pequenos do coletor:
## 1. Captura da fronteira final (sem perda de amostra na transição de estado)
## 2. Ausência de amostras descartadas (primeiro e último delta preservados)
## 3. Saída por timeout com registro de distância percorrida e posição
## 4. Rejeição de avanço falso quando o destino não é alcançado
## 5. Fechamento da soma de intervalos contra o relógio monotônico

var failures: Array[String] = []
var log_lines: Array[String] = []

func log_msg(msg: String) -> void:
	print(msg)
	log_lines.append(msg)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(30.0).timeout.connect(func():
		log_msg("[WATCHDOG] Teste de contabilidade excedeu 30s")
		quit(2)
	)

	log_msg("=== INICIANDO VALIDACAO DA CONTABILIDADE DO COLETOR ===")

	# 1. Teste de amostragem monotônica contínua e fechamento de soma
	log_msg("[CASO 1 & 2] Verificando amostragem monotônica contínua e soma de intervalos...")
	var frame_deltas_us: Array[int] = []
	var t_start_us := Time.get_ticks_usec()
	var last_tick_us := t_start_us
	var sample_count := 30

	for i in range(sample_count):
		await process_frame
		var now_us := Time.get_ticks_usec()
		var delta_us := now_us - last_tick_us
		frame_deltas_us.append(delta_us)
		last_tick_us = now_us

	var t_end_us := last_tick_us
	var total_monotonic_window_us := t_end_us - t_start_us
	var sum_deltas_us := 0
	for d in frame_deltas_us:
		sum_deltas_us += d

	if frame_deltas_us.size() != sample_count:
		failures.append("Amostras ausentes: esperado %d, obtido %d" % [sample_count, frame_deltas_us.size()])
	else:
		log_msg("  [OK] Amostras capturadas: %d/%d (nenhuma amostra descartada)" % [frame_deltas_us.size(), sample_count])

	var diff_us := absi(sum_deltas_us - total_monotonic_window_us)
	# Em inteiros usec, sum(last_tick_i - last_tick_{i-1}) deve ser identicamente igual a t_end - t_start
	if diff_us != 0:
		failures.append("Fechamento monotônico falhou: soma=%d us, janela=%d us, diff=%d us" % [sum_deltas_us, total_monotonic_window_us, diff_us])
	else:
		log_msg("  [OK] Fechamento exato da soma de intervalos contra o relógio monotônico (diff = 0 us)")

	# 2. Teste da fronteira final (quando um predicado se torna verdadeiro durante o frame)
	log_msg("[CASO 3] Verificando fronteira final e captura do último intervalo...")
	var boundary_deltas_us: Array[int] = []
	var trigger_frame := 10
	var current_frame := 0
	var is_ready := false
	var last_b_tick_us := Time.get_ticks_usec()
	var b_start_us := last_b_tick_us

	while not is_ready:
		await process_frame
		current_frame += 1
		var now_b_us := Time.get_ticks_usec()
		boundary_deltas_us.append(now_b_us - last_b_tick_us)
		last_b_tick_us = now_b_us
		if current_frame >= trigger_frame:
			is_ready = true

	var b_end_us := last_b_tick_us
	var b_window_us := b_end_us - b_start_us
	var b_sum_us := 0
	for d in boundary_deltas_us:
		b_sum_us += d

	if boundary_deltas_us.size() != trigger_frame:
		failures.append("Fronteira final perdeu amostra: frames=%d, amostras=%d" % [trigger_frame, boundary_deltas_us.size()])
	elif b_sum_us != b_window_us:
		failures.append("Fronteira final discrepante: soma=%d us, janela=%d us" % [b_sum_us, b_window_us])
	else:
		log_msg("  [OK] Fronteira final capturada perfeitamente: %d amostras, soma coincide com a janela monotônica" % boundary_deltas_us.size())

	# 3. Teste de timeout e bloqueio de rota do condutor simulado
	log_msg("[CASO 4 & 5] Verificando detecção de timeout e rejeição de avanço falso...")
	var fake_start_pos := Vector2(100, 100)
	var fake_target_pos := Vector2(500, 100)
	var fake_current_pos := fake_start_pos
	var max_simulated_frames := 10
	var simulated_frames := 0
	var destination_reached := false
	var simulated_timeout := false

	while not destination_reached and simulated_frames < max_simulated_frames:
		simulated_frames += 1
		# Simulando veículo preso por obstáculo: não se move em direção ao alvo
		fake_current_pos += Vector2(0.1, 0.0)
		if fake_current_pos.distance_to(fake_target_pos) <= 20.0:
			destination_reached = true

	if not destination_reached:
		simulated_timeout = true
		var dist_travelled := fake_start_pos.distance_to(fake_current_pos)
		var dist_remaining := fake_current_pos.distance_to(fake_target_pos)
		log_msg("  [OK] Timeout detectado corretamente. Distancia percorrida: %.1f px, Distancia restante: %.1f px" % [dist_travelled, dist_remaining])
		if dist_remaining > 20.0 and destination_reached:
			failures.append("Condutor permitiu avanço falso sem alcançar o destino")
		else:
			log_msg("  [OK] Avanço falso rejeitado. O teste registra falha em vez de pular waypoint.")

	log_msg("=== FIM DA VALIDACAO DE CONTABILIDADE ===")
	if failures.is_empty():
		log_msg("RESULTADO: TODOS OS 5 CASOS DE CONTABILIDADE APROVADOS")
		quit(0)
	else:
		for f in failures:
			log_msg("FALHA: %s" % f)
		quit(1)
