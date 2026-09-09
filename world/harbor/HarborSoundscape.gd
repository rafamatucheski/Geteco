extends Node
## Four crossfaded beds and one positional detail voice, independent of NPC count.
const BANK := preload("res://world/harbor/HarborAudioBank.gd")
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

func _ready() -> void:
	_rng.randomize()
	for kind in weights:
		var audio := AudioStreamPlayer.new()
		audio.name = kind.capitalize() + "Bed"
		audio.stream = ProceduralAudio.get_city_ambience_stream() if kind == "city" else BANK.sound(kind)
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

func _process(delta: float) -> void:
	_clock += delta
	_detail_clock -= delta
	if _clock >= 0.2:
		_clock = 0.0
		_update_zones()
	focus_gain = move_toward(focus_gain, 0.35 if dialogue_focused else 1.0, delta / (0.2 if dialogue_focused else 0.8))
	detail.volume_db = -16.0 + linear_to_db(focus_gain)
	for kind in weights:
		weights[kind] = move_toward(float(weights[kind]), float(targets[kind]), delta * 0.6)
		var audio: AudioStreamPlayer = beds[kind]
		var gain := float(weights[kind]) * focus_gain
		audio.volume_db = linear_to_db(maxf(gain, 0.0001)) - 18.0
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
	var interiors := world.get_node("Interiors")
	var inside := is_instance_valid(room)
	var dark := bool(world.weather.is_dark)
	targets.city = 0.03 if inside else (0.22 if dark else 0.42)
	targets.water = 0.0 if inside else clampf(1.0 - absf(pos.x - 3500.0) / 950.0, 0.0, 1.0) * clampf(1.0 - maxf(absf(pos.y - 1400.0) - 1400.0, 0.0) / 600.0, 0.0, 1.0)
	targets.terminal = 0.0 if inside else clampf(1.0 - pos.distance_to(Vector2(1700, 1130)) / 550.0, 0.0, 1.0)
	if dark:
		targets.terminal *= 0.5
	targets.workshop = 1.0 if inside and room == interiors.get("garage_interior") else 0.0
	var terminal := world.get_node("ArrivalStop")
	if terminal.visits != _visits or terminal.departures != _departures:
		_visits = terminal.visits
		_departures = terminal.departures
		if not inside and is_instance_valid(terminal.bus) and pos.distance_to(terminal.bus.global_position) < 650.0:
			_play_detail("air", terminal.bus.global_position)
	if _detail_clock <= 0.0:
		_detail_clock = _rng.randf_range(10.0, 22.0)
		if targets.water > 0.25 and not dark:
			_play_detail("gull", Vector2(clampf(pos.x, 3250, 3900), pos.y + _rng.randf_range(-180, 180)))
		elif targets.workshop > 0.5:
			_play_detail("metal", pos + Vector2(90, -50))

func _play_detail(kind: String, position: Vector2) -> void:
	if dialogue_focused:
		return
	# Never allocate a player per event; a more recent physical bus event wins.
	detail.stream = BANK.sound(kind)
	detail.global_position = position
	detail.pitch_scale = _rng.randf_range(0.94, 1.04)
	detail.play()
