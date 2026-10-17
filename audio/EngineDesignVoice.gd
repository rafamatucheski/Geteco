extends Node3D
## Four native voices: two adjacent RPM bands x loaded/coast. Their start phases
## follow one crank clock. Turbo FX are foreground-only and never run for diesel
## bypass or aspirated engines. The caller owns eligibility and spatial slots.
const BANKS := preload("res://audio/EngineDesignBanks.gd")
const CATALOG := preload("res://audio/FleetEngineDesign.gd")
const MOTOR_VOICE_LIMIT := 4
var profile := ""
var spatial_range := 45.0
var spatial_unit_size := 8.0
var _loaded: Array[AudioStreamWAV] = []
var _coast: Array[AudioStreamWAV] = []
var _rpm_bands: Array = []
var _players: Array[AudioStreamPlayer3D] = []
var _spool: AudioStreamPlayer3D
var _release: AudioStreamPlayer3D
var _spool_stream: AudioStreamWAV
var _release_stream: AudioStreamWAV
var _band_log_spans: Array[float] = []
var _phase := 0.0
var _load := 0.0
var _last_load := 0.0
var _boost := 0.0
var _release_cooldown := 0.0
var _foreground := false
var _combustion_load := 0.0
var _active := false

func configure(archetype: String) -> bool:
	var chosen := CATALOG.profile(archetype) if BANKS.enabled() else ""
	if chosen.is_empty() or not BANKS.is_ready(chosen):
		stop()
		return false
	if profile == chosen: return true
	stop()
	profile = chosen
	_loaded = BANKS.bank(profile)
	_coast = BANKS.bank(profile, "coast")
	_rpm_bands = CATALOG.rpm_bands(profile)
	_spool_stream = BANKS.effect(profile, "turbo_spool")
	_release_stream = BANKS.effect(profile, "bypass_release")
	_band_log_spans.clear()
	for i in 6:
		_band_log_spans.append(log(float(_rpm_bands[i + 1]) / float(_rpm_bands[i])))
	if _players.is_empty():
		for i in MOTOR_VOICE_LIMIT: _players.append(_player("DesignEngine%d" % i))
	_phase = 0.0
	_load = 0.0
	_last_load = 0.0
	_boost = 0.0
	return true

