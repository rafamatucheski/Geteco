class_name OpeningCutsceneAudio
extends Node

## Passagem sonora provisória 100% procedural.
## Nenhum arquivo de áudio externo é necessário: os buffers PCM são sintetizados
## deterministicamente ao iniciar a cena e disparados pelos cue_requested do timeline.

const SAMPLE_RATE := 22050
const MASTER_GAIN_DB := -4.0
const SUPPORTED_CUES: Array[StringName] = [
	&"rain_city", &"traffic_distant", &"thunder_distant", &"music_prologue_start",
	&"phone_ring_old", &"phone_vibrate_wood", &"phone_answer_click", &"lightning_flash",
	&"photo_paper", &"jacket_fabric", &"backpack_buckle", &"chair_creak", &"floor_steps",
	&"door_open", &"rain_gust", &"door_close", &"bus_diesel_exterior", &"music_travel",
	&"bus_wiper", &"bus_diesel_interior", &"bus_body_rattle", &"bus_brakes",
	&"terminal_ambience", &"terminal_pa_distant", &"bus_air_brake",
]

@export var enabled := true
@export_range(-18.0, 0.0, 0.5) var master_gain_db := MASTER_GAIN_DB

var _streams: Dictionary = {}
var _levels_db: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _rain_player: AudioStreamPlayer
var _bus_player: AudioStreamPlayer
var _wiper_player: AudioStreamPlayer
var _terminal_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_streams()
	preload("res://ExpressiveVoice.gd").line(tr("CGI_DANTE_WHO_ARE_YOU"), "dante", 1.6)
	preload("res://ExpressiveVoice.gd").line(tr("CGI_CALLER_BROTHER_MISSING"), "caller", 4.1)
	_rain_player = _make_player("RainLoop")
	_bus_player = _make_player("BusLoop")
	_wiper_player = _make_player("WiperLoop")
	_terminal_player = _make_player("TerminalLoop")
	_music_player = _make_player("ProvisionalUnderscore")
	for index in range(8):
		var player := _make_player("Foley%02d" % index)
		player.max_polyphony = 2
		_sfx_players.append(player)


func play_cue(cue_id: StringName, _payload: Dictionary = {}) -> void:
	if not enabled:
		return
	match cue_id:
		&"rain_city":
			_start_loop(_rain_player, &"rain", -29.0)
		&"music_prologue_start":
			_start_loop(_music_player, &"drone", -24.0)
		&"bus_diesel_exterior":
			_rain_player.volume_db = master_gain_db - 30.0
			_start_loop(_bus_player, &"bus_exterior", -8.0)
		&"bus_diesel_interior":
			_rain_player.volume_db = master_gain_db - 38.0
			_start_loop(_bus_player, &"bus_interior", -10.0, true)
		&"bus_wiper":
			_start_loop(_wiper_player, &"wiper", -12.0)
		&"terminal_ambience":
			_start_loop(_terminal_player, &"terminal", -17.0)
			_bus_player.volume_db = master_gain_db - 14.0
		&"music_travel":
			_start_loop(_music_player, &"travel_drone", -25.0, true)
		&"voice_caller_brother_missing", &"voice_dante_who_are_you":
			var voice := _find_sfx_player()
			var is_dante := cue_id == &"voice_dante_who_are_you"
			voice.stream = preload("res://ExpressiveVoice.gd").line(tr("CGI_DANTE_WHO_ARE_YOU") if is_dante else tr("CGI_CALLER_BROTHER_MISSING"), "dante" if is_dante else "caller", 1.6 if is_dante else 4.1)
			voice.volume_db = -21.0
			voice.play()
		_:
			_play_one_shot(cue_id)


func reset() -> void:
	for player in _all_players():
		player.stop()
		player.stream_paused = false

func enter_shot(id: StringName) -> void:
	# Foley belongs to an image; never carry a wiper/ring into a different place.
	for audio in _sfx_players:
		audio.stop()
	if id not in [&"bus_highway", &"dante_bus_interior"]:
		_wiper_player.stop()
	if id in [&"apartment_phone_wide", &"phone_closeup", &"call_reaction", &"photo_in_jacket", &"backpack_departure"]:
		_rain_player.volume_db = master_gain_db - 42.0
	if id == &"bus_terminal_arrival":
		_bus_player.stop()
		_rain_player.volume_db = master_gain_db - 30.0


