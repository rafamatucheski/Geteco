extends Node3D
## Flush musical paving: existing floor owns support/collision. No input capture.
signal note_played(index: int, by_player: bool)
signal melody_completed

const NOTES := [261.63, 293.66, 329.63, 349.23, 392.0, 440.0, 493.88, 523.25]
const MELODY := [0, 2, 4, 7, 4, 2, 0]
const COLORS := ["ed796b", "e9a254", "e3c45c", "83b979", "65b9bf", "799dd3", "a290c7", "cf91b0"]
const WIDTH := 1.05
static var tones: Array[AudioStreamWAV] = []
var progress := 0
var celebrations := 0
var world: Node
var keys: Array[StandardMaterial3D] = []
var voices: Array[AudioStreamPlayer3D] = []
var flashes: Array[float] = []
var occupants: Dictionary = {}
var clock := 0.0
var celebration_until := 0.0
var idle := 0.0
var timer: Timer

func _ready() -> void:
	name = "UnionPiano"
	_build()
	world = get_tree().current_scene
	timer = Timer.new()
	timer.wait_time = 0.06
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()

func _build() -> void:
	if tones.is_empty():
		for frequency in NOTES: tones.append(_tone(frequency))
	_tile("KeyboardBorder", Vector3(0, .055, 0), Vector3(8.7, .016, 3.5), Color("303b42"))
	for i in 8:
		var x := (float(i) - 3.5) * WIDTH
		keys.append(_tile("Key%d" % i, Vector3(x, .07, 0), Vector3(.99, .012, 3.2), Color("eee7d5")))
		_tile("Color%d" % i, Vector3(x, .08, 1.35), Vector3(.85, .006, .22), Color(COLORS[i]))
		flashes.append(0.0)
		var voice := AudioStreamPlayer3D.new()
		voice.stream = tones[i]
		voice.position = Vector3(x, .12, 0)
		voice.max_distance = 28.0
		voice.unit_size = 5.0
		voice.volume_db = -10.0
		if AudioServer.get_bus_index("SFX") >= 0: voice.bus = &"SFX"
		add_child(voice)
		voices.append(voice)
	for i in [0, 1, 3, 4, 5]:
		_tile("Accidental%d" % i, Vector3((float(i)-3.0)*WIDTH, .085, -.8), Vector3(.38, .008, 1.5), Color("25323c"))
	_refresh()

func _tile(label: String, point: Vector3, size: Vector3, color: Color) -> StandardMaterial3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = point
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .85
	mesh.material_override = material
	add_child(mesh)
	return material

static func _tone(frequency: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	var rate := 22050
	data.resize(rate * 2)
	for i in rate:
		var t := float(i)/rate
		var envelope := minf(t/.008, 1.0) * exp(-5.5*t) * minf((1.0-t)/.05, 1.0)
		var sample := (sin(TAU*frequency*t) + .28*sin(TAU*frequency*2.0*t) + .08*sin(TAU*frequency*3.0*t)) * envelope * .48
		data.encode_s16(i*2, int(sample*32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream

func key_at(point: Vector3) -> int:
	if absf(point.z) > 1.6 or point.y < -.3 or point.y > .6: return -1
	var index := floori((point.x + 4.0*WIDTH)/WIDTH)
	return index if index >= 0 and index < 8 else -1

func _tick() -> void:
	clock += timer.wait_time
	if not is_instance_valid(world) or world.get("player") == null: return
	var player = world.player
	var session = world.get("session")
	if player.global_position.distance_squared_to(global_position) > 1600.0 or (session != null and (session.room != null or session.modal or session.is_transition_blocked())):
		_reset()
		timer.wait_time = .5
		return
	timer.wait_time = .06
	var next: Dictionary = {}
	if player.visible and player.health > 0 and not world.driving.occupied:
		_visit(player, true, next)
	for person in world.people:
		if is_instance_valid(person) and person.visible and not person.dead:
			_visit(person, false, next)
	occupants = next
	idle += timer.wait_time
	if idle > 15.0: progress = 0
	_refresh()

func _visit(actor: Node3D, by_player: bool, next: Dictionary) -> void:
	var index := key_at(to_local(actor.global_position))
	if index < 0: return
	var id := actor.get_instance_id()
	next[id] = index
	if occupants.get(id, -1) != index: play_note(index, by_player)

func play_note(index: int, by_player: bool) -> void:
	if index < 0 or index >= 8: return
	# Limita a polifonia a oito vozes mesmo se vários moradores dividirem uma tecla.
	if clock >= flashes[index]: voices[index].play()
	flashes[index] = clock + .32
	note_played.emit(index, by_player)
	if by_player and clock >= celebration_until:
		idle = 0.0
		if index == MELODY[progress]: progress += 1
		else: progress = 1 if index == MELODY[0] else 0
		if progress == MELODY.size():
			progress = 0
			celebrations += 1
			celebration_until = clock + 2.4
			melody_completed.emit()
	_refresh()

func _refresh() -> void:
	for i in keys.size():
		var active := clock < flashes[i] or clock < celebration_until
		keys[i].albedo_color = Color(COLORS[i]) if active else Color("eee7d5")
		if not active and i == MELODY[progress]: keys[i].albedo_color = Color(COLORS[i]).lightened(.25)

func _reset() -> void:
	occupants.clear()
	progress = 0
	idle = 0.0
	celebration_until = 0.0
	for i in voices.size():
		voices[i].stop()
		flashes[i] = 0.0
	_refresh()
