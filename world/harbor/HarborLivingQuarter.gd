extends Node2D
## Primeiro quarteirão vivo: fontes fixas nas fachadas, sem vozes por pedestre.
const AUDIO := preload("res://audio/living_city/LivingCityAudio.gd")
const NEIGHBOR := preload("res://world/harbor/HarborCafeNeighbor.gd")
const RADIO_PROP := preload("res://world/harbor/HarborStreetRadio.gd")
var sources: Dictionary = {}
var neighbors: Array[Node2D] = []
var _gains: Dictionary = {}
var _props: Array[Node2D] = []
var _rng := RandomNumberGenerator.new()
var _garage: Node2D
var _next_bird := 7.0
var _bird_variant := 0
var _bird: AudioStreamPlayer2D

func _ready() -> void:
	_rng.randomize()
	var world := get_parent().get_parent()
	_garage = world.get_node("Interiors").garage_interior
	_add_source("cafe", Vector2(621, 1132), AUDIO.bed("cafe"), 290, -3)
	_add_source("market", Vector2(1750, 805), AUDIO.bed("street", 1), 390, -9)
	_add_source("tools", Vector2(790, 1690), AUDIO.bed("workshop", 1), 310, -3)
	_add_source("courtyard", Vector2(855, 875), AUDIO.bed("birds", 1), 320, -7)
	var stations := AUDIO.stations()
	_add_source("garage_radio", Vector2(790, 1690), stations[0], 290, -12, true)
	_add_source("cafe_radio", Vector2(685, 1132), stations[1], 190, -20, true)
	var bench: Vector2 = _garage.to_global(_garage.workshop_point(Vector3(-1.1, 1.04, -3.65)))
	_add_source("indoor_radio", bench, stations[0], 800, -12, true)
	for key in ["garage_radio", "cafe_radio", "indoor_radio"]:
		var prop := RADIO_PROP.new()
		prop.name = key.to_pascal_case() + "Prop"
		prop.position = sources[key].position
		prop.scale = Vector2.ONE * (0.32 if key == "indoor_radio" else 0.65)
		prop.z_index = 10
		add_child(prop)
		_props.append(prop)
	for i in 2:
		var person := NEIGHBOR.new()
		person.name = "DinerNeighbor%d" % i
		person.district_theme = 1
		person.archetype_override = i + 1
		person.social_pause = 22.0 + i * 5.0
		person.sidewalk_half_width = 8.0
		person.detour_amplitude = 6.0
		person.configure_authored_route(PackedVector2Array([Vector2(530 + i * 52, 1150), Vector2(652 + i * 52, 1150)]), "diner_social_%d" % i)
		add_child(person)
		neighbors.append(person)
	neighbors[0].companion = neighbors[1]
	neighbors[1].companion = neighbors[0]
	_bird = AudioStreamPlayer2D.new()
	_bird.name = "CourtyardBird"
	_bird.position = Vector2(855, 850)
	_bird.bus = &"SFX"
	_bird.max_distance = 400
	_bird.volume_db = -6
	add_child(_bird)

func _add_source(key: String, point: Vector2, stream: AudioStream, radius: float, db: float, radio := false) -> void:
	var source := AudioStreamPlayer2D.new()
	source.name = key.to_pascal_case()
	source.position = point
	source.stream = stream
	source.bus = &"Music" if radio else &"SFX"
	source.max_distance = radius
	source.attenuation = 1.35
	source.volume_db = -80
	source.set_meta("base_db", db)
	source.set_meta("resume", _rng.randf_range(0, maxf(stream.get_length() - 1.0, 0.0)))
	add_child(source)
	sources[key] = source
	_gains[key] = 0.0

func update_context(pos: Vector2, room: Node2D, dark: bool, focus: float, district: float, delta: float) -> void:
	var inside := is_instance_valid(room)
	var panic := false
	for person in neighbors:
		if is_instance_valid(person) and (person.is_scared or person.is_dead or person.is_incapacitated):
			panic = true
	var active := {
		"cafe": 0.12 if panic else (0.8 if dark else 1.0),
		"market": 0.08 if dark else 1.0,
		"tools": 0.0 if dark else 1.0,
		"courtyard": 0.0 if dark else 1.0,
		"garage_radio": 0.35 if dark else 1.0,
		"cafe_radio": 1.0,
		"indoor_radio": 1.0,
	}
	for key in sources:
		var source: AudioStreamPlayer2D = sources[key]
		var allowed := room == _garage if key == "indoor_radio" else not inside
		var near := source.global_position.distance_to(pos) < source.max_distance + 40
		var target := float(active[key]) * focus * district if allowed and near else 0.0
		_gains[key] = move_toward(float(_gains[key]), target, delta * 1.5)
		var gain := float(_gains[key])
		source.volume_db = float(source.get_meta("base_db")) + linear_to_db(maxf(gain, 0.0001))
		if gain > 0.001 and not source.playing:
			source.play(float(source.get_meta("resume")))
		elif gain <= 0.001 and source.playing:
			source.set_meta("resume", source.get_playback_position())
			source.stop()
	_props[0].powered = true
	_props[1].powered = true
	_props[2].visible = room == _garage
	_next_bird -= delta
	if inside or dark or focus < 0.9 or district < 0.1:
		_bird.stop()
	elif _next_bird <= 0.0 and pos.distance_to(_bird.global_position) < 370:
		_bird.stream = AUDIO.detail("birds", _bird_variant)
		_bird_variant = (_bird_variant + 1) % 3
		_bird.play()
		_next_bird = _rng.randf_range(18.0, 32.0)
	# Apenas os dois novos moradores; os pedestres do mundo mantêm seu orçamento.
	for person in neighbors:
		if not is_instance_valid(person): continue
		var simulate: bool = not inside and pos.distance_to(person.global_position) < 1100
		person.set_physics_process(simulate or person.is_scared or person.is_flying)