func stop_all() -> void:
	for player in _all_players():
		player.stop()


func set_paused(paused: bool) -> void:
	for player in _all_players():
		player.stream_paused = paused


func _build_streams() -> void:
	_streams = {
		&"rain": _synthesize(&"rain", 7.0, true),
		&"traffic_distant": _synthesize(&"traffic", 2.5),
		&"thunder_distant": _synthesize(&"thunder", 3.2),
		&"drone": _synthesize(&"drone", 6.0, true),
		&"phone_ring_old": _synthesize(&"phone_ring", 1.25),
		&"phone_vibrate_wood": _synthesize(&"vibrate", 0.9),
		&"phone_answer_click": _synthesize(&"click", 0.18),
		&"lightning_flash": _synthesize(&"thunder_light", 2.0),
		&"photo_paper": _synthesize(&"paper", 0.55),
		&"jacket_fabric": _synthesize(&"fabric", 0.8),
		&"backpack_buckle": _synthesize(&"buckle", 0.55),
		&"chair_creak": _synthesize(&"chair", 0.9),
		&"floor_steps": _synthesize(&"steps", 2.1),
		&"door_open": _synthesize(&"door_open", 1.2),
		&"rain_gust": _synthesize(&"rain_gust", 1.8),
		&"door_close": _synthesize(&"door_close", 0.75),
		&"bus_exterior": _synthesize(&"bus_exterior", 4.0, true),
		&"travel_drone": _synthesize(&"travel_drone", 6.0, true),
		&"wiper": _synthesize(&"wiper", 2.2, true),
		&"bus_interior": _synthesize(&"bus_interior", 4.0, true),
		&"bus_body_rattle": _synthesize(&"body_rattle", 1.1),
		&"bus_brakes": _synthesize(&"brakes", 2.2),
		&"terminal": _synthesize(&"terminal", 5.0, true),
		&"terminal_pa_distant": _synthesize(&"terminal_pa", 1.7),
		&"bus_air_brake": _synthesize(&"air_brake", 1.2),
	}
	_levels_db = {
		&"traffic_distant": -19.0,
		&"thunder_distant": -12.0,
		&"phone_ring_old": -8.5,
		&"phone_vibrate_wood": -10.0,
		&"phone_answer_click": -8.0,
		&"lightning_flash": -16.0,
		&"photo_paper": -12.0,
		&"jacket_fabric": -15.0,
		&"backpack_buckle": -10.0,
		&"chair_creak": -13.0,
		&"floor_steps": -10.0,
		&"door_open": -10.0,
		&"rain_gust": -12.0,
		&"door_close": -7.5,
		&"bus_body_rattle": -14.0,
		&"bus_brakes": -9.0,
		&"terminal_pa_distant": -19.0,
		&"bus_air_brake": -8.0,
	}


func _play_one_shot(cue_id: StringName) -> void:
	if not _streams.has(cue_id):
		return
	var player := _find_sfx_player()
	player.stream = _streams[cue_id]
	player.volume_db = master_gain_db + float(_levels_db.get(cue_id, -12.0))
	player.pitch_scale = 1.0
	player.play()


func _start_loop(player: AudioStreamPlayer, stream_id: StringName, level_db: float, replace := false) -> void:
	if not _streams.has(stream_id):
		return
	if player.playing and player.stream == _streams[stream_id] and not replace:
		return
	player.stop()
	player.stream = _streams[stream_id]
	player.volume_db = master_gain_db + level_db
	player.play()


func _find_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_players:
		if not player.playing:
			return player
	return _sfx_players[0]


