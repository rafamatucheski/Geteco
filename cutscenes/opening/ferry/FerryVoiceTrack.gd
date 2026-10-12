extends Node
## Replace only the speech stem when all eleven validated takes fit the film.
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const DEADLINES := [15.82,20.82,24.82,28.82,36.82,41.82,48.82,51.82,61.82,64.82,67.32]
var directed := false
var reason := ""
var failure: Dictionary = {}
var failures: Array[Dictionary] = []
var windows: Array[Dictionary] = []
var takes: Array[Dictionary] = []
var player: AudioStreamPlayer
var disconnect: AudioStreamPlayer
var _current := -1
var _beeps := [false, false]
var _memory_bus := ""

func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.name = "DirectedFerryDialogue"
	player.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	player.volume_db = -8.0
	add_child(player)
	disconnect = AudioStreamPlayer.new()
	disconnect.name = "RememberedPhoneDisconnect"
	disconnect.bus = player.bus
	disconnect.stream = _disconnect_beep()
	add_child(disconnect)

func configure(lines: Array, voice_language: String) -> bool:
	stop()
	directed = false
	takes.clear()
	_current = -1
	_beeps = [false, false]
	reason = "disabled_or_incomplete"
	failure.clear()
	failures.clear()
	windows.clear()
	if not VOICE.DIRECTED.enabled() or lines.size() != DEADLINES.size(): return false
	for index in lines.size():
		var line: Dictionary = lines[index]
		var shown := VOICE.presentation(str(line.text), str(line.speaker), voice_language, "pt_BR", "", "opening_ferry")
		var deadline := float(DEADLINES[index])
		var diagnostic := {"id":line.id, "source_key":VOICE.recording_key(str(line.text), str(line.speaker)),
			"language":voice_language, "start":float(line.start), "deadline":deadline,
			"available_seconds":deadline-float(line.start), "directed":bool(shown.directed), "fits":false}
		if not shown.directed or shown.stream == null:
			diagnostic.reason = "missing_validated_take:" + str(line.id)
			windows.append(diagnostic)
			failures.append(diagnostic)
			continue
		diagnostic.duration_seconds = float(shown.duration)
		diagnostic.overflow_seconds = maxf(0.0, float(line.start) + float(shown.duration) - deadline)
		if float(line.start) + float(shown.duration) > deadline:
			diagnostic.reason = "take_exceeds_film_window:" + str(line.id)
			windows.append(diagnostic)
			failures.append(diagnostic)
			continue
		diagnostic.fits = true
		windows.append(diagnostic)
		var row := VOICE.DIRECTED.canonical(str(line.text), str(line.speaker))
		takes.append({"stream":shown.stream, "start":float(line.start), "end":float(line.start)+float(shown.duration),
			"pt":str(row.spoken_pt), "en":str(row.spoken_en), "memory":bool(line.get("memory", false))})
	if not failures.is_empty():
		failure = failures[0]
		reason = str(failure.reason)
		takes.clear()
		return false
	directed = true
	reason = "all_takes_validated_and_fit"
	return true

func update_clock(time: float) -> void:
	if not directed: return
	var chosen := -1
	for index in takes.size():
		if time >= float(takes[index].start) and time < float(takes[index].end):
			chosen = index
			break
	if chosen != _current:
		_current = chosen
		player.stop()
		if chosen >= 0:
			var take: Dictionary = takes[chosen]
			player.bus = _phone_bus() if take.memory else (&"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master")
			player.stream = take.stream
			player.volume_db = VOICE.playback_volume(player.stream, -8.0)
			player.play(maxf(0.0, time - float(take.start)))
	for index in 2:
		var start := 52.0 + .35 * index
		if not _beeps[index] and time >= start:
			_beeps[index] = true
			if time < start + .13: disconnect.play(time - start)

func caption(index: int, language: String) -> String:
	return str(takes[index].en if language == "en" else takes[index].pt)

func pause_playback(paused: bool) -> void:
	player.stream_paused = paused
	disconnect.stream_paused = paused

func stop() -> void:
	if is_instance_valid(player): player.stop()
	if is_instance_valid(disconnect): disconnect.stop()

func fade(tween: Tween, seconds: float) -> void:
	tween.tween_property(player, "volume_db", -60.0, seconds)
	tween.tween_property(disconnect, "volume_db", -60.0, seconds)

func _phone_bus() -> StringName:
	if _memory_bus.is_empty():
		_memory_bus = "FerryMemoryVoice_%d" % get_instance_id()
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, _memory_bus)
		AudioServer.set_bus_send(index, &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master")
		var high := AudioEffectHighPassFilter.new()
		high.cutoff_hz = 300.0
		var low := AudioEffectLowPassFilter.new()
		low.cutoff_hz = 3700.0
		AudioServer.add_bus_effect(index, high)
		AudioServer.add_bus_effect(index, low)
	return StringName(_memory_bus)

func _disconnect_beep() -> AudioStreamWAV:
	var pcm := PackedByteArray()
	var rate := 22050
	var samples := roundi(.13 * rate)
	pcm.resize(samples * 2)
	for index in samples:
		var t := float(index) / rate
		var fade := minf(1.0, t / .012) * minf(1.0, (.13 - t) / .025)
		pcm.encode_s16(index * 2, roundi(sin(TAU * 440.0 * t) * .027 * fade * 32767.0))
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = rate
	result.data = pcm
	return result

func _exit_tree() -> void:
	stop()
	var index := AudioServer.get_bus_index(_memory_bus)
	if not _memory_bus.is_empty() and index >= 0: AudioServer.remove_bus(index)
