extends Node
## Separate mix stage: attenuation never rewrites the user's Music/SFX levels.
const WORLD_BUS := &"MissionWorld"
const VOICE_BUS := &"Dialogue"
const DUCK_DB := -16.0
const HOLD_SECONDS := 1.2
var _sources: Array[WeakRef] = []
var _hold := 0.0
var _level := 0.0
var _routing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	get_node("/root/SettingsManager").apply_audio_settings()
	AudioServer.bus_layout_changed.connect(_setup_buses)
	get_tree().node_added.connect(_node_added)
	set_process(false)

func _setup_buses() -> void:
	if _routing: return
	_routing = true
	# Sends must point to an earlier bus in Godot's mix order.
	if AudioServer.get_bus_index(WORLD_BUS) < 0:
		AudioServer.add_bus(1)
		AudioServer.set_bus_name(1, WORLD_BUS)
	if AudioServer.get_bus_index(VOICE_BUS) < 0:
		AudioServer.add_bus(2)
		AudioServer.set_bus_name(2, VOICE_BUS)
	for index in range(1, AudioServer.get_bus_count()):
		var bus := AudioServer.get_bus_name(index)
		if bus in [WORLD_BUS, VOICE_BUS]:
			AudioServer.set_bus_send(index, &"Master")
		elif AudioServer.get_bus_send(index) == &"Master":
			AudioServer.set_bus_send(index, WORLD_BUS)
	_routing = false

func _node_added(node: Node) -> void:
	# Audio with an omitted bus otherwise bypasses every category slider.
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		if node.bus == &"Master": node.bus = &"SFX"

func track(source: Node) -> void:
	for reference in _sources:
		if reference.get_ref() == source: return
	source.bus = VOICE_BUS
	_sources.append(weakref(source))
	set_process(true)

func _process(delta: float) -> void:
	var speaking := false
	for index in range(_sources.size()-1, -1, -1):
		var source: Node = _sources[index].get_ref()
		if not is_instance_valid(source) or not source.is_inside_tree():
			_sources.remove_at(index)
			continue
		if source.can_process() and source.playing and not source.stream_paused and source.stream != null:
			speaking = speaking or source.stream.has_meta("speech_envelope") or source.stream.get_meta("mission_voice", false)
	_hold = HOLD_SECONDS if speaking else maxf(0.0, _hold-delta)
	var target := DUCK_DB if _hold > 0.0 else 0.0
	_level = move_toward(_level, target, delta * (80.0 if target < _level else 18.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(WORLD_BUS), _level)
	if _sources.is_empty() and is_zero_approx(_level): set_process(false)
