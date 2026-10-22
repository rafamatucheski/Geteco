extends Node
## Low-rate exhaust layer over the existing diesel engine; no generation at runtime.
const RUMBLE := preload("res://audio/digo/amarok_exhaust.wav")
const RELEASE := preload("res://audio/digo/amarok_turbo_release.wav")
static var _rumble: AudioStreamWAV
static var _release: AudioStreamWAV
var car: CharacterBody3D
var rumble: AudioStreamPlayer3D
var release: AudioStreamPlayer3D
var pressure := 0.0
var _last_throttle := 0.0
var _clock := 0.0
var _cooldown := 0.0
var _gear := 0
func _ready() -> void:
	car = get_parent() as CharacterBody3D
	if _rumble == null:
		_rumble = RUMBLE.duplicate() as AudioStreamWAV
		_rumble.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_rumble.loop_end = floori(float(_rumble.data.size())/2.0)
		_release = RELEASE
	rumble = _player("DieselExhaust",_rumble,-19.0)
	release = _player("TurboRelease",_release,-10.0)
	car.destroyed.connect(stop)
func _player(label: String,stream: AudioStream,db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = label
	player.stream = stream
	player.position = Vector3(.78,.42,2.48)
	player.unit_size = 5.0
	player.max_distance = 52.0
	player.volume_db = db
	player.max_db = -4.0
	if AudioServer.get_bus_index("Vehicles") >= 0: player.bus = "Vehicles"
	car.add_child(player)
	return player
func _physics_process(delta: float) -> void:
	_clock += delta
	if _clock < .05: return
	var step := _clock
	_clock = 0.0
	tick(step)
func tick(delta: float) -> void:
	var camera := car.get_viewport().get_camera_3d()
	var running: bool = car.health>0 and not car.engine_disabled and (car.controlled or car.traffic or car.external_input or absf(car.speed)>.3)
	var nearby := camera != null and car.is_visible_in_tree()
	if nearby: nearby = camera.global_position.distance_squared_to(car.global_position)<52.0*52.0
	if not running or not nearby:
		stop()
		return
	var throttle: float = maxf(car.throttle_input,0.0)
	var speed: float = absf(car.speed)
	var gear := mini(6,int(speed/5.5))
	_cooldown = maxf(0.0,_cooldown-delta)
	pressure = move_toward(pressure,throttle*smoothstep(1.0,13.0,speed),delta*1.8)
	rumble.pitch_scale = .82+fmod(speed,5.5)*.12+throttle*.18
	rumble.volume_db = -22.0+throttle*7.0+minf(speed/35.0,1.0)*3.0
	if not rumble.playing: rumble.play()
	if _cooldown<=0.0 and pressure>.38 and ((_last_throttle>.55 and throttle<.18) or gear>_gear):
		release.pitch_scale = .90+pressure*.16
		release.play()
		_cooldown = .75
		pressure *= .25
	_last_throttle = throttle
	_gear = gear
func stop() -> void:
	if is_instance_valid(rumble): rumble.stop()
	if is_instance_valid(release): release.stop()
	pressure = 0.0
	_last_throttle = 0.0
	_gear = 0
