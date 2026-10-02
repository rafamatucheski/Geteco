extends RefCounted
## Original, offline-authored PCM. Runtime only loads and reuses a small fixed bank.
const NOMINAL := [10, 13, 16, 20, 24, 28, 33]
const START_SECONDS := 2.8
static var _cache: Dictionary = {}
static var _bank: Array[AudioStreamWAV] = []

static func engine_bank() -> Array[AudioStreamWAV]:
	if _bank.size() == 7: return _bank
	_bank.clear()
	for index in 7:
		var stream := _stream("diesel_%d" % index, true)
		if stream == null:
			_bank.clear()
			return _bank
		_bank.append(stream)
	return _bank

static func fire_stream() -> AudioStreamWAV:
	return _stream("cannon_fire", false)

static func impact_stream() -> AudioStreamWAV:
	return _stream("cannon_impact", false)

static func start_stream() -> AudioStreamWAV:
	return _stream("diesel_start", false)

static func tracks_stream() -> AudioStreamWAV:
	return _stream("tracks", true)

## Quadros de áudio do recurso. `data.size() / 2` só vale para PCM de 16 bits: os WAVs entram
## como QOA (`compress/mode=2`), cujos bytes são ~1/5 das amostras, e o laço do motor e das
## esteiras fechava aos 0,4 s de um som de 2 s.
static func frame_count(stream: AudioStreamWAV) -> int:
	# Audio buffer/loop lengths count whole samples.
	@warning_ignore("integer_division")
	if stream.format == AudioStreamWAV.FORMAT_16_BITS: return stream.data.size() / (4 if stream.stereo else 2)
	return roundi(stream.get_length() * stream.mix_rate)

static func _stream(id: String, looped: bool) -> AudioStreamWAV:
	if _cache.has(id): return _cache[id]
	var path := "res://audio/tank/%s.wav" % id
	var source: AudioStreamWAV
	if ResourceLoader.exists(path, "AudioStreamWAV"):
		source = ResourceLoader.load(path, "AudioStreamWAV") as AudioStreamWAV
	elif FileAccess.file_exists(path):
		# Fresh source checkout before the editor imports assets. Export uses resources above.
		source = AudioStreamWAV.load_from_file(path)
	if source == null:
		push_error("TankAudio: missing original sound %s" % path)
		return null
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = frame_count(stream)
	_cache[id] = stream
	return stream

static func tracks_gain(speed: float) -> float:
	# Zero while stationary, including revving in neutral; identical in reverse.
	return smoothstep(0.08, 1.3, absf(speed)) * lerpf(0.35, 1.0, clampf(absf(speed) / 13.0, 0.0, 1.0))

static func tracks_pitch(speed: float) -> float:
	return clampf(0.42 + absf(speed) * 0.095, 0.42, 2.2)

static func claim_start(vehicle: Node) -> bool:
	if vehicle.get_meta(&"tank_engine_heard", false): return false
	vehicle.set_meta(&"tank_engine_heard", true)
	return absf(float(vehicle.get("speed"))) < 0.4

static func mix_spatial(players: Array, vehicle: CharacterBody3D, rpm: float, gain: float, base_db: float, position: Vector3) -> void:
	# Keep the established two-voice NPC budget: continuous diesel plus independent tracks.
	var bank := engine_bank()
	if bank.size() != 7 or players.size() < 2: return
	vehicle.set_meta(&"tank_engine_heard", true)
	var engine: AudioStreamPlayer3D = players[0]
	var tracks: AudioStreamPlayer3D = players[1]
	engine.global_position = position
	tracks.global_position = position
	_set_voice(engine, bank[2], base_db + 2.0, gain,
		lerpf(0.625, 2.06, clampf(rpm, 0.0, 1.0)))
	_set_voice(tracks, tracks_stream(), base_db + 2.0,
		gain * tracks_gain(float(vehicle.get("speed"))), tracks_pitch(float(vehicle.get("speed"))))

static func _set_voice(player: AudioStreamPlayer3D, stream: AudioStreamWAV, db: float, gain: float, pitch: float) -> void:
	if gain <= 0.001 or stream == null:
		player.stop()
		return
	if player.stream != stream:
		player.stop()
		player.stream = stream
	player.volume_db = db + linear_to_db(gain)
	player.pitch_scale = pitch
	if not player.playing: player.play()
