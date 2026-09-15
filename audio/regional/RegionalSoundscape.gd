extends Node
## Mar na rodovia e trabalho ambiente no pátio, usando o contexto do ouvinte real.
const BANK := preload("res://audio/regional/RegionalAudio.gd")
const CITY := preload("res://audio/living_city/LivingCityAudio.gd")
var sea: AudioStreamPlayer
var metal: AudioStreamPlayer2D
var sea_gain := 0.0
var sea_target := 0.0
var yard_active := false
var _yard: Node2D
var _timer := 1.5
var _variant := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	sea = AudioStreamPlayer.new()
	sea.name = "CoastalHighwaySea"
	sea.bus = &"Ambient"
	sea.stream = CITY.bed("water", 1)
	sea.volume_db = -80
	add_child(sea)
	metal = AudioStreamPlayer2D.new()
	metal.name = "SalvageMetal"
	metal.bus = &"Ambient"
	metal.max_distance = 1000
	metal.attenuation = 1.2
	add_child(metal)

static func coast_weight(point: Vector2) -> float:
	# O tabuleiro entre 6480 e 7300 cruza água; o acesso oeste fica em terra.
	var on_span := clampf((point.x - 6250.0) / 300.0, 0, 1) * (1.0 - smoothstep(7300, 7750, point.x))
	return on_span * (1.0 - smoothstep(130, 650, absf(point.y + 4560.0)))

func update_context(point: Vector2, inside: bool, dark: bool, focus: float, delta: float) -> void:
	sea_target = 0.0 if inside else coast_weight(point)
	sea_gain = move_toward(sea_gain, sea_target, delta * 0.65)
	sea.volume_db = -5.0 + linear_to_db(maxf(sea_gain * focus, 0.0001))
	if sea_gain > 0.001 and not sea.playing: sea.play(_rng.randf_range(0, 20))
	elif sea_gain <= 0.001 and sea.playing: sea.stop()
	if not is_instance_valid(_yard):
		_yard = get_tree().get_first_node_in_group("chop_shop") as Node2D
	var was_active := yard_active
	yard_active = not inside and is_instance_valid(_yard) and point.distance_to(_yard.global_position) < 900
	metal.volume_db = -8.0 + linear_to_db(maxf(focus, 0.0001))
	if not yard_active:
		metal.stop()
		_timer = 1.5
		return
	# A prensa já tem efeitos sincronizados. O pátio deixa espaço à entrega.
	var art: Node2D = _yard.get("art")
	if is_instance_valid(art) and art.get("animating") == true:
		metal.stop()
		_timer = 3.0
		return
	if not was_active: _timer = 1.5
	_timer -= delta
	if _timer > 0 or metal.playing or focus < 0.5: return
	metal.stream = BANK.sound("scrap", _variant)
	# Bancada e pilhas físicas do pátio, sem posicionar batidas sobre o jogador.
	var spots := [Vector3(-9, 0, -5), Vector3(-10, 0, 4), Vector3(8, 0, -5)]
	metal.global_position = _yard.global_position
	if is_instance_valid(art) and art.has_method("projected"):
		metal.global_position = art.to_global(art.projected(spots[_variant % spots.size()]))
	metal.pitch_scale = _rng.randf_range(0.82, 0.98)
	metal.play()
	_variant = (_variant + _rng.randi_range(1, 5)) % 6
	_timer = _rng.randf_range(11, 20) if dark else _rng.randf_range(3.8, 7.5)
