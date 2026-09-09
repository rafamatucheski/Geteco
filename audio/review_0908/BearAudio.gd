class_name BearAudio
extends RefCounted
## Sons procedurais e independentes para os ursos (Bear NPCs).
##
## Módulo isolado: não referencia nenhum script de urso existente. A ideia é
## que o agente responsável pelos ursos conecte estas streams a um
## AudioStreamPlayer2D (ou 3D) próprio -- este arquivo não precisa conhecer
## a implementação do urso, e nenhum script de urso foi editado para criar
## este módulo.
##
## Todo o áudio é sintetizado proceduralmente (mesma técnica usada em
## ProceduralAudio.gd -- osciladores + ruído filtrado, sem samples de
## terceiros), então não há questão de licenciamento.
##
## --------------------------------------------------------------------
## Interface pública (3 sons discretos, cada um cacheado após a 1a geração):
##
##   BearAudio.get_breathing_stream() -> AudioStream
##       Respiração contínua e grave. loop_mode == LOOP_FORWARD (loop
##       verdadeiramente contínuo, sem estalo na costura). Pensado para
##       tocar baixo enquanto o urso está parado/patrulhando/idle.
##
##   BearAudio.get_grunt_alert_stream() -> AudioStream
##       Grunhido/alerta curto, one-shot (loop_mode == LOOP_DISABLED).
##       Pensado para o instante em que o urso percebe o jogador (transição
##       para estado de alerta/perseguição).
##
##   BearAudio.get_charge_stream() -> AudioStream
##       Rugido de investida, one-shot (loop_mode == LOOP_DISABLED). Pensado
##       para o instante em que o urso inicia uma investida/ataque.
##
## Uso sugerido (exemplo, para o script do urso conectar):
##
##   const BEAR_AUDIO := preload("res://audio/review_0908/BearAudio.gd")
##
##   var breath_player: AudioStreamPlayer2D
##   func _ready() -> void:
##       breath_player = AudioStreamPlayer2D.new()
##       breath_player.bus = &"SFX"
##       breath_player.stream = BEAR_AUDIO.get_breathing_stream()
##       breath_player.volume_db = -18.0
##       add_child(breath_player)
##       breath_player.play()
##
##   func _on_player_detected() -> void:
##       var alert := AudioStreamPlayer2D.new()
##       alert.bus = &"SFX"
##       alert.stream = BEAR_AUDIO.get_grunt_alert_stream()
##       add_child(alert)
##       alert.play()
##       alert.finished.connect(alert.queue_free)
##
##   func _on_charge_started() -> void:
##       var charge := AudioStreamPlayer2D.new()
##       charge.bus = &"SFX"
##       charge.stream = BEAR_AUDIO.get_charge_stream()
##       add_child(charge)
##       charge.play()
##       charge.finished.connect(charge.queue_free)
##
## Todas as streams retornadas são AudioStreamWAV, mono, 16-bit, 22050Hz --
## mesmo formato usado por todo o resto do áudio procedural do projeto.

const SAMPLE_RATE := 22050

static var _cached_breathing: AudioStream = null
static var _cached_grunt_alert: AudioStream = null
static var _cached_charge: AudioStream = null

# ==========================================
# RESPIRAÇÃO (LOOP CONTÍNUO)
# ==========================================
static func get_breathing_stream() -> AudioStream:
	if _cached_breathing != null:
		return _cached_breathing
	_cached_breathing = _generate_breathing_stream()
	return _cached_breathing

static func _generate_breathing_stream() -> AudioStream:
	# 3.2s = um ciclo respiratório completo. O envelope (raised-cosine) vale
	# 0 tanto em t=0 quanto em t=duration com a mesma inclinação, então o
	# loop fecha sem estalo.
	var duration := 3.2
	var num_samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	var low_pass := 0.0
	for i in range(num_samples):
		var t := float(i) / float(SAMPLE_RATE)
		var noise := randf_range(-1.0, 1.0)
		low_pass += (noise - low_pass) * 0.05 # sopro grave e encorpado (ar passando pelas narinas)
		var breath_phase := t / duration
		# Envelope assimétrico: sobe suave (inspira), sustenta um pico curto,
		# desce (expira) -- mas perfeitamente periódico em `duration`.
		var envelope := pow(0.5 - 0.5 * cos(2.0 * PI * breath_phase), 1.6)
		var chest_rumble := sin(2.0 * PI * 55.0 * t) * 0.18 * envelope
		var sample := (low_pass * 0.5 * envelope + chest_rumble) * 0.5
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples
	stream.data = data
	return stream

# ==========================================
# GRUNHIDO / ALERTA (ONE-SHOT)
# ==========================================
static func get_grunt_alert_stream() -> AudioStream:
	if _cached_grunt_alert != null:
		return _cached_grunt_alert
	_cached_grunt_alert = _generate_grunt_alert_stream()
	return _cached_grunt_alert

static func _generate_grunt_alert_stream() -> AudioStream:
	var duration := 0.55
	var num_samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	var attack := 0.02
	var low_pass := 0.0
	for i in range(num_samples):
		var t := float(i) / float(SAMPLE_RATE)
		var env: float = (t / attack) if t < attack else exp(-(t - attack) * 7.0)
		var noise := randf_range(-1.0, 1.0)
		low_pass += (noise - low_pass) * 0.10
		# Formante grave descendente (95Hz -> 60Hz aprox.), típico de grunhido de urso.
		var freq := 95.0 - t * 45.0
		var growl := sin(2.0 * PI * freq * t) + 0.4 * sin(4.0 * PI * freq * t)
		var sample := tanh((growl * 0.55 + low_pass * 0.35) * env * 1.1) * 0.75
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream

# ==========================================
# INVESTIDA / CARGA (ONE-SHOT)
# ==========================================
static func get_charge_stream() -> AudioStream:
	if _cached_charge != null:
		return _cached_charge
	_cached_charge = _generate_charge_stream()
	return _cached_charge

static func _generate_charge_stream() -> AudioStream:
	var duration := 1.1
	var num_samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	var low_pass := 0.0
	for i in range(num_samples):
		var t := float(i) / float(SAMPLE_RATE)
		var ramp := clampf(t / duration, 0.0, 1.0)
		var env := sin(PI * clampf(t / (duration * 0.7), 0.0, 1.0)) * (1.0 - 0.3 * ramp)
		var noise := randf_range(-1.0, 1.0)
		low_pass += (noise - low_pass) * 0.08
		var roar_freq := 70.0 + ramp * 40.0
		var roar := sin(2.0 * PI * roar_freq * t) + 0.5 * sin(4.0 * PI * roar_freq * t)
		var huff := (0.5 + 0.5 * sin(2.0 * PI * 3.2 * t)) * low_pass * 0.4
		var sample := tanh((roar * 0.5 + huff + low_pass * 0.25) * env * 1.1) * 0.8
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream
