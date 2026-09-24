extends Node3D
## Presentation-only counterpart of V1 HarborAutoService.
## Services.gd remains the sole owner of eligibility, money, repair and wanted state.

const EFFECT_RESOURCES := preload("res://gameplay/vehicle_effects/VehicleEffectResources.gd")
const SHUTTER_CLOSED_Y := 1.72
const SHUTTER_OPEN_Y := 5.18

var shutter: Node3D
var spray: GPUParticles3D
var service_audio: AudioStreamPlayer3D
var _door_motion: Tween
var _door_open := false

func _ready() -> void:
	name = "NorthgateServicePresentation"
	add_to_group("northgate_service_presentation")
	_build_shutter()
	_build_spray()
	_build_audio()
	set_shutter_open(false, true)

func _build_shutter() -> void:
	shutter = Node3D.new()
	shutter.name = "ServiceShutter"
	shutter.position = Vector3(0, SHUTTER_CLOSED_Y, -3.60)
	add_child(shutter)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("425a60")
	metal.metallic = .42
	metal.roughness = .58
	var leaf := MeshInstance3D.new()
	var leaf_mesh := BoxMesh.new()
	leaf_mesh.size = Vector3(6.875, 3.4, .08)
	leaf.mesh = leaf_mesh
	leaf.material_override = metal
	shutter.add_child(leaf)
	var slat_material := StandardMaterial3D.new()
	slat_material.albedo_color = Color("81b1a4")
	slat_material.metallic = .25
	slat_material.roughness = .48
	for index in 8:
		var slat := MeshInstance3D.new()
		var slat_mesh := BoxMesh.new()
		slat_mesh.size = Vector3(6.72, .035, .035)
		slat.mesh = slat_mesh
		slat.position = Vector3(0, -1.48 + float(index) * .42, .055)
		slat.material_override = slat_material
		slat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shutter.add_child(slat)

func _build_spray() -> void:
	spray = EFFECT_RESOURCES.emitter("ServiceSpray", 20, .60, Vector2(.10, .22))
	spray.position = Vector3(0, .75, -8.15)
	var process := EFFECT_RESOURCES.particle_process()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(1.35, .28, 1.65)
	process.direction = Vector3.UP
	process.spread = 75
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = .75
	process.initial_velocity_max = 1.75
	process.color = Color(.70, .92, .85, .35)
	spray.process_material = process
	add_child(spray)

func _build_audio() -> void:
	service_audio = AudioStreamPlayer3D.new()
	service_audio.name = "ServiceSprayAudio"
	service_audio.bus = &"SFX"
	service_audio.stream = _service_stream()
	service_audio.pitch_scale = 1.8
	service_audio.volume_db = -24
	service_audio.max_distance = 350.0 / 16.0
	service_audio.position = Vector3(0, 1.0, -8.15)
	add_child(service_audio)

func set_shutter_open(opened: bool, instant := false) -> void:
	if _door_open == opened and not instant: return
	_door_open = opened
	if is_instance_valid(_door_motion): _door_motion.kill()
	var target := SHUTTER_OPEN_Y if opened else SHUTTER_CLOSED_Y
	if instant:
		shutter.position.y = target
		return
	_door_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_door_motion.tween_property(shutter, "position:y", target, .35)

func begin_service() -> void:
	set_shutter_open(false)

func begin_repair() -> void:
	spray.emitting = true
	service_audio.play()

func end_repair() -> void:
	spray.emitting = false
	service_audio.stop()

func finish_service() -> void:
	end_repair()
	set_shutter_open(true)

func cancel_service() -> void:
	end_repair()
	set_shutter_open(true)

func _service_stream() -> AudioStreamWAV:
	# Same bounded looping friction bed used by V1's ProceduralAudio fallback.
	var sample_rate := 22050
	var samples := int(sample_rate * .8)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 49251198
	for index in samples:
		var t := float(index) / float(sample_rate)
		var fm := sin(2.0 * PI * 29.0 * t) * 205.0
		var squeal := sin(2.0 * PI * (1385.0 + fm) * t) * .30
		var harmonic := sin(2.0 * PI * (2604.0 + fm * 1.5) * t) * .15
		var sample := (squeal + harmonic + rng.randf_range(-.24, .24)) * .35
		data.encode_s16(index * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.data = data
	return stream
