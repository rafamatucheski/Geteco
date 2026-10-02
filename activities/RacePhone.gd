extends StaticBody3D
## Shared street-race contact. No lights, viewport, or per-frame animation.
const RANGE := 3.2
static var ring_stream: AudioStreamWAV
var session
var available: Callable
var audio: AudioStreamPlayer3D
var clock := 0.0
var cooldown := 0.0

func configure(owner_session, point: Vector3, eligibility: Callable) -> void:
	session = owner_session
	available = eligibility
	position = point
	name = "RacePhone"
	collision_layer = 1
	collision_mask = 0
	var orange := _material("ec621b",.45)
	var metal := _material("626b70",.7)
	var dark := _material("171e23",.1)
	_box(Vector3(.36,.12,.36),Vector3(0,.06,0),metal)
	_box(Vector3(.13,1.35,.13),Vector3(0,.73,0),metal)
	_box(Vector3(.55,.83,.29),Vector3(0,1.55,0),orange)
	_box(Vector3(.43,.62,.035),Vector3(0,1.54,.16),metal)
	_box(Vector3(.24,.13,.025),Vector3(.06,1.73,.19),dark)
	# Handset, earpieces and hanging cord, facing the street.
	_box(Vector3(.07,.35,.08),Vector3(-.14,1.56,.23),dark)
	for y in [1.37,1.75]: _box(Vector3(.12,.10,.12),Vector3(-.14,y,.23),dark)
	_box(Vector3(.026,.31,.026),Vector3(-.14,1.17,.19),dark)
	_box(Vector3(.14,.026,.026),Vector3(-.08,1.02,.19),dark)
	_box(Vector3(.026,.21,.026),Vector3(-.01,1.12,.19),dark)
	for row in 4:
		for col in 3:
			_box(Vector3(.044,.039,.025),Vector3(.015+col*.06,1.57-row*.055,.195),dark)
	_box(Vector3(.19,.035,.03),Vector3(.075,1.27,.19),dark)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.56,1.98,.38)
	collision.shape = shape
	collision.position.y = .99
	add_child(collision)
	audio = AudioStreamPlayer3D.new()
	audio.stream = _ring()
	audio.position.y = 1.6
	audio.max_distance = 9.0
	audio.unit_size = 2.0
	audio.volume_db = -13
	if AudioServer.get_bus_index("SFX") >= 0: audio.bus = "SFX"
	add_child(audio)

func _process(delta: float) -> void:
	clock += delta
	if clock < .15: return
	cooldown = maxf(0,cooldown-clock)
	clock = 0
	var active := false
	if session != null and session.ready_for_play and not session.modal and not get_tree().paused and session.world.gameplay.health > 0:
		var point: Vector3 = session.world.driving.car.position if session.world.driving.occupied else session.world.player.position
		active = global_position.distance_to(point) <= RANGE and available.call()
	if not active:
		audio.stop()
		return
	if cooldown <= 0:
		audio.play()
		cooldown = 5.0

func silence() -> void:
	audio.stop()
	cooldown = 5.0

func _material(color: String, metallic: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(color)
	result.metallic = metallic
	result.roughness = .55
	return result

func _box(size: Vector3, point: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = point
	add_child(mesh)

static func _ring() -> AudioStreamWAV:
	if ring_stream != null: return ring_stream
	var bytes := PackedByteArray()
	var rate := 22050
	bytes.resize(int(rate*1.4)*2)
	for i in bytes.size()/2:
		var t := float(i)/rate
		var pulse := fmod(t,.72)
		var envelope := clampf(minf(pulse/.015,(.48-pulse)/.035),0,1)
		var sample := (sin(TAU*740*t)+.45*sin(TAU*990*t))*.30*envelope*(.7+.3*sin(TAU*24*t))
		bytes.encode_s16(i*2,int(sample*32767))
	ring_stream = AudioStreamWAV.new()
	ring_stream.format = AudioStreamWAV.FORMAT_16_BITS
	ring_stream.mix_rate = rate
	ring_stream.data = bytes
	return ring_stream
