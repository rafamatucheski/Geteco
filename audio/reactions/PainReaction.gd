extends AudioStreamPlayer2D
## Short occasional hurt vocals, separate from contact sounds and death voices.
const BANK := preload("res://audio/reactions/CharacterReactionBank.gd")
const MAX_ACTIVE := 6
const COOLDOWN_MS := 1800
var next_voice_ms := 0
var next_attempt_ms := 0
var reactions_played := 0

static func react(actor: Node2D, damage: float, chance_roll: float = -1.0) -> bool:
	if damage <= 0 or actor.get("health") == null or actor.get("health") <= 0 or actor.get("is_dead") == true: return false
	if not actor.is_visible_in_tree(): return false
	var voice := actor.get_node_or_null("PainReaction")
	if voice == null:
		voice = new()
		voice.name = "PainReaction"
		actor.add_child(voice)
	return voice._try_voice(damage, chance_roll)

func _ready() -> void:
	bus = &"SFX"
	max_distance = 550
	volume_db = -3 if get_parent().is_in_group("player") else -8
	stream = BANK.sound("hurt")
	add_to_group("pain_reaction_voices")
	finished.connect(func(): set_process(false))
	set_process(false)

func _try_voice(damage: float, chance_roll: float) -> bool:
	var now := Time.get_ticks_msec()
	if playing or now < next_voice_ms or now < next_attempt_ms: return false
	next_attempt_ms = now + 180
	var roll := randf() if chance_roll < 0 else chance_roll
	if roll >= (0.65 if damage >= 25 else 0.42): return false
	var active := 0
	for voice in get_tree().get_nodes_in_group("pain_reaction_voices"):
		if voice.playing: active += 1
	if active >= MAX_ACTIVE: return false
	next_voice_ms = now + COOLDOWN_MS
	pitch_scale = 1.0 if get_parent().is_in_group("player") else (1.04 if get_parent().get("is_female") == true else .97)
	play()
	set_process(true)
	reactions_played += 1
	return true

func _process(_delta: float) -> void:
	var actor := get_parent()
	if actor.get("is_dead") == true or actor.get("health") == 0 or not actor.is_visible_in_tree():
		stop()
		set_process(false)
