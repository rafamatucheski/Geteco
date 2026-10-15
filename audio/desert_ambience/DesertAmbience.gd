extends Node
## Bounded regional mix: one wind bed and one positional detail, no PCM synthesis.
const CATALOG := preload("res://audio/v1_ambience/V1AudioCatalog.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const FIREFLY := preload("res://audio/FireflyBank.gd")
## Gravados no Firefly (2026-10-15): coiote e grilos só de noite, rajada longa de vento a
## qualquer hora. Cada um aponta para (pasta, nome) em audio/; sem o arquivo importado o
## sorteio usa o som que já existia (cachorro à noite, rajada do V1 de dia).
const RECORDED := {"coyote": ["wildlife", "coyote", "dog"], "crickets": ["wildlife", "crickets", "dog"],
	"wind": ["desert_ambience", "wind", "gust"]}
var world
var wind: AudioStreamPlayer
var detail: AudioStreamPlayer3D
var rng := RandomNumberGenerator.new()
var gain := 0.0
var gust_gain := 0.7
var gust_target := 0.7
var gust_clock := 0.0
var detail_clock := 12.0
var tick := 0.0
var bank: Dictionary = {}
var enabled := true
var last_kind := ""

func _ready() -> void:
	rng.randomize()
	wind = AudioStreamPlayer.new()
	wind.name = "DesertWind"
	wind.bus = &"Ambient" if AudioServer.get_bus_index(&"Ambient") >= 0 else &"Master"
	wind.volume_db = -80.0
	add_child(wind)
	detail = AudioStreamPlayer3D.new()
	detail.name = "DesertDetail"
	detail.bus = wind.bus
	detail.unit_size = 12.0
	detail.max_distance = 100.0
	add_child(detail)

func _warm() -> void:
	if not bank.is_empty(): return
	wind.stream = CATALOG.regional("wind", 1)
	for kind in ["gust", "scrap", "birds", "dog", "coyote", "crickets", "wind"]:
		bank[kind] = []
		for variant in 3:
			var recorded: AudioStream = null
			if RECORDED.has(kind):
				var total: int = FIREFLY.count(RECORDED[kind][0], RECORDED[kind][1])
				if total > 0: recorded = FIREFLY.stream(RECORDED[kind][0], RECORDED[kind][1], variant % total)
			if recorded != null: bank[kind].append(recorded)
			elif RECORDED.has(kind): bank[kind].append(CATALOG.regional(RECORDED[kind][2], variant) if RECORDED[kind][2] == "gust" else CATALOG.detail(RECORDED[kind][2], variant))
			else: bank[kind].append(CATALOG.regional(kind, variant) if kind in ["gust", "scrap"] else CATALOG.detail(kind, variant))

func _process(delta: float) -> void:
	# Context and fades run at 10 Hz, without world scans or per-frame resource loads.
	tick += delta
	if tick < 0.1: return
	var elapsed := tick
	tick = 0.0
	if world == null or world.session == null: return
	var session = world.session
	var active: bool = enabled and str(session.state.region_id) == "desert"
	var inside: bool = not str(session.state.place_id).is_empty()
	var focus := 0.35 if session.dialogue_open else (0.6 if session.modal else 1.0)
	if active: _warm()
	gust_clock -= elapsed
	if gust_clock <= 0.0:
		gust_target = rng.randf_range(0.45, 1.0)
		gust_clock = rng.randf_range(7.0, 19.0)
	gust_gain = lerpf(gust_gain, gust_target, 1.0 - exp(-elapsed / 3.0))
	var target: float = (0.12 if inside else 1.0) * focus if active else 0.0
	gain = lerpf(gain, target, 1.0 - exp(-elapsed / 0.8))
	wind.volume_db = -24.0 + linear_to_db(maxf(gain * gust_gain, 0.0001))
	if gain > 0.005 and not wind.playing and wind.stream != null: wind.play(rng.randf_range(0.0, maxf(0.0, wind.stream.get_length() - 1.0)))
	elif gain < 0.001 and wind.playing: wind.stop()
	if not active or inside or focus < 0.8:
		detail.stop()
		detail_clock = maxf(detail_clock, 8.0)
		return
	detail_clock -= elapsed
	if detail_clock <= 0.0 and not detail.playing:
		_play_detail()

func _play_detail() -> void:
	var point: Vector3 = world.player.global_position
	var hour := float(world.session.weather.time_of_day) if world.session.weather != null else 0.5
	var dark := hour < 0.28 or hour > 0.78
	var anchor := LAYOUT.WORKSHOP if point.distance_to(LAYOUT.WORKSHOP) < point.distance_to(LAYOUT.TRUCK_STOP) else LAYOUT.TRUCK_STOP
	var near_structure := Vector2(point.x - anchor.x, point.z - anchor.z).length() < 48.0
	var kinds: Array[String] = ["gust", "wind", "dog" if dark else "birds"]
	if dark: kinds.append_array(["coyote", "crickets"])
	if near_structure: kinds.append("scrap")
	# Avoid consecutive identical cues; timing and direction are independently varied.
	if kinds.has(last_kind): kinds.erase(last_kind)
	var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
	last_kind = kind
	detail.stream = bank[kind][rng.randi_range(0, 2)]
	var angle := rng.randf_range(-PI, PI)
	var distance := rng.randf_range(45.0, 80.0) if kind == "coyote" else rng.randf_range(16.0, 30.0)
	detail.global_position = anchor + Vector3.UP * 2.0 if kind == "scrap" else point + Vector3(cos(angle) * distance, 2.0, sin(angle) * distance)
	detail.volume_db = -25.0 if kind == "scrap" else (-21.0 if kind in ["gust", "wind"] else (-22.0 if kind == "coyote" else (-27.0 if kind == "crickets" else -24.0)))
	detail.pitch_scale = rng.randf_range(0.94, 1.04)
	if detail.stream != null: detail.play()
	detail_clock = rng.randf_range(24.0, 52.0)

func _exit_tree() -> void:
	for channel in [wind, detail]:
		if is_instance_valid(channel):
			channel.stop()
			channel.stream = null
	bank.clear()
