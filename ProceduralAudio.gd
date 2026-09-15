class_name ProceduralAudio
extends RefCounted

const REWARD_AUDIO := preload("res://audio/rewards/RewardAudioBank.gd")

const COMBAT_AUDIO := preload("res://audio/combat/CombatAudioBank.gd")
const VEHICLE_CATALOG := preload("res://cars/VehicleCatalog.gd")

static var _cached_engine: AudioStream = null
static var _cached_skid: Dictionary = {}
static var _cached_horn: Dictionary = {}
static var _cached_ambience: AudioStream = null
static var _cached_siren: AudioStream = null
static var _cached_squish: AudioStream = null
static var _cached_scream: AudioStream = null
static var _cached_wasted: AudioStream = null
static var _cached_radio: Array[AudioStream] = []

# ==========================================
# MOTOR (ENGINE LOOP)
# ==========================================
static func get_engine_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/engine_loop.wav"):
		return load("res://audio/engine_loop.wav")
	if ResourceLoader.exists("res://audio/engine_loop.ogg"):
		return load("res://audio/engine_loop.ogg")
	if _cached_engine != null:
		return _cached_engine

	var sample_rate := 22050
	var duration := 1.0 # 1 segundo loopable
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Síntese de motor V8 encorpado com pulsos de combustão e escape
		var sub := sin(2.0 * PI * 48.0 * t) * 0.5
		var wave1 := sin(2.0 * PI * 96.0 * t) * 0.4
		var wave2 := sin(2.0 * PI * 144.0 * t) * 0.25
		var wave3 := sin(2.0 * PI * 192.0 * t) * 0.15
		var pulse := pow(maxf(0.0, sin(2.0 * PI * 24.0 * t)), 3.0) * 0.35
		var exhaust := randf_range(-0.10, 0.10) * (0.2 + pulse)
		var sample := (sub + wave1 + wave2 + wave3 + pulse + exhaust) * 0.35
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples
	stream.data = data
	_cached_engine = stream
	return stream

# ==========================================
# HELPERS DE ÁUDIO POR VEÍCULO / FAMÍLIA
# ==========================================
static func _cache_key(vehicle_id: String, sound_name: String) -> String:
	var normalized_id := vehicle_id.strip_edges()
	if normalized_id.is_empty():
		return "global::" + sound_name
	return normalized_id + "::" + sound_name

static func _candidate_sound_paths(vehicle_id: String, sound_name: String) -> Array[String]:
	var id := vehicle_id.strip_edges()
	var extensions: Array[String] = [".wav", ".ogg", ".mp3"]
	var result: Array[String] = []
	for ext in extensions:
		if not id.is_empty():
			result.append("res://audio/vehicle/%s_%s%s" % [id, sound_name, ext])
			result.append("res://audio/vehicle/%s%s" % [id, ext])
			result.append("res://audio/%s_%s%s" % [id, sound_name, ext])
			result.append("res://audio/%s%s" % [id, ext])
		result.append("res://audio/%s%s" % [sound_name, ext])
	return result

static func _resolve_vehicle_sound_stream(vehicle_id: String, sound_name: String) -> AudioStream:
	for path in _candidate_sound_paths(vehicle_id, sound_name):
		if ResourceLoader.exists(path):
			var stream := load(path)
			if stream is AudioStream:
				return stream
	return null

# ==========================================
# DERRAPAGEM (SKID / TIRE SCREECH)
# ==========================================
static func get_skid_stream(vehicle_id: String = "") -> AudioStream:
	var key := _cache_key(vehicle_id, "skid")
	if _cached_skid.has(key):
		return _cached_skid[key]
	var stream := _resolve_vehicle_sound_stream(vehicle_id, "skid")
	if stream == null:
		stream = _generate_skid_stream(vehicle_id)
	_cached_skid[key] = stream
	return stream

static func _generate_skid_stream(vehicle_id: String = "") -> AudioStream:
	var spec: Dictionary = VEHICLE_CATALOG.get_vehicle_spec(vehicle_id)
	var mass: float = float(spec.get("mass", 1.0))
	var drift: float = float(spec.get("drift_factor", 0.9))
	var drivetrain: String = String(spec.get("drivetrain", "fwd"))
	var signature: int = vehicle_id.hash() & 0x7fffffff
	var drive_tone: float = float({"fwd": 90.0, "rwd": 250.0, "awd": 150.0, "4x4": 115.0}.get(drivetrain, 130.0))
	# Cada modelo recebe pequenas diferenças determinísticas; massa, acerto e
	# tração dão a diferença maior. Assim o cache é barato e o timbre é estável.
	var base_frequency: float = clampf(1380.0 - mass * 155.0 + drift * 185.0 + drive_tone + float(signature % 137), 760.0, 1780.0)
	var modulation_rate: float = 21.0 + float(int(signature / 137.0) % 19)
	var noise_amount: float = clampf(0.16 + mass * 0.055 + float(signature % 11) * 0.006, 0.16, 0.42)
	var rng := RandomNumberGenerator.new()
	rng.seed = signature if signature > 0 else 1
	var sample_rate := 22050
	var duration := 0.8
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var fm := sin(2.0 * PI * modulation_rate * t) * (145.0 + drift * 75.0)
		var squeal := sin(2.0 * PI * (base_frequency + fm) * t) * 0.3
		var squeal2 := sin(2.0 * PI * (base_frequency * 1.88 + fm * 1.5) * t) * 0.15
		var friction_noise := rng.randf_range(-noise_amount, noise_amount)
		var sample := (squeal + squeal2 + friction_noise) * 0.35
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.data = data
	return stream

# ==========================================
# COLISÃO (CRASH / IMPACT)
# ==========================================
static func get_crash_stream(vehicle_id: String = "") -> AudioStream:
	var authored := _resolve_vehicle_sound_stream(vehicle_id, "crash")
	if authored != null:
		return authored
	return preload("res://audio/VehicleCrashAudio.gd").sound("solid", randi_range(0, 3))

