extends Node2D
## One small positional voice pool per scene; shotgun pellets cannot flood the mixer.
const BANK := preload("res://audio/combat/CombatAudioBank.gd")
const MAX_VOICES := 10
var voices: Array[AudioStreamPlayer2D] = []
var events_played := 0
var _next := 0
var _recent: Array[Dictionary] = []

static func play_hit(context: Node, pos: Vector2, material: StringName) -> void:
	var world := context.get_tree().current_scene
	if world == null:
		world = context.get_parent()
	var pool := world.get_node_or_null("CombatImpactAudio")
	if pool == null:
		pool = load("res://audio/combat/CombatImpactAudio.gd").new()
		pool.name = "CombatImpactAudio"
		world.add_child(pool)
	pool.play_impact(pos, material)

func _ready() -> void:
	for material in ["metal", "concrete", "flesh", "wood", "glass"]:
		BANK.sound(material)
	for i in MAX_VOICES:
		var player := AudioStreamPlayer2D.new()
		player.bus = &"SFX"
		player.max_distance = 750.0
		player.volume_db = -8.0
		add_child(player)
		voices.append(player)

func play_impact(pos: Vector2, material: StringName) -> void:
	var now := Time.get_ticks_msec()
	for event in _recent:
		if now - int(event.time) < 40 and event.material == material and pos.distance_squared_to(event.pos) < 1024.0:
			return
	_recent.append({"time": now, "material": material, "pos": pos})
	if _recent.size() > 32:
		_recent.pop_front()
	var player := voices[_next]
	for available in voices:
		if not available.playing:
			player = available
			break
	_next = (_next + 1) % MAX_VOICES
	player.stream = BANK.sound(String(material))
	player.global_position = pos
	player.volume_db = -10.0 if material == &"flesh" else -8.0
	player.play()
	events_played += 1

func _exit_tree() -> void:
	for player in voices:
		player.stop()
