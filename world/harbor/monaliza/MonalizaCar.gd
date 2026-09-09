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
func _init() -> void:
	active_archetype_id = "monaliza"
	paint_color = Color("183b91")
	max_speed = 560
	acceleration = 460
	turn_speed = 3.1
	has_nitro = false
func _create_body_model() -> Node3D: return MONALIZA_MODEL.new()
func _wheel_axles() -> PackedFloat32Array: return PackedFloat32Array([-1.28,1.22])
func _wheel_track() -> float: return 0.94
func _headlamp_mounts() -> Array[Vector3]: return [Vector3(-0.63,0.7,-2.06),Vector3(0.63,0.7,-2.06)]
func _ready() -> void:
	super._ready()
	add_to_group("personal_vehicle")
	max_health = 180
	health = 180
	engine_audio.stream = MONALIZA_AUDIO.stream("engine")
	for kind in ["turbo_spool","turbo_release","ignition"]:
		var sound := AudioStreamPlayer2D.new()
		sound.stream = MONALIZA_AUDIO.stream(kind)
		sound.bus = &"SFX"
		sound.max_distance = 440
		sound.volume_db = -17
		add_child(sound)
		if kind == "turbo_spool": spool = sound
		elif kind == "turbo_release": release = sound
		else: ignition = sound
func enter_vehicle(actor: CharacterBody2D) -> void:
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
	# The shared RPM controller chooses a family stream when driving starts.
	# Keep its pitch/gear modulation, but retain this car's exclusive recording.
	var exclusive := MONALIZA_AUDIO.stream("engine")
	if engine_audio.stream != exclusive:
		engine_audio.stream = exclusive
		if is_driven_by_player and not is_broken: engine_audio.play()
	if not is_instance_valid(spool): return
	var throttle := is_driven_by_player and not is_broken and Input.get_axis("ui_down","ui_up") > 0.1
	boost_pressure = move_toward(boost_pressure,1.0 if throttle and velocity.length()>55 else 0.0,delta*(0.8 if throttle else 3.0))
	if throttle and boost_pressure > 0.1:
		if not spool.playing: spool.play()
		spool.pitch_scale = 0.8+boost_pressure*0.7
		spool.volume_db = lerpf(-30,-17,boost_pressure)
	elif spool.playing: spool.stop()
	if previous_throttle and not throttle and boost_pressure > 0.25 and is_driven_by_player: release.play()
	previous_throttle = throttle
	var target := -1.1 if trunk_open else 0.0
	if absf(body_model.trunk_pivot.rotation.x-target)>0.001:
		body_model.trunk_pivot.rotation.x = move_toward(body_model.trunk_pivot.rotation.x,target,delta*2)
		request_appearance_update()
func take_damage(amount: int, attacker: bool = false) -> void:
	if unlocked: super.take_damage(amount,attacker)