# ==========================================
# BUZINA (HORN)
# ==========================================
static func get_horn_stream(vehicle_id: String = "") -> AudioStream:
	var key := _cache_key(vehicle_id, "horn")
	if _cached_horn.has(key):
		return _cached_horn[key]

	var stream := _resolve_vehicle_sound_stream(vehicle_id, "horn")
	if stream == null:
		stream = _generate_horn_stream()
	_cached_horn[key] = stream
	return stream

static func _generate_horn_stream() -> AudioStream:
	var sample_rate := 22050
	var duration := 0.4
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var env := 1.0
		if t < 0.03: env = t / 0.03
		elif t > 0.35: env = (duration - t) / 0.05
		# Duas frequências clássicas de buzina automotiva (Fá e Lá)
		var tone1 := sin(2.0 * PI * 435.0 * t)
		var tone2 := sin(2.0 * PI * 545.0 * t)
		var sample := (tone1 * 0.5 + tone2 * 0.5) * env * 0.4
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream

# ==========================================
# AMBIENTE DA CIDADE (CITY AMBIENCE LOOP)
# ==========================================
static func get_city_ambience_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/city_ambience.wav"):
		return load("res://audio/city_ambience.wav")
	if ResourceLoader.exists("res://audio/city_ambience.ogg"):
		return load("res://audio/city_ambience.ogg")
	if _cached_ambience != null:
		return _cached_ambience

	var sample_rate := 22050
	var duration := 2.5
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	var last_sample := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Ruído rosa/browniano suave (som de vento e tráfego distante)
		var white := randf_range(-1.0, 1.0)
		last_sample = (last_sample * 0.95) + (white * 0.05)
		var rumble := sin(2.0 * PI * 40.0 * t) * 0.1
		var sample := (last_sample * 0.6 + rumble) * 0.2
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.data = data
	_cached_ambience = stream
	return stream

# ==========================================
# SIRENE POLICIAL (POLICE SIREN)
# ==========================================
static func get_siren_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/siren.wav"):
		return load("res://audio/siren.wav")
	if ResourceLoader.exists("res://audio/siren.ogg"):
		return load("res://audio/siren.ogg")
	if _cached_siren != null:
		return _cached_siren
	_cached_siren = _generate_siren_stream()
	return _cached_siren

static func _generate_siren_stream() -> AudioStream:
	var sample_rate := 22050
	# 3.0s wail cycle (650Hz <-> 1150Hz, average 900Hz). 900 * 3.0 = 2700 whole
	# cycles, so the accumulated phase lands back on a multiple of 2*PI at the
	# loop point with the same instantaneous frequency it started with --
	# the waveform wraps with matching value AND slope, so LOOP_FORWARD is a
	# genuinely seamless loop instead of clicking at the seam.
	var duration := 3.0
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	var freq_lo := 650.0
	var freq_hi := 1150.0
	var phase := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Raised-cosine sweep: zero slope at both ends of the cycle, so the
		# pitch itself glides smoothly through the wrap instead of jumping --
		# this is what reads as a recognizable, continuous "wail" alternation
		# rather than an abrupt siren toggle.
		var lfo := 0.5 - 0.5 * cos(2.0 * PI * t / duration)
		var freq := freq_lo + (freq_hi - freq_lo) * lfo
		# Sample using the phase accumulated so far (phase starts at exactly 0
		# for sample 0), THEN advance it -- so sample[0] == sin(0) and the
		# last sample lands one small increment short of sample[0]'s phase
		# (mod 2*PI), i.e. exactly what a continuously running oscillator
		# would produce next. Incrementing before sampling would shift the
		# whole buffer by one step and reintroduce a seam-edge jump.
		var tone := sin(phase)
		var warmth := sin(phase * 2.0) * 0.10 + sin(phase * 3.0) * 0.04
		phase += 2.0 * PI * freq / float(sample_rate)
		# Soft-clip (tanh) instead of hard clamp: keeps the top of the wail
		# rounded instead of harsh/painful, with headroom so nothing clips.
		var sample := tanh((tone + warmth) * 0.75) * 0.55
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples
	stream.data = data
	return stream

static var _cached_police_alarm: AudioStream = null

# ==========================================
# ALARME DE VIATURA DA PM (POLICE CAR ALARM)
# ==========================================
static func get_police_alarm_stream() -> AudioStream:
	if _cached_police_alarm != null:
		return _cached_police_alarm
	_cached_police_alarm = _generate_police_alarm_stream()
	return _cached_police_alarm

static func _generate_police_alarm_stream() -> AudioStream:
	var sample_rate := 22050
	# 0.8s = exactly two hi/lo pairs at a 0.4s period, and both carrier
	# frequencies complete a whole number of cycles across that span
	# (880*0.8=704, 1320*0.8=1056) -- both the crossfade envelope and the
	# tones themselves close cleanly on the loop boundary.
	var duration := 0.8
	var period := 0.4
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	var freq_a := 880.0
	var freq_b := 1320.0
	var phase_a := 0.0
	var phase_b := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Sample on the phase accumulated so far (starts at 0 for sample 0),
		# then advance -- see the matching note in _generate_siren_stream()
		# for why the order matters for a click-free loop seam.
		var tone_a := sin(phase_a) + sin(phase_a * 2.0) * 0.08
		var tone_b := sin(phase_b) + sin(phase_b * 2.0) * 0.08
		phase_a += 2.0 * PI * freq_a / float(sample_rate)
		phase_b += 2.0 * PI * freq_b / float(sample_rate)
		# Smoothed square wave (tanh of a sine) crossfades between the two
		# tones with a short, click-free glide instead of an instant
		# frequency jump -- the previous int(t*6)%2 switch caused a phase
		# discontinuity every ~0.17s, which is what read as "estalos".
		var m := 0.5 + 0.5 * tanh(12.0 * sin(2.0 * PI * t / period))
		var sample := (tone_a * m + tone_b * (1.0 - m)) * 0.38
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples
	stream.data = data
	return stream

