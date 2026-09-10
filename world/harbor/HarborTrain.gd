extends "res://world/shared/rail/AmbientTrain.gd"

const PIECE_3D := preload("res://world/shared/rail/TrainPiece3D.gd")
const AUDIO := preload("res://world/shared/rail/TrainAudioBank.gd")
var locomotive: Node2D
var _rail_sounds: Array[AudioStreamPlayer2D] = []
var _bridge_sound: AudioStreamPlayer2D
var _curve_sound: AudioStreamPlayer2D
var _horn: AudioStreamPlayer2D
var _horn_cooldown := 0.0
var _last_surface := false
var _sound_initialized := false
var _audio_bank := AUDIO.new()

func _process(delta: float) -> void:
	if is_instance_valid(_rail_line) and speed > 0.0:
		speed = move_toward(speed, _rail_line.get_cruise_speed_at_offset(_progress), delta * 45.0)
	super._process(delta)

func _rebuild_freight_visuals() -> void:
	for visual in _freight_visuals:
		if is_instance_valid(visual): visual.queue_free()
	_freight_visuals.clear()
	if is_instance_valid(locomotive): locomotive.queue_free()
	locomotive = PIECE_3D.new()
	locomotive.name = "Locomotive3D"
	add_child(locomotive)
	for index in freight_car_count:
		var wagon := PIECE_3D.new()
		wagon.wagon_index = index
		wagon.name = "FreightWagon_%02d" % (index + 1)
		add_child(wagon)
		_freight_visuals.append(wagon)

func _draw() -> void:
	pass

func _update_pose() -> void:
	super._update_pose()
	if not is_instance_valid(_rail_line) or not is_instance_valid(locomotive): return
	var state: Dictionary = _rail_line.get_track_state_at_offset(_progress)
	# Cada peça atravessa o portal separadamente, inclusive seus filhos 3D.
	self_modulate.a = float(state.opacity)
	z_as_relative = false
	z_index = int(state.z_index)
	locomotive.modulate.a = float(state.opacity)
	locomotive.update_heading(global_rotation)
	var reveal: ShaderMaterial = _rail_line.get_underpass_material() if float(state.elevation) >= 48.0 else null
	locomotive.set_reveal(reveal)
	for index in _freight_visuals.size():
		var wagon_state: Dictionary = _rail_line.get_track_state_at_offset(_wagon_offset(index))
		var wagon := _freight_visuals[index]
		var heading := wagon.global_rotation
		wagon.modulate.a = float(wagon_state.opacity)
		wagon.z_as_relative = false
		wagon.z_index = int(wagon_state.z_index)
		wagon.update_heading(heading)
		wagon.set_reveal(_rail_line.get_underpass_material() if float(wagon_state.elevation) >= 48.0 else null)


func _wagon_offset(index: int) -> float:
	return fposmod(_progress - ENGINE_LENGTH * 0.5 - WAGON_LENGTH * 0.5 - COUPLER_GAP - float(index) * WAGON_STEP, maxf(1.0, _route_length))

func _setup_train_audio() -> void:
	if is_instance_valid(_train_audio): return
	_train_audio = _speaker("DieselEngine", "diesel", self, 1100.0, -14.0)
	_bridge_sound = _speaker("ViaductResonance", "bridge", self, 650.0, -21.0)
	_curve_sound = _speaker("WheelFlangeCurve", "curve", self, 500.0, -60.0)
	_horn = _speaker("PortalHorn", "horn", self, 1500.0, -12.0)
	_horn.stop()
	_rail_sounds.append(_speaker("LocomotiveRailJoints", "rail", self, 650.0, -20.0))
	for index in _freight_visuals.size():
		var sound := _speaker("WagonRailJoints", "rail", _freight_visuals[index], 600.0, -24.0)
		# Eixos consecutivos passam pela mesma emenda em instantes diferentes.
		sound.play(fposmod(float(index + 1) * WAGON_STEP / maxf(speed, 1.0), 2.0))
		_rail_sounds.append(sound)

func _speaker(label: String, kind: String, parent: Node, reach: float, volume: float) -> AudioStreamPlayer2D:
	var speaker := AudioStreamPlayer2D.new()
	speaker.name = label
	speaker.stream = _audio_bank.sound(kind)
	speaker.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	speaker.max_distance = reach
	speaker.attenuation = 1.4
	speaker.volume_db = volume
	parent.add_child(speaker)
	speaker.play()
	return speaker

func _update_train_audio(delta: float) -> void:
	if not is_instance_valid(_train_audio): return
	var state: Dictionary = _rail_line.get_track_state_at_offset(_progress)
	var surface := bool(state.above_ground)
	var moving := speed > 0.1 and visible and _rail_line.train_enabled
	var ratio := clampf(speed / 105.0, 0.25, 1.6)
	_train_audio.pitch_scale = lerpf(0.65, 1.0, clampf(ratio, 0.0, 1.0))
	_set_loudness(_train_audio, -14.0 if surface else -39.0, 1.0 if moving else 0.0, delta)
	_set_loudness(_bridge_sound, -22.0, float(state.opacity) if moving and float(state.elevation) >= 48.0 else 0.0, delta)
	var curve := _rail_line.get_route_curve()
	var ahead := curve.sample_baked(fposmod(_progress + 36.0, _route_length), true)
	var here := curve.sample_baked(_progress, true)
	var bend := absf(angle_difference(global_rotation - _rail_line.global_rotation, here.angle_to_point(ahead)))
	_set_loudness(_curve_sound, -24.0, clampf(bend * 8.0, 0.0, 1.0) if moving and surface else 0.0, delta)
	_curve_sound.pitch_scale = 0.85 + ratio * 0.15
	for index in _rail_sounds.size():
		var piece: Dictionary = state if index == 0 else _rail_line.get_track_state_at_offset(_wagon_offset(index - 1))
		var sound := _rail_sounds[index]
		sound.pitch_scale = ratio
		_set_loudness(sound, -20.0 if index == 0 else -24.0, float(piece.opacity) if moving else 0.0, delta)
	_horn_cooldown = maxf(0.0, _horn_cooldown - delta)
	if _sound_initialized and surface and not _last_surface and moving and _horn_cooldown <= 0.0:
		_horn.play()
		_horn_cooldown = 18.0
	if not surface or not moving: _horn.stop()
	_last_surface = surface
	_sound_initialized = true

func _set_loudness(speaker: AudioStreamPlayer2D, db: float, amount: float, delta: float) -> void:
	var target := db + linear_to_db(maxf(amount, 0.001))
	speaker.volume_db = lerpf(speaker.volume_db, maxf(-70.0, target), 1.0 - exp(-delta * 9.0))


func get_rail_state() -> Dictionary:
	var result := super.get_rail_state()
	var pieces: Array[Dictionary] = []
	if is_instance_valid(_rail_line):
		pieces.append(_rail_line.get_track_state_at_offset(_progress))
		for index in _freight_visuals.size():
			pieces.append(_rail_line.get_track_state_at_offset(_wagon_offset(index)))
	result["pieces"] = pieces
	result["locomotive_opacity"] = self_modulate.a
	result["presentation"] = "3d"
	result["rail_sound_sources"] = _rail_sounds.size()
	return result
