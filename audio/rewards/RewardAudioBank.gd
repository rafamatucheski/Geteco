extends RefCounted
## Original, pre-rendered reward cues. Completion uses synthesis, not recordings.
const STREAMS := {
	"pickup": preload("res://audio/rewards/pickup_0.wav"),
	"cash": preload("res://audio/rewards/cash_0.wav"),
	"weapon": preload("res://audio/rewards/weapon.wav"),
	"collectible": preload("res://audio/rewards/collectible.wav"),
	"checkpoint": preload("res://audio/rewards/checkpoint.wav"),
	"countdown": preload("res://audio/rewards/countdown.wav"),
	"mission_start": preload("res://audio/rewards/mission_start.wav"),
	"complete": preload("res://audio/rewards/complete.wav"),
	"achievement": preload("res://audio/rewards/achievement.wav"),
}
const VARIANTS := {
	"pickup": [preload("res://audio/rewards/pickup_0.wav"), preload("res://audio/rewards/pickup_1.wav"), preload("res://audio/rewards/pickup_2.wav")],
	"cash": [preload("res://audio/rewards/cash_0.wav"), preload("res://audio/rewards/cash_1.wav"), preload("res://audio/rewards/cash_2.wav")],
}
const VOICES := 4

static func sound(kind: String) -> AudioStreamWAV:
	return STREAMS[kind] as AudioStreamWAV

static func play(context: Node, kind: String, volume_db: float = -3.0) -> void:
	if not is_instance_valid(context) or not context.is_inside_tree(): return
	var tree := context.get_tree()
	# The scene owns the pool: pickups can disappear without cutting their tails,
	# and unloading the world releases everything. No persistent gameplay state.
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	var pool := host.get_node_or_null("RewardAudioVoices")
	if pool == null:
		pool = Node.new()
		pool.name = "RewardAudioVoices"
		host.add_child(pool)
		for i in VOICES:
			var voice := AudioStreamPlayer.new()
			voice.bus = &"SFX"
			pool.add_child(voice)
	# Coalesce same-frame piles of loot; bounded polyphony keeps bursts controlled.
	var now := Time.get_ticks_msec()
	var stamp := "last_" + kind
	if now - int(pool.get_meta(stamp, -1000)) < 65: return
	pool.set_meta(stamp, now)
	var selected := pool.get_child(0) as AudioStreamPlayer
	for child in pool.get_children():
		var voice := child as AudioStreamPlayer
		if not voice.playing:
			selected = voice
			break
		if int(voice.get_meta("started", 0)) < int(selected.get_meta("started", 0)):
			selected = voice
	var stream := sound(kind)
	if VARIANTS.has(kind):
		var take := (int(pool.get_meta("take_" + kind, -1)) + 1) % 3
		pool.set_meta("take_" + kind, take)
		stream = VARIANTS[kind][take]
	selected.stream = stream
	selected.volume_db = volume_db
	selected.pitch_scale = 1.0
	selected.set_meta("started", now)
	selected.play()
