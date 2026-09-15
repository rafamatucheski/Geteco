extends Node

# Gerenciador global de ambiente sonoro da cidade
var ambience_player: AudioStreamPlayer
var distant_siren_player: AudioStreamPlayer
var radio_chatter_player: AudioStreamPlayer
var park_ambience_player: AudioStreamPlayer

var horn_timer: float = 4.0
var distant_siren_timer: float = 18.0
var radio_chatter_timer: float = 28.0
var ambience_active := false
var _rng := RandomNumberGenerator.new()

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	
	# 1. Som contínuo de ambiente da cidade (trânsito ao longe e vento urbano)
	ambience_player = AudioStreamPlayer.new()
	ambience_player.name = "CityAmbience"
	ambience_player.stream = ProceduralAudio.get_city_ambience_stream()
	ambience_player.volume_db = -24.0
	ambience_player.bus = "Ambient"
	add_child(ambience_player)
	ambience_player.autoplay = false

	# 2. Sirenes distantes da metrópole
	distant_siren_player = AudioStreamPlayer.new()
	distant_siren_player.name = "DistantSirens"
	distant_siren_player.volume_db = -22.0
	distant_siren_player.bus = "Ambient"
	add_child(distant_siren_player)

	# 3. Rádio comunicador policial distante
	radio_chatter_player = AudioStreamPlayer.new()
	radio_chatter_player.name = "PoliceRadioChatter"
	radio_chatter_player.volume_db = -25.0
	radio_chatter_player.bus = "Ambient"
	add_child(radio_chatter_player)

	# 4. Ambiente de parque (pássaros e brisa)
	park_ambience_player = AudioStreamPlayer.new()
	park_ambience_player.name = "ParkAmbience"
	park_ambience_player.stream = ProceduralAudio.get_birds_wind_stream()
	park_ambience_player.volume_db = -28.0
	park_ambience_player.bus = "Ambient"
	add_child(park_ambience_player)

	# Inicia mudo por padrão para evitar áudio de abertura em loading/menu/cutscene.
	_set_ambient_enabled(false)

func _process(delta: float):
	if not ambience_active:
		return

	# Harbor owns regional beds. Do not layer global music-bed/fake sirens over
	# its opening or interiors. Other districts retain the legacy soundscape.
	var scene := get_tree().current_scene
	if scene != null and scene.has_node("HarborSoundscape"):
		ambience_player.volume_db = -80.0
		if ambience_player.playing:
			ambience_player.stop()
		park_ambience_player.stop()
		distant_siren_player.stop()
		radio_chatter_player.stop()
		return
	ambience_player.volume_db = -24.0
	# 1. Buzinas ocasionais de tráfego
	horn_timer -= delta
	if horn_timer <= 0.0:
		_trigger_random_traffic_horn()
		horn_timer = _rng.randf_range(5.0, 14.0)

	# 2. Sirenes policiais distantes
	distant_siren_timer -= delta
	if distant_siren_timer <= 0.0:
		_play_distant_siren()
		distant_siren_timer = _rng.randf_range(25.0, 55.0)

	# 3. Chiados de rádio policial da central
	radio_chatter_timer -= delta
	if radio_chatter_timer <= 0.0:
		_play_radio_chatter()
		radio_chatter_timer = _rng.randf_range(35.0, 75.0)

func set_active(enabled: bool) -> void:
	_set_ambient_enabled(enabled)

func _set_ambient_enabled(enabled: bool) -> void:
	ambience_active = enabled
	if not is_instance_valid(ambience_player):
		return
	if not ambience_active:
		if ambience_player.playing:
			ambience_player.stop()
		if distant_siren_player.playing:
			distant_siren_player.stop()
		if radio_chatter_player.playing:
			radio_chatter_player.stop()
		if park_ambience_player.playing:
			park_ambience_player.stop()
		return

	if not ambience_player.playing and ambience_player.stream != null:
		ambience_player.play()
	if not park_ambience_player.playing and park_ambience_player.stream != null:
		park_ambience_player.play()

func _trigger_random_traffic_horn():
	var traffic_vehicles := get_tree().get_nodes_in_group("ambient_traffic")
	if traffic_vehicles.is_empty():
		return
	
	var candidate = traffic_vehicles[_rng.randi_range(0, traffic_vehicles.size() - 1)]
	if is_instance_valid(candidate) and candidate.has_method("honk_horn"):
		candidate.honk_horn()

func _play_distant_siren():
	if distant_siren_player:
		distant_siren_player.stream = ProceduralAudio.get_distant_siren_stream()
		distant_siren_player.pitch_scale = _rng.randf_range(0.90, 1.10)
		distant_siren_player.play()

func _play_radio_chatter():
	if radio_chatter_player:
		radio_chatter_player.stream = ProceduralAudio.get_police_radio_chatter_stream()
		radio_chatter_player.pitch_scale = _rng.randf_range(0.95, 1.05)
		radio_chatter_player.play()

func play_pedestrian_panic(pos: Vector2) -> void:
	var p = AudioStreamPlayer2D.new()
	p.stream = ProceduralAudio.get_pedestrian_scream_stream()
	p.volume_db = -12.0
	p.pitch_scale = _rng.randf_range(0.85, 1.25)
	p.max_distance = 600.0
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

func play_prop_impact(pos: Vector2, prop_type: String = "trashcan") -> void:
	var p = AudioStreamPlayer2D.new()
	if prop_type == "hydrant":
		p.stream = ProceduralAudio.get_hydrant_burst_stream()
		p.volume_db = -6.0
	else:
		p.stream = ProceduralAudio.get_trashcan_hit_stream()
		p.volume_db = -8.0
	p.pitch_scale = _rng.randf_range(0.92, 1.10)
	p.max_distance = 650.0
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
