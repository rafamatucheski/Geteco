extends Node
## Camadas gravadas com transição suave e fontes ligadas ao primeiro quarteirão.
const BANK := preload("res://world/harbor/HarborAudioBank.gd")
const RECORDED := preload("res://audio/living_city/LivingCityAudio.gd")
var beds: Dictionary = {}
var weights := {"city": 0.0, "water": 0.0, "terminal": 0.0, "workshop": 0.0}
var targets := {"city": 0.0, "water": 0.0, "terminal": 0.0, "workshop": 0.0}
var detail: AudioStreamPlayer2D
var _clock := 0.0
var dialogue_focused := false
var focus_gain := 1.0
var _detail_clock := 9.0
var _rng := RandomNumberGenerator.new()
var _visits := 0
var _departures := 0
var quarter: Node2D
var _listener_position := Vector2.ZERO
var _room: Node2D
var _dark := false
var _district_gain := 1.0
var _detail_variant := 0
var _detail_room: Node2D
var water_details: Node
var regional: Node

func _ready() -> void:
	_rng.randomize()
	for kind in weights:
		var audio := AudioStreamPlayer.new()
		audio.name = kind.capitalize() + "Bed"
		var recordings := {"city": "street", "water": "water", "terminal": "street", "workshop": "workshop"}
		audio.stream = RECORDED.bed(recordings[kind], 1 if kind == "terminal" else 0)
		audio.bus = "SFX"
		audio.volume_db = -80.0
		add_child(audio)
		beds[kind] = audio
	for kind in ["air", "gull", "metal"]:
		BANK.sound(kind)
	detail = AudioStreamPlayer2D.new()
	detail.name = "NearbyDetail"
	detail.bus = "SFX"
	detail.max_distance = 700.0
	detail.volume_db = -16.0
	add_child(detail)
	quarter = preload("res://world/harbor/HarborLivingQuarter.gd").new()
	quarter.name = "LivingQuarter"
	add_child(quarter)
	water_details = preload("res://audio/WaterSoundscape.gd").new()
	water_details.name = "WaterDetails"
	add_child(water_details)
	regional = preload("res://audio/regional/RegionalSoundscape.gd").new()
	regional.name = "RegionalSoundscape"
	add_child(regional)

func _process(delta: float) -> void:
	_clock += delta
	_detail_clock -= delta
	if _clock >= 0.2:
		_clock = 0.0
		_update_zones()
	focus_gain = move_toward(focus_gain, 0.35 if dialogue_focused else 1.0, delta / (0.2 if dialogue_focused else 0.8))
	detail.volume_db = -7.0 + linear_to_db(focus_gain)
	quarter.update_context(_listener_position, _room, _dark, focus_gain, _district_gain, delta)
	var actor := get_parent().get_node("Player")
	var indoors := is_instance_valid(_room) or bool(actor.get_meta("mountain_interior", false)) or bool(actor.get_meta("harbor_interior", false))
	regional.update_context(_listener_position, indoors, _dark, focus_gain, delta)
	water_details.update_context(_listener_position, indoors, focus_gain, delta)
	for kind in weights:
		weights[kind] = move_toward(float(weights[kind]), float(targets[kind]), delta * 0.6)
		var audio: AudioStreamPlayer = beds[kind]
		var gain := float(weights[kind]) * focus_gain
		audio.volume_db = linear_to_db(maxf(gain, 0.0001)) - (10.0 if kind == "city" else 4.0)
		if gain > 0.001 and not audio.playing:
			audio.play()
		elif gain <= 0.001 and audio.playing:
			audio.stop()

func _update_zones() -> void:
	var world := get_parent()
	var actor: Node2D = world.get_node("Player")
	var room: Node2D = world.get("_last_room")
	dialogue_focused = bool(actor.get("is_in_dialogue"))
	if is_instance_valid(world.weather.weather_audio):
		world.weather.weather_audio.set_dialogue_focus(dialogue_focused)
	var pos := actor.global_position
	if not actor.visible:
		for car in get_tree().get_nodes_in_group("vehicle"):
			if car.get("is_driven_by_player") == true:
				pos = car.global_position
				break
	var interiors := world.get_node("Interiors")
	var inside := is_instance_valid(room)
	var dark := bool(world.weather.is_dark)
	_listener_position = pos
	_room = room
	_dark = dark
	# O porto deixa de tocar ao seguir para a montanha, inclusive no mundo contínuo.
	_district_gain = clampf((pos.y + 1800.0) / 1300.0, 0.0, 1.0) if not inside else 1.0
	targets.city = 0.03 if inside else (0.22 if dark else 0.42)
	targets.water = 0.0 if inside or actor.get_meta("mountain_interior", false) or actor.get_meta("harbor_interior", false) else preload("res://audio/WaterSoundscape.gd").coast_weight(pos)
	targets.terminal = 0.0 if inside else clampf(1.0 - pos.distance_to(Vector2(1700, 1130)) / 550.0, 0.0, 1.0)
	if dark:
		targets.terminal *= 0.5
	targets.workshop = 1.0 if inside and room == interiors.get("garage_interior") else 0.0
	for kind in targets:
		if kind != "water": targets[kind] *= _district_gain
	if _detail_room != room or _district_gain < 0.1:
		detail.stop()
	var terminal := world.get_node("ArrivalStop")
	if terminal.visits != _visits or terminal.departures != _departures:
		_visits = terminal.visits
		_departures = terminal.departures
		if not inside and _district_gain > 0.1 and is_instance_valid(terminal.bus) and pos.distance_to(terminal.bus.global_position) < 650.0:
			_play_detail("air", terminal.bus.global_position)
	if _detail_clock <= 0.0:
		_detail_clock = _rng.randf_range(13.0, 27.0)
		# O navio tem gaivotas próprias, para não sobrepor os dois agendamentos.
		var crew := world.get_node_or_null("Waterfront/DockCrew")
		if targets.water > 0.25 and not dark and not (crew != null and crew.active):
			_play_detail("gull", Vector2(clampf(pos.x, 3250, 3900), pos.y + _rng.randf_range(-180, 180)))
		elif targets.workshop > 0.5:
			_play_detail("metal", quarter.sources.indoor_radio.global_position)

func _play_detail(kind: String, position: Vector2) -> void:
	if dialogue_focused:
		return
	_detail_room = _room
	# Never allocate a player per event; a more recent physical bus event wins.
	if kind == "air":
		detail.stream = BANK.sound(kind)
	else:
		detail.stream = RECORDED.detail("workshop" if kind == "metal" else kind, _detail_variant)
		_detail_variant = (_detail_variant + 1) % 3
	detail.global_position = position
	detail.pitch_scale = _rng.randf_range(0.94, 1.04)
	detail.play()
