extends Node3D
## Tunnel sound bed and scoped SFX reverb. Routing is restored when Dante
## leaves so gunshots, footsteps and impacts only echo underground.

const BUS_NAME := &"SecretTunnelReverb"
const SAMPLE_RATE := 22050
static var _ambient_stream: AudioStreamWAV
static var _drip_stream: AudioStreamWAV
var player: Node3D
var active := false
var bed: AudioStreamPlayer3D
var drip: AudioStreamPlayer3D
var _drip_clock := 1.0
var _previous_sfx_send := &"Master"
var _owns_routing := false
var _rng := RandomNumberGenerator.new()

func configure(target: Node3D) -> void:
	player = target
	_rng.seed = 5101978
	_build_audio()
	set_active(false)

func set_active(value: bool) -> void:
	if active == value: return
	active = value
	set_process(value)
	if value:
		_enable_reverb()
		if not bed.playing: bed.play()
	else:
		if is_instance_valid(bed): bed.stop()
		if is_instance_valid(drip): drip.stop()
		_restore_routing()

func _exit_tree() -> void:
	_restore_routing()

func _process(delta: float) -> void:
	if not active or not is_instance_valid(player): return
	bed.global_position = player.global_position
	_drip_clock -= delta
	if _drip_clock > 0.0: return
	_drip_clock = _rng.randf_range(2.4,6.8)
	drip.global_position = player.global_position+Vector3(_rng.randf_range(-4,4),_rng.randf_range(1,2.5),_rng.randf_range(-6,6))
	drip.pitch_scale = _rng.randf_range(.82,1.18)
	drip.play()

func _build_audio() -> void:
	if _ambient_stream == null: _ambient_stream = _make_ambient()
	if _drip_stream == null: _drip_stream = _make_drip()
	bed = AudioStreamPlayer3D.new()
	bed.name = "TunnelDampAmbience"
	bed.stream = _ambient_stream
	bed.volume_db = -19.0
	bed.unit_size = 12.0
	bed.max_distance = 42.0
	bed.bus = _bus(&"Ambient")
	add_child(bed)
	drip = AudioStreamPlayer3D.new()
	drip.name = "TunnelWaterDrip"
	drip.stream = _drip_stream
	drip.volume_db = -13.0
	drip.unit_size = 5.0
	drip.max_distance = 28.0
	drip.bus = _bus(&"SFX")
	add_child(drip)

func _enable_reverb() -> void:
	var sfx_index := AudioServer.get_bus_index(&"SFX")
	if sfx_index < 0 or _owns_routing: return
	var tunnel_index := AudioServer.get_bus_index(BUS_NAME)
	if tunnel_index < 0:
		AudioServer.add_bus()
		tunnel_index = AudioServer.bus_count-1
		AudioServer.set_bus_name(tunnel_index,BUS_NAME)
		AudioServer.set_bus_send(tunnel_index,&"Master")
		var reverb := AudioEffectReverb.new()
		reverb.room_size = .86
		reverb.damping = .42
		reverb.wet = .34
		reverb.dry = .86
		reverb.predelay_msec = 38.0
		reverb.predelay_feedback = .22
		AudioServer.add_bus_effect(tunnel_index,reverb)
	_previous_sfx_send = AudioServer.get_bus_send(sfx_index)
	AudioServer.set_bus_send(sfx_index,BUS_NAME)
	_owns_routing = true

func _restore_routing() -> void:
	if not _owns_routing: return
	var sfx_index := AudioServer.get_bus_index(&"SFX")
	if sfx_index >= 0: AudioServer.set_bus_send(sfx_index,_previous_sfx_send)
	_owns_routing = false

func _bus(preferred: StringName) -> StringName:
	return preferred if AudioServer.get_bus_index(preferred)>=0 else &"Master"

static func _make_ambient() -> AudioStreamWAV:
	var seconds := 8.0
	var samples := int(SAMPLE_RATE*seconds)
	var bytes := PackedByteArray()
	bytes.resize(samples*2)
	var noise := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7441
	for i in samples:
		var t := float(i)/SAMPLE_RATE
		noise = lerpf(noise,rng.randf_range(-1.0,1.0),.012)
		var rumble := sin(TAU*43.0*t)*.09+sin(TAU*61.0*t)*.045
		var air := noise*.13*(.72+.28*sin(TAU*.125*t))
		_write_sample(bytes,i,clampf(rumble+air,-.9,.9))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = samples-1
	return stream

static func _make_drip() -> AudioStreamWAV:
	var seconds := .42
	var samples := int(SAMPLE_RATE*seconds)
	var bytes := PackedByteArray()
	bytes.resize(samples*2)
	for i in samples:
		var t := float(i)/SAMPLE_RATE
		var envelope := exp(-t*18.0)
		var tone := sin(TAU*(930.0-520.0*t)*t)*envelope*.72
		var delayed := maxf(0.0,t-.085)
		var echo := sin(TAU*610.0*delayed)*exp(-delayed*22.0)*(.22 if t>.085 else 0.0)
		_write_sample(bytes,i,clampf(tone+echo,-1.0,1.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream

static func _write_sample(bytes: PackedByteArray,index: int,value: float) -> void:
	var encoded := int(round(clampf(value,-1.0,1.0)*32767.0))
	if encoded < 0: encoded += 65536
	bytes[index*2] = encoded&255
	bytes[index*2+1] = (encoded>>8)&255
