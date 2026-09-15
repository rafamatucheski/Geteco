extends Node
## Mixer próprio para abafamento; continua apenas para desligar áudio de região suspensa.
const BANK := preload("res://audio/regional/RegionalAudio.gd")
var bed: AudioStreamPlayer
var gale: AudioStreamPlayer
var gust: AudioStreamPlayer
var exposure := 0.0
var strength := 0.0
var active := false
var regional_weight := -1.0 # Negative preserves standalone/legacy region selection.
var _focus := 1.0
var _shelter := 0.0
var _timer := 4.0
var _variant := 0
var _bus: StringName
var _filter: AudioEffectLowPassFilter
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_bus = StringName("SnowWind_%d" % get_instance_id())
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, _bus)
	AudioServer.set_bus_send(index, &"Ambient")
	_filter = AudioEffectLowPassFilter.new()
	_filter.cutoff_hz = 16000
	AudioServer.add_bus_effect(index, _filter)
	bed = _player("ColdBreeze", BANK.sound("wind", 0))
	gale = _player("BlizzardWind", BANK.sound("wind", 1))
	gust = _player("SnowGust", BANK.sound("gust", 0))

func _player(label: String, stream: AudioStream) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.name = label
	audio.bus = _bus
	audio.stream = stream
	audio.volume_db = -80
	add_child(audio)
	return audio

func _process(delta: float) -> void:
	var storm := get_parent()
	var region := storm.get_parent()
	var weight := regional_weight if regional_weight >= 0.0 else (1.0 if region.get("region_selected") != false else 0.0)
	active = not get_tree().paused and storm.can_process() and weight > 0.001
	var target := clampf(float(storm.storm_intensity), 0, 1.5) / 1.5
	if int(storm.current_state) == 0: target *= 0.12
	elif int(storm.current_state) == 1: target *= 0.45
	strength = move_toward(strength, target, delta * 0.3)
	exposure = move_toward(exposure, weight if active else 0.0, delta * 1.2)
	_shelter = move_toward(_shelter, 1.0 if storm.sheltered else 0.0, delta * 1.5)
	var actor: Node2D = storm.follow_target
	_focus = move_toward(_focus, 0.35 if is_instance_valid(actor) and actor.get("is_in_dialogue") == true else 1.0, delta * 2)
	_filter.cutoff_hz = lerpf(16000, 850, _shelter)
	var gain := exposure * _focus * lerpf(1, 0.14, _shelter)
	_mix(bed, gain * lerpf(0.4, 0.55, strength), -7)
	_mix(gale, gain * smoothstep(0.08, 0.8, strength), -3)
	gust.volume_db = -5.0 + linear_to_db(maxf(gain * lerpf(0.3, 1, strength), 0.0001))
	if not active or storm.sheltered:
		gust.stop()
		_timer = 3.0
		return
	_timer -= delta
	if _timer <= 0 and not gust.playing and _focus > 0.5:
		gust.stream = BANK.sound("gust", _variant)
		_variant = (_variant + _rng.randi_range(1, 2)) % 3
		gust.pitch_scale = _rng.randf_range(0.92, 1.06)
		gust.play()
		_timer = _rng.randf_range(11, 22) * lerpf(1.5, 0.7, strength)

func _mix(audio: AudioStreamPlayer, gain: float, offset: float) -> void:
	audio.volume_db = offset + linear_to_db(maxf(gain, 0.0001))
	if gain > 0.001 and not audio.playing: audio.play(_rng.randf_range(0, 20))
	elif gain <= 0.001 and audio.playing: audio.stop()

func _exit_tree() -> void:
	var index := AudioServer.get_bus_index(_bus)
	if index > 0: AudioServer.remove_bus(index)
