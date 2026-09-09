extends SceneTree

func _init() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("=================================================================")
	print("=== TESTE: ENGINE DE PASSOS SUTIS E PASSOS NA CHUVA (WET) =======")
	print("=================================================================")

	# 1. Testar streams secos (concrete)
	print("[PASSO 1] Testando sintese e variacoes de passos secos (concreto)...")
	for v in range(4):
		var stream = ProceduralAudio.get_footstep_stream("concrete", v)
		assert(stream is AudioStreamWAV, "Stream de passo seco deve ser AudioStreamWAV")
		var wav = stream as AudioStreamWAV
		assert(wav.data.size() > 0, "Audio data nao pode ser vazio")
		print("  ✓ Variacao seca %d gerada: mix_rate=%d, samples=%d" % [v, wav.mix_rate, wav.data.size() / 2])

	# 2. Testar streams molhados (wet / rain)
	print("[PASSO 2] Testando sintese e variacoes de passos molhados (chuva/poca)...")
	for v in range(4):
		var stream_wet = ProceduralAudio.get_footstep_stream("wet", v)
		assert(stream_wet is AudioStreamWAV, "Stream de passo molhado deve ser AudioStreamWAV")
		var wav_wet = stream_wet as AudioStreamWAV
		assert(wav_wet.data.size() > 0, "Audio data de chuva nao pode ser vazio")
		print("  ✓ Variacao molhada %d gerada: mix_rate=%d, samples=%d" % [v, wav_wet.mix_rate, wav_wet.data.size() / 2])

	# 3. Testar Player com tempo seco
	print("[PASSO 3] Testando integracao no Player (Tempo Seco)...")
	var player_script = load("res://Player.gd")
	var player = CharacterBody2D.new()
	player.set_script(player_script)
	root.add_child(player)
	await process_frame

	assert(not player._is_raining_outside(), "Em tempo padrao nao deve estar chovendo")
	player.walk_clock = 1.0 # sin(1.0) > 0
	player._handle_footsteps(true, false) # walking
	await process_frame

	# Encontrar o AudioStreamPlayer2D gerado
	var footstep_node: AudioStreamPlayer2D = null
	for child in player.get_children():
		if child is AudioStreamPlayer2D and child != player.get_node_or_null("EngineAudio"):
			footstep_node = child
			break

	assert(footstep_node != null, "Player deve ter gerado um AudioStreamPlayer2D de passos")
	print("  ✓ Volume do passo seco caminhando: %.1f dB (Sutil!)" % footstep_node.volume_db)
	assert(footstep_node.volume_db <= -28.0, "Volume de passos caminhando deve ser sutil (<= -28 dB)")

	# 4. Testar Player na chuva (DayNightWeatherManager)
	print("[PASSO 4] Ativando chuva no DayNightWeatherManager e testando passos molhados...")
	var dnm_script = load("res://DayNightWeatherManager.gd")
	var dnm = CanvasModulate.new()
	dnm.set_script(dnm_script)
	root.add_child(dnm)
	dnm.set_weather(1) # 1 = chuva
	await process_frame

	assert(dnm.is_raining(), "DayNightWeatherManager deve reportar is_raining() == true")
	assert(player._is_raining_outside(), "Player deve detectar chuva externa")

	# Disparar passo na chuva
	player.walk_clock = -1.0 # alternar lado
	player._handle_footsteps(true, true) # sprinting na chuva
	await process_frame

	var wet_footstep_node: AudioStreamPlayer2D = null
	for child in player.get_children():
		if child is AudioStreamPlayer2D and child != footstep_node:
			wet_footstep_node = child
			break

	assert(wet_footstep_node != null, "Player deve ter gerado passo molhado na chuva")
	print("  ✓ Volume do passo correndo na chuva: %.1f dB" % wet_footstep_node.volume_db)
	assert(wet_footstep_node.volume_db <= -24.0, "Volume correndo deve ser <= -24 dB")

	# Testar modo interior (dentro de loja, não deve chover no pé!)
	print("[PASSO 5] Testando modo interior (dentro de predio/loja)...")
	dnm.set_interior_mode(true)
	await process_frame
	assert(not player._is_raining_outside(), "Dentro de interiores nao deve ter som de passo molhado")
	print("  ✓ Dentro de interior, passos voltam a ser secos automaticamente!")

	print("=================================================================")
	print("=== SUCESSO: TESTES DE PASSOS SUTIS E CHUVA APROVADOS! (EXIT 0) =")
	print("=================================================================")
	quit(0)