# ==========================================
# ESTAÇÕES DE RÁDIO (RADIO CHANNELS)
# ==========================================
static func get_radio_stations() -> Array:
	# Programas gravados completos; o fallback antigo só serve projetos sem o banco.
	if ResourceLoader.exists("res://audio/living_city/porto_fm.ogg"):
		return preload("res://audio/living_city/LivingCityAudio.gd").stations()
	var list: Array = []
	# 1. Checa se existem músicas no diretório
	var dir := DirAccess.open("res://audio/radio/") if DirAccess.dir_exists_absolute("res://audio/radio/") else null
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".mp3") or fname.ends_with(".ogg") or fname.ends_with(".wav"):
				var track = load("res://audio/radio/" + fname)
				if track: list.append(track)
			fname = dir.get_next()

	if not list.is_empty():
		return list

	# Se não tiver arquivos na pasta, gera 3 canais sintetizados retrô estilizados
	if not _cached_radio.is_empty():
		return _cached_radio

	var sample_rate := 22050
	var duration := 3.0 # loop de 3s
	var num_samples := int(sample_rate * duration)

	# Canal 1: Synthwave Arp (130 BPM)
	var data1 := PackedByteArray()
	data1.resize(num_samples * 2)
	var notes1 := [220.0, 261.63, 329.63, 392.0, 329.63, 261.63]
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var note_idx := int(t * 4.0) % notes1.size()
		var f: float = notes1[note_idx]
		var sub := sin(2.0 * PI * (f * 0.5) * t) * 0.3
		var lead := (sin(2.0 * PI * f * t) + 0.3 * sin(2.0 * PI * f * 2.0 * t)) * 0.2
		var beat := sin(2.0 * PI * 65.0 * t) * exp(-fmod(t, 0.5) * 12.0) * 0.4
		var sample := (sub + lead + beat) * 0.4
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data1.encode_s16(i * 2, int_sample)

	var s1 := AudioStreamWAV.new()
	s1.format = AudioStreamWAV.FORMAT_16_BITS
	s1.mix_rate = sample_rate
	s1.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s1.data = data1
	_cached_radio.append(s1)

	# Canal 2: Funk/Bassline Chords (110 BPM)
	var data2 := PackedByteArray()
	data2.resize(num_samples * 2)
	var notes2 := [110.0, 110.0, 146.83, 164.81, 130.81]
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var note_idx := int(t * 3.0) % notes2.size()
		var f: float = notes2[note_idx]
		var bass := sin(2.0 * PI * f * t) * 0.35
		var hihat := randf_range(-0.15, 0.15) * exp(-fmod(t, 0.25) * 20.0)
		var sample := (bass + hihat) * 0.4
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data2.encode_s16(i * 2, int_sample)

	var s2 := AudioStreamWAV.new()
	s2.format = AudioStreamWAV.FORMAT_16_BITS
	s2.mix_rate = sample_rate
	s2.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s2.data = data2
	_cached_radio.append(s2)

	# Canal 3: Lo-Fi Chill Beats
	var data3 := PackedByteArray()
	data3.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var chord := (sin(2.0 * PI * 330.0 * t) + sin(2.0 * PI * 392.0 * t) + sin(2.0 * PI * 493.88 * t)) * 0.12
		var vinyl_crackle := randf_range(-0.04, 0.04)
		var kick := sin(2.0 * PI * 55.0 * t) * exp(-fmod(t, 1.0) * 6.0) * 0.3
		var sample := (chord + vinyl_crackle + kick) * 0.4
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data3.encode_s16(i * 2, int_sample)

	var s3 := AudioStreamWAV.new()
	s3.format = AudioStreamWAV.FORMAT_16_BITS
	s3.mix_rate = sample_rate
	s3.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s3.data = data3
	_cached_radio.append(s3)

	return _cached_radio

# ==========================================
# ATROPELAMENTO (MEAT SQUISH / BLOOD SPLAT)
# ==========================================
static func get_squish_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/squish.wav"):
		return load("res://audio/squish.wav")
	if ResourceLoader.exists("res://audio/squish.ogg"):
		return load("res://audio/squish.ogg")
	if _cached_squish != null:
		return _cached_squish

	var sample_rate := 22050
	var duration := 0.35
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 11.0)
		var low_thump := sin(2.0 * PI * (75.0 - t * 40.0) * t) * env * 0.7
		var wet_noise := randf_range(-0.4, 0.4) * exp(-t * 16.0)
		var squelch := sin(2.0 * PI * (420.0 - t * 600.0) * t) * env * 0.35
		var sample := (low_thump + wet_noise + squelch) * 0.75
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_squish = stream
	return stream

# ==========================================
# GRITO DE PEDESTRE (SCREAM / YELL)
# ==========================================
static func get_scream_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/scream.wav"):
		return load("res://audio/scream.wav")
	if ResourceLoader.exists("res://audio/scream.ogg"):
		return load("res://audio/scream.ogg")
	return preload("res://audio/reactions/CharacterReactionBank.gd").sound("hurt")

static func get_death_reaction_stream() -> AudioStream:
	return preload("res://audio/reactions/CharacterReactionBank.gd").sound("death")

# ==========================================
# WASTED / MORTE
# ==========================================
static func get_wasted_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/wasted.wav"):
		return load("res://audio/wasted.wav")
	if _cached_wasted != null:
		return _cached_wasted

	var sample_rate := 22050
	var duration := 1.8
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 2.2)
		var bass := sin(2.0 * PI * 55.0 * t) * 0.6
		var minor_third := sin(2.0 * PI * 65.41 * t) * 0.4
		var fifth := sin(2.0 * PI * 82.41 * t) * 0.3
		var sample := (bass + minor_third + fifth) * env * 0.65
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_wasted = stream
	return stream

# ==========================================
# MANGUEIRA D'ÁGUA / BOMBEIRO (WATER HOSE)
# ==========================================
static var _cached_water: AudioStream = null

