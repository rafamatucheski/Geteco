extends SceneTree

## Mede o áudio realmente mixado pelo motor de som do carro procurando o
## "estalinho" periódico: um degrau entre amostras muito maior do que qualquer
## degrau natural do waveform. Precisa de driver de áudio real (sem --headless),
## porque o driver dummy nunca mixa nada.
const ENGINE := preload("res://audio/VehicleEngineSound.gd")

var failures := 0
var inconclusive := 0

func _initialize() -> void:
	call_deferred("_run")

## Maior degrau entre amostras vizinhas dentro do próprio buffer do stream:
## é a referência de "degrau natural" contra a qual um clique se destaca.
func _natural_max_step(stream: AudioStreamWAV) -> float:
	var data := stream.data
	var frames := data.size() / 2
	var previous := 0.0
	var worst := 0.0
	for i in frames:
		var sample := float(data.decode_s16(i * 2)) / 32768.0
		if i > 0:
			worst = maxf(worst, absf(sample - previous))
		previous = sample
	return worst

## Verifica a emenda de UMA camada. Cada família tem três, e a de alto giro é a
## que mais carrega ruído de admissão — justamente onde uma emenda mal fechada
## teria mais chance de passar despercebida numa inspeção só do buffer.
func _check_family(family: String, layer: int = 0) -> void:
	var stream: AudioStreamWAV = ENGINE.get_layer_streams(family)[layer]
	var natural := _natural_max_step(stream)

	var capture := AudioEffectCapture.new()
	capture.buffer_length = 4.0
	AudioServer.add_bus_effect(0, capture, 0)

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = 0.0
	player.pitch_scale = 1.82  # pitch de velocidade máxima: o laço reinicia ~1.8x/s
	root.add_child(player)
	player.play()

	await create_timer(0.4).timeout
	capture.clear_buffer()
	await create_timer(3.0).timeout

	var buffer := capture.get_buffer(capture.get_frames_available())
	player.stop()
	player.queue_free()
	AudioServer.remove_bus_effect(0, 0)

	if buffer.size() < 4096:
		print("ENGINE_LOOP_SEAM %s camada %d inconclusive: mixer nao entregou audio (frames=%d)" % [family, layer, buffer.size()])
		inconclusive += 1
		return

	# Um clique se destaca como degrau muito acima de qualquer degrau natural do
	# waveform. Fator 2.0 dá folga para o resampler sem deixar passar o estalo,
	# que media ~4.8x o degrau natural.
	var worst_step := 0.0
	var spikes := 0
	var threshold := maxf(natural * 2.0, 0.02)
	var previous: Vector2 = buffer[0]
	for i in range(1, buffer.size()):
		var current: Vector2 = buffer[i]
		var step := maxf(absf(current.x - previous.x), absf(current.y - previous.y))
		worst_step = maxf(worst_step, step)
		if step > threshold:
			spikes += 1
		previous = current

	print("ENGINE_LOOP_SEAM %-12s camada=%d frames=%d natural_step=%.4f mixed_worst=%.4f threshold=%.4f spikes=%d" % [
		family, layer, buffer.size(), natural, worst_step, threshold, spikes,
	])
	if spikes > 0:
		failures += 1
		push_error("Estalo no ponto de laco do motor '%s' camada %d: %d degraus acima do natural" % [family, layer, spikes])

func _run() -> void:
	if "rosso-only" in OS.get_cmdline_user_args():
		for layer in 3: await _check_family("rosso_v12", layer)
		print("ROSSO_LOOP_SEAM failures=%d inconclusive=%d" % [failures,inconclusive])
		quit(1 if failures or inconclusive else 0)
		return
	if "monaliza-only" in OS.get_cmdline_user_args():
		for layer in ENGINE.get_layer_streams("monaliza").size(): await _check_family("monaliza", layer)
		print("MONALIZA_LOOP_SEAM failures=%d inconclusive=%d" % [failures, inconclusive])
		quit(1 if failures or inconclusive else 0)
		return
	if "bikes-only" in OS.get_cmdline_user_args():
		for family in ["bike_sport", "bike_cruiser", "bike_urban"]:
			for layer in 3: await _check_family(family, layer)
		print("MOTORCYCLE_LOOP_SEAM failures=%d inconclusive=%d" % [failures, inconclusive])
		quit(1 if failures or inconclusive else 0)
		return
	if "sport-only" in OS.get_cmdline_user_args():
		for layer in 3: await _check_family("sport", layer)
		print("SPORT_LOOP_SEAM failures=%d inconclusive=%d" % [failures, inconclusive])
		quit(1 if failures or inconclusive else 0)
		return
	for family in ["street", "sport", "muscle", "suv", "diesel", "bus", "truck", "fire_diesel", "ambulance", "police"]:
		await _check_family(family)
	# A camada de alto giro e a que mais tem ruido: a emenda dela e a mais dificil.
	for family in ["street", "truck", "sport"]:
		await _check_family(family, 2)
	print("ENGINE_LOOP_SEAM failures=%d inconclusive=%d" % [failures, inconclusive])
	quit(1 if failures else 0)
