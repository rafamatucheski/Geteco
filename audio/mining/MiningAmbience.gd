extends Node3D
## Two positional voices per site, owned by the streamed chunk or active room.
## Recorded sources are cached; no synthesis or resource work in the frame loop.
const CATALOG := preload("res://audio/v1_ambience/V1AudioCatalog.gd")
var cavern := false
var _enabled := true
var _bed: AudioStreamPlayer3D
var _detail: AudioStreamPlayer3D
var _tick := 0.0
var _detail_clock := 4.0
var _variant := 0
var _details: Array[AudioStream] = []
static var _crusher_stream: AudioStreamWAV

func _ready() -> void:
	name = "MineCavernAmbience" if cavern else "MineCrusherAmbience"
	_bed = _voice("DrainWater" if cavern else "CrusherMotor", -28.0 if cavern else -22.0)
	_detail = _voice("MineStructuralCreaks", -24.0 if cavern else -19.0)
	if cavern:
		_bed.stream = CATALOG.bed("water", 0)
		_bed.pitch_scale = .87
	else:
		if _crusher_stream == null:
			_crusher_stream = (load("res://audio/acoustic/engine_truck_0.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
			_crusher_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			_crusher_stream.loop_begin = 0
			_crusher_stream.loop_end = maxi(1, roundi(_crusher_stream.get_length() * _crusher_stream.mix_rate) - 8)
		_bed.stream = _crusher_stream
		_bed.pitch_scale = .72
	for index in 3: _details.append(CATALOG.regional("scrap", index))
	visibility_changed.connect(_update_presence)
	_update_presence()

func _voice(label: String, level: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = label
	voice.bus = &"Ambient" if AudioServer.get_bus_index(&"Ambient") >= 0 else &"Master"
	voice.unit_size = 18.0 if cavern else 12.0
	voice.max_distance = 65.0 if cavern else 85.0
	voice.volume_db = level
	add_child(voice)
	return voice

func set_active(value: bool) -> void:
	_enabled = value
	set_process(value)
	if is_node_ready(): _update_presence()

func _update_presence() -> void:
	if _bed == null: return
	var camera := get_viewport().get_camera_3d()
	var audible := _enabled and is_visible_in_tree() and camera != null
	if audible: audible = camera.global_position.distance_squared_to(global_position) < _bed.max_distance * _bed.max_distance
	if not audible:
		_bed.stop()
		_detail.stop()
		_detail_clock = maxf(_detail_clock, 3.0)
	elif not _bed.playing and _bed.stream != null:
		_bed.play()

func _process(delta: float) -> void:
	_tick += delta
	if _tick < .25: return
	var elapsed := _tick
	_tick = 0.0
	_update_presence()
	if not _bed.playing: return
	_detail_clock -= elapsed
	if _detail_clock > 0.0 or _detail.playing: return
	_detail.stream = _details[_variant % _details.size()]
	_detail.pitch_scale = .78 + float(_variant % 3) * .07 if cavern else .94
	_detail.position = Vector3(2.0 + float(_variant % 3) * 3.0, 1.8, -2.0) if cavern else Vector3(0, 2, 0)
	if _detail.stream != null: _detail.play()
	_variant += 1
	_detail_clock = 8.0 + float((_variant * 7) % 9)

func debug_snapshot() -> Dictionary:
	return {"enabled": _enabled, "cavern": cavern, "voices": 2,
		"bed_playing": _bed != null and _bed.playing,
		"detail_playing": _detail != null and _detail.playing}
