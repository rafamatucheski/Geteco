extends "res://world/mountain_pass/MountainSUV.gd"
const MONALIZA_MODEL := preload("res://world/harbor/monaliza/MonalizaModel.gd")
const MONALIZA_AUDIO := preload("res://world/harbor/monaliza/MonalizaAudio.gd")
var unlocked := false
var trunk_open := false
var boost_pressure := 0.0
var previous_throttle := false
var spool: AudioStreamPlayer2D
var release: AudioStreamPlayer2D
var ignition: AudioStreamPlayer2D
var flutter: AudioStreamPlayer2D
var _spool_gain := 0.0
var _release_cooldown := 0.0
var _last_audio_gear := 1
var _pending_shift_pressure := 0.0
func _init() -> void:
	active_archetype_id = "monaliza"
	paint_color = Color("183b91")
	restore_factory_handling()
	has_nitro = false
func restore_factory_handling() -> void:
	var spec := VehicleCatalog.get_vehicle_spec("monaliza")
	max_speed = float(spec.max_speed)
	acceleration = float(spec.acceleration)
	braking = float(spec.braking)
	turn_speed = float(spec.turn_speed)
	drift_factor = float(spec.drift_factor)
	# Lift-off should let the coupe roll; the inherited 600 stopped it in ~0.5s.
	friction = 120.0
func _create_body_model() -> Node3D: return MONALIZA_MODEL.new()
func _wheel_axles() -> PackedFloat32Array: return PackedFloat32Array([-1.28,1.22])
func _wheel_track() -> float: return 0.94
func _headlamp_mounts() -> Array[Vector3]: return [Vector3(-0.63,0.7,-2.06),Vector3(0.63,0.7,-2.06)]
func _ready() -> void:
	super._ready()
	add_to_group("personal_vehicle")
	max_health = 180
	health = 180
	engine_audio.bus = &"SFX"
	for layer in _engine_sound._layer_players:
		layer.bus = &"SFX"
	for kind in ["turbo_spool","turbo_release","turbo_shift","ignition"]:
		var sound := AudioStreamPlayer2D.new()
		sound.stream = MONALIZA_AUDIO.stream(kind)
		sound.bus = &"SFX"
		sound.max_distance = 440
		sound.volume_db = -22 if kind == "ignition" else -30
		add_child(sound)
		if kind == "turbo_spool": spool = sound
		elif kind == "turbo_release": release = sound
		elif kind == "turbo_shift": flutter = sound
		else: ignition = sound
func enter_vehicle(actor: CharacterBody2D) -> void:
	if not visible: return
	if not unlocked:
		actor._show_weapon_notice("MONALIZA — Maciota ainda está com as chaves.")
		return
	set_trunk_open(false)
	super.enter_vehicle(actor)
	if is_driven_by_player: ignition.play()
func set_trunk_open(value: bool) -> void:
	trunk_open = value
func _physics_process(delta: float) -> void:
	if not unlocked:
		velocity = Vector2.ZERO
		# Display car cannot be damaged or displaced before being earned.
		health = max_health
	super._physics_process(delta)
	if is_driven_by_player and not has_meta("vehicle_boarding"):
		var manager := get_tree().get_first_node_in_group("personal_car_manager")
		if manager != null: manager.show_introduction()
	_update_turbo_audio(delta)
	var target := -1.1 if trunk_open else 0.0
	if absf(body_model.trunk_pivot.rotation.x-target)>0.001:
		body_model.trunk_pivot.rotation.x = move_toward(body_model.trunk_pivot.rotation.x,target,delta*2)
		request_appearance_update()
func _update_turbo_audio(delta: float) -> void:
	if not is_instance_valid(spool): return
	var running := is_driven_by_player and not is_broken and health > 0
	var throttle: bool = running and _drive_input_armed and get_node("/root/GameInput").vehicle_input().y > 0.1
	var current_gear: int = _engine_sound.gear
	if throttle and current_gear > _last_audio_gear and boost_pressure >= 0.06:
		_pending_shift_pressure = boost_pressure
	_last_audio_gear = current_gear
	if not throttle:
		_pending_shift_pressure = 0.0
	elif _pending_shift_pressure > 0.0 and _engine_sound.shift_remaining <= 0.0:
		_play_shift_flutter(_pending_shift_pressure)
		_pending_shift_pressure = 0.0
	_release_cooldown = maxf(0.0, _release_cooldown - delta)
	# Sample pressure before decay, so release does not depend on frame rate.
	if previous_throttle and not throttle and boost_pressure > 0.35 and running and _release_cooldown <= 0.0:
		release.volume_db = lerpf(-32.0, -25.0, boost_pressure)
		release.play()
		_release_cooldown = 0.5
	boost_pressure = move_toward(boost_pressure,1.0 if throttle and velocity.length()>55 else 0.0,delta*(0.8 if throttle else 3.0))
	var target_gain := db_to_linear(lerpf(-42.0, -29.0, boost_pressure)) if throttle and boost_pressure > 0.1 else 0.0
	_spool_gain = lerpf(_spool_gain, target_gain, 1.0 - exp(-delta * 12.0))
	if _spool_gain > 0.0001:
		spool.volume_db = linear_to_db(_spool_gain)
		spool.pitch_scale = 0.9 + boost_pressure * 0.25
		if not spool.playing: spool.play()
	elif spool.playing: spool.stop()
	if not running:
		release.stop()
		ignition.stop()
		flutter.stop()
	previous_throttle = throttle
func _play_shift_flutter(pressure: float) -> void:
	flutter.volume_db = lerpf(-24.0, -16.0, clampf(pressure, 0.0, 1.0))
	flutter.play()
func _trigger_backfire() -> void:
	# A clean turbo tune uses the soft pressure release, not the generic gunlike pop.
	pass
func take_damage(amount: int, attacker: bool = false) -> void:
	if unlocked: super.take_damage(amount,attacker)
