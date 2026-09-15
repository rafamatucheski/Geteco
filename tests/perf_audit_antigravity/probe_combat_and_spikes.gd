extends SceneTree
## GETECO-PERF-01-ANTIGRAVITY: Diagnóstico de Picos (CLAUDE-PERF-005 e Primeiro Tiro)
## Mede com precisão de microssegundos:
## 1. Primeiro tiro:
##    - Carga síncrona dos 25 arquivos WAV em CombatAudioBank
##    - Instanciação de 10 AudioStreamPlayer2D em CombatImpactAudio
##    - Instanciação e primeiro frame de Bullet, ShotFeedback, WeaponEffects
##    - Comparação do 1º disparo com o 2º disparo na mesma sessão
## 2. Impacto em semáforo (FixedTrafficSignal):
##    - Construção de SubViewport 384x384 com MSAA 2X e TrafficSignalModel3D
##    - Primeiro frame de renderização vs segundo frame no tween de queda

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requer renderização real")
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)

	for i in 10:
		await process_frame

	print("=== DIAGNÓSTICO: PRIMEIRO TIRO E COMBATIMPACTAUDIO ===")
	
	# Teste isolado A: Carregamento do banco de áudio de combate
	var materials := ["metal", "concrete", "flesh", "wood", "glass"]
	var total_wav_files := 0
	var bank = preload("res://audio/combat/CombatAudioBank.gd")

	var t0 := Time.get_ticks_usec()
	for mat in materials:
		for take in 5:
			var path := "res://audio/combat/%s_%d.wav" % [mat, take]
			if ResourceLoader.exists(path):
				var s = load(path)
				total_wav_files += 1
	var t_raw_wav_load := Time.get_ticks_usec() - t0
	print("[1.1] Carregamento síncrono de %d arquivos WAV de impacto (disco/cache): %.3f ms" % [
		total_wav_files, t_raw_wav_load / 1000.0
	])

	# Teste isolado B: Instanciação de CombatImpactAudio
	t0 = Time.get_ticks_usec()
	var impact_audio_node = load("res://audio/combat/CombatImpactAudio.gd").new()
	var t_audio_pool_new := Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec()
	root.add_child(impact_audio_node) # Executa _ready() que instancia os 10 AudioStreamPlayer2D
	var t_audio_pool_ready := Time.get_ticks_usec() - t0

	print("[1.2] Instanciação de CombatImpactAudio.new(): %.3f ms" % (t_audio_pool_new / 1000.0))
	print("[1.3] Entrada na árvore de CombatImpactAudio (criação de 10 AudioStreamPlayer2D): %.3f ms" % [
		t_audio_pool_ready / 1000.0
	])

	# Teste isolado C: Disparo real de projétil (1º tiro vs 2º tiro)
	var bullet_scene = load("res://guns/Bullet.tscn")
	var dummy_target = StaticBody2D.new()
	var dummy_col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(50, 50)
	dummy_col.shape = shape
	dummy_target.add_child(dummy_col)
	dummy_target.position = Vector2(400, 300)
	dummy_target.set_meta("physics_material", &"concrete")
	root.add_child(dummy_target)

	# 1º Tiro
	t0 = Time.get_ticks_usec()
	var bullet1 = bullet_scene.instantiate()
	bullet1.position = Vector2(390, 300)
	bullet1.direction = Vector2.RIGHT
	root.add_child(bullet1)
	var t_shot1_spawn := Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec()
	await process_frame
	var t_shot1_frame := Time.get_ticks_usec() - t0

	print("[1.4] 1º TIRO: Instanciação=%.3f ms | Frame total de voo/impacto=%.3f ms" % [
		t_shot1_spawn / 1000.0, t_shot1_frame / 1000.0
	])

	# 2º Tiro (Cenário quente / pós-primeiro uso)
	t0 = Time.get_ticks_usec()
	var bullet2 = bullet_scene.instantiate()
	bullet2.position = Vector2(390, 300)
	bullet2.direction = Vector2.RIGHT
	root.add_child(bullet2)
	var t_shot2_spawn := Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec()
	await process_frame
	var t_shot2_frame := Time.get_ticks_usec() - t0

	print("[1.5] 2º TIRO: Instanciação=%.3f ms | Frame total de voo/impacto=%.3f ms" % [
		t_shot2_spawn / 1000.0, t_shot2_frame / 1000.0
	])

	print("\n=== DIAGNÓSTICO: IMPACTO EM SEMÁFORO (FIXEDTRAFFICSIGNAL) ===")
	
	# Simula o caminho exato de queda de FixedTrafficSignal
	var signal_script = load("res://geodata/roads/traffic/FixedTrafficSignal.gd")
	var signal_node = signal_script.new()
	signal_node.entry_tangent = Vector2.RIGHT
	root.add_child(signal_node)
	await process_frame

	# 1º Impacto (Criação do SubViewport 384x384 MSAA 2X para a queda)
	t0 = Time.get_ticks_usec()
	signal_node.receive_vehicle_impact(250.0, Vector2.RIGHT)
	var t_impact_call := Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec()
	await process_frame
	var t_impact_first_render_frame := Time.get_ticks_usec() - t0

	print("[2.1] 1º IMPACTO: receive_vehicle_impact() síncrono: %.3f ms" % (t_impact_call / 1000.0))
	print("[2.2] 1º IMPACTO: Frame de 1º render da queda (384x384 MSAA 2X): %.3f ms" % [
		t_impact_first_render_frame / 1000.0
	])

	# Frames seguintes do tween de queda
	var tween_frames := []
	for i in 15:
		t0 = Time.get_ticks_usec()
		await process_frame
		tween_frames.append((Time.get_ticks_usec() - t0) / 1000.0)

	var avg_tween := 0.0
	for tf in tween_frames: avg_tween += tf
	avg_tween /= tween_frames.size()
	print("[2.3] Frames subsequentes da animação de queda: média=%.3f ms, pior=%.3f ms" % [
		avg_tween, tween_frames.max()
	])

	# Limpeza
	signal_node.queue_free()
	impact_audio_node.queue_free()
	dummy_target.queue_free()
	await process_frame

	print("\n=== FIM DO DIAGNÓSTICO DE PICOS ===")
	quit(0)
