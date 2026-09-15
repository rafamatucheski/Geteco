extends Node2D
## One small positional voice pool per scene; shotgun pellets cannot flood the mixer.
const BANK := preload("res://audio/combat/CombatAudioBank.gd")
const MAX_VOICES := 10
var voices: Array[AudioStreamPlayer2D] = []
var events_played := 0
var _next := 0
var _recent: Array[Dictionary] = []

static func play_hurt(actor: Node2D, damage: float) -> void:
	if damage <= 0.0: return
	play_hit(actor, actor.global_position, &"flesh", damage, actor.get_instance_id())

static func ensure_pool(context: Node) -> Node:
	if not is_instance_valid(context):
		return null
	var world := preload("res://guns/combat/CombatWorld.gd").scene_for(context)
	if world == null:
		world = context if (context is Node2D and not (context is Window)) else context.get_parent()
	if world == null:
		return null
	var pool := world.get_node_or_null("CombatImpactAudio")
	if pool == null:
		var script: Script = preload("res://audio/combat/CombatImpactAudio.gd")
		pool = script.new()
		pool.name = "CombatImpactAudio"
		world.add_child(pool)
	return pool

static func prepare(context: Node = null) -> void:
	BANK.prepare_impact_palette()
	if is_instance_valid(context):
		ensure_pool(context)

static func play_hit(context: Node, pos: Vector2, material: StringName, damage: float = 15.0, subject_id: int = 0) -> void:
	var pool := ensure_pool(context)
	if pool != null:
		pool.play_impact(pos, material, damage, subject_id)

func _ready() -> void:
	BANK.prepare_impact_palette()
	for i in MAX_VOICES:
		var player := AudioStreamPlayer2D.new()
		player.bus = &"SFX"
		player.max_distance = 750.0
		player.volume_db = -8.0
		add_child(player)
		voices.append(player)

func play_impact(pos: Vector2, material: StringName, damage: float = 15.0, subject_id: int = 0) -> void:
	var now := Time.get_ticks_msec()
	for event in _recent:
		if now - int(event.time) < 40 and event.material == material:
			# The actor's damage callback and the projectile describe the same
			# injury. Group by actor so two people standing together both react.
			var same_actor := subject_id != 0 and subject_id == int(event.get("subject_id",0))
			var same_contact := subject_id == 0 and int(event.get("subject_id",0)) == 0 and pos.distance_squared_to(event.pos) < 1024.0
			if same_actor or same_contact: return
	_recent.append({"time": now, "material": material, "pos": pos, "subject_id":subject_id})
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
	# Contact must remain audible under a gunshot; heavy hits add weight with
	# bounded gain. Nearby shotgun pellets still share one contact voice.
	player.volume_db = (-6.0 if material == &"flesh" else -5.0) + clampf((damage - 15.0) / 15.0, -0.8, 2.0)
	player.play()
	events_played += 1

func _exit_tree() -> void:
	for player in voices:
		player.stop()
