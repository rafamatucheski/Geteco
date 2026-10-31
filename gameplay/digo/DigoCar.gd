extends "res://scripts/Vehicle.gd"
## Usa os caminhos comuns de física, embarque, dano e áudio de turbo de veículo.
const SPEC := preload("res://gameplay/digo/DigoCarSpec.gd")
const MUSIC := preload("res://audio/living_city/porto_club.ogg")
var stereo: AudioStreamPlayer3D
var stereo_enabled := true:
	set(value):
		stereo_enabled = value
		if is_instance_valid(stereo): _update_stereo()

func _init() -> void:
	archetype = SPEC.ID
	vehicle_id = "digo_gol_1993"
	paint_color = Color("bcc2c4")
	set_meta("owner_id", "digo")
	set_meta("personal_vehicle", true)

func _ready() -> void:
	super._ready()
	stereo = install_stereo(self)
	_update_stereo()

## Também se anexa a um Vehicle comum restaurado de FleetState.
static func install_stereo(car: CharacterBody3D) -> AudioStreamPlayer3D:
	car.add_to_group("digo_car")
	car.set_meta("owner_id", "digo")
	car.set_meta("personal_vehicle", true)
	if car.has_node("DigoStereo"): return car.get_node("DigoStereo") as AudioStreamPlayer3D
	var player := AudioStreamPlayer3D.new()
	player.name = "DigoStereo"
	var music := MUSIC.duplicate() as AudioStreamOggVorbis
	music.loop = true
	player.stream = music
	player.position = Vector3(0, .8, 1.05)
	player.unit_size = 7.0
	player.max_distance = 42.0
	player.volume_db = -7.0
	player.max_db = -3.0
	if AudioServer.get_bus_index("Ambience") >= 0: player.bus = "Ambience"
	car.add_child(player)
	var timer := Timer.new()
	timer.name = "StereoRangeCheck"
	timer.wait_time = .5
	timer.timeout.connect(func(): _tick_stereo(car,player))
	player.add_child(timer)
	timer.start()
	car.destroyed.connect(func(): player.stop())
	_tick_stereo(car,player)
	return player

func _update_stereo() -> void:
	stereo.set_meta("enabled",stereo_enabled)
	_tick_stereo(self,stereo)

static func _tick_stereo(car: CharacterBody3D,player: AudioStreamPlayer3D) -> void:
	var camera := car.get_viewport().get_camera_3d()
	var audible: bool = player.get_meta("enabled",true) and car.health > 0 and car.is_visible_in_tree() and camera != null
	if audible: audible = camera.global_position.distance_squared_to(car.global_position) < 42.0 * 42.0
	if audible and not player.playing: player.play()
	elif not audible and player.playing: player.stop()
