extends RefCounted
## Sons de recompensa da V1 (`audio/rewards/RewardAudioBank.gd`) para qualquer coleta
## do V2: achado, dinheiro, arma, item e conquista. As amostras vêm de
## `assets/gameplay/audio/reward_*.wav`, carregadas por `CombatAudio.wav`.
const AUDIO := preload("res://gameplay/CombatAudio.gd")
## Quantos takes cada família tem (pickup e cash alternam sem mudar o tom, como na V1).
const TAKES := {"pickup": 3, "cash": 3}
const FILES := {
	"weapon": "reward_weapon.wav",
	"collectible": "reward_collectible.wav",
	"achievement": "reward_achievement.wav",
}
const VOICES := 4
## Rajadas de loot no mesmo quadro contam uma vez só (mesma janela da V1).
const COALESCE_MSEC := 65

## Categoria de som para um `kind` de recompensa de mundo ("cash", "weapon", "item").
static func kind_for_reward(reward_kind: String) -> String:
	match reward_kind:
		"cash": return "cash"
		"weapon": return "weapon"
	return "pickup"

static func stream(kind: String, take: int = 0) -> AudioStream:
	if TAKES.has(kind): return AUDIO.wav("reward_%s_%d.wav" % [kind, take % int(TAKES[kind])])
	if FILES.has(kind): return AUDIO.wav(FILES[kind])
	return null

## O pool de vozes fica na cena: o item pode sumir sem cortar a cauda do som, e
## descarregar o mundo libera tudo. Sem estado de jogo persistente.
static func play(context: Node, kind: String, volume_db: float = -3.0) -> void:
	if not is_instance_valid(context) or not context.is_inside_tree(): return
	var tree := context.get_tree()
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	var pool := host.get_node_or_null("RewardAudioVoices")
	if pool == null:
		pool = Node.new()
		pool.name = "RewardAudioVoices"
		host.add_child(pool)
		for i in VOICES:
			var voice := AudioStreamPlayer.new()
			voice.bus = AUDIO.SFX_BUS_NAME
			pool.add_child(voice)
	var now := Time.get_ticks_msec()
	var stamp := "last_" + kind
	if now - int(pool.get_meta(stamp, -1000)) < COALESCE_MSEC: return
	var take := 0
	if TAKES.has(kind):
		take = (int(pool.get_meta("take_" + kind, -1)) + 1) % int(TAKES[kind])
	var sample := stream(kind, take)
	if sample == null: return
	pool.set_meta(stamp, now)
	if TAKES.has(kind): pool.set_meta("take_" + kind, take)
	var selected := pool.get_child(0) as AudioStreamPlayer
	for child in pool.get_children():
		var voice := child as AudioStreamPlayer
		if not voice.playing:
			selected = voice
			break
		if int(voice.get_meta("started", 0)) < int(selected.get_meta("started", 0)):
			selected = voice
	selected.stream = sample
	selected.volume_db = volume_db
	selected.pitch_scale = 1.0
	selected.set_meta("started", now)
	selected.play()
