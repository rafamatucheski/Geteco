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

func _check_family(family: String) -> void:
	var stream: AudioStreamWAV = ENGINE.get_stream(family)
	var natural := _natural_max_step(stream)

	var capture := AudioEffectCapture.new()
	capture.buffer_length = 3.0
	AudioServer.add_bus_effect(0, capture, 0)

	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = 0.0
	player.pitch_scale = 1.82  # pitch de velocidade máxima: o laço reinicia ~1.8x/s
	root.add_child(player)
	player.play()

	await create_timer(0.4).timeout
	capture.clear_buffer()
	await create_timer(1.6).timeout

	var buffer := capture.get_buffer(capture.get_frames_available())
	player.stop()
	player.queue_free()
	AudioServer.remove_bus_effect(0, 0)

	if buffer.size() < 4096:
		print("ENGINE_LOOP_SEAM %s inconclusive: mixer nao entregou audio (frames=%d)" % [family, buffer.size()])
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

	print("ENGINE_LOOP_SEAM %-12s frames=%d natural_step=%.4f mixed_worst=%.4f threshold=%.4f spikes=%d" % [
		family, buffer.size(), natural, worst_step, threshold, spikes,
	])
	if spikes > 0:
		failures += 1
		push_error("Estalo no ponto de laco do motor '%s': %d degraus acima do natural" % [family, spikes])

func _run() -> void:
	for family in ["street", "sport", "diesel", "bus", "truck", "fire_diesel", "ambulance", "police"]:
		await _check_family(family)
	print("ENGINE_LOOP_SEAM failures=%d inconclusive=%d" % [failures, inconclusive])
	quit(1 if failures else 0)