func _make_player(node_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	var preferred_bus := &"Music" if node_name == "ProvisionalUnderscore" else &"SFX"
	if AudioServer.get_bus_index(preferred_bus) >= 0:
		player.bus = preferred_bus
	add_child(player)
	return player


func _all_players() -> Array[AudioStreamPlayer]:
	var players: Array[AudioStreamPlayer] = [
		_rain_player, _bus_player, _wiper_player, _terminal_player, _music_player,
	]
	players.append_array(_sfx_players)
	return players


func _synthesize(kind: StringName, duration: float, looped := false) -> AudioStreamWAV:
	var frame_count := maxi(1, int(duration * SAMPLE_RATE))
	var pcm := PackedByteArray()
	pcm.resize(frame_count * 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash(String(kind))) + 730_201
	var low_l := 0.0
	var low_r := 0.0
	var drop_l := 0.0
	var drop_r := 0.0
	for index in range(frame_count):
		var time := float(index) / SAMPLE_RATE
		var white_l := rng.randf_range(-1.0, 1.0)
		var white_r := rng.randf_range(-1.0, 1.0)
		low_l += (white_l - low_l) * 0.025
		low_r += (white_r - low_r) * 0.021
		var left := 0.0
		var right := 0.0
		match kind:
			&"rain":
				if rng.randf() < 0.0018:
					drop_l += rng.randf_range(0.15, 0.36)
				if rng.randf() < 0.0018:
					drop_r += rng.randf_range(0.15, 0.36)
				drop_l *= 0.91
				drop_r *= 0.91
				left = white_l * 0.08 + low_l * 0.19 + drop_l
				right = white_r * 0.08 + low_r * 0.19 + drop_r
			&"traffic":
				var env := sin(PI * clampf(time / duration, 0.0, 1.0))
				left = (low_l * 0.42 + sin(TAU * 52.0 * time) * 0.035) * env
				right = (low_r * 0.42 + sin(TAU * 49.0 * time) * 0.035) * env
			&"thunder", &"thunder_light":
				var delay := 0.18 if kind == &"thunder" else 0.05
				var local_t := maxf(0.0, time - delay)
				var env := (1.0 - exp(-local_t * 7.0)) * exp(-local_t * (0.75 if kind == &"thunder" else 1.2))
				var rumble := sin(TAU * (38.0 - local_t * 2.5) * local_t) * 0.22
				left = (low_l * 1.15 + rumble) * env
				right = (low_r * 1.05 + rumble * 0.92) * env
			&"drone", &"travel_drone":
				var root := 43.0 if kind == &"drone" else 49.0
				left = sin(TAU * root * time) * 0.09 + sin(TAU * root * 1.5 * time) * 0.025
				right = sin(TAU * (root + 0.25) * time) * 0.09 + sin(TAU * root * 1.5 * time) * 0.025
			&"phone_ring":
				var phase := fmod(time, 0.62)
				var gate := 1.0 if phase < 0.42 else 0.0
				var edge := minf(1.0, phase * 35.0) * minf(1.0, maxf(0.0, 0.42 - phase) * 35.0)
				left = (sin(TAU * 480.0 * time) + sin(TAU * 620.0 * time)) * 0.18 * gate * edge
				right = left * 0.96
			&"vibrate":
				var phase := fmod(time, 0.3)
				var gate := 1.0 if phase < 0.19 else 0.0
				var knock := exp(-phase * 32.0)
				left = (sin(TAU * 88.0 * time) * 0.22 + white_l * 0.07 * knock) * gate
				right = (sin(TAU * 91.0 * time) * 0.21 + white_r * 0.07 * knock) * gate
			&"click":
				var env := exp(-time * 46.0)
				left = (white_l * 0.46 + sin(TAU * 1100.0 * time) * 0.22) * env
				right = left
			&"paper":
				var env := sin(PI * time / duration)
				left = (white_l - low_l) * 0.18 * env * (0.55 + 0.45 * sin(TAU * 9.0 * time))
				right = (white_r - low_r) * 0.16 * env * (0.55 + 0.45 * sin(TAU * 9.0 * time + 0.4))
			&"fabric":
				var env := sin(PI * time / duration)
				left = low_l * 0.55 * env * (0.7 + 0.3 * sin(TAU * 6.0 * time))
				right = low_r * 0.55 * env * (0.7 + 0.3 * sin(TAU * 5.6 * time))
			&"buckle":
				var env := exp(-time * 8.5)
				var metal := sin(TAU * 1280.0 * time) + 0.55 * sin(TAU * 1870.0 * time)
				left = metal * 0.17 * env + low_l * 0.08 * sin(PI * time / duration)
				right = left * 0.93
			&"chair":
				var env := sin(PI * time / duration)
				var creak_hz := 260.0 - time * 130.0 + sin(time * 19.0) * 25.0
				left = (sin(TAU * creak_hz * time) * 0.13 + low_l * 0.27) * env
				right = (sin(TAU * (creak_hz + 7.0) * time) * 0.12 + low_r * 0.25) * env
			&"steps":
				var pulse := 0.0
				for hit_time in [0.12, 0.78, 1.45]:
					var since: float = time - float(hit_time)
					if since >= 0.0:
						pulse += exp(-since * 18.0)
				left = pulse * (sin(TAU * 72.0 * time) * 0.2 + low_l * 0.36)
				right = pulse * (sin(TAU * 68.0 * time) * 0.18 + low_r * 0.34)
			&"door_open":
				var env := sin(PI * time / duration)
				var creak_hz := 180.0 + sin(time * 8.0) * 55.0
				left = (sin(TAU * creak_hz * time) * 0.16 + low_l * 0.32) * env
				right = (sin(TAU * (creak_hz + 4.0) * time) * 0.15 + low_r * 0.29) * env
			&"rain_gust":
				var env := sin(PI * time / duration)
				left = (white_l * 0.12 + low_l * 0.48) * env
				right = (white_r * 0.12 + low_r * 0.52) * env
			&"door_close":
				var impact := exp(-time * 13.0)
				left = (sin(TAU * 64.0 * time) * 0.39 + low_l * 0.48) * impact
				right = (sin(TAU * 61.0 * time) * 0.36 + low_r * 0.45) * impact
			&"bus_exterior", &"bus_interior":
				var root := 54.0 if kind == &"bus_exterior" else 47.0
				var gain := 0.19 if kind == &"bus_exterior" else 0.15
				var engine := sin(TAU * root * time) + 0.42 * sin(TAU * root * 2.0 * time) + 0.16 * sin(TAU * root * 3.0 * time)
				left = engine * gain + low_l * (0.17 if kind == &"bus_exterior" else 0.1)
				right = engine * gain * 0.96 + low_r * (0.17 if kind == &"bus_exterior" else 0.1)
			&"wiper":
				var phase := fmod(time, 2.2)
				var sweep := 0.0
				if phase < 0.48:
					sweep = sin(PI * phase / 0.48)
				elif phase > 1.05 and phase < 1.58:
					sweep = sin(PI * (phase - 1.05) / 0.53)
				var end_knock := exp(-abs(phase - 0.49) * 85.0) + exp(-abs(phase - 1.59) * 85.0)
				left = (white_l - low_l) * 0.11 * sweep + sin(TAU * 105.0 * time) * 0.08 * end_knock
				right = (white_r - low_r) * 0.1 * sweep + sin(TAU * 108.0 * time) * 0.07 * end_knock
			&"body_rattle":
				var pulse := pow(maxf(0.0, sin(TAU * 7.0 * time)), 9.0)
				left = (white_l * 0.18 + sin(TAU * 240.0 * time) * 0.12) * pulse
				right = (white_r * 0.18 + sin(TAU * 232.0 * time) * 0.12) * pulse
			&"brakes":
				var env := sin(PI * time / duration)
				var hz := 1250.0 - 720.0 * time / duration
				left = (sin(TAU * hz * time) * 0.13 + white_l * 0.09 + low_l * 0.22) * env
				right = (sin(TAU * (hz + 18.0) * time) * 0.12 + white_r * 0.09 + low_r * 0.22) * env
			&"terminal":
				var murmur := low_l * 0.25 + sin(TAU * 92.0 * time) * 0.015
				left = murmur + white_l * 0.018
				right = low_r * 0.25 + sin(TAU * 87.0 * time) * 0.015 + white_r * 0.018
			&"terminal_pa":
				var env := sin(PI * time / duration)
				var chime := sin(TAU * 660.0 * time) + 0.7 * sin(TAU * 880.0 * time)
				left = chime * 0.055 * env + low_l * 0.18 * env
				right = chime * 0.05 * env + low_r * 0.18 * env
			&"air_brake":
				var env := (1.0 - exp(-time * 35.0)) * exp(-time * 2.8)
				left = (white_l * 0.2 + low_l * 0.42) * env
				right = (white_r * 0.2 + low_r * 0.42) * env
		var base := index * 4
		pcm.encode_s16(base, int(clampf(left, -0.98, 0.98) * 32767.0))
		pcm.encode_s16(base + 2, int(clampf(right, -0.98, 0.98) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = pcm
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = frame_count
	return stream