func _player(label: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = label
	p.max_polyphony = 1
	# This mixer routes directly to its bus. The game has no Area3D audio
	# overrides; skip their per-voice physics queries while retaining 3D pan.
	p.area_mask = 0
	p.unit_size = spatial_unit_size
	p.max_distance = spatial_range
	p.volume_db = -80.0
	p.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	add_child(p)
	return p

func set_bus(bus: StringName) -> void:
	for p in _all_players(): p.bus = bus

func _all_players() -> Array:
	var result: Array = _players.duplicate()
	if is_instance_valid(_spool): result.append(_spool)
	if is_instance_valid(_release): result.append(_release)
	return result

func update_mix(rpm: float, load_value: float, delta: float, volume_db: float, at: Vector3,
		foreground: bool, boost_allowed := true, shifted := false) -> void:
	if _loaded.size() != 7: return
	if global_position != at: global_position = at
	var changed := foreground != _foreground or not _active
	_foreground = foreground
	_active = true
	rpm = clampf(rpm, float(_rpm_bands[0]) * .85, float(_rpm_bands[6]) * 1.1)
	_phase += rpm / 120.0 * delta
	_load = lerpf(_load, clampf(load_value, 0, 1), 1.0 - exp(-delta * 40.0))
	_combustion_load = maxf(_load, 1.0 - smoothstep(float(_rpm_bands[0]) * 1.1, float(_rpm_bands[0]) * 1.8, rpm))
	var lower := 0
	while lower < 5 and rpm > float(_rpm_bands[lower + 1]): lower += 1
	var blend := clampf(log(rpm / float(_rpm_bands[lower])) / _band_log_spans[lower], 0, 1)
	for state in 2:
		var state_gain := sqrt(_combustion_load if state == 0 else 1.0 - _combustion_load)
		var streams: Array[AudioStreamWAV] = _loaded if state == 0 else _coast
		for offset in 2:
			var index := lower + offset
			var p := _players[state * 2 + index % 2]
			var gain := sqrt(1.0 - blend if index == lower else blend) * state_gain
			if gain <= .001:
				if p.playing: p.stop()
				continue
			if p.stream != streams[index]:
				if p.playing: p.stop()
				p.stream = streams[index]
			p.pitch_scale = clampf(rpm / float(_rpm_bands[index]), .35, 3.0)
			p.volume_db = volume_db + linear_to_db(gain)
			if changed or not p.playing: _spatial(p)
			if not p.playing:
				var seconds := float(streams[index].loop_end) / streams[index].mix_rate
				p.play(fposmod(_phase / (float(_rpm_bands[index]) / 120.0), seconds))
	_update_turbo(rpm, delta, volume_db, boost_allowed, shifted, changed)
	_last_load = _load

func _spatial(p: AudioStreamPlayer3D) -> void:
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED if _foreground else AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.max_distance = 0.0 if _foreground else spatial_range
	p.panning_strength = 0.0 if _foreground else 1.0
	p.attenuation_filter_db = 0.0 if _foreground else -24.0

func _update_turbo(rpm: float, delta: float, volume_db: float, allowed: bool, shifted: bool, changed: bool) -> void:
	_release_cooldown = maxf(0.0, _release_cooldown - delta)
	var stream := _spool_stream
	if not _foreground or not allowed or stream == null:
		_boost = 0.0
		if is_instance_valid(_spool) and _spool.playing: _spool.stop()
		if is_instance_valid(_release) and _release.playing: _release.stop()
		return
	if not is_instance_valid(_spool):
		_spool = _player("DesignTurbo")
		_spool.stream = stream
		changed = true
	elif _spool.stream != stream:
		if _spool.playing: _spool.stop()
		_spool.stream = stream
	if changed: _spatial(_spool)
	var prior := _boost
	var target := _load * smoothstep(float(_rpm_bands[6]) * .32, float(_rpm_bands[6]) * .72, rpm)
	_boost = lerpf(_boost, target, 1.0 - exp(-delta / (.48 if target > _boost else .13)))
	_spool.pitch_scale = .72 + _boost * .48
	_spool.volume_db = volume_db + linear_to_db(maxf(.0001, pow(_boost, 1.6)))
	if _boost > .02 and not _spool.playing: _spool.play()
	elif _boost <= .02 and _spool.playing: _spool.stop()
	var release_stream := _release_stream
	if release_stream != null and _release_cooldown <= 0 and prior > .20 and (shifted or (_last_load > .45 and _load < .45)):
		if not is_instance_valid(_release): _release = _player("DesignBypass")
		_release.stream = release_stream
		_spatial(_release)
		_release.volume_db = volume_db + linear_to_db(prior)
		_release.play()
		_release_cooldown = .22

func stop() -> void:
	if not _active: return
	for p in _players:
		if p.playing: p.stop()
	if is_instance_valid(_spool) and _spool.playing: _spool.stop()
	if is_instance_valid(_release) and _release.playing: _release.stop()
	_active = false
	_boost = 0.0
	_release_cooldown = 0.0

func snapshot() -> Dictionary:
	var playing := 0
	var by_state := [0, 0]
	for i in _players.size():
		if _players[i].playing:
			playing += 1
			by_state[i / 2] += 1
	return {"profile": profile, "active": _active, "ready": BANKS.is_ready(profile),
		"motor_voices": playing, "voice_limit": MOTOR_VOICE_LIMIT, "playing_by_state": by_state,
		"loaded_weight": _combustion_load, "coast_weight": 1.0 - _combustion_load,
		"spool_playing": is_instance_valid(_spool) and _spool.playing,
		"release_playing": is_instance_valid(_release) and _release.playing, "foreground": _foreground}