static func get_water_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/water.wav"):
		return load("res://audio/water.wav")
	if ResourceLoader.exists("res://audio/water.ogg"):
		return load("res://audio/water.ogg")
	if _cached_water != null:
		return _cached_water

	var sample_rate := 22050
	var duration := 1.0
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	var last_val := 0.0
	for i in range(num_samples):
		var white := randf_range(-1.0, 1.0)
		last_val = (last_val * 0.8) + (white * 0.2)
		var hiss := last_val * 0.45
		var int_sample := clampi(int(hiss * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.data = data
	_cached_water = stream
	return stream

# ==========================================
# POWERUP / ATENDIMENTO MÉDICO (HEAL / CHIME)
# ==========================================

static func get_powerup_stream() -> AudioStream:
	return REWARD_AUDIO.sound("pickup")

# ==========================================
# CAIXA REGISTRADORA / COMPRA (CASH REGISTER)
# ==========================================

static func get_cash_register_stream() -> AudioStream:
	return REWARD_AUDIO.sound("cash")

# ==========================================
# AMASSAMENTO DE METAL (METAL CRUMPLE / DEFORMATION)
# ==========================================
static var _cached_metal_crumple: AudioStream = null

static func get_metal_crumple_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/crumple.wav"):
		return load("res://audio/crumple.wav")
	if _cached_metal_crumple != null:
		return _cached_metal_crumple

	var sample_rate := 22050
	var duration := 0.55
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var env := exp(-t * 9.0)
		var sub_thud := sin(2.0 * PI * 75.0 * t) * env * 0.7
		var metal_creak := sin(2.0 * PI * (320.0 + sin(t * 120.0) * 80.0) * t) * env * 0.35
		var crunch := randf_range(-0.6, 0.6) * env * 0.5
		var sample := (sub_thud + metal_creak + crunch) * 0.75
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_metal_crumple = stream
	return stream

# ==========================================
# IMPACTO DE BALA EM LATARIA / METAL (BULLET METAL CLANG & RICOCHET)
# ==========================================
static func get_bullet_metal_hit_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/bullet_metal.wav"):
		return load("res://audio/bullet_metal.wav")
	return get_ricochet_stream()

# ==========================================
# EXPLOSÃO DE CARRO (VEHICLE EXPLOSION BOOM)
# ==========================================
static var _cached_explosion: AudioStream = null

static func get_explosion_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/explosion.wav"):
		return load("res://audio/explosion.wav")
	if _cached_explosion != null:
		return _cached_explosion

	var sample_rate := 22050
	var duration := 1.4
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var sub_env := exp(-t * 3.5)
		var noise_env := exp(-t * 5.0)
		var sub_boom := sin(2.0 * PI * (65.0 - t * 25.0) * t) * sub_env * 0.9
		var fireball_roar := randf_range(-0.8, 0.8) * noise_env * 0.7
		var debris_clatter := randf_range(-0.4, 0.4) * exp(-maxf(0.0, t - 0.2) * 8.0) * 0.4
		var sample := (sub_boom + fireball_roar + debris_clatter) * 0.85
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_explosion = stream
	return stream

# ==========================================
# CHUVA (RAIN AMBIENCE LOOP SUAVE COM GOTAS)
# ==========================================
static var _cached_rain: AudioStream = null

static func get_rain_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/rain.wav"):
		return load("res://audio/rain.wav")
	if _cached_rain != null:
		return _cached_rain

	var sample_rate := 22050
	var duration := 3.0
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	var last_noise := 0.0
	for i in range(num_samples):
		var raw_white := randf_range(-0.35, 0.35)
		# Filtro passa-baixas (Low-Pass Filter) para som encorpado e suave de água
		last_noise = lerp(last_noise, raw_white, 0.12)
		var rain_bed := last_noise * 0.55
		
		# Pingos suaves de chuva atingindo o solo
		var drop := 0.0
		if randf() < 0.008:
			drop = randf_range(-0.3, 0.3)
			
		var sample := (rain_bed + drop) * 0.65
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples
	stream.data = data
	_cached_rain = stream
	return stream

# ==========================================
# TROVÃO / RAIO (THUNDER CRACK & ROLL)
# ==========================================
static var _cached_thunder: AudioStream = null

static func get_thunder_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/thunder.wav"):
		return load("res://audio/thunder.wav")
	if _cached_thunder != null:
		return _cached_thunder

	var sample_rate := 22050
	var duration := 2.6
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)

	var last_noise := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# 1. Estalo inicial de choque elétrico seco (crack)
		var crack_env := exp(-t * 24.0)
		var crack := randf_range(-0.7, 0.7) * crack_env
		
		# 2. Ronco encorpado e contínuo de trovão (Low-pass brownian rumble)
		var raw_noise := randf_range(-1.0, 1.0)
		last_noise = lerp(last_noise, raw_noise, 0.05) # Filtro passa-baixa profundo elimina chiados estranhos
		var rumble_env := exp(-t * 1.3) * (0.85 + 0.15 * sin(t * 3.5))
		var sub_bass := sin(2.0 * PI * 44.0 * t) * 0.3 * rumble_env
		
		var sample := (crack * 0.65 + (last_noise * 1.8 + sub_bass) * rumble_env) * 0.6
		var int_sample := clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, int_sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_thunder = stream
	return stream

# ==========================================
# TIROS E RICOCHETE PROCEDURAIS ULTRA-PUNCHY (GUNSHOTS & RICOCHET)
# ==========================================
static var _cached_gunshot_pistol: AudioStream = null
static var _cached_gunshot_magnum: AudioStream = null
static var _cached_gunshot_smg: AudioStream = null
static var _cached_gunshot_ak47: AudioStream = null
static var _cached_gunshot_m4a1: AudioStream = null
static var _cached_gunshot_shotgun: AudioStream = null
static var _cached_gunshot_sawed_off: AudioStream = null
static var _cached_rpg_launch: AudioStream = null
static var _cached_flamethrower: AudioStream = null
static var _cached_grenade: AudioStream = null
static var _cached_ricochet: AudioStream = null

static var _cached_punch_swing: AudioStream = null
static var _cached_knife_slash: AudioStream = null

static func get_melee_swing_stream(weapon_id: String = "fists") -> AudioStream:
	match weapon_id:
		"bat":
			return preload("res://audio/combat/BatAudio.gd").swing()
		"knife":
			return get_knife_slash_stream()
		_:
			return get_punch_swing_stream()

# --- PUNHO (Curto whoosh de ar seguido de um thud grave surdo -- sem faisca metalica) ---
static func get_punch_swing_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/punch_swing.wav"):
		return load("res://audio/punch_swing.wav")
	if _cached_punch_swing != null:
		return _cached_punch_swing

	var sample_rate := 22050
	var duration := 0.22
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var last_noise := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Whoosh: ruido filtrado subindo e caindo rapido, como o braco cortando o ar.
		var raw_noise := randf_range(-1.0, 1.0)
		last_noise = last_noise * 0.82 + raw_noise * 0.18
		var whoosh_env := sin(PI * clampf(t / 0.10, 0.0, 1.0)) * exp(-t * 9.0)
		var whoosh := last_noise * whoosh_env * 0.55
		# Thud grave surdo no instante do impacto (~0.09s), sem componente metalica.
		var impact_t := maxf(0.0, t - 0.09)
		var thud := sin(2.0 * PI * 92.0 * impact_t) * exp(-impact_t * 40.0) * 0.75
		var thud_noise := randf_range(-1.0, 1.0) * exp(-impact_t * 70.0) * 0.25
		var sample := tanh((whoosh + thud + thud_noise) * 1.15) * 0.8
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_punch_swing = stream
	return stream

# --- FACA (Whoosh mais agudo/rapido com um "shk" metalico curto na ponta do golpe) ---
static func get_knife_slash_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/knife_slash.wav"):
		return load("res://audio/knife_slash.wav")
	if _cached_knife_slash != null:
		return _cached_knife_slash

	var sample_rate := 22050
	var duration := 0.20
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var last_noise := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var raw_noise := randf_range(-1.0, 1.0)
		last_noise = last_noise * 0.75 + raw_noise * 0.25
		var slash_env := sin(PI * clampf(t / 0.075, 0.0, 1.0)) * exp(-t * 15.0)
		var slash := last_noise * slash_env * 0.6
		# "shk" metalico curto e agudo no fio da lamina cortando o ar.
		var ring_t := maxf(0.0, t - 0.05)
		var metal_ring := (sin(2.0 * PI * 3400.0 * ring_t) + 0.4 * sin(2.0 * PI * 5200.0 * ring_t)) * exp(-ring_t * 90.0) * 0.30
		var sample := tanh((slash + metal_ring) * 1.2) * 0.78
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_knife_slash = stream
	return stream

static func get_gunshot_stream(weapon_id: String = "pistol") -> AudioStream:
	match weapon_id:
		"hunting_rifle":
			return COMBAT_AUDIO.sound("hunting_rifle")
		"magnum":
			return get_gunshot_magnum_stream()
		"sawed_off":
			return get_gunshot_sawed_off_stream()
		"shotgun":
			return get_gunshot_shotgun_stream()
		"ak47":
			return get_gunshot_ak47_stream()
		"m4a1":
			return get_gunshot_m4a1_stream()
		"rpg":
			return get_rpg_launch_stream()
		"flamethrower":
			return get_flamethrower_stream()
		"grenade", "molotov":
			return get_grenade_throw_stream()
		"smg", "micro_smg":
			return get_gunshot_smg_stream()
		_:
			return get_gunshot_pistol_stream()

# --- PISTOLA 9MM (Snappy, punchy 9mm gunshot with crisp transient, gunpowder explosion, and slide recoil) ---
static func get_gunshot_pistol_stream() -> AudioStream:
	# Preserve optional externally supplied overrides.
	for extension in ["wav", "ogg"]:
		var path: String = "res://audio/gunshot_pistol." + extension
		if ResourceLoader.exists(path):
			return load(path)
	return COMBAT_AUDIO.sound("pistol")

# --- SUBMETRALHADORA SMG (Aggressive, rapid-fire submachinegun with high-velocity crack and tight bass punch) ---
static func get_gunshot_smg_stream() -> AudioStream:
	# Preserve optional externally supplied overrides.
	for extension in ["wav", "ogg"]:
		var path: String = "res://audio/gunshot_smg." + extension
		if ResourceLoader.exists(path):
			return load(path)
	return COMBAT_AUDIO.sound("smg")

# --- ESCOPETA 12-GAUGE PUMP (Thunderous, heavy 12-gauge blast with deep sub-bass thump) ---
static func get_gunshot_shotgun_stream() -> AudioStream:
	# Preserve optional externally supplied overrides.
	for extension in ["wav", "ogg"]:
		var path: String = "res://audio/gunshot_shotgun." + extension
		if ResourceLoader.exists(path):
			return load(path)
	return COMBAT_AUDIO.sound("shotgun")

# --- REVÓLVER MAGNUM .44 (Canhão de mão estrondoso com estalo de pólvora pesada e sub-bass maciço) ---
static func get_gunshot_magnum_stream() -> AudioStream:
	# Preserve optional externally supplied overrides.
	for extension in ["wav", "ogg"]:
		var path: String = "res://audio/gunshot_magnum." + extension
		if ResourceLoader.exists(path):
			return load(path)
	return COMBAT_AUDIO.sound("magnum")

# --- FUZIL AK-47 (7.62mm soviético pesado, seco, rítmico e metálico) ---
static func get_gunshot_ak47_stream() -> AudioStream:
	# Preserve optional externally supplied overrides.
	for extension in ["wav", "ogg"]:
		var path: String = "res://audio/gunshot_ak47." + extension
		if ResourceLoader.exists(path):
			return load(path)
	return COMBAT_AUDIO.sound("ak47")

# --- FUZIL M4A1 (5.56mm militar de alta velocidade, estalo cortante e cadência estalada) ---
static func get_gunshot_m4a1_stream() -> AudioStream:
	# Preserve optional externally supplied overrides.
	for extension in ["wav", "ogg"]:
		var path: String = "res://audio/gunshot_m4a1." + extension
		if ResourceLoader.exists(path):
			return load(path)
	return COMBAT_AUDIO.sound("m4a1")

# --- ESCOPETA CANO SERRADO (Dois canos disparados em estrondo brutal de 12 gauge) ---
static func get_gunshot_sawed_off_stream() -> AudioStream:
	# Preserve optional externally supplied overrides.
	for extension in ["wav", "ogg"]:
		var path: String = "res://audio/gunshot_sawed_off." + extension
		if ResourceLoader.exists(path):
			return load(path)
	return COMBAT_AUDIO.sound("sawed_off")

# --- LANÇA-MÍSSEIS RPG (Disparo do foguete com propulsão sibilante) ---
static func get_rpg_launch_stream() -> AudioStream:
	if _cached_rpg_launch != null: return _cached_rpg_launch
	var sample_rate := 22050
	var duration := 0.65
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var last_noise := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var whoosh := (0.4 + 0.6 * sin(2.0 * PI * (320.0 + 850.0 * t) * t)) * exp(-t * 6.0)
		var raw_noise := randf_range(-1.0, 1.0)
		last_noise = last_noise * 0.70 + raw_noise * 0.30
		var jet := last_noise * exp(-t * 5.0) * 0.90
		var sub := sin(2.0 * PI * 55.0 * t) * exp(-t * 12.0) * 0.80
		var sample := tanh((whoosh + jet + sub) * 1.25) * 0.92
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_rpg_launch = stream
	return stream

# --- LANÇA-CHAMAS (Sopro e rugido contínuo de gás e combustão de chamas) ---
static func get_flamethrower_stream() -> AudioStream:
	if _cached_flamethrower != null: return _cached_flamethrower
	var sample_rate := 22050
	var duration := 0.38
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var lp := 0.0
	var lp_sub := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var env := sin(PI * clampf(t / duration, 0.0, 1.0)) # Envelope suave
		var raw_noise := randf_range(-1.0, 1.0)
		lp += (raw_noise - lp) * 0.14 # Filtro passa-baixa aveludado de chama
		lp_sub += (raw_noise - lp_sub) * 0.03 # Sub-grave abafado
		var roar := (lp * 0.45 + lp_sub * 0.55) * (0.88 + 0.12 * sin(2.0 * PI * 10.0 * t))
		var hiss := (raw_noise - lp) * 0.08 # Sopro suave de gás
		var sample := (roar + hiss) * env * 0.42 # Volume moderado e agradável
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_flamethrower = stream
	return stream

# --- GRANADA / ARREMESSO ---
static func get_grenade_throw_stream() -> AudioStream:
	if _cached_grenade != null: return _cached_grenade
	var sample_rate := 22050
	var duration := 0.22
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var pin_click := sin(2.0 * PI * 3400.0 * t) * exp(-t * 220.0) * 0.85
		var swoosh := sin(2.0 * PI * (300.0 + 400.0 * t) * t) * exp(-t * 18.0) * 0.50
		var sample := (pin_click + swoosh) * 0.70
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_grenade = stream
	return stream

# --- RICOCHETE METÁLICO (Iconic high-velocity metal ricochet whistle / ping PEEOWW when bullets hit cars / metal surfaces) ---
static func get_ricochet_stream() -> AudioStream:
	if ResourceLoader.exists("res://audio/ricochet.wav"):
		return load("res://audio/ricochet.wav")
	if ResourceLoader.exists("res://audio/ricochet.ogg"):
		return load("res://audio/ricochet.ogg")
	return COMBAT_AUDIO.sound("metal")

# ==========================================
# AMBIÊNCIA CLIMÁTICA POR BIOMA (LOOPS)
# ==========================================
static var _cached_snow_wind: AudioStream = null
static var _cached_desert_wind: AudioStream = null
static var _cached_forest_ambience: AudioStream = null
static var _cached_beach_waves: AudioStream = null

static func get_snow_wind_stream() -> AudioStream:
	if _cached_snow_wind != null: return _cached_snow_wind
	var sample_rate := 22050
	var duration := 3.0
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var low_pass := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var noise := randf_range(-1.0, 1.0)
		low_pass += (noise - low_pass) * 0.04
		var gust := 0.5 + 0.5 * sin(2.0 * PI * 0.4 * t)
		var howl := sin(2.0 * PI * (220.0 + 40.0 * sin(2.0 * PI * 0.25 * t)) * t) * 0.12 * gust
		var sample := (low_pass * 0.45 * gust + howl) * 0.35
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples
	stream.data = data
	_cached_snow_wind = stream
	return stream

static func get_desert_wind_stream() -> AudioStream:
	if _cached_desert_wind != null: return _cached_desert_wind
	var sample_rate := 22050
	var duration := 3.0
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var low_pass := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var noise := randf_range(-1.0, 1.0)
		low_pass += (noise - low_pass) * 0.025
		var heat_pulse := 0.6 + 0.4 * sin(2.0 * PI * 0.15 * t)
		var sample := low_pass * 0.55 * heat_pulse
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples
	stream.data = data
	_cached_desert_wind = stream
	return stream

static func get_forest_ambience_stream() -> AudioStream:
	if _cached_forest_ambience != null: return _cached_forest_ambience
	var sample_rate := 22050
	var duration := 3.0
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var low_pass := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var noise := randf_range(-1.0, 1.0)
		low_pass += (noise - low_pass) * 0.06
		var rustle := low_pass * 0.35 * (0.7 + 0.3 * sin(2.0 * PI * 0.5 * t))
		var bird := 0.0
		if fmod(t, 1.5) < 0.08:
			var bt := fmod(t, 1.5)
			bird = sin(2.0 * PI * (2800.0 + 600.0 * sin(2.0 * PI * 35.0 * bt)) * bt) * 0.15
		var sample := rustle + bird
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples
	stream.data = data
	_cached_forest_ambience = stream
	return stream

static func get_beach_waves_stream() -> AudioStream:
	if _cached_beach_waves != null: return _cached_beach_waves
	var sample_rate := 22050
	var duration := 4.0
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	var low_pass := 0.0
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var noise := randf_range(-1.0, 1.0)
		low_pass += (noise - low_pass) * 0.05
		var wave_cycle := pow(maxf(0.0, sin(2.0 * PI * 0.25 * t)), 2.5)
		var sample := low_pass * 0.50 * wave_cycle
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples
	stream.data = data
	_cached_beach_waves = stream
	return stream

# ==========================================
# SONS DE INTERFACE
# ==========================================
static var _cached_empty_weapon: AudioStreamWAV = null

static func get_empty_weapon_stream() -> AudioStreamWAV:
	if _cached_empty_weapon != null: return _cached_empty_weapon
	# Short hammer impact and spring return, without a gunshot's blast or bass.
	var sample_rate := 44100
	var samples := int(sample_rate * 0.14)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 7142
	for i in samples:
		var t := float(i) / sample_rate
		var attack := minf(t / 0.0006, 1.0)
		var hammer := (sin(TAU * 620.0 * t) * 0.45 + noise.randf_range(-0.55, 0.55)) * exp(-t * 155.0) * attack
		var metal := sin(TAU * 2650.0 * t) * exp(-t * 100.0) * 0.24 * attack
		var release_time := maxf(0.0, t - 0.028)
		var spring := sin(TAU * 1450.0 * release_time) * exp(-release_time * 180.0) * 0.20
		data.encode_s16(i * 2, clampi(roundi((hammer + metal + spring) * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_empty_weapon = stream
	return stream

static var _cached_ui_click: AudioStream = null

static func get_ui_click_stream() -> AudioStream:
	if _cached_ui_click != null: return _cached_ui_click
	var sample_rate := 22050
	var duration := 0.06
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var click := sin(2.0 * PI * 1800.0 * t) * exp(-t * 120.0) * 0.6
		data.encode_s16(i * 2, clampi(int(click * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	_cached_ui_click = stream
	return stream

# ==========================================
# SONS DE PASSOS (FOOTSTEPS POR SUPERFÍCIE)
# ==========================================
static var _cached_footstep_concrete: Array[AudioStream] = []
static var _cached_footstep_wet: Array[AudioStream] = []
static var _cached_footstep_grass: Array[AudioStream] = []
static var _cached_footstep_metal: AudioStream = null

static func get_footstep_stream(surface: String = "concrete", variation: int = 0) -> AudioStream:
	return preload("res://audio/footsteps/FootstepAudioBank.gd").sound(surface, variation)


# ==========================================
# PORTAS DE CARRO & ROUBO (CAR DOORS & CARJACKING)
# ==========================================
static var _cached_door_open: AudioStream = null
static var _cached_door_close: AudioStream = null
static var _cached_phone_dial: AudioStream = null
static var _cached_punch: AudioStream = null

static func get_car_door_open_stream() -> AudioStream:
	if _cached_door_open != null: return _cached_door_open
	var sample_rate := 22050
	var duration := 0.18
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var latch := sin(2.0 * PI * 1200.0 * t) * exp(-t * 120.0) * 0.6
		var swing := sin(2.0 * PI * 340.0 * t) * exp(-t * 25.0) * 0.35
		data.encode_s16(i * 2, clampi(int((latch + swing) * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_door_open = s
	return s

static func get_car_door_close_stream() -> AudioStream:
	if _cached_door_close != null: return _cached_door_close
	var sample_rate := 22050
	var duration := 0.22
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var thud := sin(2.0 * PI * 95.0 * t) * exp(-t * 40.0) * 0.85
		var click := sin(2.0 * PI * 1850.0 * t) * exp(-t * 140.0) * 0.50
		var metal := randf_range(-0.3, 0.3) * exp(-t * 70.0) * 0.35
		data.encode_s16(i * 2, clampi(int((thud + click + metal) * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_door_close = s
	return s

static func get_phone_dial_stream() -> AudioStream:
	if _cached_phone_dial != null: return _cached_phone_dial
	var sample_rate := 22050
	var duration := 0.40
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var beep1 := sin(2.0 * PI * 941.0 * t) * (1.0 if t < 0.12 else 0.0) * 0.4
		var beep2 := sin(2.0 * PI * 1336.0 * t) * (1.0 if (t > 0.16 and t < 0.28) else 0.0) * 0.4
		var beep3 := sin(2.0 * PI * 1209.0 * t) * (1.0 if t > 0.32 else 0.0) * 0.4
		data.encode_s16(i * 2, clampi(int((beep1 + beep2 + beep3) * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_phone_dial = s
	return s

static func get_punch_whack_stream() -> AudioStream:
	return preload("res://audio/combat/CombatAudioBank.gd").sound("flesh")

# ==========================================
# PACOTE SONORO URBANO: SIRENES DISTANTES, RÁDIO POLICIAL, GRITOS E PROPS
# ==========================================
static var _cached_distant_siren: AudioStream = null
static var _cached_radio_chatter: AudioStream = null
static var _cached_ped_scream: AudioStream = null
static var _cached_trashcan: AudioStream = null
static var _cached_hydrant: AudioStream = null
static var _cached_birds: AudioStream = null

static func get_distant_siren_stream() -> AudioStream:
	if _cached_distant_siren != null: return _cached_distant_siren
	var sample_rate := 22050
	var duration := 2.6
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var freq := 520.0 + sin(2.0 * PI * 0.8 * t) * 180.0
		var siren := sin(2.0 * PI * freq * t) * 0.25
		# Filtro passa-baixa e reverberação abafada de longa distância
		var echo := sin(2.0 * PI * freq * (t - 0.18)) * 0.12
		var env := sin(PI * (t / duration))
		var sample := (siren + echo) * env * 0.6
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_distant_siren = s
	return s

static func get_police_radio_chatter_stream() -> AudioStream:
	if _cached_radio_chatter != null: return _cached_radio_chatter
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 22050
	s.data = PackedByteArray()
	_cached_radio_chatter = s
	return s

static func get_pedestrian_scream_stream() -> AudioStream:
	return preload("res://audio/reactions/CharacterReactionBank.gd").sound("panic")

static func get_trashcan_hit_stream() -> AudioStream:
	if _cached_trashcan != null: return _cached_trashcan
	var sample_rate := 22050
	var duration := 0.42
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var clang := sin(2.0 * PI * 340.0 * t) * exp(-t * 22.0) * 0.75
		var rattle := sin(2.0 * PI * 820.0 * t) * exp(-t * 14.0) * 0.40
		var metal_noise := randf_range(-0.35, 0.35) * exp(-t * 30.0) * 0.50
		data.encode_s16(i * 2, clampi(int((clang + rattle + metal_noise) * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_trashcan = s
	return s

static func get_hydrant_burst_stream() -> AudioStream:
	if _cached_hydrant != null: return _cached_hydrant
	var sample_rate := 22050
	var duration := 0.70
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var rush := randf_range(-0.6, 0.6) * (0.8 + 0.2 * sin(2.0 * PI * 14.0 * t))
		var hiss := sin(2.0 * PI * 2200.0 * t) * 0.2
		var sample := (rush + hiss) * 0.65
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_hydrant = s
	return s

static func get_birds_wind_stream() -> AudioStream:
	if _cached_birds != null: return _cached_birds
	var sample_rate := 22050
	var duration := 2.5
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var breeze := randf_range(-0.25, 0.25) * sin(2.0 * PI * 0.4 * t) * 0.4
		var chirp := sin(2.0 * PI * (3200.0 + sin(2.0 * PI * 35.0 * t) * 600.0) * t) * (1.0 if (t > 0.4 and t < 0.65) or (t > 1.4 and t < 1.62) else 0.0) * 0.25
		data.encode_s16(i * 2, clampi(int((breeze + chirp) * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_birds = s
	return s

static var _cached_phone: AudioStream = null
static func get_phone_ring_stream() -> AudioStream:
	if _cached_phone != null: return _cached_phone
	var sample_rate := 22050
	var duration := 1.8
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var is_ringing := (t >= 0.0 and t < 0.45) or (t >= 0.65 and t < 1.10)
		var bell := 0.0
		if is_ringing:
			bell = (sin(2.0 * PI * 853.0 * t) + sin(2.0 * PI * 960.0 * t)) * 0.35 * (0.8 + 0.2 * sin(2.0 * PI * 20.0 * t))
		data.encode_s16(i * 2, clampi(int(bell * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_phone = s
	return s

static func get_mission_start_stream() -> AudioStream:
	return REWARD_AUDIO.sound("mission_start")

static func get_mission_passed_stream() -> AudioStream:
	return REWARD_AUDIO.sound("complete")


static var _cached_nitro: AudioStream = null
static func get_nitro_stream() -> AudioStream:
	if _cached_nitro != null: return _cached_nitro
	var sample_rate := 22050
	var duration := 1.2
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Síntese de Nitro: Jato de foguete pressurizado + apito agudo de turbo compressor
		var hiss := randf_range(-0.55, 0.55) * (0.8 + 0.2 * sin(2.0 * PI * 24.0 * t))
		var turbo_whine := sin(2.0 * PI * (1200.0 + 800.0 * (t / duration)) * t) * 0.35
		var sub_roar := sin(2.0 * PI * 55.0 * t) * 0.4
		var sample := (hiss * 0.6 + turbo_whine * 0.25 + sub_roar * 0.35) * 0.85
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.data = data
	_cached_nitro = s
	return s

static var _cached_blowoff: AudioStream = null
static func get_turbo_blowoff_stream() -> AudioStream:
	if _cached_blowoff != null: return _cached_blowoff
	var sample_rate := 22050
	var duration := 0.65
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Efeito "Tchuu-stututu" clássico de válvula wastegate/blowoff
		var flutter_freq := 18.0
		var flutter := 0.5 + 0.5 * sin(2.0 * PI * flutter_freq * t)
		var rush := randf_range(-0.5, 0.5) * exp(-t * 4.5) * (0.4 + 0.6 * flutter)
		var chirp := sin(2.0 * PI * (2400.0 - t * 1600.0) * t) * exp(-t * 6.0) * 0.35
		data.encode_s16(i * 2, clampi(int((rush + chirp) * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_blowoff = s
	return s

static var _cached_chalk: AudioStream = null
static func get_chalk_scratch_stream() -> AudioStream:
	if _cached_chalk != null: return _cached_chalk
	var sample_rate := 22050
	var duration := 0.75
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Raspagem de giz na lousa
		var scratch := randf_range(-0.35, 0.35) * sin(2.0 * PI * 850.0 * t) * exp(-fmod(t, 0.2) * 5.0)
		data.encode_s16(i * 2, clampi(int(scratch * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_chalk = s
	return s

static var _cached_tire_pop: AudioStream = null
static func get_tire_pop_stream() -> AudioStream:
	if _cached_tire_pop != null: return _cached_tire_pop
	var sample_rate := 22050
	var duration := 0.85
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Estouro de pneu em alta velocidade (Explosão súbita + esvaziamento tsssssh violento)
		var boom := sin(2.0 * PI * 80.0 * t) * exp(-t * 12.0) * 0.7
		var hiss := randf_range(-0.6, 0.6) * exp(-t * 2.8) * 0.55
		var sample := (boom + hiss) * 0.95
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_tire_pop = s
	return s

static var _cached_nos_purge: AudioStream = null
static func get_nos_purge_stream() -> AudioStream:
	if _cached_nos_purge != null: return _cached_nos_purge
	var sample_rate := 22050
	var duration := 0.45
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Purga de Nitro NOS estilo Velozes e Furiosos (Jato pressurizado PSSSHT)
		var hiss := randf_range(-0.7, 0.7) * (0.8 + 0.2 * sin(2.0 * PI * 45.0 * t)) * exp(-t * 3.5)
		data.encode_s16(i * 2, clampi(int(hiss * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_nos_purge = s
	return s

static var _cached_backfire: AudioStream = null
static func get_exhaust_backfire_stream() -> AudioStream:
	if _cached_backfire != null: return _cached_backfire
	var sample_rate := 22050
	var duration := 0.35
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		# Estalo de retorno do escapamento (Backfire pop)
		var pop := (sin(2.0 * PI * 180.0 * t) + randf_range(-0.5, 0.5)) * exp(-t * 18.0) * 0.85
		data.encode_s16(i * 2, clampi(int(pop * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_backfire = s
	return s

static var _cached_dialogue_blip: AudioStream = null
static func get_dialogue_blip_stream() -> AudioStream:
	if _cached_dialogue_blip != null: return _cached_dialogue_blip
	var sample_rate := 22050
	var duration := 0.09
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var freq := 240.0 + sin(2.0 * PI * 18.0 * t) * 45.0
		var tone := sin(2.0 * PI * freq * t) * (1.0 - t / duration) * 0.40
		data.encode_s16(i * 2, clampi(int(tone * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = sample_rate
	s.data = data
	_cached_dialogue_blip = s
	return s
